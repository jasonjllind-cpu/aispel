extends RefCounted
class_name RuntimePerformanceBudget

const FORMAT_VERSION: int = 1
const DEFAULT_WINDOW_SIZE: int = 240

const BUDGETS: Dictionary = {
	"frame_ms": {"aggregation": "p95", "limit": 20.0, "unit": "ms"},
	"frame_peak_ms": {"aggregation": "max", "limit": 50.0, "unit": "ms"},
	"physics_ms": {"aggregation": "p95", "limit": 12.0, "unit": "ms"},
	"world_graph_generation_ms": {"aggregation": "max", "limit": 5000.0, "unit": "ms"},
	"active_regions": {"aggregation": "max", "limit": 7.0, "unit": "count"},
	"active_generated_regions": {"aggregation": "max", "limit": 9.0, "unit": "count"},
	"active_dungeons": {"aggregation": "max", "limit": 2.0, "unit": "count"},
	"active_enemies": {"aggregation": "max", "limit": 64.0, "unit": "count"},
	"active_npcs": {"aggregation": "max", "limit": 96.0, "unit": "count"},
	"queued_generation_jobs": {"aggregation": "max", "limit": 24.0, "unit": "count"},
	"pooled_chunks": {"aggregation": "max", "limit": 96.0, "unit": "count"}
}

var _window_size: int = DEFAULT_WINDOW_SIZE
var _samples: Dictionary = {}
var _sequence: int = 0

func configure(window_size: int = DEFAULT_WINDOW_SIZE) -> void:
	_window_size = clampi(window_size, 16, 4096)
	_samples.clear()
	_sequence = 0

func metric_ids() -> Array[String]:
	var result: Array[String] = []
	for metric_id in BUDGETS.keys():
		result.append(str(metric_id))
	result.sort()
	return result

func record(metric_id: String, value: float) -> bool:
	if not BUDGETS.has(metric_id) or not is_finite(value) or value < 0.0:
		return false
	var values: Array = _samples.get(metric_id, []) as Array
	values.append(value)
	while values.size() > _window_size:
		values.pop_front()
	_samples[metric_id] = values
	_sequence += 1
	return true

func record_frame(frame_ms: float, physics_ms: float) -> bool:
	if not record("frame_ms", frame_ms):
		return false
	if not record("frame_peak_ms", frame_ms):
		return false
	return record("physics_ms", physics_ms)

func record_runtime_counts(counts: Dictionary) -> bool:
	var mapping: Dictionary = {
		"active_regions": "active_regions",
		"active_generated_regions": "active_generated_regions",
		"active_dungeons": "active_dungeons",
		"active_enemies": "active_enemies",
		"active_npcs": "active_npcs",
		"queued_generation_jobs": "queued_generation_jobs",
		"pooled_chunks": "pooled_chunks"
	}
	for source_key in mapping.keys():
		if not counts.has(source_key):
			continue
		if not record(str(mapping[source_key]), float(counts[source_key])):
			return false
	return true

func summary(metric_id: String) -> Dictionary:
	if not BUDGETS.has(metric_id):
		return {}
	var values: Array = _samples.get(metric_id, []) as Array
	if values.is_empty():
		return {
			"metric_id": metric_id,
			"sample_count": 0,
			"average": 0.0,
			"p95": 0.0,
			"max": 0.0,
			"budget": (BUDGETS[metric_id] as Dictionary).duplicate(true)
		}
	var sorted: Array[float] = []
	var total: float = 0.0
	var maximum: float = 0.0
	for value in values:
		var numeric: float = float(value)
		sorted.append(numeric)
		total += numeric
		maximum = maxf(maximum, numeric)
	sorted.sort()
	var p95_index: int = clampi(ceili(float(sorted.size()) * 0.95) - 1, 0, sorted.size() - 1)
	return {
		"metric_id": metric_id,
		"sample_count": sorted.size(),
		"average": total / float(sorted.size()),
		"p95": sorted[p95_index],
		"max": maximum,
		"budget": (BUDGETS[metric_id] as Dictionary).duplicate(true)
	}

func evaluate(metric_id: String) -> Dictionary:
	var stats: Dictionary = summary(metric_id)
	if stats.is_empty():
		return {"metric_id": metric_id, "passed": false, "reason": "unknown_metric"}
	var budget: Dictionary = stats.get("budget", {}) as Dictionary
	var aggregation: String = str(budget.get("aggregation", "max"))
	var measured: float = float(stats.get(aggregation, 0.0))
	var limit: float = float(budget.get("limit", 0.0))
	var has_samples: bool = int(stats.get("sample_count", 0)) > 0
	return {
		"metric_id": metric_id,
		"passed": has_samples and measured <= limit,
		"reason": "" if has_samples and measured <= limit else ("no_samples" if not has_samples else "budget_exceeded"),
		"aggregation": aggregation,
		"measured": measured,
		"limit": limit,
		"unit": str(budget.get("unit", "")),
		"sample_count": int(stats.get("sample_count", 0))
	}

func evaluate_all(require_all_metrics: bool = false) -> Dictionary:
	var results: Array[Dictionary] = []
	var violations: Array[Dictionary] = []
	for metric_id in metric_ids():
		var values: Array = _samples.get(metric_id, []) as Array
		if values.is_empty() and not require_all_metrics:
			continue
		var result: Dictionary = evaluate(metric_id)
		results.append(result)
		if not bool(result.get("passed", false)):
			violations.append(result)
	return {
		"format_version": FORMAT_VERSION,
		"passed": violations.is_empty(),
		"sequence": _sequence,
		"results": results,
		"violations": violations
	}

func snapshot() -> Dictionary:
	var metrics: Dictionary = {}
	for metric_id in metric_ids():
		var values: Array = _samples.get(metric_id, []) as Array
		if values.is_empty():
			continue
		metrics[metric_id] = summary(metric_id)
	return {
		"format_version": FORMAT_VERSION,
		"sequence": _sequence,
		"window_size": _window_size,
		"metrics": metrics,
		"evaluation": evaluate_all(false)
	}

static func validate_snapshot(data: Dictionary) -> bool:
	if int(data.get("format_version", -1)) != FORMAT_VERSION or int(data.get("sequence", -1)) < 0:
		return false
	if int(data.get("window_size", 0)) < 16:
		return false
	var metrics_value: Variant = data.get("metrics", {})
	if not metrics_value is Dictionary:
		return false
	for metric_id in (metrics_value as Dictionary).keys():
		if not BUDGETS.has(str(metric_id)):
			return false
		var stats: Variant = (metrics_value as Dictionary)[metric_id]
		if not stats is Dictionary or int((stats as Dictionary).get("sample_count", 0)) <= 0:
			return false
	return data.get("evaluation", {}) is Dictionary
