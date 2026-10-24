extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Encounters = preload("res://src/game/encounter_rules.gd")
const Events = preload("res://src/game/event_catalog.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
var passed := 0
var failed := 0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		push_error(message)

func distribution_checks() -> void:
	var r = Rules.new()
	r.rng.seed = 93428
	var weights := {"gold":12, "pit":1, "goose":0, "unknown":100, "altar":-1}
	var first_gold := 0
	var repeated_gold := 0
	for trial in range(13000):
		var used := {}
		var first: String = Encounters.weighted_event(r, Vector2i.ZERO, -1, weights, used)
		if first == "gold": first_gold += 1
		used[first] = true
		var second: String = Encounters.weighted_event(r, Vector2i.ZERO, -1, weights, used)
		expect(second in ["gold", "pit"] and second != first, "Unused event wins even against a larger used weight")
		used[second] = true
		var third: String = Encounters.weighted_event(r, Vector2i.ZERO, -1, weights, used)
		expect(third in ["gold", "pit"], "Exhausted pool repeats only enabled, known types")
		if third == "gold": repeated_gold += 1
	for count in [first_gold, repeated_gold]:
		expect(count > 11800 and count < 12200, "Both initial and fallback draws retain 12:1 weighting")
	var before: int = r.rng.state
	expect(Encounters.weighted_event(r, Vector2i.ZERO, -1, {"gold":0}, {"gold":true}) == "" and r.rng.state == before, "Empty weighted pool does not consume RNG")

func generation_checks() -> void:
	var original: Dictionary = Events.WEIGHTS.duplicate()
	for weights in [{"gold":12, "pit":1}, {"pit":1}, {"gold":0}, original]:
		Events.WEIGHTS.assign(weights)
		for seed_value in range(16):
			var r = Rules.new()
			r.rule_mode = "modern"
			r.faction_count = 2
			for q in range(16):
				for y in range(16): r.cells[Vector2i(q*3,y*3)] = r.make_cell()
			r.rng.seed = seed_value
			var snapshot: Dictionary = Snapshots.capture(r)
			r.magic.generate_events(r)
			var types := {}
			var count := 0
			for cell in r.cells.values():
				if cell.event == "": continue
				count += 1
				types[cell.event] = true
				expect(int(weights.get(cell.event,0)) > 0, "Generated markers exclude zero-weight types")
			var enabled := 0
			for id in weights:
				if int(weights[id]) > 0: enabled += 1
			expect(count == (16 if enabled > 0 else 0), "Small or empty catalog never loses valid encounter slots")
			expect(types.size() == mini(enabled,count), "All distinct types are used before repetitions")
			var cells: Dictionary = r.cells.duplicate(true)
			var rng_state: int = r.rng.state
			Snapshots.restore(r,snapshot)
			r.magic.generate_events(r)
			expect(r.cells == cells and r.rng.state == rng_state, "Map distribution is deterministic")
	Events.WEIGHTS.assign(original)
	for seed_value in range(12):
		var r = Rules.new()
		r.rule_mode = "modern"
		r.generate(seed_value,"very_small",2)
		var types := {}
		var count := 0
		for cell in r.cells.values():
			if cell.event != "":
				count += 1
				types[cell.event] = true
		expect(types.size() == count, "Real small maps have no repeated event types")

func replacement_checks() -> void:
	var original: Dictionary = Events.WEIGHTS.duplicate()
	Events.WEIGHTS.assign({"pit":100, "wizard":1, "altar":1})
	var r = Rules.new()
	r.rule_mode = "modern"
	r.human_factions = [0]
	for x in range(3): r.cells[Vector2i(x,0)] = r.make_cell(0)
	var coord := Vector2i.ZERO
	r.cells[coord].unit = 1
	r.cells[coord].event = "lumberjack" # No forest: must replace.
	r.cells[Vector2i(1,0)].event = "pit" # Reserve an unrevealed type.
	r.cells[Vector2i(2,0)].event_seen = "wizard" # Already consumed.
	var before: Dictionary = Snapshots.capture(r)
	expect(r.magic.trigger_event(r,coord,0), "Ineligible encounter still triggers")
	expect(r.pending_events[0].id == "altar", "Replacement avoids both reserved and previously revealed types")
	expect(r.cells[coord].event_seen == "altar", "Revealed type is retained after marker consumption")
	var after: Dictionary = Snapshots.capture(r)
	Snapshots.restore(r,before)
	r.magic.trigger_event(r,coord,0)
	expect(Snapshots.capture(r) == after, "Restoring before reveal repeats the same encounter and history")
	Snapshots.restore(r,after)
	expect(r.cells[Vector2i(2,0)].event_seen == "wizard", "Snapshot retains consumed-event history")
	r.cells[Vector2i(2,0)].event_seen = "altar"
	r.cells[coord].event_seen = "wizard"
	r.cells[coord].event = "lumberjack"
	expect(not Encounters.prepare_event(r,"lumberjack",coord,0).is_empty(), "Exhausted eligible replacement pool still produces an event")
	Events.WEIGHTS.assign(original)

func run() -> void:
	distribution_checks()
	generation_checks()
	replacement_checks()
	print("Event distribution checks: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)
