"""Bake original, matte bark into shared UV textures for the diverse grove.

Run through build_diverse_trees.py in Blender. No external image sources.
Each species uses one albedo/normal pair shared by all three exported LODs.
"""
import json
import struct
import time
import bpy


PALETTES = {
    'oak': ('54483a', '81705b', 'aa977c'),
    'birch': ('43443c', 'c9c8b8', 'eee9d9'),
    'maple': ('65554b', '8c7b70', 'b3a08d'),
    'poplar': ('45493c', '9a9e89', 'c6c9b3'),
    'pine': ('614834', '927059', 'b3977a'),
    'willow': ('4a4e40', '777b68', 'a2a38c'),
}


def color(code):
    values = [int(code[i:i+2], 16)/255 for i in (0, 2, 4)]
    return tuple(v/12.92 if v < .04045 else ((v+.055)/1.055)**2.4 for v in values)+(1,)


def bake_bark(obj, cfg, output_dir):
    """Bake before LOD decimation so coarse meshes inherit the same UV atlas."""
    sid, form = cfg['id'], cfg['form']
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    obj.data.uv_layers.new(name='BarkUV')
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=.015)
    bpy.ops.object.mode_set(mode='OBJECT')
    mat = bpy.data.materials.new(sid+' / baked bark')
    mat.use_nodes = True
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()

    def node(kind, label):
        result = nodes.new(kind)
        result.label = label
        return result

    def ramp(source, stops):
        result = node('ShaderNodeValToRGB', 'Painted bark tones')
        cr = result.color_ramp
        for index, (position, value) in enumerate(stops):
            element = cr.elements[index] if index < 2 else cr.elements.new(position)
            element.position = position
            element.color = value
        links.new(source, result.inputs[0])
        return result.outputs['Color']

    coordinates = node('ShaderNodeTexCoord', 'Local metre coordinates')
    scale = node('ShaderNodeVectorMath', 'Long grain / short cross cracks')
    scale.operation = 'MULTIPLY'
    scale.inputs[1].default_value = (8, 8, 2.4) if form == 'pine' else (12, 12, .85)
    links.new(coordinates.outputs['Object'], scale.inputs[0])
    distortion = node('ShaderNodeTexNoise', 'Uneven growth')
    distortion.inputs['Scale'].default_value = 2.2
    distortion.inputs['Detail'].default_value = 2.5
    links.new(coordinates.outputs['Object'], distortion.inputs['Vector'])
    warp = node('ShaderNodeVectorMath', 'Small flowing irregularity')
    warp.operation = 'SCALE'
    warp.inputs[3].default_value = .65
    links.new(distortion.outputs['Color'], warp.inputs[0])
    add = node('ShaderNodeVectorMath', 'Warped grain')
    add.operation = 'ADD'
    links.new(scale.outputs[0], add.inputs[0])
    links.new(warp.outputs[0], add.inputs[1])
    cells = node('ShaderNodeTexVoronoi', 'Fissures between bark plates')
    cells.feature = 'DISTANCE_TO_EDGE'
    cells.inputs['Scale'].default_value = 1
    links.new(add.outputs[0], cells.inputs['Vector'])
    relief = ramp(cells.outputs['Distance'], [(.015, (.05,.05,.05,1)), (.105, (.72,.72,.72,1)), (.27, (.92,.92,.92,1))])
    fine = node('ShaderNodeTexNoise', 'Fine bark grain')
    fine.inputs['Scale'].default_value = 5
    fine.inputs['Detail'].default_value = 2
    links.new(add.outputs[0], fine.inputs['Vector'])
    detail = node('ShaderNodeMixRGB', 'Quiet surface grain')
    detail.blend_type = 'MULTIPLY'
    detail.inputs[0].default_value = .27
    links.new(relief, detail.inputs[1])
    links.new(fine.outputs['Fac'], detail.inputs[2])
    height = detail.outputs[0]
    grain = node('ShaderNodeTexNoise', 'Layered longitudinal fibres')
    grain.inputs['Scale'].default_value = 1.8
    grain.inputs['Detail'].default_value = 3
    grain.inputs['Roughness'].default_value = .7
    links.new(add.outputs[0], grain.inputs['Vector'])
    fibres = node('ShaderNodeMixRGB', 'Fibres with occasional fine fissures')
    fibres.blend_type = 'MIX' if form == 'pine' else 'MULTIPLY'
    fibres.inputs[0].default_value = .5 if form == 'pine' else .22
    links.new(grain.outputs['Fac'], fibres.inputs[1])
    links.new(height, fibres.inputs[2])
    height = fibres.outputs[0]
    dark, middle, light = map(color, PALETTES[form])
    painted = ramp(height, [(.12, dark), (.44, middle), (.82, light)])
    if form in ('birch', 'poplar'):
        stripes = node('ShaderNodeVectorMath', 'Horizontal lenticels')
        stripes.operation = 'MULTIPLY'
        stripes.inputs[1].default_value = (3.2, 3.2, 40)
        links.new(coordinates.outputs['Object'], stripes.inputs[0])
        flecks = node('ShaderNodeTexNoise', 'Broken irregular horizontal marks')
        flecks.inputs['Scale'].default_value = 1
        flecks.inputs['Detail'].default_value = 2
        links.new(stripes.outputs[0], flecks.inputs[0])
        marks = ramp(flecks.outputs['Fac'], [(.48, (1,1,1,1)), (.64, (1,1,1,1)), (.70, (.05,.05,.05,1))])
        painted = ramp(marks, [(0, dark), (.6, middle), (1, light)])
        height = marks

    z = node('ShaderNodeSeparateXYZ', 'Root height')
    links.new(coordinates.outputs['Object'], z.inputs[0])
    moss_mask = ramp(z.outputs['Z'], [(0, (.32,.32,.32,1)), (.45, (0,0,0,1))])
    moss = node('ShaderNodeMixRGB', 'Soft moss at the ground')
    links.new(moss_mask, moss.inputs[0])
    links.new(painted, moss.inputs[1])
    moss.inputs[2].default_value = color('5a6144')
    output = node('ShaderNodeOutputMaterial', 'Output')
    emission = node('ShaderNodeEmission', 'Unlit albedo bake')
    links.new(moss.outputs[0], emission.inputs[0])
    links.new(emission.outputs[0], output.inputs['Surface'])
    shader = node('ShaderNodeBsdfPrincipled', 'Matte bark')
    shader.inputs['Roughness'].default_value = .94
    shader.inputs['Specular IOR Level'].default_value = .12
    links.new(moss.outputs[0], shader.inputs['Base Color'])
    bump = node('ShaderNodeBump', 'Shallow fissures, no added geometry')
    bump.inputs['Strength'].default_value = .48
    bump.inputs['Distance'].default_value = .018 if form not in ('birch', 'poplar') else .006
    links.new(height, bump.inputs['Height'])
    links.new(bump.outputs[0], shader.inputs['Normal'])
    target = node('ShaderNodeTexImage', 'Bake target')
    nodes.active = target
    scene = bpy.context.scene
    old_samples = scene.cycles.samples
    scene.cycles.samples = 8
    scene.render.bake.margin = 12
    scene.render.bake.use_selected_to_active = False
    baked = {}
    for kind in ('albedo', 'normal'):
        image = bpy.data.images.new(sid+'_bark_'+kind, width=1024, height=1024, alpha=False)
        if kind == 'normal':
            image.colorspace_settings.name = 'Non-Color'
            links.new(shader.outputs[0], output.inputs['Surface'])
        target.image = image
        bpy.ops.object.bake(type='EMIT' if kind == 'albedo' else 'NORMAL')
        image.filepath_raw = str(output_dir/(image.name+'.png'))
        image.file_format = 'PNG'
        image.save()
        image.pack()
        assert image.packed_file
        baked[kind] = image
    scene.cycles.samples = old_samples
    # Preserve the procedural source in a fake-user material for later art edits.
    source = mat.copy()
    source.name = sid+' / editable procedural bark'
    source.use_fake_user = True
    nodes.clear()
    output = nodes.new('ShaderNodeOutputMaterial')
    shader = nodes.new('ShaderNodeBsdfPrincipled')
    shader.inputs['Roughness'].default_value = .94
    shader.inputs['Specular IOR Level'].default_value = .12
    albedo = nodes.new('ShaderNodeTexImage'); albedo.image = baked['albedo']
    normal = nodes.new('ShaderNodeTexImage'); normal.image = baked['normal']
    normal_map = nodes.new('ShaderNodeNormalMap')
    links.new(albedo.outputs['Color'], shader.inputs['Base Color'])
    links.new(normal.outputs['Color'], normal_map.inputs['Color'])
    links.new(normal_map.outputs['Normal'], shader.inputs['Normal'])
    links.new(shader.outputs[0], output.inputs['Surface'])
    # The atlas already contains the color and moss; do not multiply old brown paint.
    for value in obj.data.color_attributes['Paint'].data:
        value.color = (1, 1, 1, 1)
    print('BARK_BAKED', sid, flush=True)


def share_bark_images(filename, destination):
    """Remove embedded image payloads; external PNGs are shared across LODs."""
    raw = filename.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20+size])
    binary = raw[28+size:]
    removed = set()
    for image in document.get('images', []):
        name = image['name']
        assert (destination.parent/(name+'.png')).is_file(), name
        removed.add(image['bufferView'])
        image.clear()
        image.update(name=name, uri=name+'.png')
    views, payload, indices = [], bytearray(), {}
    for index, view in enumerate(document['bufferViews']):
        if index in removed:
            continue
        payload.extend(b'\0'*(-len(payload)%4))
        indices[index] = len(views)
        updated = dict(view, byteOffset=len(payload))
        start = view.get('byteOffset', 0)
        payload.extend(binary[start:start+view['byteLength']])
        views.append(updated)

    def remap(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == 'bufferView': value[key] = indices[item]
                else: remap(item)
        elif isinstance(value, list):
            for item in value: remap(item)
    remap(document)
    document['bufferViews'] = views
    document['buffers'][0]['byteLength'] = len(payload)
    encoded = json.dumps(document, separators=(',', ':')).encode()
    encoded += b' '*(-len(encoded)%4)
    payload.extend(b'\0'*(-len(payload)%4))
    temporary = destination.with_suffix('.glb.tmp')
    temporary.write_bytes(struct.pack('<III', 0x46546C67, 2, 28+len(encoded)+len(payload))+
                          struct.pack('<II', len(encoded), 0x4E4F534A)+encoded+
                          struct.pack('<II', len(payload), 0x004E4942)+payload)
    # The editor may be reading an earlier model; publish only the complete GLB.
    for attempt in range(6):
        try:
            temporary.replace(destination)
            break
        except PermissionError:
            if attempt == 5: raise
            time.sleep(.2)
