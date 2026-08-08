# Retro Fantasy Exploration — Roadmap

## Current build: 0.29

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

## Procedural foundation completed before 0.30

- [x] RegionCatalog is the single data source for streamed region definitions and authored slots
- [x] Generation job queue interface with frame-time budget for future threaded/background data generation
- [x] Chunk pool lifecycle wired into streamed region unload/reload
- [x] Runtime generation counters and generation budget
- [x] Stable generated entity IDs for vegetation, POIs, encounters and loot
- [x] Same world seed reproduces the same terrain and procedural exploration content
- [x] Automated determinism and runtime-foundation regression tests

## Next large package: 0.30–0.34 — Living World

- [ ] 0.30 Data-driven persistent NPC foundation with streamed regional NPC placement
- [ ] 0.31 Dialogue system with reusable conversation UI and NPC interaction
- [ ] 0.32 Quest state, objectives, rewards and first exploration quest chain
- [ ] 0.33 Merchant inventory, buying/selling and relic economy foundation
- [ ] 0.34 Faction/reputation foundation and NPC state reactions

## Later milestones

- [ ] 0.35–0.39 Dungeons, modular dungeon generation and bosses
- [ ] 0.40–0.44 Save/load and full world persistence
- [ ] 0.45–0.50 Singleplayer + 2–4 player co-op networking
- [ ] 0.51–0.59 Procedural Generation 2.0 and larger region graphs
- [ ] 0.60–0.69 Major world/content expansion
- [ ] 0.70–0.79 Progression, magic, equipment and quest chains
- [ ] 0.80–0.89 Full game progression and end-game structure
- [ ] 0.90–0.99 Beta, optimization and polish
- [ ] 1.00 Release target

Architecture principle: persistent state is stored as stable IDs and data, not scene-tree objects. Static world generation is deterministic from the world seed. Generation data is kept separate from render and physics instances. Major landmarks remain authored/module-based while terrain, nature and minor exploration content can be generated procedurally.

Design principle: exploration first, light survival, memorable landmarks, mysterious retro fantasy atmosphere.
