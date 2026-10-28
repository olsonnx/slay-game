extends RefCounted
## Worker-owned simulation only. No scene, rendering, live rules or game RNG.
const Planner = preload("res://src/game/ai_planner.gd")
const Strategist = preload("res://src/game/ai_strategist.gd")
var context: Dictionary = {}
var preparation_cache: Dictionary = {}
var model
var faction: int
var spending: bool
var planner
var cancelled := false
var mutex := Mutex.new()

func _init(snapshot, owner: int, preparation: bool, memory: Dictionary = {}, purchase_cache: Dictionary = {}) -> void:
	model = snapshot
	faction = owner
	spending = preparation
	context = memory.duplicate(true)
	preparation_cache = purchase_cache

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
	if is_cancelled():
		return
	planner = Strategist.new(model, faction, spending, true, context, preparation_cache) if model.uses_strategic_ai() else Planner.new(model, faction, spending, true, preparation_cache)
	while not is_cancelled() and not planner.step():
		pass
