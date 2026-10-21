extends Node
## Collect abandoned tasks on the main thread, including after a viewer closes.
var jobs: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	for index in range(jobs.size() - 1, -1, -1):
		if not jobs[index].is_alive():
			jobs[index].wait_to_finish()
			jobs.remove_at(index)

func _exit_tree() -> void:
	# Only application shutdown drains outstanding disk operations. Navigation
	# never waits for a slow filesystem, and every pool task is collected once.
	for job in jobs:
		if not job.collected:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			job.collected = true
	jobs.clear()
