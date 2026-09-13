"""Encode raw Godot capture frames; the manifest excludes stale frames."""
import json
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
for clip in ('walk','run'):
    directory=ROOT/'tmp/player-upright-motion'/clip
    capture=json.loads((directory/'capture.json').read_text())
    frames=[Image.open(directory/f'{i:03d}.png').convert('RGB') for i in range(capture['frames'])]
    destination=ROOT/f'art/concepts/player/player-{clip}.gif'
    frames[0].save(destination,save_all=True,append_images=frames[1:],duration=20,loop=0,optimize=False)
    with Image.open(destination) as result:assert result.n_frames==capture['frames']
    print(destination.name,capture['frames'],'frames')
