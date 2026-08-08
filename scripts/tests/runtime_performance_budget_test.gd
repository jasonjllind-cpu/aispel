extends SceneTree

const PERF := preload("res://scripts/core/runtime_performance_budget.gd")
const MONITOR := preload("res://scripts/core/runtime_performance_monitor.gd")

func _initialize() -> void:
	var catalog: Dictionary = PERF.validate_catalog()
	if catalog.get("valid", false) != true:
		_fail("Performance budget catalog is invalid: %s" % str(catalog.get("errors", [])))
		return
	if PERF.metric_ids().size() < 10:
		_fail("Performance budget catalog has insufficient runtime coverage")
		return

	var nominal: Dictionary = {
		"frame_p95_msec": 15.5,
		"frame_p99_msec": 18.0,
		"scene_nodes": 2400.0,
		"orphan_nodes": 2.0,
		"generated_terrain_chunks": 42.0,
		"active_enemies": 55.0,
		"interactables": 120.0,
		"generation_pending_jobs": 4.0,
		"generation_last_batch_msec": 3.0,
		"exploration_last_build_msec": 9.5,
		"terrain_pool_available": 48.0
	}
	var nominal_gate: Dictionary = PERF.evaluate(nominal)
	if nominal_gate.get("passed", false) != true or str(nominal_gate.get("status", "")) != "ok":
		_fail("Nominal runtime snapshot failed budgets: %s" % str(nominal_gate))
		return

	var warning_snapshot: Dictionary = nominal.duplicate(true)
	warning_snapshot["active_enemies"] = 100.0
	var warning_gate: Dictionary = PERF.evaluate(warning_snapshot)
	if warning_gate.get("passed", false) != true or str(warning_gate.get("status", "")) != "warning":
		_fail("Soft budget breach did not surface as warning")
		return

	var hard_snapshot: Dictionary = nominal.duplicate(true)
	hard_snapshot["active_enemies"] = 150.0
	var hard_gate: Dictionary = PERF.evaluate(hard_snapshot)
	if hard_gate.get("passed", true) != false or str(hard_gate.get("status", "")) != "hard_fail":
		_fail("Hard performance breach was not rejected")
		return
	if (hard_gate.get("hard_breaches", []) as Array).size() != 1:
		_fail("Hard breach accounting is not deterministic")
		return

	var structural: Dictionary = PERF.structural_gate(nominal)
	if structural.get("passed", false) != true or int(structural.get("evaluated_metrics", 0)) != PERF.STRUCTURAL_GATE_METRICS.size():
		_fail("Structural performance gate did not evaluate every required metric")
		return

	var monitor: Node = MONITOR.new()
	root.add_child(monitor)
	for index in range(60):
		monitor.call("record_frame_sample", 12.0 + float(index % 5) * 0.5)
	var runtime_snapshot: Dictionary = monitor.call("collect_snapshot_now")
	if int(runtime_snapshot.get("sample_count", 0)) != 60 or runtime_snapshot.get("warm", false) != true:
		monitor.free()
		_fail("Runtime monitor did not retain warm frame sample window")
		return
	if float(runtime_snapshot.get("frame_p95_msec", 99.0)) > 20.0 or float(runtime_snapshot.get("frame_p99_msec", 99.0)) > 20.0:
		monitor.free()
		_fail("Runtime monitor percentile calculation is incorrect")
		return
	var runtime_report: Dictionary = monitor.call("current_report")
	if int(runtime_report.get("evaluated_metrics", 0)) <= 0:
		monitor.free()
		_fail("Runtime monitor did not evaluate captured telemetry")
		return
	monitor.call("reset_samples")
	if not (monitor.call("current_snapshot") as Dictionary).is_empty():
		monitor.free()
		_fail("Runtime telemetry reset left stale snapshot state")
		return
	monitor.free()

	print("RUNTIME_PERFORMANCE_BUDGET_OK metrics=%d frame_samples=60" % PERF.metric_ids().size())
	quit(0)

func _fail(message: String) -> void:
	printerr("RUNTIME_PERFORMANCE_BUDGET_FAILED: %s" % message)
	quit(1)
