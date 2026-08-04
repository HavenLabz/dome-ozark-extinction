"""Headless Blender: convert a .glb to a Mixamo-uploadable .fbx.
Usage:  blender --background --python glb_to_fbx.py -- <input.glb> <output.fbx>
"""
import bpy, sys

argv = sys.argv[sys.argv.index("--") + 1:]
inp, outp = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=inp)
bpy.ops.export_scene.fbx(
    filepath=outp,
    path_mode='COPY',
    embed_textures=True,
    add_leaf_bones=False,   # Mixamo auto-rig prefers no leaf bones
    bake_anim=False,        # we don't need the A-pose clip going up
)
print("WROTE", outp)
