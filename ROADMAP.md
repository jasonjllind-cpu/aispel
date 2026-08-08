# Retro Fantasy Exploration — Roadmap

## Current build: 0.20

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

## Next large package: 0.21–0.24 — World Generator 1.0

- [ ] Player-selectable / generated world seed
- [ ] Deterministic generation namespaces per region and generation layer
- [ ] Noise-based terrain height data rather than flat region platforms
- [ ] Biome-map generation and biome transition rules
- [ ] Generated terrain mesh with reusable chunk data
- [ ] Separate generation data from render/physics instances
- [ ] Chunk lifecycle ready for background generation and pooling
- [ ] Preserve authored landmark placement slots inside generated regions

## 0.25–0.29 — Procedural Exploration

- [ ] Procedural forests and vegetation using MultiMesh where appropriate
- [ ] Procedural roads connecting landmarks and region exits
- [ ] Placement rules for minor ruins, camps, cave mouths and secrets
- [ ] Deterministic encounter and loot placement
- [ ] Point-of-interest spacing and sightline rules so exploration feels intentional
- [ ] World regeneration from the same seed produces the same world

## Later milestones

- [ ] 0.30–0.34 NPCs, merchants, dialogue, quests and factions
- [ ] 0.35–0.39 Dungeons, modular dungeon generation and bosses
- [ ] 0.40–0.44 Save/load and full world persistence
- [ ] 0.45–0.50 Singleplayer + 2–4 player co-op networking
- [ ] 0.51–0.59 Procedural Generation 2.0 and larger region graphs
- [ ] 0.60–0.69 Major world/content expansion
- [ ] 0.70–0.79 Progression, magic, equipment and quest chains
- [ ] 0.80–0.89 Full game progression and end-game structure
- [ ] 0.90–0.99 Beta, optimization and polish
- [ ] 1.00 Release target

Architecture principle: persistent state is stored as stable IDs and data, not scene-tree objects. Static world generation is deterministic from the world seed. Major landmarks remain authored/module-based while terrain, nature and minor exploration content can be generated procedurally.

Design principle: exploration first, light survival, memorable landmarks, mysterious retro fantasy atmosphere.
