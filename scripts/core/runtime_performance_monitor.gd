extends Node
class_name RuntimePerformanceMonitor

signal snapshot_updated(snapshot: Dictionary)
signal hard_budget_breached(report: Dictionary)

const BUDGET := preload("res://scripts/core/runtime_performance_budget.gd")
const SAMPLE_WINDOW: int = 240
const REFRESH_INTERVAL: float = 0.50
const WARMUP_SAMPLES: int = 30

var frame_samples_msec: Array[float] = []
var refresh_elapsed: float = 0.0
var latest_snapshot: Dictionary = {}
var latest_report: Dictionary = {}
var sample_revision: int = 0
var hard_breach_latched: bool = false

func _ready() -> void:
	add_to_group("runtime_performance_monitor")
	set_process(true)

func _process(delta: float) -> void:
	record_frame_sample(delta * 1000.0)
	refresh_elapsed += delta
	if refresh_elapsed < REFRESH_INTERVAL:
		return
	refresh_elapsed = 0.0
	collect_snapshot_now()

func record_frame_sample(frame_msec: float) -> void:
	if frame_msec <= 0.0 or is_nan(frame_msec) or is_inf(frame_msec):
		return
	frame_samples_msec.append(frame_msec)
	while frame_samples_msec.size() > SAMPLE_WINDOW:
		frame_samples_msec.pop_front()

func collect_snapshot_now() -> Dictionary:
	sample_revision += 1
	var snapshot: Dictionary = {
		"format_version": 1,
		"revision": sample_revision,
		"sample_count": frame_samples_msec.size(),
		"warm": frame_samples_msec.size() >= WARMUP_SAMPLES,
		"frame_p50_msec": _percentile(frame_samples_msec, 0.50),
		"frame_p95_msec": _percentile(frame_samples_msec, 0.95),
		"frame_p99_msec": _percentile(frame_samples_msec, 0.99),
		"scene_nodes": float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": float(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"generated_terrain_chunks": float(get_tree().get_nodes_in_group("generated_terrain_chunk").size()),
		"active_enemies": float(get_tree().get_nodes_in_group("enemy").size()),
		"interactables": float(get_tree().get_nodes_in_group("interactable").size()),
		"generation_pending_jobs": 0.0,
		"generation_last_batch_msec": 0.0,
		"exploration_last_build_msec": 0.0,
		"terrain_pool_available": 0.0
	}
	_collect_generation_metrics(snapshot)
	latest_snapshot = snapshot
	var gate_metrics: Array[String] = BUDGET.metric_ids()
	if frame_samples_msec.size() < WARMUP_SAMPLES:
		gate_metrics.erase("frame_p95_msec")
		gate_metrics.erase("frame_p99_msec")
	latest_report = BUDGET.evaluate(snapshot, gate_metrics)
	latest_snapshot["budget_status"] = str(latest_report.get("status", "unknown"))
	latest_snapshot["hard_breach_count"] = (latest_report.get("hard_breaches", []) as Array).size()
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

func structural_gate_now() -> Dictionary:
	var snapshot: Dictionary = collect_snapshot_now()
	return BUDGET.structural_gate(snapshot)

func reset_samples() -> void:
	frame_samples_msec.clear()
	refresh_elapsed = 0.0
	latest_snapshot.clear()
	latest_report.clear()
	sample_revision = 0
	hard_breach_latched = false

func _collect_generation_metrics(snapshot: Dictionary) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var exploration: Node = parent.get_node_or_null("ProceduralExplorationSystem")
	if exploration != null:
		var queue_value: Variant = exploration.get("job_queue")
		if queue_value != null:
			var queue: Object = queue_value as Object
			if queue.has_method("pending_count"):
				snapshot["generation_pending_jobs"] = float(queue.call("pending_count"))
			var batch_value: Variant = queue.get("last_batch_msec")
			if batch_value is int or batch_value is float:
				snapshot["generation_last_batch_msec"] = float(batch_value)
		var build_value: Variant = exploration.get("last_build_msec")
		if build_value is int or build_value is float:
			snapshot["exploration_last_build_msec"] = float(build_value)
	var procedural_world: Node = parent.get_node_or_null("ProceduralWorldSystem")
	if procedural_world != null and procedural_world.has_method("get_pool_stats"):
		var pool_value: Variant = procedural_world.call("get_pool_stats")
		if pool_value is Dictionary:
			snapshot["terrain_pool_available"] = float((pool_value as Dictionary).get("available", 0))

func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var index: int = clampi(int(ceil(clampf(percentile, 0.0, 1.0) * float(sorted_values.size()))) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]
