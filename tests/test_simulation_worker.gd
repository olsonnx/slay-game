extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Fixture = preload("res://tools/heavy_strain_probe.gd")
var checks := 0
var failures := 0
class Host extends Node:
	var closing := false

func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func position(model) -> Dictionary:
	var result := Snapshots.capture(model)
	result.erase("ai_last_decision") # Wall-clock search diagnostics differ.
	return result

func comparable_rows(recorder) -> Array:
	var result := []
	for row in recorder.rows:
		var copy: Dictionary = row.duplicate(true)
		if copy["action"] == "ai_decision":
			copy["args"].erase("search_ms")
			copy["args"].erase("max_step_ms")
		result.append(copy)
	return result

func compare_paths(model, host) -> void:
	var reference = Rules.new()
	Snapshots.restore(reference, Snapshots.capture(model))
	model.replay_log = Replay.new()
	reference.replay_log = Replay.new()
	model.replay_log.start(model)
	reference.replay_log.start(reference)
	var worker = model.KingdomAI.new(model)
	var serial = reference.KingdomAI.new(reference)
	var expected: Array = serial.prepare_ai_turn(1)
	var displayed: Dictionary = model.cells.duplicate(true)
	var actual: Array = await worker.prepare_async(host, 1)
	expect(actual == expected, "Worker preparation preserves ordered animation records")
	expect(position(model) == position(reference), "Worker preparation preserves full rules, encounters and RNG")
	if worker.presentation_patch_ready:
		displayed.merge(worker.preparation_cells(), true)
		expect(displayed == model.cells, "Scoped preparation patch reconstructs the complete displayed board")
	else: displayed = model.cells.duplicate(true)
	for batch in range(3):
		var prior: Dictionary = model.cells.duplicate()
		expected = serial.ai_movements(1)
		actual = await worker.movements_async(host, 1)
		expect(actual == expected, "Worker movement preserves serial decisions and animation records")
		expect(position(model) == position(reference), "Worker movement preserves authoritative state and RNG")
		expect(comparable_rows(model.replay_log) == comparable_rows(reference.replay_log), "Worker replay preserves every intermediate command delta and order")
		if worker.presentation_patch_ready:
			displayed.merge(worker.movement_cells(actual), true)
			expect(displayed == model.cells, "Scoped movement patch includes distant collateral changes")
		else: displayed = model.cells.duplicate(true)
		for coord in model.cells:
			if prior.has(coord) and prior[coord] == model.cells[coord]:
				expect(is_same(prior[coord], model.cells[coord]), "Publishing retains unchanged live records")
		if actual.is_empty(): break
	var world_expected: Array = reference.world_turn()
	var world_actual: Array = await worker.world_async(host)
	expect(world_actual == world_expected and position(model) == position(reference), "Worker World turn preserves tree growth, animal actions and RNG")
	expect(model.replay_log.round_number == reference.replay_log.round_number, "Worker World turn advances the recorder round")
	var deaths_expected: int = reference.begin_turn(0)
	var deaths_actual: int = await worker.begin_turn_async(host, 0)
	expect(deaths_actual == deaths_expected and position(model) == position(reference), "Worker player settlement preserves income, upkeep, expiry and starvation")
	expect(comparable_rows(model.replay_log) == comparable_rows(reference.replay_log), "World and player settlement retain ordered replay deltas")
	# Publishing transfers independent records; later worker synchronization must
	# not mutate an already handed-off board or the previous replay tape.
	var frozen := Snapshots.capture(model)
	var packet := Snapshots.worker_input(model)
	Snapshots.update_worker(worker.simulation_job.model, packet)
	for coord in worker.simulation_job.model.cells:
		worker.simulation_job.model.cells[coord]["value"] += 1
		break
	expect(Snapshots.capture(model) == frozen, "Worker retains no mutable live cell aliases after publication")

func run() -> void:
	var initial = Rules.new()
	initial.rule_mode = "modern"
	initial.generate(42, "very_small", 3)
	var input := Snapshots.worker_input(initial)
	var private = Rules.new()
	Snapshots.update_worker(private, input)
	var coord: Vector2i = private.cells.keys()[0]
	private.cells.erase(coord)
	private.cells[Vector2i(100,100)] = private.make_cell()
	private.pending_events.append({"coord":Vector2i.ZERO,"choices":[1,2]})
	private.effects_by_faction[0] = {"test":true}
	private.capital_relocations[0] = 2
	private.mana_by_faction[0] = 1
	private.faction_count += 1
	private.rng.randf()
	private.rebuild_kingdoms()
	Snapshots.publish_worker(initial, Snapshots.worker_result(private, input))
	expect(Snapshots.capture(initial) == Snapshots.capture(private), "Worker patch transfers removals, new tiles, topology, effects, mana, encounters and RNG")
	private.pending_events[0]["choices"].append(3)
	expect(initial.pending_events[0]["choices"] == [1,2], "Published events own their nested records")
	var view = Snapshots.analysis_view(initial)
	var point: Vector2i = initial.cells.keys()[0]
	expect(is_same(view.cells[point], initial.cells[point]), "Read-only planning reuses unchanged cell records")
	initial.cells[point]["event"] = "duel"
	view = Snapshots.analysis_view(initial)
	expect(view.cells[point]["event"] == "" and initial.cells[point]["event"] == "duel", "Read-only view conceals encounters without modifying source records")
	var host := Host.new()
	root.add_child(host)
	for algorithm in ["legacy", "strategic"]:
		var model = Rules.new()
		model.rule_mode = "modern"
		model.generate(71, "very_small", 3)
		model.ai_algorithm = algorithm
		model.ai_difficulty = "easy" if algorithm == "legacy" else "normal"
		await compare_paths(model, host)
	# Crowded board exercises splits, multiple commands and retained assignments.
	var crowded = Fixture.crowded("large", 71, 60)
	crowded.ai_algorithm = "strategic"
	await compare_paths(crowded, host)
	var encounter = Rules.new()
	encounter.rule_mode = "modern"
	encounter.ai_algorithm = "strategic"
	encounter.faction_count = 2
	encounter.rng.seed = 42
	for q in range(5):
		encounter.cells[Vector2i(q,0)] = encounter.make_cell(1 if q < 2 else -1 if q == 2 else 0)
		encounter.cells[Vector2i(q,0)]["value"] = 2
	encounter.cells[Vector2i(0,0)]["unit"] = 1
	encounter.cells[Vector2i(1,0)]["capital"] = 1
	encounter.cells[Vector2i(2,0)]["event"] = "duel"
	encounter.cells[Vector2i(3,0)]["building"] = "tower"
	encounter.cells[Vector2i(4,0)]["capital"] = 0
	encounter.rebuild_kingdoms()
	var rng_before: int = encounter.rng.state
	await compare_paths(encounter, host)
	expect(encounter.cells[Vector2i(2,0)]["event"] == "" and encounter.rng.state != rng_before, "Worker equivalence fixture actually resolves a randomized encounter")
	var cancelled = Fixture.crowded("huge", 71, 120)
	var before := position(cancelled)
	var opponent = cancelled.KingdomAI.new(cancelled)
	var done := [false]
	var start := func():
		await opponent.movements_async(host, 1)
		done[0] = true
	start.call()
	host.closing = true
	while not done[0]: await process_frame
	expect(position(cancelled) == before, "Cancellation discards the complete worker transaction")
	expect(opponent.simulation_job == null, "Cancellation releases the private worker lane")
	host.queue_free()
	await process_frame
	print("Simulation worker checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
