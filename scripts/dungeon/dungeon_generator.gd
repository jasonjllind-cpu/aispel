extends RefCounted
class_name DungeonGenerator

const DUNGEON_CATALOG := preload("res://scripts/dungeon/dungeon_catalog.gd")

var world_seed: int = 8242601

func configure(seed_value: int) -> void:
	world_seed = abs(seed_value) if seed_value != 0 else 8242601

func generation_seed(dungeon_id: String, layer_id: String) -> int:
	return int(("%d:dungeon:%s:%s" % [world_seed, dungeon_id, layer_id]).hash() & 0x7fffffff)

func generate_layout(dungeon_id: String) -> Dictionary:
	var definition: Dictionary = DUNGEON_CATALOG.get_dungeon(dungeon_id)
	if definition.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = generation_seed(dungeon_id, "layout")
	var room_count: int = max(4, int(definition.get("room_count", 7)))
	var grid_step: float = float(definition.get("grid_step", 18.0))
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var visited: Dictionary = {Vector2i.ZERO: true}
	var current := Vector2i.ZERO

	for i in range(1, room_count):
		var candidates: Array[Vector2i] = [
			current + Vector2i(0, -1),
			current + Vector2i(1, 0),
			current + Vector2i(-1, 0)
		]
		var available: Array[Vector2i] = []
		for candidate in candidates:
			if not visited.has(candidate):
				available.append(candidate)
		if available.is_empty():
			var fallback := current + Vector2i(0, -1)
			while visited.has(fallback):
				fallback += Vector2i(0, -1)
			current = fallback
		else:
			# Forward progression remains common, while side chambers keep each
			# seed recognisably different without allowing disconnected layouts.
			var choice_index: int = 0 if rng.randf() < 0.56 else rng.randi_range(0, available.size() - 1)
			current = available[choice_index]
		visited[current] = true
		cells.append(current)

	var rooms: Array[Dictionary] = []
	for i in range(cells.size()):
		var cell: Vector2i = cells[i]
		var room_type := "chamber"
		if i == 0:
			room_type = "entrance"
		elif i == cells.size() - 1:
			room_type = "boss"
		elif i == cells.size() - 2:
			room_type = "treasure"
		elif i % 3 == 0:
			room_type = "crypt"
		rooms.append({
			"id": "room:%s:%d" % [dungeon_id, i],
			"index": i,
			"type": room_type,
			"cell": cell,
			"center": Vector3(float(cell.x) * grid_step, 0.0, float(cell.y) * grid_step),
			"seed": generation_seed(dungeon_id, "room:%d" % i)
		})

	var connections: Array[Dictionary] = []
	for i in range(rooms.size() - 1):
		connections.append({
			"id": "corridor:%s:%d" % [dungeon_id, i],
			"from": i,
			"to": i + 1
		})

	var encounters: Array[Dictionary] = []
	for i in range(1, rooms.size() - 1):
		var room: Dictionary = rooms[i]
		if str(room.get("type", "")) == "treasure":
			continue
		var encounter_rng := RandomNumberGenerator.new()
		encounter_rng.seed = generation_seed(dungeon_id, "encounter:%d" % i)
		var center: Vector3 = room.get("center", Vector3.ZERO)
		encounters.append({
			"id": "enemy:dungeon:%s:%d" % [dungeon_id, i],
			"room_index": i,
			"position": center + Vector3(encounter_rng.randf_range(-2.0, 2.0), 1.0, encounter_rng.randf_range(-2.0, 2.0)),
			"profile": "catacomb_guardian"
		})

	var treasure_room: Dictionary = rooms[max(1, rooms.size() - 2)]
	var treasure_center: Vector3 = treasure_room.get("center", Vector3.ZERO)
	var loot: Array[Dictionary] = [
		{
			"id": "loot:dungeon:%s:treasure" % dungeon_id,
			"room_index": int(treasure_room.get("index", 0)),
			"position": treasure_center + Vector3(0, 0.65, 0),
			"item_name": str(definition.get("reward_item", "Moon Shard")),
			"amount": max(1, int(definition.get("reward_amount", 1)))
		}
	]

	return {
		"format_version": 1,
		"world_seed": world_seed,
		"dungeon_id": dungeon_id,
		"layout_seed": generation_seed(dungeon_id, "layout"),
		"rooms": rooms,
		"connections": connections,
		"encounters": encounters,
		"loot": loot,
		"boss_room_index": rooms.size() - 1,
		"boss_id": str(definition.get("boss_id", "boss"))
	}
