"""Extract CC0 Quaternius locomotion as portable rest-space pose samples.

Blender --background --python extract_player_locomotion.py -- path/to/UAL1_Standard.glb
The upstream archive is available from https://quaternius.itch.io/universal-animation-library.
Only pose data is retained, not the reference mannequin or unrelated animations.
"""
import bpy
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/'art/animations/player/quaternius_locomotion.json'

def main():
    source=Path(sys.argv[sys.argv.index('--')+1]).resolve()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=str(source))
    rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
    for track in rig.animation_data.nla_tracks:track.mute=True
    names=[b.name for b in rig.data.bones if 'leaf' not in b.name and '_04_' not in b.name]
    def values(v):return [round(float(x),7) for x in v]
    data={'source':'Quaternius Universal Animation Library 1 Standard v3.0',
          'url':'https://quaternius.itch.io/universal-animation-library','license':'CC0-1.0',
          'rest':{n:values(rig.data.bones[n].head_local) for n in names},'clips':{}}
    for name in ['Walk_Loop','Jog_Fwd_Loop','Sprint_Loop']:
        action=bpy.data.actions[name]
        rig.animation_data.action=action
        rig.animation_data.action_slot=action.slots[0]
        end=action.frame_range[1]
        frames=[]
        for i in range(61):
            f=end*i/60
            bpy.context.scene.frame_set(int(f),subframe=f%1)
            frames.append({n:{'p':values(rig.pose.bones[n].head),
                              'q':values((rig.pose.bones[n].matrix.to_3x3() @ rig.data.bones[n].matrix_local.to_3x3().inverted()).to_quaternion())}
                           for n in names})
        data['clips'][name]={'duration':float(end)/30,'frames':frames}
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    OUTPUT.write_text(json.dumps(data,separators=(',',':'))+'\n',encoding='utf-8')
    print('Extracted locomotion:',OUTPUT)

if __name__=='__main__':main()
