extends SceneTree

const PERF := preload("res://scripts/performance/runtime_performance_budget.gd")
const GRAPH := preload("res://scripts/world/world_graph_generator.gd")

func _init() -> void:
	var telemetry: RefCounted = PERF.new()
	telemetry.call("configure", 64)
	for index in range(60):
		var frame_ms: float = 11.0 + float(index % 6) * 0.7
		var physics_ms: float = 3.0 + float(index % 4) * 0.4
		if not bool(telemetry.call("record_frame", frame_ms, physics_ms)):
			_fail("Frame telemetry rejected valid sample")
			return
	if not bool(telemetry.call("record_runtime_counts", {
		"active_regions": 5,
		"active_generated_regions": 7,
		"active_dungeons": 1,
		"active_enemies": 42,
		"active_npcs": 64,
		"queued_generation_jobs": 9,
		"pooled_chunks": 48
	})):
		_fail("Runtime count telemetry rejected valid snapshot")
		return

	var generator: RefCounted = GRAPH.new()
	generator.call("configure", 90082601)
	var started_usec: int = Time.get_ticks_usec()
	var graph: Dictionary = generator.call("generate_graph", 128) as Dictionary
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	if (graph.get("nodes", []) as Array).size() < 128:
		_fail("Performance fixture world graph underfilled")
		return
	if not bool(telemetry.call("record", "world_graph_generation_ms", elapsed_ms)):
		_fail("World graph timing telemetry rejected valid sample")
		return

	var evaluation: Dictionary = telemetry.call("evaluate_all", false)
	if evaluation.get("passed", false) != true:
		_fail("Nominal runtime metrics exceeded budget: %s" % str(evaluation.get("violations", [])))
		return
	var frame: Dictionary = telemetry.call("summary", "frame_ms")
	if int(frame.get("sample_count", 0)) != 60 or float(frame.get("p95", 99.0)) > 20.0:
		_fail("Frame percentile aggregation is incorrect")
		return

	if not bool(telemetry.call("record", "active_enemies", 65.0)):
		_fail("Telemetry rejected over-budget sample instead of recording it")
		return
	var enemy_gate: Dictionary = telemetry.call("evaluate", "active_enemies")
	if enemy_gate.get("passed", true) != false or str(enemy_gate.get("reason", "")) != "budget_exceeded":
		_fail("Budget violation was not surfaced")
		return
	if bool(telemetry.call("record", "not_a_metric", 1.0)):
		_fail("Unknown metric was accepted")
		return
	if bool(telemetry.call("record", "frame_ms", -1.0)):
		_fail("Negative performance metric was accepted")
		return

	var snapshot: Dictionary = telemetry.call("snapshot")
	if not PERF.validate_snapshot(snapshot):
		_fail("Performance telemetry snapshot failed validation")
		return
	var all_required: Dictionary = telemetry.call("evaluate_all", true)
	if (all_required.get("results", []) as Array).size() != (telemetry.call("metric_ids") as Array).size():
		_fail("Required-metric gate did not cover every declared budget")
		return

	print("RUNTIME_PERFORMANCE_BUDGET_OK graph_ms=%.3f metrics=%d" % [elapsed_ms, (snapshot.get("metrics", {}) as Dictionary).size()])
	quit(0)

func _fail(message: String) -> void:
	printerr("RUNTIME_PERFORMANCE_BUDGET_FAILED: %s" % message)
	quit(1)
