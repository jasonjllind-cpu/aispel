extends RefCounted
class_name GenerationJobQueue

var jobs: Array[Dictionary] = []
var queued_ids: Dictionary = {}
var completed_jobs: int = 0
var last_batch_msec: float = 0.0

func enqueue(job_id: String, callback: Callable) -> bool:
	if job_id.is_empty() or not callback.is_valid() or queued_ids.has(job_id):
		return false
	jobs.append({"id": job_id, "callback": callback})
	queued_ids[job_id] = true
	return true

func cancel(job_id: String) -> void:
	if not queued_ids.has(job_id):
		return
	for i in range(jobs.size() - 1, -1, -1):
		if str(jobs[i].get("id", "")) == job_id:
			jobs.remove_at(i)
	queued_ids.erase(job_id)

func process_budget(max_jobs: int = 1, budget_msec: float = 4.0) -> int:
	if jobs.is_empty() or max_jobs <= 0:
		last_batch_msec = 0.0
		return 0
	var started_usec: int = Time.get_ticks_usec()
	var processed: int = 0
	while not jobs.is_empty() and processed < max_jobs:
		var elapsed_msec: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
		if processed > 0 and elapsed_msec >= budget_msec:
			break
		var job: Dictionary = jobs.pop_front()
		var job_id: String = str(job.get("id", ""))
		queued_ids.erase(job_id)
		var callback_value: Variant = job.get("callback", Callable())
		if callback_value is Callable:
			var callback: Callable = callback_value as Callable
			if callback.is_valid():
				callback.call()
				processed += 1
				completed_jobs += 1
	last_batch_msec = float(Time.get_ticks_usec() - started_usec) / 1000.0
	return processed

func pending_count() -> int:
	return jobs.size()

func clear() -> void:
	jobs.clear()
	queued_ids.clear()
	last_batch_msec = 0.0
