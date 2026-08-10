"""Create and export a low-poly retro-fantasy hero for Godot.

How to use:
1. In Blender choose Scripting > New, paste this file and press Run Script.
2. Save the .blend file wherever you want.
3. Run again. The script writes retro_fantasy_hero.glb beside the .blend file.
4. Copy the .glb into Godot: assets/models/characters/

This first geometry pass exports a stable model; animation is added only after its shape is approved.
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


def parent_to_hero_root(obj, hero_root):
    # Keep the visual model as one stable hierarchy. The previous export used
    # direct bone-parenting and Blender applied rest-pose offsets incorrectly,
    # scattering the body parts after Godot imported the GLB.
    world_matrix = obj.matrix_world.copy()
    obj.parent = hero_root
    obj.matrix_parent_inverse = hero_root.matrix_world.inverted()
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

def create_hero(hero_root, collection, materials):
    skin = materials["skin"]
    cloth = materials["cloth"]
    dark = materials["dark"]
    leather = materials["leather"]
    metal = materials["metal"]
    cape_mat = materials["cape"]

    parts = []

    def part(obj):
        parent_to_hero_root(obj, hero_root)
        for linked_collection in list(obj.users_collection):
            linked_collection.objects.unlink(obj)
        collection.objects.link(obj)
        parts.append(obj)
        return obj

    # A compact, readable silhouette with every neighboring piece overlapping
    # slightly. This prevents visible gaps from any third-person camera angle.
    part(add_cone("Tunic", (0, 0, 1.19), 0.39, 0.31, 0.72, cloth, 8))
    part(add_box("ShoulderBridge", (0, 0, 1.48), (0.48, 0.20, 0.13), cloth, 0.04))
    part(add_box("Belt", (0, -0.005, 0.91), (0.40, 0.24, 0.065), leather, 0.025))
    part(add_box("BeltBuckle", (0, -0.255, 0.91), (0.075, 0.025, 0.075), metal, 0.012))

    # Cape begins under the shoulders and ends above the boots.
    cape = add_cone("Cape", (0, 0.18, 1.08), 0.42, 0.25, 1.02, cape_mat, 7)
    cape.rotation_euler = (math.radians(4), 0, 0)
    part(cape)

    # Head, face and hood are nested closely instead of stacked apart.
    part(add_uv_sphere("Head", (0, -0.015, 1.76), (0.245, 0.225, 0.255), skin))
    part(add_box("FaceShadow", (0, -0.222, 1.76), (0.17, 0.025, 0.14), dark, 0.025))
    part(add_cone("Hood", (0, 0.005, 1.95), 0.315, 0.055, 0.54, dark, 8))
    part(add_box("HoodCollar", (0, 0.01, 1.54), (0.34, 0.22, 0.105), dark, 0.04))

    # Arms hang directly below the shoulder bridge. Upper arm, forearm and
    # hand overlap so the character remains a single visual figure.
    for side, sign in (("L", 1), ("R", -1)):
        x = 0.405 * sign
        part(add_uv_sphere("Shoulder_" + side, (x, 0, 1.42), (0.17, 0.17, 0.18), cloth))
        part(add_box("UpperArm_" + side, (x, 0, 1.20), (0.135, 0.145, 0.255), cloth, 0.035))
        part(add_box("Forearm_" + side, (x, -0.005, 0.91), (0.125, 0.135, 0.20), dark, 0.03))
        part(add_uv_sphere("Hand_" + side, (x, -0.01, 0.73), (0.13, 0.125, 0.14), skin))

    # Legs overlap the tunic hem and boots overlap the lower legs.
    for side, sign in (("L", 1), ("R", -1)):
        x = 0.155 * sign
        part(add_box("UpperLeg_" + side, (x, 0, 0.66), (0.145, 0.16, 0.27), dark, 0.03))
        part(add_box("LowerLeg_" + side, (x, 0, 0.34), (0.13, 0.145, 0.22), dark, 0.03))
        part(add_box("Boot_" + side, (x, -0.075, 0.105), (0.17, 0.235, 0.13), leather, 0.035))

    # The sword grip passes through the right hand. The guard sits above the
    # fist and the blade points upward in the neutral pose.
    sword_x = -0.405
    part(add_box("SwordGrip", (sword_x, -0.015, 0.76), (0.045, 0.045, 0.18), leather, 0.012))
    part(add_box("SwordGuard", (sword_x, -0.015, 0.94), (0.19, 0.055, 0.04), metal, 0.012))
    part(add_box("SwordBlade", (sword_x, -0.015, 1.28), (0.052, 0.035, 0.34), metal, 0.012))
    part(add_cone("SwordTip", (sword_x, -0.015, 1.69), 0.052, 0.0, 0.14, metal, 4))

    # Small equipment details add scale without losing the retro low-poly look.
    part(add_box("LeftPouch", (0.28, -0.22, 0.87), (0.105, 0.075, 0.13), leather, 0.025))
    part(add_box("RightPouch", (-0.22, -0.22, 0.87), (0.09, 0.07, 0.11), leather, 0.025))

    # Animation pivots are exported as stable glTF nodes. Godot rotates these
    # nodes from the player's real movement state, keeping animation responsive
    # while every mesh stays attached to its anatomical joint.
    by_name = {obj.name: obj for obj in parts}

    def pivot(name, location, member_names):
        node = bpy.data.objects.new(name, None)
        node.empty_display_type = "PLAIN_AXES"
        node.empty_display_size = 0.12
        node.location = location
        collection.objects.link(node)
        parent_to_hero_root(node, hero_root)
        for member_name in member_names:
            member = by_name.get(member_name)
            if member is not None:
                parent_to_hero_root(member, node)
        return node

    pivot("HeroArmPivotL", (0.405, 0, 1.43), [
        "UpperArm_L", "Forearm_L", "Hand_L"
    ])
    pivot("HeroArmPivotR", (-0.405, 0, 1.43), [
        "UpperArm_R", "Forearm_R", "Hand_R",
        "SwordGrip", "SwordGuard", "SwordBlade", "SwordTip"
    ])
    pivot("HeroLegPivotL", (0.155, 0, 0.86), [
        "UpperLeg_L", "LowerLeg_L", "Boot_L"
    ])
    pivot("HeroLegPivotR", (-0.155, 0, 0.86), [
        "UpperLeg_R", "LowerLeg_R", "Boot_R"
    ])
    pivot("HeroHeadPivot", (0, 0, 1.55), [
        "Head", "FaceShadow", "Hood"
    ])
    pivot("HeroCapePivot", (0, 0.16, 1.48), ["Cape"])

    return parts

def export_glb(collection, hero_root):
    # Export exactly this hero collection, including the rig and its NLA actions.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = hero_root

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
    hero_root = bpy.data.objects.new("RetroFantasyHero", None)
    collection.objects.link(hero_root)
    create_hero(hero_root, collection, materials)
    export_path = export_glb(collection, hero_root)

    # Geometry pass: export a stable, complete hero before animation is added.
    bpy.context.scene.frame_set(1)
    print("Hero geometry ready. File: " + export_path)


if __name__ == "__main__":
    main()
