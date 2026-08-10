"""Generate the core low-poly retro-fantasy asset pack for Godot.

Run through tools/blender/build_all_models.ps1. Individual GLB files are placed
under assets/models/environment, assets/models/props and assets/models/enemies.
"""

import bpy
import math
import os
import sys

ROOT_COLLECTION = "GeneratedAsset"


def material(name, color, metallic=0.0, roughness=0.85, emission=None):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Metallic"].default_value = metallic
    if emission:
        p.inputs["Emission Color"].default_value = (*emission, 1.0)
        p.inputs["Emission Strength"].default_value = 1.6
    return mat


M = {
    "bark": material("RF_Bark", (0.10, 0.045, 0.018)),
    "bark_light": material("RF_BarkLight", (0.20, 0.09, 0.03)),
    "pine": material("RF_Pine", (0.035, 0.13, 0.085)),
    "pine_light": material("RF_PineLight", (0.08, 0.24, 0.13)),
    "stone": material("RF_Stone", (0.22, 0.23, 0.29)),
    "stone_dark": material("RF_StoneDark", (0.09, 0.10, 0.15)),
    "ore": material("RF_Ore", (0.14, 0.34, 0.50), metallic=0.45, roughness=0.30, emission=(0.07, 0.20, 0.35)),
    "moss": material("RF_Moss", (0.12, 0.32, 0.10)),
    "gold": material("RF_Gold", (0.72, 0.38, 0.06), metallic=0.75, roughness=0.28),
    "wood": material("RF_Wood", (0.28, 0.12, 0.035)),
    "cloth": material("RF_Cloth", (0.27, 0.035, 0.07)),
    "glass": material("RF_Glass", (0.22, 0.68, 0.80), metallic=0.15, roughness=0.12, emission=(0.05, 0.15, 0.20)),
    "fire": material("RF_Fire", (1.0, 0.16, 0.015), roughness=0.4, emission=(1.0, 0.05, 0.0)),
    "skin": material("RF_GoblinSkin", (0.19, 0.40, 0.11)),
    "leather": material("RF_Leather", (0.19, 0.075, 0.025)),
    "bone": material("RF_Bone", (0.72, 0.62, 0.43)),
}


def link(obj, col):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    col.objects.link(obj)
    return obj


def box(name, pos, scale, mat, col, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return link(obj, col)


def cone(name, pos, r1, r2, depth, mat, col, vertices=6, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=depth, location=pos, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return link(obj, col)


def sphere(name, pos, scale, mat, col, segments=8):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2 if segments > 6 else 1, radius=1, location=pos)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return link(obj, col)


def reset_collection():
    old = bpy.data.collections.get(ROOT_COLLECTION)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)
    col = bpy.data.collections.new(ROOT_COLLECTION)
    bpy.context.scene.collection.children.link(col)
    return col


def pine_tree(col):
    cone("Trunk", (0, 0, 1.8), 0.26, 0.17, 3.6, M["bark"], col, 7)
    cone("CanopyLow", (0, 0, 3.1), 1.4, 0.28, 2.2, M["pine"], col, 7)
    cone("CanopyMid", (0, 0, 4.1), 1.05, 0.20, 2.0, M["pine_light"], col, 7)
    cone("CanopyTop", (0, 0, 5.0), 0.65, 0.04, 1.7, M["pine"], col, 7)
    for angle in (0.1, 2.2, 4.3):
        box("Branch", (math.cos(angle) * 0.65, math.sin(angle) * 0.65, 2.8), (0.75, 0.08, 0.08), M["bark_light"], col, (0.0, 0.45, angle))


def dead_tree(col):
    cone("DeadTrunk", (0, 0, 1.65), 0.24, 0.12, 3.3, M["bark"], col, 6)
    for i, (angle, height, length) in enumerate(((0.2, 2.25, 1.25), (2.4, 1.85, 1.05), (4.5, 2.65, 0.85))):
        box("DeadBranch_%d" % i, (math.cos(angle) * length * .45, math.sin(angle) * length * .45, height), (length * .55, .07, .07), M["bark_light"], col, (0.0, 0.55, angle))
    cone("BrokenTop", (0, 0, 3.38), .14, .02, .35, M["bark_light"], col, 5)


def boulder(col):
    sphere("Boulder", (0, 0, .65), (1.05, .85, .72), M["stone"], col)
    sphere("BoulderShardA", (-.62, .13, .52), (.48, .40, .45), M["stone_dark"], col)
    sphere("MossCap", (.14, -.30, 1.20), (.58, .38, .16), M["moss"], col)


def ore_node(col):
    sphere("OreRock", (0, 0, .55), (.82, .70, .60), M["stone_dark"], col)
    for x, y, z, scale in ((-.35,-.22,.82,.24), (.28,.08,.70,.26), (.05,.38,.58,.17), (.22,-.40,.35,.16)):
        cone("OreCrystal", (x,y,z), scale, .04, scale * 2.2, M["ore"], col, 5, (0.15, .25, 0.0))


def grass_tuft(col):
    for i, angle in enumerate((0, .75, 1.55, 2.4, 3.1, 4.0, 4.8, 5.5)):
        length = .55 + (i % 3) * .10
        blade = cone("GrassBlade", (math.cos(angle)*.12, math.sin(angle)*.12, length*.5), .055, .008, length, M["pine_light"], col, 4, (.35, 0, angle))
        blade.rotation_euler.y += math.sin(angle) * .28


def mushroom_cluster(col):
    for i, (x, y, size) in enumerate(((0,0,.42), (.32,.11,.28), (-.22,.18,.25), (.12,-.27,.20))):
        cone("MushroomStem", (x, y, size*.42), size*.10, size*.08, size*.7, M["bone"], col, 6)
        cone("MushroomCap", (x, y, size*.80), size*.32, .04, size*.18, M["cloth"], col, 8)


def chest(col):
    box("ChestBase", (0, 0, .37), (.70, .42, .36), M["wood"], col, (0, 0, 0))
    box("ChestLid", (0, -.02, .76), (.70, .42, .16), M["wood"], col, (math.radians(12), 0, 0))
    box("ChestBandA", (-.42, 0, .42), (.045, .45, .39), M["gold"], col)
    box("ChestBandB", (.42, 0, .42), (.045, .45, .39), M["gold"], col)
    box("Lock", (0, -.45, .48), (.12, .04, .14), M["gold"], col)


def potion(col):
    sphere("PotionBottle", (0, 0, .35), (.24, .24, .35), M["glass"], col)
    cone("PotionNeck", (0, 0, .73), .09, .09, .28, M["glass"], col, 8)
    sphere("PotionCork", (0, 0, .89), (.10, .10, .08), M["wood"], col)


def campfire(col):
    for angle in (0, math.pi/3, 2*math.pi/3):
        box("Log", (0, 0, .16), (.82, .13, .13), M["wood"], col, (0, 0, angle))
    cone("FireOuter", (0, 0, .60), .43, .05, .92, M["fire"], col, 6)
    cone("FireCore", (0, 0, .55), .24, .03, .64, M["gold"], col, 5)


def moss_goblin(col):
    # Deliberately broad silhouette: clear enemy at distance in a dark forest.
    cone("GoblinBody", (0,0,1.05), .38, .26, .88, M["leather"], col, 6)
    sphere("GoblinHead", (0,0,1.65), (.31,.28,.30), M["skin"], col)
    cone("GoblinEarL", (.33,0,1.70), .11,.01,.35, M["skin"], col, 4, (0, .8, 0))
    cone("GoblinEarR", (-.33,0,1.70), .11,.01,.35, M["skin"], col, 4, (0, -.8, 0))
    for side in (-1, 1):
        box("GoblinLeg", (side*.18,0,.42), (.13,.15,.37), M["leather"], col)
        box("GoblinArm", (side*.42,0,1.08), (.12,.13,.33), M["skin"], col, (0, side*.22, 0))
    box("GoblinClub", (.58,0,.83), (.07,.07,.60), M["wood"], col, (0, .32, 0))
    sphere("GoblinEyeL", (.11,-.25,1.69), (.045,.028,.045), M["ore"], col, 5)
    sphere("GoblinEyeR", (-.11,-.25,1.69), (.045,.028,.045), M["ore"], col, 5)


ASSETS = {
    "environment/pine_tree": pine_tree,
    "environment/dead_tree": dead_tree,
    "environment/boulder": boulder,
    "environment/ore_node": ore_node,
    "environment/grass_tuft": grass_tuft,
    "environment/mushroom_cluster": mushroom_cluster,
    "props/ancient_chest": chest,
    "props/mana_potion": potion,
    "props/campfire": campfire,
    "enemies/moss_goblin": moss_goblin,
}


def export_asset(root_dir, asset_name, build_fn):
    col = reset_collection()
    root = bpy.data.objects.new(asset_name.replace("/", "_"), None)
    col.objects.link(root)
    build_fn(col)
    for obj in col.objects:
        if obj != root and obj.parent is None:
            obj.parent = root

    bpy.ops.object.select_all(action="DESELECT")
    for obj in col.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root

    destination = os.path.join(root_dir, asset_name + ".glb")
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=destination,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print("RETRO_FANTASY_ASSET_EXPORTED: " + destination)


def main():
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not arguments:
        raise RuntimeError("Output directory missing. Use Blender -- <godot assets/models path>.")
    root_dir = os.path.abspath(arguments[0])
    for name, builder in ASSETS.items():
        export_asset(root_dir, name, builder)
    print("RETRO_FANTASY_ASSET_PACK_OK count=%d root=%s" % (len(ASSETS), root_dir))


if __name__ == "__main__":
    main()
