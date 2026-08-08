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
    |      +-- BiomeCatalog   data describing biome identity
    |      +-- WorldGenerator deterministic generation from seed
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

It currently owns:

- world seed
- current region
- discovered regions
- global progression flags
- persistent entity states
- snapshot/restore data

Examples of persistent IDs:

```text
region:blackwood
enemy:blackwood:0
chest:veilmoor:grave_ring:1
gate:moon_cathedral:west
boss:hollow_king
```

The important rule is that generated objects do not become the save format. Their stable IDs and changed state become the save format.

This also maps naturally to multiplayer later: the host/server owns WorldState and replicates state changes.

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

Future region implementations should become scenes/modules instead of adding more code to the manager.

## Biomes

`res://scripts/world/biome_catalog.gd` is data, not gameplay logic.

Biome definitions describe parameters such as:

- visual palette
- vegetation density
- rock density
- terrain character
- encounter profile

The procedural generator should consume biome data. It should not contain hard-coded checks such as `if biome == blackwood` for every object type once the system matures.

## Procedural generation

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

Changing decorative generation must not ideally reshuffle progression-critical landmarks. Separate seed namespaces should therefore be used for each generation layer.

Example:

```text
8242601:blackwood:terrain
8242601:blackwood:vegetation
8242601:blackwood:poi
8242601:blackwood:encounters
```

## Authored versus generated content

Use procedural generation for scale and authored content for meaning.

Generated:

- terrain variation
- forests
- rocks and vegetation
- minor roads
- camps
- small ruins
- optional encounters
- common loot

Authored/module-based:

- major castles
- villages
- story locations
- important dungeons
- bosses
- quest-critical spaces
- unique vistas

Major landmarks receive placement constraints from the generator rather than being generated as arbitrary geometry.

## Save/load foundation

A future save file should primarily serialize `WorldState.snapshot()` plus player progression.

Do not serialize the entire scene tree.

A loaded/generated entity checks its stable ID when entering the world:

```text
entity is generated
    -> ask WorldState for entity ID
    -> apply saved state
```

For example, a defeated enemy does not respawn just because its region was unloaded and rebuilt.

## Multiplayer foundation

The intended authority model is host/server authoritative.

Long-term rule:

```text
Server/host:
- world seed
- region state
- enemy authority
- loot authority
- progression flags
- combat validation

Clients:
- local input
- rendering
- interpolation
- UI
```

Clients may generate deterministic static world geometry from the same seed, while the host/server synchronizes mutable state.

## Performance direction

For a large world, prefer:

- region/chunk streaming
- MultiMesh for repeated vegetation
- pooled encounter objects
- LOD / visibility ranges
- collision only where gameplay needs it
- asynchronous generation where safe
- generated data separated from rendered objects

The current procedural primitives are intentionally simple. They prove lifecycle and data flow before expensive asset/content work is attached to the architecture.

## Migration rule

`world.gd` is legacy prototype composition code. Do not continue growing it indefinitely.

New large systems should live under:

```text
scripts/core/
scripts/world/
scripts/gameplay/
scripts/ui/
```

As systems mature, authored landmarks and actors should move into reusable `.tscn` scenes under:

```text
scenes/world/
scenes/actors/
scenes/landmarks/
scenes/dungeons/
```

The project can be migrated incrementally while remaining playable.
