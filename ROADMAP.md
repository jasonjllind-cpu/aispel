# Retro Fantasy Exploration — Roadmap

## Current build: 0.69

- [x] 0.01 Third-person movement and camera
- [x] 0.02 Retro rendering baseline
- [x] 0.03 First exploration area
- [x] 0.04 Interaction and loot
- [x] 0.05 First enemies
- [x] 0.06 Combat, health, enemy attacks and death
- [x] 0.07 Inventory UI and item database
- [x] 0.08 Equipment, weapon/armor stats and first low-poly humanoid art pass
- [x] 0.09 Retro pixel material set and stronger fantasy palette
- [x] 0.10 World art pass: curved road, layered landscape, mountain silhouettes, vegetation and props
- [x] 0.11 Landmark pass: ruined keep, gate towers, watchtower, moon shrine and torch lighting
- [x] 0.12 Character art and procedural movement animation polish
- [x] 0.13 Discoverable named locations and exploration notifications
- [x] 0.14 Secrets, Old Key progression and treasure containers
- [x] 0.15 Moon Shrine checkpoint, healing and respawn progression
- [x] 0.16 Whispering Crypt interior, hidden reliquary and additional world encounters
- [x] 0.17 Region lifecycle and streamed world foundation
- [x] 0.18 Distinct Blackwood, Windscar Highlands and Veilmoor biome regions
- [x] 0.19 Connected routes, regional landmarks and encounter profiles
- [x] 0.20 Global WorldState foundation for deterministic seeds, persistence and future multiplayer authority
- [x] 0.21 Player-selectable world seeds, random seeds and generation namespaces
- [x] 0.22 Deterministic noise-based terrain data with biome-driven height character
- [x] 0.23 Reusable terrain chunks with generation data separated from render and collision instances
- [x] 0.24 Deterministic biome-map sampling, blended biome transitions and reserved authored landmark slots
- [x] 0.25 Procedural forests, rocks and biome vegetation with MultiMesh presentation
- [x] 0.26 Deterministic roads connecting region entries, landmarks and exits
- [x] 0.27 Spaced minor ruins, camps, cave mouths, grave sites and secrets
- [x] 0.28 Deterministic generated encounters, loot and stable persistent entity IDs
- [x] 0.29 Procedural exploration runtime, RegionCatalog, generation budget/job queue, chunk pooling and reusable authored landmark modules

## Living World — 0.30–0.34

- [x] 0.30 Data-driven persistent NPC foundation with streamed regional NPC placement
- [x] 0.31 Dialogue system with reusable conversation UI and NPC interaction
- [x] 0.32 Quest state, objectives, rewards and first exploration quest chain
- [x] 0.33 Merchant inventory, buying/selling and relic economy foundation
- [x] 0.34 Faction/reputation foundation and NPC state reactions

## Dungeons — 0.35–0.39

- [x] 0.35–0.39 Deterministic modular dungeon generation, streamed dungeon runtime, persistent dungeon state, portals, treasure and boss foundation

## Persistence — 0.40–0.44

- [x] 0.40–0.44 Versioned atomic save files, corruption handling, automatic full-session persistence and restoration across world/dungeon state

## Co-op Networking — 0.45–0.50

- [x] 0.45–0.50 Server-authoritative 2–4 player session foundation with Host/Join UI, command routing, player ownership/state replication, WorldState deltas, authoritative combat and enemy replication

## Procedural Generation 2.0 — 0.51–0.59

- [x] 0.51 Scalable deterministic macro world graph, procedural region template catalog and streamed generated-region lifecycle
- [x] 0.52 Deterministic graph topology metadata: neighbour IDs, degree, shortest-path depth, progression bands and route depth
- [x] 0.53 Graph-aware deterministic region content profiles driven by biome and progression depth
- [x] 0.54 Route hierarchy, gateways and deterministic shortcut candidates
- [x] 0.55 Hierarchical subregion graphs for larger regions without increasing active scene-tree cost
- [x] 0.56 Streaming priority derived from graph topology, player route and generation budget
- [x] 0.57 Deterministic landmark/settlement distribution constraints across the macro graph
- [x] 0.58 Multi-scale world regeneration tests and large-seed stress coverage
- [x] 0.59 Procedural Generation 2.0 integration/polish pass and performance gates

## Major World & Content Expansion — 0.60–0.69

- [x] 0.60 Ashen Fen and Frostmere biome expansion across climate mapping, region templates, content profiles and deterministic theme palettes
- [x] 0.61 Data-driven regional encounter archetypes and deterministic encounter composition plans
- [x] 0.62 Regional loot tables, rarity bands and progression-aware reward plans
- [x] 0.63 Expanded minor POI archetypes and theme-aware placement rules
- [x] 0.64 Settlement archetypes, services and deterministic population profiles
- [x] 0.65 Regional dungeon entrance families and dungeon-theme routing
- [x] 0.66 World-event archetypes with deterministic regional scheduling/state IDs
- [x] 0.67 Lore discovery catalog: shrines, inscriptions, relic records and region history fragments
- [x] 0.68 Content-density balancing across biomes/progression bands with large-world coverage gates
- [x] 0.69 Major World & Content Expansion integration/polish pass with unified deterministic RegionContentBundle

## Progression, Magic, Equipment & Quest Chains — 0.70–0.79

- [ ] 0.70 Persistent player progression state, XP/level curves and progression rewards
- [ ] 0.71 Data-driven spell catalog, schools, resource costs and casting contracts
- [ ] 0.72 Equipment progression, rarity tiers, stat scaling and deterministic item rolls
- [ ] 0.73 Quest-chain graph with prerequisites, branching objectives and stable progression IDs
- [ ] 0.74 Magic-school progression, unlocks and world/quest discovery integration
- [ ] 0.75 Regional progression gates and rewards connected to encounters, dungeons and exploration content
- [ ] 0.76 Character build/loadout model integrating equipment, magic and derived combat stats
- [ ] 0.77 Authoritative co-op replication for progression, equipment, spells and quest-chain state
- [ ] 0.78 Save migration, balance coverage and end-to-end progression regression gates
- [ ] 0.79 Progression/Magic/Equipment/Quest Chains integration and polish pass

## Verified architecture foundations

- [x] RegionCatalog is the single data source for streamed authored region definitions and slots
- [x] Generation job queue interface with frame-time budget
- [x] Chunk pool lifecycle wired into streamed region unload/reload
- [x] Runtime generation counters and generation budget
- [x] Stable generated entity IDs for vegetation, POIs, encounters and loot
- [x] Same world seed reproduces the same terrain and procedural exploration content
- [x] Automated generation, world graph, Living World, dungeon, save/persistence, networking and content-expansion regression tests
- [x] Main-scene headless Godot smoke test

## Later milestones

- [ ] 0.80–0.89 Full game progression and end-game structure
- [ ] 0.90–0.99 Beta, optimization and polish
- [ ] 1.00 Release target

Architecture principle: persistent state is stored as stable IDs and data, not scene-tree objects. Static world generation is deterministic from the world seed. Generation data is kept separate from render and physics instances. Major landmarks remain authored/module-based while terrain, nature and minor exploration content can be generated procedurally. Network authority owns mutable gameplay state while clients may reconstruct deterministic static world data.

Design principle: exploration first, light survival, memorable landmarks, mysterious retro fantasy atmosphere.
