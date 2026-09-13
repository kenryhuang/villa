"""Retarget Quaternius CC0 locomotion to the farmer, with restrained hip travel.

Source upper-body rotations carry the timing through the whole chain. Foot
targets are adapted to the farmer's shorter legs and rigid boot soles before IK.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector, Quaternion
from player_gait import global_rotation, solve_leg

DATA=Path(__file__).resolve().parents[2]/'art/animations/player/quaternius_locomotion.json'
IDENTITY=Quaternion((1,0,0,0))
WALK_REFERENCE_SPEED=1.73
RUN_REFERENCE_SPEED=4.34
WALK_STANCE=.40
RUN_STANCE=.28
MAP={'pelvis':'pelvis','spine':'spine_01','chest':'spine_03','neck':'neck_01','head':'Head'}
for side,suffix in [('L','l'),('R','r')]:
    for target,source in [('shoulder','clavicle'),('upper_arm','upperarm'),('forearm','lowerarm'),('hand','hand')]:
        MAP[target+'.'+side]=source+'_'+suffix
    for finger in ['index','middle','ring','pinky','thumb']:
        for digit in ['01','02','03']:
            MAP[('' if finger=='thumb' else 'finger_')+finger+'.'+digit+'.'+side]=finger+'_'+digit+'_'+suffix


def sample(data, clip, phase):
    frames=data['clips'][clip]['frames']
    f=(phase%1)*(len(frames)-1)
    i=int(f); t=f-i
    return {n:{'p':Vector(a['p']).lerp(Vector(frames[i+1][n]['p']),t),
               'q':Quaternion(a['q']).slerp(Quaternion(frames[i+1][n]['q']),t)}
            for n,a in frames[i].items()}


def foot_phase(phase, running):
    """Lengthen support to avoid the source jog's long floating interval.

    The recovery time warp meets the support slope at both boundaries.
    """
    stance=RUN_STANCE if running else WALK_STANCE
    source_stance=.20 if running else .24
    p=phase%1
    if p<=stance:return p*source_stance/stance
    t=(p-stance)/(1-stance)
    v=source_stance/stance*(1-stance)
    return (2*t**3-3*t*t+1)*source_stance+(t**3-2*t*t+t)*v+(-2*t**3+3*t*t)+(t**3-t*t)*v


def foot_target(rig, data, pose, side, running, phase):
    # The same contact timing on both sides avoids the library sprint's
    # asymmetric right-foot plant. Torso/arms retain the original asymmetry.
    suffix='l';source=pose['foot_'+suffix]
    rest=Vector(data['rest']['foot_'+suffix])
    ankle=rig.data.bones['foot.'+side].head_local.copy()
    # Compress reach without changing the authored lift/plant/recovery timing.
    reach=.86 if running else .60
    ankle.x+=(source['p'].x-rest.x)*(.60 if side=='L' else -.60)
    rotation=source['q']
    pitch=max(-.32,min(1.12,rotation.to_euler('XYZ').x))
    source_pivot=Vector((0,.070 if pitch<0 else -.228,-rest.z))
    source_unrolled=source['p'].y-(source_pivot-rotation@source_pivot).y
    ankle.y=rig.data.bones['thigh.'+side].head_local.y+.040+(source_unrolled-.075)*reach
    if not running and phase<WALK_STANCE and pitch>0:
        # The mannequin jog runs on its forefoot. With the farmer's long rigid
        # boots that lifts the ankle too soon and folds the support knee.
        t=max(0,min(1,(phase-.16)/(WALK_STANCE-.16)))
        pitch=min(pitch,.65)*t*t*(3-2*t)
    elif not running and pitch>0:
        t=max(0,min(1,(phase-WALK_STANCE)/.12))
        pitch=min(pitch,.65+.47*t*t*(3-2*t))
    # Retarget boot roll about the actual heel/toe instead of reusing the
    # mannequin's ankle height, which has a much shorter sole and articulated toe.
    q=Quaternion((1,0,0),pitch)
    pivot=Vector((0,.100 if pitch<0 else -.205,-ankle.z))
    ankle+=pivot-q@pivot
    # Source ground contact is measured at its heel and toe. During flight we
    # retain a smaller clearance, keeping the recovery foot low and relaxed.
    heel=source['p']+rotation@Vector((0,.070,-rest.z))
    toe=pose['ball_'+suffix]['p'];toe_height=toe.z-.0152
    clearance=max(0,min(heel.z,toe_height)-.015)
    stance=RUN_STANCE if running else WALK_STANCE
    if phase<=stance:clearance=0
    else:
        t=min(1,(phase-stance)/.08,(1-phase)/.08)
        clearance*=t*t*(3-2*t)
    ankle.z+=clearance*(.40 if running else .20)
    return ankle,pitch


def body_pose(rig, data, pose, walking_pose, running, phase):
    pelvis=pose['pelvis']['p']
    # No added push-off pulse. Limit the original large stylized bounce.
    center=.870 if running else .823
    offset=Vector((pelvis.x*.45,-.022,(-.022 if running else -.010)+(pelvis.z-center)*(.25 if running else .12)))
    root=rig.pose.bones['root']
    root.location=root.bone.matrix_local.to_3x3().inverted()@offset
    bpy.context.view_layer.update()
    source_rotations={source:(pose[source]['q'] if running else walking_pose[source]['q'].slerp(pose[source]['q'],.35)) for source in MAP.values()}
    target_rotations={}
    for target,source in MAP.items():
        parent=rig.data.bones[target].parent.name
        source_parent=source_rotations[MAP[parent]] if parent in MAP else IDENTITY
        relative=source_parent.inverted()@source_rotations[source]
        if target in ['pelvis','spine','chest','neck','head']:
            relative=IDENTITY.slerp(relative,.70 if running else .65)
        elif target.startswith(('finger_','thumb.')):
            relative=IDENTITY.slerp(relative,.80)
        if target=='pelvis' and not running:
            # Small hip roll/yaw completes the mannequin's mostly translating
            # pelvis without adding another vertical bounce curve.
            relative=Quaternion((1,0,0),.012)@Quaternion((0,0,1),-.065*math.cos(phase*math.tau))@Quaternion((0,1,0),-.050*math.sin(phase*math.tau))@relative
        q=target_rotations.get(parent,IDENTITY)@relative
        target_rotations[target]=q
        desired=q.to_matrix()@rig.data.bones[target].matrix_local.to_3x3()
        global_rotation(rig,target,desired)


def build_animations(rig, original_animate):
    data=json.loads(DATA.read_text(encoding='utf-8'))
    original_animate(rig)
    for clip,source,frames in [('Walk','Jog_Fwd_Loop',36),('Run','Sprint_Loop',24)]:
        old=bpy.data.actions.get(clip)
        if rig.animation_data.action==old:rig.animation_data.action=None
        if old:bpy.data.actions.remove(old)
        action=bpy.data.actions.new(clip);action.use_fake_user=True
        rig.animation_data.action=action
        for frame in range(frames+1):
            bpy.context.scene.frame_set(frame)
            for bone in rig.pose.bones:
                bone.rotation_mode='QUATERNION';bone.rotation_quaternion=(1,0,0,0)
                bone.location=(0,0,0);bone.scale=(1,1,1)
            phase=frame/frames;running=clip=='Run'
            pose=sample(data,source,phase)
            body_pose(rig,data,pose,sample(data,'Walk_Loop',phase),running,phase)
            targets={side:foot_target(rig,data,sample(data,source,foot_phase(phase+(0 if side=='L' else .5),running)),side,running,(phase+(0 if side=='L' else .5))%1) for side in ['L','R']}
            # Lower only as far as needed to reach a support target. Source
            # rotations never force an unreachable planted knee backward.
            correction=0.0
            for side,(target,pitch) in targets.items():
                hip=rig.pose.bones['thigh.'+side].head
                thigh=rig.data.bones['thigh.'+side];shin=rig.data.bones['shin.'+side];foot=rig.data.bones['foot.'+side]
                length=(shin.head_local-thigh.head_local).length+(foot.head_local-shin.head_local).length-.002
                horizontal=(target.x-hip.x)**2+(target.y-hip.y)**2
                ceiling=target.z+math.sqrt(max(0,length*length-horizontal))
                correction=max(correction,hip.z-ceiling)
            if correction>0:
                root=rig.pose.bones['root']
                root.location-=root.bone.matrix_local.to_3x3().inverted()@Vector((0,0,correction))
                bpy.context.view_layer.update()
            for side,(target,pitch) in targets.items():solve_leg(rig,side,target,pitch)
            for bone in rig.pose.bones:
                bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
                if bone.name=='root':bone.keyframe_insert('location',frame=frame,group=bone.name)
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:key.interpolation='LINEAR'
    rig.animation_data.action=bpy.data.actions['Idle'];bpy.context.scene.frame_set(0)
    rig['locomotion_source']='Quaternius Universal Animation Library 1 Standard / CC0-1.0'
    rig['walk_reference_speed']=WALK_REFERENCE_SPEED
    rig['run_reference_speed']=RUN_REFERENCE_SPEED
