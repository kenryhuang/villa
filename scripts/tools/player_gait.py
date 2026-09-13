"""Bake foot trajectories with forward knee poles into the player's existing rig.

Blender model forward is -Y, up is +Z. The exported Godot model faces +Z.
The support contact moves at constant speed; the pelvis and spine carry the
weight transfer while the swing ankle lifts and returns.
"""
import math
import bpy
from mathutils import Vector, Matrix, Quaternion

WALK_STANCE = .60
WALK_DISTANCE = .78
WALK_DURATION = 1.2
RUN_STANCE = .40
RUN_DISTANCE = .88


def smooth(t):
    return t*t*(3-2*t)


def global_rotation(rig, name, rotation):
    bone=rig.pose.bones[name]
    inherited=bone.bone.matrix_local.to_3x3()
    if bone.parent:
        inherited=(bone.parent.matrix.to_3x3()
            @ bone.parent.bone.matrix_local.to_3x3().inverted() @ inherited)
    bone.rotation_quaternion=(inherited.inverted() @ rotation).to_quaternion()
    bpy.context.view_layer.update()


def rotate_world(rig, name, axis, angle):
    bone=rig.pose.bones[name]
    global_rotation(rig,name,Quaternion(Vector(axis),angle).to_matrix() @ bone.matrix.to_3x3())


def aim(rig, name, target):
    bone=rig.pose.bones[name]
    rest=bone.bone
    direction=(target-bone.head).normalized()
    turn=(rest.tail_local-rest.head_local).normalized().rotation_difference(direction)
    global_rotation(rig,name,turn.to_matrix() @ rest.matrix_local.to_3x3())


def solve_leg(rig, side, target, foot_pitch=0):
    thigh=rig.pose.bones['thigh.'+side]
    shin=rig.pose.bones['shin.'+side]
    foot=rig.pose.bones['foot.'+side]
    hip=thigh.head.copy()
    # Use joint offsets, not nominal edit-bone lengths: the original rig has tiny gaps.
    upper=(shin.bone.head_local-thigh.bone.head_local).length
    lower=(foot.bone.head_local-shin.bone.head_local).length
    direction=(target-hip).normalized()
    distance=min((target-hip).length,upper+lower-.001)
    along=(upper*upper-lower*lower+distance*distance)/(2*distance)
    pole=Vector((0,-1,0))
    pole=(pole-direction*direction.dot(pole)).normalized()
    knee=hip+direction*along+pole*math.sqrt(max(0,upper*upper-along*along))
    aim(rig,'thigh.'+side,knee)
    aim(rig,'shin.'+side,target)
    global_rotation(rig,'foot.'+side,Quaternion(Vector((1,0,0)),foot_pitch).to_matrix() @ foot.bone.matrix_local.to_3x3())


def walking_foot(rig, side, p):
    """Heel contact, flat support, toe pivot, then low relaxed swing.

    The ground contact point, rather than the ankle, travels at constant speed.
    Positive pitch lifts the heel around the toe; negative pitch lifts the toe.
    """
    ankle=rig.data.bones['foot.'+side].head_local.copy()
    center=rig.data.bones['thigh.'+side].head_local.y+.07
    if p<WALK_STANCE:
        ankle.y=center+WALK_DISTANCE*(p/WALK_STANCE-.5)
        heel=-.24*(1-smooth(min(1,p/.10)))
        toe=.65*smooth(max(0,min(1,(p-.38)/(.60-.38))))
        pitch=heel+toe
        pivot=Vector((0,.100 if pitch<0 else -.205,-ankle.z))
        ankle+=pivot-Quaternion(Vector((1,0,0)),pitch) @ pivot
    else:
        t=(p-WALK_STANCE)/(1-WALK_STANCE)
        # Match the ankle positions of the two pivoted contact endpoints.
        start,_=walking_foot(rig,side,WALK_STANCE-1e-7)
        end,_=walking_foot(rig,side,0)
        ankle=start.lerp(end,smooth(t))
        ankle.z+=.075*math.sin(math.pi*t)
        pitch=.65+(-.24-.65)*smooth(min(1,t/.80))
    return ankle,pitch


def relaxed_hand(rig, side, sign, running):
    # Fingers bend toward the palm, about world Y after lowering the arms.
    # The former world-X rotations fanned them sideways into a rigid open claw.
    middle=rig.pose.bones['finger_middle.01.'+side].vector.normalized()
    for finger in ['finger_index','finger_middle','finger_ring','finger_pinky']:
        first=rig.pose.bones[finger+'.01.'+side]
        aim(rig,first.name,first.head+first.vector.normalized().lerp(middle,.50)*first.length)
        for digit,angle in [('01',.18),('02',.40),('03',.28)]:
            rotate_world(rig,finger+'.'+digit+'.'+side,(0,1,0),sign*angle*(1.35 if running else 1))


def walking_body(rig, phase):
    """Transfer weight through the pelvis before solving the planted legs.

    Roll raises the support-side hip; yaw carries the advancing hip forward.
    A small push-off rise and forward pitch propagate through the whole chain.
    """
    cycle=phase*math.tau
    push=(.5+.5*math.cos((phase-.055)*math.tau*2))**4
    rise=-.020-.020*math.cos(cycle*2)+.010*push
    offset=Vector((.010*math.sin(cycle),-.020-.004*push,rise))
    root=rig.pose.bones['root']
    root.location=root.bone.matrix_local.to_3x3().inverted() @ offset
    bpy.context.view_layer.update()
    rotate_world(rig,'pelvis',(1,0,0),.025+.009*push)
    rotate_world(rig,'pelvis',(0,1,0),-.040*math.sin(cycle))
    rotate_world(rig,'pelvis',(0,0,1),-.055*math.cos(cycle))
    # Shared lower-back motion carries the shirt with the hips. The chest
    # counter-rotates gently so the shoulders do not swing as one rigid block.
    rotate_world(rig,'spine',(1,0,0),.026+.004*push)
    rotate_world(rig,'spine',(0,0,1),.035*math.cos(cycle))
    rotate_world(rig,'chest',(1,0,0),.014)
    rotate_world(rig,'chest',(0,1,0),.024*math.sin(cycle))
    rotate_world(rig,'chest',(0,0,1),.032*math.cos(cycle-.18))
    rotate_world(rig,'head',(1,0,0),-.035)
    rotate_world(rig,'head',(0,0,1),-.012*math.cos(cycle))
    # Keep both support soles grounded when the new pelvis motion approaches
    # full extension. Correct only the necessary vertical amount, before IK.
    correction=0.0
    for side,shift in [('L',0),('R',.5)]:
        p=(phase+shift)%1
        if p>=WALK_STANCE:continue
        target,_=walking_foot(rig,side,p)
        thigh=rig.pose.bones['thigh.'+side]
        shin=rig.data.bones['shin.'+side]
        foot=rig.data.bones['foot.'+side]
        length=(shin.head_local-thigh.bone.head_local).length+(foot.head_local-shin.head_local).length-.0015
        horizontal=Vector((target.x-thigh.head.x,target.y-thigh.head.y,0)).length_squared
        ceiling=target.z+math.sqrt(max(0,length*length-horizontal))
        correction=max(correction,thigh.head.z-ceiling)
    if correction>0:
        root.location-=root.bone.matrix_local.to_3x3().inverted() @ Vector((0,0,correction))
        bpy.context.view_layer.update()


def build_animations(rig, original_animate):
    original_animate(rig)
    for clip,frames,stance,distance,lift in [
        ('Walk',36,WALK_STANCE,WALK_DISTANCE,.075),
        ('Run',24,RUN_STANCE,RUN_DISTANCE,.24)]:
        old=bpy.data.actions.get(clip)
        if rig.animation_data.action==old:
            rig.animation_data.action=None
        bpy.data.actions.remove(old)
        action=bpy.data.actions.new(clip)
        action.use_fake_user=True
        rig.animation_data.action=action
        for frame in range(frames+1):
            bpy.context.scene.frame_set(frame)
            for bone in rig.pose.bones:
                bone.rotation_mode='QUATERNION'
                bone.rotation_quaternion=(1,0,0,0)
                bone.location=(0,0,0)
                bone.scale=(1,1,1)
            phase=frame/frames
            # Rise onto the almost-straight support leg at midstance. The old
            # constant -65 mm offset forced BOTH legs to remain crouched.
            drop=(-.020-.020*math.cos(phase*math.tau*2) if clip=='Walk'
                  else -.085-.040*math.cos(phase*math.tau*2))
            # Root's local Y is world Z. A local-Z offset would move the hips
            # backward and make the extreme support-foot targets unreachable.
            rig.pose.bones['root'].location=rig.data.bones['root'].matrix_local.to_3x3().inverted() @ Vector((0,0,drop))
            bpy.context.view_layer.update()
            if clip=='Walk':walking_body(rig,phase)
            for sign,side in [(1,'L'),(-1,'R')]:
                p=(phase+(0 if side=='L' else .5))%1
                ankle=rig.data.bones['foot.'+side].head_local.copy()
                ankle.y=rig.data.bones['thigh.'+side].head_local.y
                pitch=0
                if clip=='Walk':
                    ankle,pitch=walking_foot(rig,side,p)
                elif p<stance:
                    travel=p/stance
                    ankle.y+=distance*(travel-.5)
                else:
                    t=(p-stance)/(1-stance)
                    ankle.y+=distance*(.5-smooth(t))
                    ankle.z+=lift*math.sin(math.pi*t)**1.4
                solve_leg(rig,side,ankle,pitch)
                rotate_world(rig,'shoulder.'+side,(0,0,1),sign*.025*math.cos(p*math.tau))
                rotate_world(rig,'upper_arm.'+side,(0,1,0),sign*math.radians(80 if clip=='Run' else 82))
                # Arm opposite the leading leg, with a small relaxed elbow bend.
                rotate_world(rig,'upper_arm.'+side,(1,0,0),(.52 if clip=='Run' else .26)*math.cos(p*math.tau))
                rotate_world(rig,'forearm.'+side,(1,0,0),-.85 if clip=='Run' else -.19-.06*math.sin(p*math.tau-.35))
                relaxed_hand(rig,side,sign,clip=='Run')
            if clip=='Run':
                rotate_world(rig,'chest',(1,0,0),.09)
                rotate_world(rig,'chest',(0,0,1),.025*math.sin(phase*math.tau))
                rotate_world(rig,'head',(0,0,1),-.018*math.sin(phase*math.tau))
            for bone in rig.pose.bones:
                bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
                if bone.name=='root':
                    bone.keyframe_insert('location',frame=frame,group=bone.name)
        # Sampling at every frame and linear interpolation cannot overshoot a knee pole.
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation='LINEAR'
    rig.animation_data.action=bpy.data.actions['Idle']
    bpy.context.scene.frame_set(0)
    rig['walk_reference_speed']=WALK_DISTANCE/(WALK_STANCE*WALK_DURATION)
    rig['run_reference_speed']=RUN_DISTANCE/(RUN_STANCE*.8)
