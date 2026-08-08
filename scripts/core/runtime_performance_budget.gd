extends RefCounted
class_name RuntimePerformanceBudget

const FORMAT_VERSION: int = 1

const BUDGETS: Dictionary = {
	"frame_p95_msec": {"soft": 20.0, "hard": 33.4, "unit": "ms", "direction": "max"},
	"frame_p99_msec": {"soft": 28.0, "hard": 50.0, "unit": "ms", "direction": "max"},
	"scene_nodes": {"soft": 4500.0, "hard": 7000.0, "unit": "nodes", "direction": "max"},
	"orphan_nodes": {"soft": 12.0, "hard": 64.0, "unit": "nodes", "direction": "max"},
	"generated_terrain_chunks": {"soft": 96.0, "hard": 160.0, "unit": "chunks", "direction": "max"},
	"active_enemies": {"soft": 80.0, "hard": 140.0, "unit": "actors", "direction": "max"},
	"interactables": {"soft": 180.0, "hard": 320.0, "unit": "nodes", "direction": "max"},
	"generation_pending_jobs": {"soft": 8.0, "hard": 24.0, "unit": "jobs", "direction": "max"},
	"generation_last_batch_msec": {"soft": 4.5, "hard": 8.0, "unit": "ms", "direction": "max"},
	"exploration_last_build_msec": {"soft": 14.0, "hard": 32.0, "unit": "ms", "direction": "max"},
	"terrain_pool_available": {"soft": 64.0, "hard": 64.0, "unit": "chunks", "direction": "max"}
}

const STRUCTURAL_GATE_METRICS: Array[String] = [
	"scene_nodes",
	"orphan_nodes",
	"generated_terrain_chunks",
	"active_enemies",
	"interactables",
	"generation_pending_jobs",
	"terrain_pool_available"
]

static func metric_ids() -> Array[String]:
	var result: Array[String] = []
	for metric_id in BUDGETS.keys():
		result.append(str(metric_id))
	result.sort()
	return result

static func get_budget(metric_id: String) -> Dictionary:
	if not BUDGETS.has(metric_id):
		return {}
	var result: Dictionary = (BUDGETS[metric_id] as Dictionary).duplicate(true)
	result["metric_id"] = metric_id
	return result

static func validate_catalog() -> Dictionary:
	var errors: Array[String] = []
	for metric_id in metric_ids():
		var budget: Dictionary = get_budget(metric_id)
		var direction: String = str(budget.get("direction", ""))
		if not ["max", "min"].has(direction):
			errors.append("invalid direction: %s" % metric_id)
			continue
		var soft: float = float(budget.get("soft", 0.0))
		var hard: float = float(budget.get("hard", 0.0))
		if soft < 0.0 or hard < 0.0:
			errors.append("negative budget: %s" % metric_id)
		elif direction == "max" and hard < soft:
			errors.append("hard max below soft max: %s" % metric_id)
		elif direction == "min" and hard > soft:
			errors.append("hard min above soft min: %s" % metric_id)
		if str(budget.get("unit", "")).is_empty():
			errors.append("missing unit: %s" % metric_id)
	return {"valid": errors.is_empty(), "errors": errors}

static func evaluate(metrics: Dictionary, selected_metric_ids: Array[String] = []) -> Dictionary:
	var ids: Array[String] = selected_metric_ids.duplicate() if not selected_metric_ids.is_empty() else metric_ids()
	ids.sort()
	var soft_breaches: Array[Dictionary] = []
	var hard_breaches: Array[Dictionary] = []
	var evaluated: int = 0
	for metric_id in ids:
		if not BUDGETS.has(metric_id) or not metrics.has(metric_id):
			continue
		var value_variant: Variant = metrics.get(metric_id)
		if not (value_variant is int or value_variant is float):
			continue
		var value: float = float(value_variant)
		var budget: Dictionary = get_budget(metric_id)
		var soft: float = float(budget.get("soft", 0.0))
		var hard: float = float(budget.get("hard", 0.0))
		var direction: String = str(budget.get("direction", "max"))
		evaluated += 1
		var hard_failed: bool = value > hard if direction == "max" else value < hard
		var soft_failed: bool = value > soft if direction == "max" else value < soft
		if hard_failed:
			hard_breaches.append(_breach(metric_id, value, budget, "hard"))
		elif soft_failed:
			soft_breaches.append(_breach(metric_id, value, budget, "soft"))
	var status: String = "hard_fail" if not hard_breaches.is_empty() else ("warning" if not soft_breaches.is_empty() else "ok")
	return {
		"format_version": FORMAT_VERSION,
		"status": status,
		"passed": hard_breaches.is_empty(),
		"evaluated_metrics": evaluated,
		"soft_breaches": soft_breaches,
		"hard_breaches": hard_breaches
	}

static func structural_gate(metrics: Dictionary) -> Dictionary:
	return evaluate(metrics, STRUCTURAL_GATE_METRICS)

static func _breach(metric_id: String, value: float, budget: Dictionary, severity: String) -> Dictionary:
	return {
		"metric_id": metric_id,
		"value": value,
		"soft": float(budget.get("soft", 0.0)),
		"hard": float(budget.get("hard", 0.0)),
		"unit": str(budget.get("unit", "")),
		"direction": str(budget.get("direction", "max")),
		"severity": severity
	}
