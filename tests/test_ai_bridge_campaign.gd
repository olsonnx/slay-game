extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Planner = preload("res://src/game/ai_planner.gd")
const Strategy = preload("res://src/game/ai_strategist.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Restore = preload("res://tools/player_replay_position_probe.gd")
var checks := 0
var failures := 0
var restore
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func recorded(name: String, authoritative := false):
	var sample = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ai_replays/"+name+".json"))
	var model = restore.restore(sample)
	if authoritative:
		model.cells = Replay.decode(sample["position"])["cells"]
		model.rng.state = int(sample["position"]["rng"])
	return model
func short_turn_checks() -> void:
	var model = recorded("ember-short-turn")
	var before := Replay.position(model)
	var planner = Strategy.new(model,1)
	var move: Dictionary = planner.run()
	expect(planner.best_sequence.any(func(action): return action.coord == Vector2i(8,4)), "Unified AI includes Ember's safe capture while advancing its rear army")
	expect(planner.best_sequence.all(func(action): return model.cells[action.coord].unit == 0), "Unified AI does not merge the rear army when a safe capture is available")
	expect(planner.evaluated <= planner.units.size() * 64, "Hard tactical comparisons stay within the per-unit budget")
	expect(Replay.position(model) == before, "Short-plan search preserves the source state and RNG")
	var options := Candidates.movements(model,1)
	var distinct := {}
	for option in options: distinct[option["coord"]] = true
	expect(distinct.size() > 1, "Nine interchangeable captures no longer hide other destinations")
	expect(options.size() <= Analysis.profile(model)["candidates"], "Movement candidate budget remains unchanged")
func recruitment_checks() -> void:
	var model = recorded("ember-bridge-preparation")
	var options := Candidates.preparation(model,1)
	expect(not options.any(func(a): return a["kind"] == "recruit" and a["tier"] == 1), "Thirteen Scouts covering one objective do not justify more Scouts")
	expect(not options.any(func(a): return a["kind"] == "spell" and a["spell"] == "summon"), "A free summon also needs an unmet job")
	for backend in [Planner,Strategy]:
		var chosen: Dictionary = backend.new(model,1,true).run()
		expect(chosen.get("kind") == "bridge" and chosen.get("coord") == Vector2i(5,8), "Both planners prioritize Ember's usable crossing on turn six")
	# Useful additional units are still bought when distinct jobs are uncovered.
	var fresh = Rules.new()
	fresh.rule_mode = "modern"
	for q in range(4):
		fresh.cells[Vector2i(q,0)] = fresh.make_cell(0)
		fresh.cells[Vector2i(q,0)]["value"] = 3
	fresh.cells[Vector2i(1,1)] = fresh.make_cell()
	fresh.cells[Vector2i(2,1)] = fresh.make_cell()
	fresh.cells[Vector2i(3,1)] = fresh.make_cell()
	fresh.cells[Vector2i.ZERO]["capital"] = 0
	fresh.cells[Vector2i(2,0)]["building"] = "city" # Cover all three frontier jobs.
	fresh.cells[Vector2i(1,0)]["unit"] = 1
	fresh.rebuild_kingdoms()
	fresh.kingdom_at(Vector2i.ZERO)["gold"] = 100
	expect(Candidates.preparation(fresh,0).any(func(a):return a["kind"] == "recruit" and a["tier"] == 1), "Distinct uncovered frontier objectives still justify Scouts")
	# The only defender is not also counted as free expansion capacity.
	fresh.cells[Vector2i(-1,0)] = fresh.make_cell(1)
	fresh.cells[Vector2i(-2,0)] = fresh.make_cell(1)
	fresh.cells[Vector2i(-2,0)]["unit"] = 2
	fresh.cells[Vector2i(1,0)]["unit"] = 2
	fresh.rebuild_kingdoms()
	expect(Analysis.Queries.new(fresh).recruitment_jobs(Vector2i.ZERO).size() >= 3, "Necessary capital guard is reserved before matching expansion jobs")
func demolition_checks() -> void:
	var model = recorded("ember-bridge-demolition")
	var query = Analysis.Queries.new(model)
	var site := Vector2i(5,8)
	expect(query.bridge_access_loss(site,1) > 10, "Demolition prices Ember's lost offensive access")
	expect(not Candidates.preparation(model,1).any(func(a):return a["kind"] == "spell" and a["spell"] == "shatter" and a["coord"] == site), "Ember does not erase its only useful crossing because a border tile is threatened")
	var emergency = Rules.new()
	emergency.rule_mode = "modern"
	for q in [-1,0,2,3]: emergency.cells[Vector2i(q,0)] = emergency.make_cell(0 if q < 1 else 1)
	emergency.cells[Vector2i.ZERO]["capital"] = 0
	emergency.cells[Vector2i(3,0)]["capital"] = 1
	emergency.cells[Vector2i(2,0)]["unit"] = 3
	emergency.cells[Vector2i(1,0)] = emergency.make_cell()
	emergency.cells[Vector2i(1,0)]["building"] = "bridge"
	emergency.cells[Vector2i.ZERO]["mana_source"] = true
	emergency.cells[Vector2i(-1,0)]["mana_source"] = true
	emergency.rebuild_kingdoms()
	emergency.set_mana(0,3)
	expect(Candidates.preparation(emergency,0).any(func(a):return a["kind"] == "spell" and a["spell"] == "shatter"), "Emergency bridge destruction can still save a capital")
	for coord in [Vector2i(1,-1),Vector2i(2,-1)]:
		emergency.cells[coord] = emergency.make_cell()
		emergency.cells[coord]["building"] = "bridge"
	expect(Analysis.Queries.new(emergency).bridge_threat_relief(Vector2i(1,0),0) == 0, "A surviving alternate route prevents imaginary defensive relief")
func turn_checks() -> void:
	for backend in ["legacy","strategic"]:
		var model = recorded("ember-before-turn",true)
		model.ai_algorithm = backend
		var replay = Replay.new()
		model.replay_log = replay
		replay.start(model)
		var started := Time.get_ticks_usec()
		var territory_before: int = model.territory(1)
		model.ai_turn(1)
		var crossing := false
		var purchases := 0
		var attacks := 0
		for row in replay.rows:
			if row["action"] == "recruit" and row["args"]["tier"] == 1: purchases += 1
			if row["action"] == "move":
				if row["args"]["path"].has(Vector2i(5,8)): crossing = true
				if row["args"]["outcome"] == "attack": attacks += 1
		expect(model.is_bridge(Vector2i(5,8)) and crossing, "Recovered turn builds and actually uses the bridge with "+backend)
		expect(purchases == 0, "Recovered turn avoids redundant Scout purchases with "+backend)
		expect(attacks > 0 or model.territory(1) > territory_before, "The recovered turn attacks or expands across its crossing with "+backend)
		for bank in model.kingdoms.values():
			if bank["owner"] == 1: expect(bank["gold"] + model.income(bank) - model.upkeep(bank) >= 0, "The offensive plan remains solvent")
		print("Recovered Ember turn ",backend," ms: ",(Time.get_ticks_usec()-started)/1000.0)
		var rebuilt := Replay.read_records(replay.records)
		expect(rebuilt.get("error") == "" and Replay.encode(rebuilt["position"]) == Replay.position(model), "Offensive turn replay reconstructs exactly")
func run() -> void:
	restore = Restore.new()
	short_turn_checks()
	recruitment_checks()
	demolition_checks()
	turn_checks()
	restore.free()
	print("AI bridge campaign checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
