"""Create and export a low-poly retro-fantasy hero for Godot.

How to use:
1. In Blender choose Scripting > New, paste this file and press Run Script.
2. Save the .blend file wherever you want.
3. Run again. The script writes retro_fantasy_hero.glb beside the .blend file.
4. Copy the .glb into Godot: assets/models/characters/

The model has an idle and a walk animation, named "Idle" and "Walk".
Designed for Blender 4.x and Godot's glTF (.glb) importer.
"""

import bpy
import math
import os
import sys
from mathutils import Vector

EXPORT_NAME = "retro_fantasy_hero.glb"
COLLECTION_NAME = "RetroFantasyHero"


# ---------- Scene helpers ----------

def clear_previous_hero():
    old = bpy.data.collections.get(COLLECTION_NAME)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)


def make_material(name, color, metallic=0.0, roughness=0.82):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1.0)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return material


def add_box(name, location, scale, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Soft low-poly edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
    obj.data.materials.append(material)
    return obj


def add_cone(name, location, radius1, radius2, depth, material, vertices=6):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius1, radius2=radius2, depth=depth, location=location
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    return obj


def add_uv_sphere(name, location, scale, material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return obj


def parent_to_bone(obj, armature, bone_name):
    # Preserve the part's visible world transform before bone parenting.
    # Without this, Blender applies the bone's rest offset a second time and
    # the hero appears to explode into separate pieces.
    world_matrix = obj.matrix_world.copy()
    obj.parent = armature
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    obj.matrix_world = world_matrix


# ---------- Rig and animations ----------

def create_rig(collection):
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    rig = bpy.context.object
    rig.name = "HeroRig"
    rig.data.name = "HeroRig"
    for linked_collection in list(rig.users_collection):
        linked_collection.objects.unlink(rig)
    collection.objects.link(rig)

    edit = rig.data.edit_bones
    root = edit[0]
    root.name = "Root"
    root.head = (0, 0, 0)
    root.tail = (0, 0, 0.85)

    spine = edit.new("Spine")
    spine.head = root.tail
    spine.tail = (0, 0, 1.55)
    spine.parent = root
    spine.use_connect = True

    head = edit.new("Head")
    head.head = spine.tail
    head.tail = (0, 0, 2.05)
    head.parent = spine
    head.use_connect = True

    for side, sign in (("L", 1), ("R", -1)):
        leg = edit.new("Leg_" + side)
        leg.head = (0.19 * sign, 0, 0.85)
        leg.tail = (0.19 * sign, 0, 0.10)
        leg.parent = root

        arm = edit.new("Arm_" + side)
        arm.head = (0.34 * sign, 0, 1.45)
        arm.tail = (0.62 * sign, 0, 0.93)
        arm.parent = spine

    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"

    # A subtle idle breath.
    idle = bpy.data.actions.new("Idle")
    rig.animation_data_create()
    rig.animation_data.action = idle
    for frame, scale_z in ((1, 1.0), (18, 1.035), (36, 1.0)):
        spine_pose = rig.pose.bones["Spine"]
        spine_pose.scale = (1.0, 1.0, scale_z)
        spine_pose.keyframe_insert(data_path="scale", frame=frame)
    idle.frame_range = (1, 36)

    # Simple readable walk cycle.
    walk = bpy.data.actions.new("Walk")
    rig.animation_data.action = walk
    for frame, leg_l, leg_r, arm_l, arm_r in (
        (1, math.radians(28), math.radians(-28), math.radians(-22), math.radians(22)),
        (9, 0.0, 0.0, 0.0, 0.0),
        (17, math.radians(-28), math.radians(28), math.radians(22), math.radians(-22)),
        (25, 0.0, 0.0, 0.0, 0.0),
        (33, math.radians(28), math.radians(-28), math.radians(-22), math.radians(22)),
    ):
        for bone_name, angle in (
            ("Leg_L", leg_l), ("Leg_R", leg_r), ("Arm_L", arm_l), ("Arm_R", arm_r)
        ):
            bone = rig.pose.bones[bone_name]
            bone.rotation_euler = (angle, 0.0, 0.0)
            bone.keyframe_insert(data_path="rotation_euler", frame=frame)
    walk.frame_range = (1, 33)

    # Keep both actions as exportable NLA tracks.
    rig.animation_data.action = None
    for action in (idle, walk):
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, int(action.frame_range[0]), action)
        strip.action_frame_start = action.frame_range[0]
        strip.action_frame_end = action.frame_range[1]

    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


# ---------- Model ----------

def create_hero(rig, collection, materials):
    skin = materials["skin"]
    cloth = materials["cloth"]
    dark = materials["dark"]
    leather = materials["leather"]
    metal = materials["metal"]
    cape_mat = materials["cape"]

    parts = []
    def part(obj, bone):
        parent_to_bone(obj, rig, bone)
        for linked_collection in list(obj.users_collection):
            linked_collection.objects.unlink(obj)
        collection.objects.link(obj)
        parts.append(obj)

    # Torso, belt and cape: a hooded adventurer silhouette.
    part(add_cone("Torso", (0, 0, 1.24), 0.42, 0.30, 0.78, cloth, 6), "Spine")
    part(add_box("Belt", (0, 0, 0.98), (0.43, 0.30, 0.08), leather, 0.025), "Spine")
    cape = add_cone("Cape", (0, 0.23, 1.15), 0.43, 0.20, 0.90, cape_mat, 5)
    cape.rotation_euler = (math.radians(8), 0, 0)
    part(cape, "Spine")

    # Head and pointed hood.
    part(add_uv_sphere("Head", (0, 0, 1.78), (0.28, 0.25, 0.28), skin), "Head")
    part(add_cone("Hood", (0, 0, 1.99), 0.34, 0.08, 0.58, dark, 6), "Head")

    # Boots and limbs.
    for side, sign in (("L", 1), ("R", -1)):
        part(add_box("Leg_" + side, (0.19 * sign, 0, 0.45), (0.15, 0.16, 0.40), dark, 0.03), "Leg_" + side)
        part(add_box("Boot_" + side, (0.19 * sign, -0.08, 0.08), (0.18, 0.25, 0.12), leather, 0.03), "Leg_" + side)
        part(add_box("Arm_" + side, (0.47 * sign, 0, 1.18), (0.13, 0.14, 0.35), cloth, 0.03), "Arm_" + side)
        part(add_uv_sphere("Hand_" + side, (0.62 * sign, 0, 0.82), (0.13, 0.13, 0.14), skin), "Arm_" + side)

    # Sword is on the right hand: blade faces forward along negative Y.
    blade = add_box("SwordBlade", (-0.68, -0.16, 0.70), (0.055, 0.055, 0.58), metal, 0.015)
    blade.rotation_euler = (math.radians(-18), 0, 0)
    part(blade, "Arm_R")
    part(add_box("SwordGuard", (-0.68, -0.10, 0.34), (0.23, 0.06, 0.045), metal, 0.01), "Arm_R")
    part(add_box("SwordGrip", (-0.68, -0.10, 0.24), (0.05, 0.05, 0.14), leather, 0.01), "Arm_R")

    return parts


def export_glb(collection, rig):
    # Export exactly this hero collection, including the rig and its NLA actions.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig

    # A terminal build may pass an explicit output path after Blender's "--".
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if arguments:
        export_path = os.path.abspath(arguments[0])
    elif bpy.data.filepath:
        export_path = os.path.join(os.path.dirname(bpy.data.filepath), EXPORT_NAME)
    else:
        export_path = os.path.join(os.path.expanduser("~"), EXPORT_NAME)
    os.makedirs(os.path.dirname(export_path), exist_ok=True)

    bpy.ops.export_scene.gltf(
        filepath=export_path,
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_nla_strips=True,
        export_apply=True,
        export_yup=True,
    )
    print("RETRO_FANTASY_HERO_EXPORTED: " + export_path)
    return export_path


def main():
    clear_previous_hero()
    collection = bpy.data.collections.new(COLLECTION_NAME)
    bpy.context.scene.collection.children.link(collection)

    materials = {
        "skin": make_material("Hero_Skin", (0.58, 0.31, 0.20)),
        "cloth": make_material("Hero_Cloth", (0.13, 0.16, 0.29)),
        "dark": make_material("Hero_Hood", (0.035, 0.025, 0.055)),
        "leather": make_material("Hero_Leather", (0.16, 0.075, 0.035)),
        "metal": make_material("Hero_Metal", (0.34, 0.37, 0.46), metallic=0.62, roughness=0.42),
        "cape": make_material("Hero_Cape", (0.19, 0.025, 0.06)),
    }
    rig = create_rig(collection)
    create_hero(rig, collection, materials)
    export_path = export_glb(collection, rig)

    # Place the hero at the world origin and select it for immediate inspection.
    bpy.context.scene.frame_set(1)
    print("Hero ready. Idle and Walk animations exported. File: " + export_path)


if __name__ == "__main__":
    main()
