extends RefCounted
## Pool tasks retain this job, never the viewer. Closing a menu never joins I/O.
var task_id := -1
var result
var collected := false
static var keeper: Node
var mutex := Mutex.new()
var cancelled := false

func cancel() -> void:
	mutex.lock()
	cancelled = true
	mutex.unlock()

func is_cancelled() -> bool:
	mutex.lock()
	var value := cancelled
	mutex.unlock()
	return value

func start(operation: Callable) -> Error:
	if not is_instance_valid(keeper):
		keeper = load("res://src/game/replay_task_keeper.gd").new()
		keeper.name = "ReplayTasks"
		Engine.get_main_loop().root.add_child(keeper)
	task_id = WorkerThreadPool.add_task(_run.bind(operation))
	if task_id >= 0: keeper.jobs.append(self)
	return OK if task_id >= 0 else ERR_CANT_CREATE

func _run(operation: Callable) -> void:
	result = operation.call()

func is_alive() -> bool:
	return not collected and task_id >= 0 and not WorkerThreadPool.is_task_completed(task_id)

func wait_to_finish():
	assert(not is_alive())
	if not collected:
		WorkerThreadPool.wait_for_task_completion(task_id)
		collected = true
	return result
