# Architecture — Retro Fantasy Exploration

This document defines the foundation for scaling the prototype into a large exploration game without turning the project into one monolithic world script.

## Core rule

Gameplay state, world generation, region streaming and presentation are separate concerns.

The long-term dependency direction is:

```text
Game / Session
    |
    +-- WorldState            persistent authoritative state
    |
    +-- RegionManager         load/unload world regions
    |      |
    |      +-- BiomeCatalog   biome identity and generation parameters
    |      +-- WorldGenerator deterministic chunk data from world seed
    |      |      |
    |      |      +-- BiomeMap      climate sampling and transitions
    |      |      +-- TerrainChunk  render/physics instance built from data
    |      |
    |      +-- Landmarks      authored scenes / modules
    |      +-- Encounters     generated or authored encounters
    |
    +-- Player / Combat / Inventory
    |
    +-- Exploration / Quests / NPCs
```

Systems should communicate through stable IDs and public methods rather than storing direct references to distant world objects.

## WorldState

`res://scripts/core/world_state.gd` is a global service and is the source of truth for mutable world state.

It owns:

- world seed
- current region
- discovered regions
- global progression flags
- persistent entity states
- snapshot/restore data
- deterministic generation seed namespaces

Examples of persistent IDs:

```text
region:blackwood
enemy:blackwood:0
chest:veilmoor:grave_ring:1
gate:moon_cathedral:west
boss:hollow_king
```

The important rule is that generated objects do not become the save format. Their stable IDs and changed state become the save format.

This maps naturally to multiplayer later: the host/server owns WorldState and replicates state changes.

## Deterministic world seed

A world seed is a first-class part of the session. The same seed must recreate the same static generated data.

The player can change the seed through the in-game F2 World Generator panel. A seed can also be supplied as a user command-line argument:

```text
--world-seed=583921
```

The seed is split into namespaces rather than using one global random stream:

```text
world seed
  -> biome map seed
  -> region + terrain seed
  -> region + vegetation seed
  -> region + road seed
  -> region + POI seed
  -> region + encounter seed
```

This prevents a decorative generator change from unnecessarily reshuffling progression-critical content.

## RegionManager

`res://scripts/world/region_manager.gd` owns the lifecycle of large world regions.

A region has:

- stable ID
- display name
- biome ID
- world-space center
- discovery radius
- authored landmark metadata
- deterministic seed namespace

Regions are loaded near the player and unloaded when sufficiently far away. The current prototype uses generous distances, but the lifecycle is already separated from the content itself.

The next migration target is a dedicated RegionCatalog so region definitions and authored placement slots have one source of truth. Region presentation should continue moving out of RegionManager into authored modules and generation systems.

## Biomes

`res://scripts/world/biome_catalog.gd` is data, not gameplay logic.

Biome definitions describe parameters such as:

- visual palette
- vegetation density
- rock density
- elevation character
- terrain scale/detail/ridge character
- encounter profile

`res://scripts/world/biome_map.gd` samples deterministic climate fields and produces a primary biome, secondary biome and blend amount. Regions keep a strong authored biome identity while borders can acquire deterministic secondary-biome influence.

## World Generator 1.0

`res://scripts/world/world_generator.gd` produces generation data. It does not directly create scene-tree objects.

The generator currently produces terrain chunk dictionaries containing:

- format version
- region ID
- chunk coordinate
- deterministic generation seed
- vertices
- normals
- vertex colors
- triangle indices
- collision faces
- biome sample metadata

This separation is deliberate. Future background worker threads should be able to produce chunk data without touching the scene tree. The main thread can then hand completed data to a renderer/physics instance.

## TerrainChunk runtime

`res://scripts/world/terrain_chunk.gd` consumes generated chunk data and owns only runtime representation:

- ArrayMesh rendering
- vertex-color terrain material
- concave terrain collision
- reset/pool lifecycle hooks

Generated data and scene objects must remain separate. Save files, multiplayer state and deterministic generation should never depend on MeshInstance3D or StaticBody3D identities.

## ProceduralWorldSystem

`res://scripts/world/procedural_world_system.gd` bridges streamed regions and WorldGenerator 1.0.

It currently:

- detects loaded streamed regions
- requests deterministic chunk data
- caches generated data separately from scene instances
- creates terrain chunk runtime nodes
- reserves flattened slots for authored landmarks
- exposes deterministic layer seed lookups for later vegetation/road/POI generators

The starting valley remains authored while streamed outer regions demonstrate generated terrain. This is intentional during migration: authored content stays playable while the procedural foundation replaces prototype region surfaces layer by layer.

## Landmark reservation

Major authored content must survive procedural generation.

Each landmark can reserve a local slot containing:

```text
stable slot ID
local center
radius
transition feather
required surface height
```

Terrain generation flattens or blends toward the required height inside that slot. The same concept will later protect roads, settlements, dungeon entrances, boss arenas and quest-critical locations.

## Chunk lifecycle

The initial generated region uses reusable terrain chunks. Current chunks are small enough for synchronous generation, but the data boundary is designed for the later pipeline:

```text
request chunk
  -> generation job queue
  -> worker produces chunk data
  -> main-thread build budget
  -> TerrainChunk instance
  -> active
  -> release / pool
```

Before large-world production, the project should add a generation job queue, active build budget, runtime metrics and a wired chunk pool.

## Procedural generation rules

Generation must be deterministic.

```text
World seed
  -> region seed
      -> terrain seed
      -> vegetation seed
      -> road seed
      -> POI seed
      -> encounter seed
```

Changing decorative generation should not ideally reshuffle progression-critical landmarks. Separate seed namespaces are therefore mandatory for each generation layer.

Use procedural generation for scale and authored content for meaning.

Generated:

- terrain variation
- forests and vegetation
- rocks and ground clutter
- roads between known anchors
- minor ruins and camps
- non-critical encounters
- exploration loot and secrets

Authored/module-based:

- major castles
- villages
- story dungeons
- bosses
- major quest locations
- strong vista compositions

## Multiplayer direction

Do not network generated meshes as gameplay state.

The future host/server should own:

- world seed
- authoritative WorldState
- generated entity IDs
- changed states such as dead/open/unlocked/collected

Clients can reconstruct deterministic static world data from the same seed and receive authoritative state changes. This keeps network traffic focused on changes rather than world geometry.

## Performance direction

Large-world work should follow these priorities:

1. Stream regions and chunks instead of keeping the world loaded.
2. Generate data separately from scene objects.
3. Pool repeatable runtime objects.
4. Use MultiMesh for high-count decorative vegetation where suitable.
5. Apply per-frame build budgets so generation does not cause long stalls.
6. Profile before increasing chunk resolution or active radius.
7. Keep critical gameplay state independent from decoration.

The project should prefer predictable bounded systems over clever systems with unbounded cost.
