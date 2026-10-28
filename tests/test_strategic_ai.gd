extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Strategy = preload("res://src/game/ai_strategist.gd")
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
func equivalent(a, b) -> void:
	expect(a.cells == b.cells, "Selective reconstruction preserves every cell field")
	expect(a.kingdoms == b.kingdoms and a.kingdoms.keys() == b.kingdoms.keys(), "Selective reconstruction preserves treasury, capitals and bank order")
	expect(a.mana_by_faction == b.mana_by_faction and a.effects_by_faction == b.effects_by_faction, "Selective reconstruction preserves mana and effects")
	expect(a.rng.state == b.rng.state and a.pending_events == b.pending_events, "Selective reconstruction preserves encounters and RNG")
func selective_checks() -> void:
	for mode in ["modern"]:
		for seed_value in range(10):
			var current = Fixture.crowded("huge", seed_value, 120)
			current.rule_mode = mode
			current.rebuild_kingdoms()
			var full = Analysis.snapshot(current)
			full.rng.state = current.rng.state
			full.incremental_kingdoms = false
			var moves := 0
			for source in current.cells.keys():
				if current.cells[source]["unit"] == 0: continue
				for target in current.reachable_targets(source):
					if current.cells[target]["owner"] == current.unit_faction(source): continue
					var expected: Dictionary = full.perform_move(source, target)
					var actual: Dictionary = current.perform_move(source, target)
					expect(actual == expected, "Recorded captures match complete reconstruction")
					equivalent(current, full)
					moves += 1
					break
				if moves >= 24: break
	var scattered = Fixture.crowded("huge", 71, 120)
	for bank in scattered.kingdoms.values():
		if bank["owner"] == 4: scattered.cells[bank["capital"]]["grave"] = true
	var reference = Analysis.snapshot(scattered)
	reference.rng.state = scattered.rng.state
	reference.incremental_kingdoms = false
	var tested := false
	for source in scattered.cells:
		if scattered.cells[source]["unit"] == 0 or scattered.unit_faction(source) != 1: continue
		for target in scattered.reachable_targets(source):
			if scattered.cells[target]["owner"] in [1, 4]: continue
			scattered.perform_move(source, target)
			reference.perform_move(source, target)
			equivalent(scattered, reference)
			tested = true
			break
		if tested: break
	expect(tested, "Unrelated capture exercises surviving-capital grave normalization")
	var model = Rules.new()
	model.rule_mode = "modern"
	for q in range(10):
		model.cells[Vector2i(q, 0)] = model.make_cell(0 if q < 4 else 1)
	model.cells[Vector2i(2, 0)]["building"] = "bridge"
	model.cells[Vector2i(2, 0)]["owner"] = -1
	model.rebuild_kingdoms()
	model.cells[Vector2i(3, 0)]["unit"] = 3
	model.cells[Vector2i(4, 0)]["capital"] = -1
	model.cells[Vector2i(5, 0)]["capital"] = 1
	model.cells[Vector2i(4, 0)]["event"] = "gold"
	model.rebuild_kingdoms()
	for bank in model.kingdoms.values(): bank["gold"] = 50 + bank["owner"] * 40
	var full = Analysis.snapshot(model)
	full.cells = model.cells.duplicate(true)
	full.rng.state = model.rng.state
	full.incremental_kingdoms = false
	model.perform_move(Vector2i(3, 0), Vector2i(4, 0))
	full.perform_move(Vector2i(3, 0), Vector2i(4, 0))
	equivalent(model, full)
	model.cells[Vector2i(4, 0)]["moved"] = false
	full.cells[Vector2i(4, 0)]["moved"] = false
	model.perform_move(Vector2i(4, 0), Vector2i(5, 0))
	full.perform_move(Vector2i(4, 0), Vector2i(5, 0))
	equivalent(model, full)
func planning_checks() -> void:
	for difficulty in ["easy", "normal", "hard"]:
		var model = Fixture.crowded("huge", 71, 120)
		model.ai_difficulty = difficulty
		var before: Dictionary = model.cells.duplicate(true)
		var rng_before: int = model.rng.state
		var first = Strategy.new(model, 1)
		first.run()
		var again = Strategy.new(model, 1)
		again.run()
		expect(first.best_sequence == again.best_sequence, "Strategic assignments are deterministic")
		expect(model.cells == before and model.rng.state == rng_before, "Planning does not mutate live rules or RNG")
		var targets: Dictionary = {}
		for action in first.best_sequence:
			expect(not targets.has(action["coord"]), "Units reserve different destinations")
			targets[action["coord"]] = true
			expect(model.can_move(action["source"], action["coord"]), "Every assignment is initially authoritative-legal")
		var repeated = Strategy.new(model, 1, false, false, first.context)
		repeated.run()
		expect(repeated.context["builds"] == first.context["builds"], "Unchanged strategic context reuses faction objectives")
		for coord in model.cells:
			model.cells[coord]["event"] = "pit" if model.cells[coord]["owner"] != 1 else ""
		var secret = Strategy.new(model, 1)
		secret.run()
		expect(secret.best_sequence == first.best_sequence, "Unknown encounter identities do not influence strategy")
	var guarded = Rules.new()
	for q in range(7): guarded.cells[Vector2i(q, 0)] = guarded.make_cell(0 if q < 3 else 1)
	guarded.cells[Vector2i(0, 0)]["unit"] = 2
	guarded.cells[Vector2i(1, -1)] = guarded.make_cell(1)
	guarded.cells[Vector2i(2, -1)] = guarded.make_cell(1)
	guarded.cells[Vector2i(2, -1)]["unit"] = 2
	guarded.rebuild_kingdoms()
	var guard_move: Dictionary = Strategy.new(guarded, 0).run()
	var protected = Analysis.snapshot(guarded)
	if not guard_move.is_empty(): protected.move_unit(guard_move["source"], guard_move["coord"])
	expect(protected.defense(Vector2i(0, 0)) >= 2, "Strategist preserves the sole capital defender's protection")
	var exposed = Rules.new()
	for q in range(7): exposed.cells[Vector2i(q, 0)] = exposed.make_cell(0 if q < 3 else -1 if q == 3 else 1)
	exposed.cells[Vector2i(2, 0)]["unit"] = 1
	exposed.cells[Vector2i(6, 0)]["unit"] = 3
	exposed.rebuild_kingdoms()
	exposed.ai_difficulty = "hard"
	var unsafe_capture: Dictionary = Strategy.new(exposed, 0).run()
	expect(unsafe_capture.get("coord", Rules.NONE) != Vector2i(3, 0), "Hard avoids an unsupported Scout capture within a Knight's three-step range")
	var breach = Rules.new()
	for q in range(8): breach.cells[Vector2i(q, 0)] = breach.make_cell(0 if q < 4 else 1)
	breach.cells[Vector2i(3, 0)]["unit"] = 3
	breach.cells[Vector2i(2, 0)]["unit"] = 2
	breach.cells[Vector2i(4, 0)]["unit"] = 3
	breach.rebuild_kingdoms()
	var opening: Dictionary = Strategy.new(breach, 0).run()
	expect(not opening.is_empty() and opening["coord"] == Vector2i(4, 0), "A supported Knight trade opens a defended frontier")
	if not opening.is_empty():
		breach.perform_move(opening["source"], opening["coord"])
		var followup: Dictionary = Strategy.new(breach, 0).run()
		expect(not followup.is_empty() and followup["coord"] == Vector2i(4, 0), "A ready follower uses the opening after the duel")
	guarded.ai_algorithm = "strategic"
	var job = load("res://src/game/ai_search_job.gd").new(Analysis.snapshot(guarded), 0, false)
	job.cancel()
	job.run()
	expect(job.planner == null, "Cancelled strategic jobs exit before planning")
func async_checks() -> void:
	var model = Fixture.crowded("huge", 71, 120)
	model.ai_algorithm = "strategic"
	var host := Host.new()
	root.add_child(host)
	var opponent = model.KingdomAI.new(model)
	var before: int = model.ai_revision
	var actions: Array = await opponent.movements_async(host, 1)
	expect(actions.size() > 0 and actions.size() <= 4, "Strategic commits use bounded movement batches")
	expect(model.ai_revision == before + actions.size(), "Each committed action records one decision")
	var plans: int = opponent.strategic_context.get("builds", 0)
	if not opponent.pending_orders.is_empty():
		await opponent.movements_async(host, 1)
		expect(opponent.strategic_context.get("builds", 0) == plans, "Ordinary batches retain their faction plan")
	host.closing = true
	var frozen: Dictionary = model.cells.duplicate(true)
	expect((await opponent.movements_async(host, 1)).is_empty(), "Closing stops queued strategic commits")
	expect(model.cells == frozen, "Cancellation leaves live rules unchanged")
	host.closing = false
	model = Fixture.crowded("huge", 42, 120)
	model.ai_algorithm = "strategic"
	opponent = model.KingdomAI.new(model)
	var flow := {"done": false}
	var start_flow := func():
		await opponent.movements_async(host, 1)
		flow["done"] = true
	start_flow.call()
	await process_frame
	paused = true
	frozen = model.cells.duplicate(true)
	await create_timer(0.06, true).timeout
	expect(model.cells == frozen, "Pause freezes strategic commands between cooperative commit phases")
	host.closing = true
	paused = false
	while not flow["done"]: await process_frame
	expect(model.cells == frozen, "Closing during a paused strategic batch stops further commits")
	host.queue_free()

func rollout_checks() -> void:
	var boundary = Rules.new()
	expect(boundary.ai_algorithm == "strategic", "New games explicitly record the unified strategic policy")
	boundary.ai_algorithm = "auto"
	for q in range(199): boundary.cells[Vector2i(q, 0)] = boundary.make_cell()
	expect(boundary.uses_strategic_ai(), "Older automatic configurations use the strategic policy on small boards")
	boundary.cells[Vector2i(199, 0)] = boundary.make_cell()
	expect(boundary.uses_strategic_ai(), "Custom boards keep the same policy across the old size threshold")
	boundary.ai_algorithm = "legacy"
	expect(not boundary.uses_strategic_ai(), "Explicit legacy diagnostics override automatic rollout")
	boundary.cells.clear()
	boundary.ai_algorithm = "strategic"
	expect(boundary.uses_strategic_ai(), "Explicit strategic diagnostics work on tiny boards")
	for size_id in ["large", "very_large", "huge"]:
		var model = Fixture.crowded(size_id, 71, 70)
		model.ai_difficulty = "hard"
		expect(model.uses_strategic_ai(), "All Large and larger presets avoid whole-board beam search")
		var host := Host.new()
		root.add_child(host)
		var opponent = model.KingdomAI.new(model)
		var moves: Array = await opponent.movements_async(host, 4)
		expect(not moves.is_empty(), "Aster commits legal actions in a crowded midgame")
		expect(model.ai_last_decision.get("algorithm") == "strategic", "Live worker dispatch uses the strategic planner")
		var batches := 0
		while not moves.is_empty() and batches < 200:
			batches += 1
			moves = await opponent.movements_async(host, 4)
		expect(moves.is_empty(), "Aster finishes its movement phase instead of repeatedly replanning")
		host.queue_free()
func run() -> void:
	selective_checks()
	planning_checks()
	await async_checks()
	await rollout_checks()
	print("Strategic AI checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
