extends RefCounted
class_name BoundedGenerationCache

const DEFAULT_CAPACITY: int = 256

var capacity: int = DEFAULT_CAPACITY
var values: Dictionary = {}
var access_order: Array[String] = []
var hits: int = 0
var misses: int = 0
var evictions: int = 0

func _init(max_entries: int = DEFAULT_CAPACITY) -> void:
	capacity = maxi(1, max_entries)

func has(key: String) -> bool:
	return values.has(key)

func get_value(key: String) -> Dictionary:
	if not values.has(key):
		misses += 1
		return {}
	hits += 1
	_touch(key)
	var value: Variant = values[key]
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func put(key: String, value: Dictionary) -> void:
	if values.has(key):
		values[key] = value.duplicate(true)
		_touch(key)
		return
	values[key] = value.duplicate(true)
	access_order.append(key)
	while values.size() > capacity:
		var oldest: String = access_order.pop_front()
		if values.erase(oldest):
			evictions += 1

func clear() -> void:
	values.clear()
	access_order.clear()

func size() -> int:
	return values.size()

func stats() -> Dictionary:
	return {
		"size": values.size(),
		"capacity": capacity,
		"hits": hits,
		"misses": misses,
		"evictions": evictions
	}

func _touch(key: String) -> void:
	var index: int = access_order.find(key)
	if index >= 0:
		access_order.remove_at(index)
	access_order.append(key)
