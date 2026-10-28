extends RefCounted
## Serial simulation lane. Only private rules are mutated; scenes stay on main.
const Snapshots = preload("res://src/game/state_snapshot.gd")
var model
var opponent
var packet: Dictionary = {}
var result: Dictionary = {}
var actions: Array[Dictionary] = []
var recorder
var faction := 0
var preparation := false
var cancelled := false
var mutex := Mutex.new()
var worker_ms := 0.0
var operation := ""
var deaths := 0

func clear_outputs() -> void:
	result = {}
	actions = []

func cancel() -> void:
	mutex.lock()
	cancelled = true
	mutex.unlock()

func is_cancelled() -> bool:
	mutex.lock()
	var value := cancelled
	mutex.unlock()
	return value

func run() -> void:
	var started := Time.get_ticks_usec()
	if is_cancelled(): return
	if model == null:
		model = packet["script"].new()
		opponent = model.KingdomAI.new(model)
	opponent.worker_cancel = is_cancelled
	opponent.planning_samples.clear()
	Snapshots.update_worker(model, packet)
	model.replay_log = recorder
	match operation:
		"world": actions = model.world_turn()
		"settlement": deaths = model.begin_turn(faction)
		_: actions = opponent.prepare_ai_turn(faction) if preparation else opponent.ai_movements(faction)
	opponent.worker_cancel = Callable()
	if not is_cancelled(): result = Snapshots.worker_result(model, packet)
	model.replay_log = null
	worker_ms = (Time.get_ticks_usec() - started) / 1000.0
