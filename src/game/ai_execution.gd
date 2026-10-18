extends RefCounted
## Main-thread execution contract: frame scheduling, cancellation, pause, tracing.
## No renderer, controls, authoritative model or gameplay-scene dependency.
var tree: SceneTree
var cancellation: Callable
var trace: Callable

func _init(scene_tree: SceneTree, cancelled: Callable, sample: Callable = Callable()) -> void:
	tree = scene_tree
	cancellation = cancelled
	trace = sample

func is_cancelled() -> bool:
	return cancellation.call()

func next_frame() -> void:
	await tree.process_frame

func wait_until_resumed() -> void:
	while tree.paused and not is_cancelled():
		await next_frame()

func start_sample() -> int:
	return Time.get_ticks_usec() if trace.is_valid() else 0

func finish_sample(started: int, stage: String) -> void:
	if started > 0 and trace.is_valid():
		trace.call({"stage": stage, "ms": (Time.get_ticks_usec() - started) / 1000.0})

static func adapt(host):
	if host is RefCounted:
		assert(host.get_script() == load("res://src/game/ai_execution.gd"), "AI requires an execution context")
		return host
	assert(host is Node, "Legacy AI hosts must be scene nodes")
	# Existing standalone probes supply only a Node with `closing`. Keep that
	# compatibility at the boundary; AI orchestration itself uses this contract.
	var owner: WeakRef = weakref(host)
	return load("res://src/game/ai_execution.gd").new(host.get_tree(), func():
		var node = owner.get_ref()
		return node == null or node.closing)
