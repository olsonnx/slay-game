extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Planner = preload("res://src/game/ai_planner.gd")
const Strategy = preload("res://src/game/ai_strategist.gd")
const ReplayProbe = preload("res://tools/player_replay_position_probe.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func line_board():
	var model = Rules.new()
	model.rule_mode = "modern"
	model.ai_difficulty = "hard"
	for q in range(12):
		model.cells[Vector2i(q,0)] = model.make_cell(0 if q < 8 else 1)
		model.cells[Vector2i(q,0)]["value"] = 6
	model.cells[Vector2i.ZERO]["capital"] = 0
	model.cells[Vector2i(11,0)]["capital"] = 1
	model.rebuild_kingdoms()
	for bank in model.kingdoms.values(): bank["gold"] = 100
	return model
func purchase_checks() -> void:
	var model = line_board()
	model.cells[Vector2i(7,0)]["unit"] = 1
	model.cells[Vector2i(9,0)]["unit"] = 2
	for q in range(8,12): model.cells[Vector2i(q,0)]["value"] = 1
	# The enemy Soldier lends defence 2 to the frontier: only a Knight breaches.
	for backend in [Planner,Strategy]:
		var buy: Dictionary = backend.new(model,0,true).run()
		expect(buy.get("kind") == "recruit" and buy.get("tier") == 3, "Both backends buy an affordable Knight for a Soldier-protected frontier")
		var copy = Analysis.snapshot(model)
		expect(Candidates.apply(copy,buy,0), "Recommended Knight purchase is authoritative-legal")
		if buy.get("kind") == "recruit": expect(copy.can_move(buy["coord"],Vector2i(8,0)), "Purchased Knight can breach the intended defence immediately")
	model.cells[Vector2i(9,0)]["unit"] = 0
	for backend in [Planner,Strategy]:
		var buy: Dictionary = backend.new(model,0,true).run()
		expect(buy.get("tier",0) != 3, "No Knight tax when a cheaper unit can do the job")
	# Different useful ranks must survive a crowded dock.
	var options := []
	for tier in [1,2,3]:
		for i in range(5): options.append({"kind":"recruit","tier":tier,"coord":Vector2i(tier,i),"priority":100.0-tier})
	var diverse := Candidates.diverse(options,9,false)
	for tier in [1,2,3]: expect(diverse.any(func(a):return a["tier"] == tier), "Useful rank %d survives shortlisting" % tier)
	expect(diverse.size() <= 9,"Purchase candidate cap is unchanged")
	model = line_board()
	for cell in model.cells.values(): cell["value"] = 1
	model.cells[Vector2i(1,0)]["unit"] = 3
	model.kingdom_at(Vector2i.ZERO)["gold"] = 22
	var queries = Analysis.Queries.new(model)
	expect(not Analysis.safe_spending(model.kingdom_at(Vector2i.ZERO),20,4,queries),"An income improvement must not spend the wages needed for settlement")
	var unsafe := Candidates.preparation(model,0).filter(func(a): return a["kind"] in ["house","tower","bridge"])
	expect(unsafe.is_empty(),"No construction that knowingly bankrupts the existing army")
func bridge_checks() -> void:
	var model = Rules.new()
	model.rule_mode = "modern"
	for direction in model.DIRECTIONS: model.cells[direction] = model.make_cell(0)
	model.rebuild_kingdoms()
	var bank: Dictionary = model.kingdoms.values()[0]
	bank["gold"] = 100
	var queries = Analysis.Queries.new(model)
	expect(queries.bridge_value(Vector2i.ZERO,bank["capital"]) == 0,"Filling an enclosed hole gives no bridge utility")
	expect(not Candidates.preparation(model,0).any(func(a):return a["kind"] == "bridge"),"AI does not buy bridges to fill territory holes")
	model.cells[Vector2i(0,3)] = model.make_cell(1)
	model.cells[Vector2i(0,4)] = model.make_cell(1)
	model.rebuild_kingdoms()
	queries = Analysis.Queries.new(model)
	expect(queries.bridge_value(Vector2i(0,2),model.cells[Vector2i(0,-1)]["kingdom"]) > 0,"A crossing that opens a new enemy shore has utility")
	# Two friendly banks separated by one water tile should still reconnect.
	model = Rules.new()
	model.rule_mode = "modern"
	for q in [0,1,3,4]: model.cells[Vector2i(q,0)] = model.make_cell(0)
	model.rebuild_kingdoms()
	queries = Analysis.Queries.new(model)
	expect(queries.bridge_value(Vector2i(2,0),model.cells[Vector2i.ZERO]["kingdom"]) >= 14,"Reconnect distinct friendly banks")
func supply_checks() -> void:
	var model = Rules.new()
	model.rule_mode = "modern"
	model.ai_difficulty = "hard"
	for q in range(8): model.cells[Vector2i(q,0)] = model.make_cell(1)
	for r in range(-4,0): model.cells[Vector2i(3,r)] = model.make_cell(0)
	model.cells[Vector2i.ZERO]["capital"] = 1
	model.cells[Vector2i(3,-4)]["capital"] = 0
	model.cells[Vector2i(6,0)]["unit"] = 2
	model.cells[Vector2i(3,-1)]["unit"] = 1
	model.rebuild_kingdoms()
	for bank in model.kingdoms.values(): bank["gold"] = 100
	var queries = Analysis.Queries.new(model)
	var before: Dictionary = model.cells.duplicate(true)
	var rng_before: int = model.rng.state
	expect(queries.cut_value(Vector2i(3,0)) > 12,"Identify a cut that strands a Soldier with insufficient income")
	expect(queries.cut_value(Vector2i(7,0)) == 0,"An endpoint is not an encirclement")
	expect(model.cells == before and model.rng.state == rng_before,"Supply analysis is read-only and consumes no RNG")
	for backend in [Planner,Strategy]:
		var action: Dictionary = backend.new(model,0).run()
		expect(action.get("reason") == "cut enemy supply","Both movement backends pursue the rewarding supply cut")
	var copy = Analysis.snapshot(model)
	expect(copy.move_unit(Vector2i(3,-1),Vector2i(3,0)),"Supply cut executes through normal movement rules")
	expect(copy.begin_turn(1) > 0 and copy.cells[Vector2i(6,0)]["unit"] == 0,"The cut actually starves the detached Soldier next turn")
	expect(queries.cut_starves(Vector2i(3,0),Vector2i(6,0)),"Counterattack analysis excludes troops starved before movement")
	var rich = Analysis.snapshot(model)
	rich.cells[Vector2i(5,0)]["value"] = 6
	rich.cells[Vector2i(7,0)]["value"] = 6
	expect(not Analysis.Queries.new(rich).cut_starves(Vector2i(3,0),Vector2i(6,0)),"A detached but self-supporting army can still counterattack")
	# Losing rich hinterland can bankrupt the retained capital's army too.
	rich.cells[Vector2i(6,0)]["unit"] = 0
	rich.cells[Vector2i(1,0)]["unit"] = 2
	rich.kingdom_at(Vector2i.ZERO)["gold"] = 3
	expect(Analysis.Queries.new(rich).cut_starves(Vector2i(3,0),Vector2i(1,0)),"Income denial accounts for the original capital's remaining reserves")
	expect(rich.move_unit(Vector2i(3,-1),Vector2i(3,0)) and rich.begin_turn(1) > 0 and rich.cells[Vector2i(1,0)]["unit"] == 0,"Predicted retained-bank bankruptcy agrees with settlement")
	# A second route must invalidate the articulation, including bridge routes.
	for q in range(2,5):
		model.cells[Vector2i(q,1)] = model.make_cell()
		model.cells[Vector2i(q,1)]["building"] = "bridge"
	model.rebuild_kingdoms()
	expect(Analysis.Queries.new(model).cut_value(Vector2i(3,0)) == 0,"An alternate bridge route prevents a false starvation prediction")
func capital_checks() -> void:
	var model = line_board()
	# Capital is one friendly approach away from two hostile Soldiers.
	model.cells[Vector2i.ZERO]["capital"] = -1
	model.cells[Vector2i(6,0)]["capital"] = 0
	model.cells[Vector2i(9,0)]["unit"] = 2
	model.cells[Vector2i(10,0)]["unit"] = 2
	model.rebuild_kingdoms()
	model.kingdom_at(Vector2i(6,0))["gold"] = 100
	var queries = Analysis.Queries.new(model)
	expect(not queries.threats(0).has(Vector2i(6,0)),"Fixture capital is outside immediate enemy reach")
	expect(queries.defense_needs(0).get(Vector2i(6,0),{}).get("projected",false),"Detect breach plus follower before capital is directly threatened")
	for backend in [Planner,Strategy]:
		var buy: Dictionary = backend.new(model,0,true).run()
		var copy = Analysis.snapshot(model)
		expect(not buy.is_empty() and Candidates.apply(copy,buy,0) and copy.defense(Vector2i(6,0)) >= 2,"Preparation protects the capital against the two-step Soldier attack")
func replay_checks() -> void:
	var restore = ReplayProbe.new()
	for id in ["small-127","small-174","large-371","large-409"]:
		var path := "res://tests/fixtures/ai_replays/position-%s.json" % id
		expect(FileAccess.file_exists(path), "Required AI tactics replay fixture exists: " + id)
		if not FileAccess.file_exists(path): continue
		var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var model = restore.restore(sample)
		var faction := int(sample["faction"])
		var options := Candidates.preparation(model,faction)
		expect(options.any(func(a):return a["kind"] == "recruit" and a["tier"] == 2),"Replay %s keeps a useful Soldier option" % id)
		if id.begins_with("small"):
			var buy: Dictionary = Planner.new(model,faction,true).run()
			expect(buy.get("tier",0) == 2,"Replay %s buys the useful Soldier" % id)
	restore.free()
func run() -> void:
	purchase_checks()
	bridge_checks()
	supply_checks()
	capital_checks()
	replay_checks()
	print("AI tactics checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
