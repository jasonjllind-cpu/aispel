extends Node
class_name RuntimePerformanceMonitor

signal snapshot_updated(snapshot: Dictionary)
signal hard_budget_breached(report: Dictionary)

const PERFORMANCE_TELEMETRY := preload("res://scripts/performance/runtime_performance_budget.gd")
const REFRESH_INTERVAL: float = 0.50

var telemetry: RefCounted
var refresh_elapsed: float = 0.0
var latest_snapshot: Dictionary = {}
var latest_report: Dictionary = {}
var hard_breach_latched: bool = false

func _ready() -> void:
	add_to_group("runtime_performance_monitor")
	telemetry = PERFORMANCE_TELEMETRY.new()
	telemetry.call("configure", PERFORMANCE_TELEMETRY.DEFAULT_WINDOW_SIZE)
	set_process(true)

func _process(delta: float) -> void:
	if telemetry == null:
		return
	var physics_msec: float = maxf(0.0, float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	telemetry.call("record_frame", maxf(0.001, delta * 1000.0), physics_msec)
	refresh_elapsed += delta
	if refresh_elapsed < REFRESH_INTERVAL:
		return
	refresh_elapsed = 0.0
	collect_snapshot_now()

func collect_snapshot_now() -> Dictionary:
	if telemetry == null:
		telemetry = PERFORMANCE_TELEMETRY.new()
		telemetry.call("configure", PERFORMANCE_TELEMETRY.DEFAULT_WINDOW_SIZE)
	var counts: Dictionary = _runtime_counts()
	telemetry.call("record_runtime_counts", counts)
	latest_snapshot = telemetry.call("snapshot") as Dictionary
	latest_snapshot["runtime"] = _runtime_details(counts)
	latest_report = telemetry.call("evaluate_all", false) as Dictionary
	latest_snapshot["evaluation"] = latest_report.duplicate(true)
	snapshot_updated.emit(latest_snapshot.duplicate(true))
	if latest_report.get("passed", true) != true:
		if not hard_breach_latched:
			hard_breach_latched = true
			hard_budget_breached.emit(latest_report.duplicate(true))
	else:
		hard_breach_latched = false
	return latest_snapshot.duplicate(true)

func current_snapshot() -> Dictionary:
	return latest_snapshot.duplicate(true)

func current_report() -> Dictionary:
	return latest_report.duplicate(true)

func reset_samples() -> void:
	if telemetry == null:
		telemetry = PERFORMANCE_TELEMETRY.new()
	telemetry.call("configure", PERFORMANCE_TELEMETRY.DEFAULT_WINDOW_SIZE)
	refresh_elapsed = 0.0
	latest_snapshot.clear()
	latest_report.clear()
	hard_breach_latched = false

func _runtime_counts() -> Dictionary:
	var tree: SceneTree = get_tree()
	var counts: Dictionary = {
		"active_regions": 1,
		"active_generated_regions": 0,
		"active_dungeons": 0,
		"active_enemies": 0,
		"active_npcs": 0,
		"queued_generation_jobs": 0,
		"pooled_chunks": 0
	}
	if tree == null:
		return counts
	counts["active_generated_regions"] = tree.get_nodes_in_group("generated_exploration_root").size()
	counts["active_dungeons"] = tree.get_nodes_in_group("dungeon_runtime").size()
	counts["active_enemies"] = tree.get_nodes_in_group("enemy").size()
	counts["active_npcs"] = tree.get_nodes_in_group("npc").size()

	var parent: Node = get_parent()
	if parent == null:
		return counts
	var runtime_regions: Node = parent.get_node_or_null("RuntimeRegions")
	if runtime_regions != null:
		counts["active_regions"] = 1 + runtime_regions.get_child_count()
	var exploration: Node = parent.get_node_or_null("ProceduralExplorationSystem")
	if exploration != null:
		var queue_value: Variant = exploration.get("job_queue")
		if queue_value is Object and (queue_value as Object).has_method("pending_count"):
			counts["queued_generation_jobs"] = int((queue_value as Object).call("pending_count"))
	var procedural_world: Node = parent.get_node_or_null("ProceduralWorldSystem")
	if procedural_world != null and procedural_world.has_method("get_pool_stats"):
		var pool_value: Variant = procedural_world.call("get_pool_stats")
		if pool_value is Dictionary:
			counts["pooled_chunks"] = int((pool_value as Dictionary).get("available", 0))
	return counts

func _runtime_details(counts: Dictionary) -> Dictionary:
	var tree: SceneTree = get_tree()
	var details: Dictionary = {
		"scene_nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"generated_terrain_chunks": 0,
		"interactables": 0,
		"generation_last_batch_msec": 0.0,
		"exploration_last_build_msec": 0.0,
		"counts": counts.duplicate(true)
	}
	if tree != null:
		details["generated_terrain_chunks"] = tree.get_nodes_in_group("generated_terrain_chunk").size()
		details["interactables"] = tree.get_nodes_in_group("interactable").size()
	var parent: Node = get_parent()
	if parent == null:
		return details
	var exploration: Node = parent.get_node_or_null("ProceduralExplorationSystem")
	if exploration != null:
		var queue_value: Variant = exploration.get("job_queue")
		if queue_value is Object:
			var batch_value: Variant = (queue_value as Object).get("last_batch_msec")
			if batch_value is int or batch_value is float:
				details["generation_last_batch_msec"] = float(batch_value)
		var build_value: Variant = exploration.get("last_build_msec")
		if build_value is int or build_value is float:
			details["exploration_last_build_msec"] = float(build_value)
	return details
