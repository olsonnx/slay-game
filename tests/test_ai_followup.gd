extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Planner = preload("res://src/game/ai_planner.gd")
const Strategy = preload("res://src/game/ai_strategist.gd")
const Restore = preload("res://tools/player_replay_position_probe.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func base():
	var model = Rules.new()
	model.rule_mode = "modern"
	model.ai_difficulty = "hard"
	model.faction_count = 3
	return model
func finish(model) -> void:
	model.rebuild_kingdoms()
	for bank in model.kingdoms.values(): bank["gold"] = 100
func core_checks() -> void:
	var model = base()
	for q in range(8):
		model.cells[Vector2i(q,0)] = model.make_cell(0 if q < 4 else 1)
		model.cells[Vector2i(q,0)]["value"] = 6 if q != 4 else 1
	for r in [1,2,3]: model.cells[Vector2i(1,r)] = model.make_cell(2)
	model.cells[Vector2i.ZERO]["capital"] = 0
	model.cells[Vector2i(7,0)]["capital"] = 1
	model.cells[Vector2i(1,3)]["capital"] = 2
	model.cells[Vector2i(1,3)]["unit"] = 2
	model.cells[Vector2i.ZERO]["unit"] = 2
	model.cells[Vector2i(2,0)]["unit"] = 2
	finish(model)
	model.kingdom_at(Vector2i(1,3))["gold"] = 0
	var query = Analysis.Queries.new(model)
	expect(query.campaign_value(Vector2i(4,0),0) > query.campaign_value(Vector2i(1,1),0),"Rich surviving core has priority over an already bankrupt offshoot")
	for backend in [Planner,Strategy]:
		var move: Dictionary = backend.new(model,0).run()
		expect(move.get("coord") == Vector2i(4,0),"Both planners pressure the surviving rich bank")
func supply_checks() -> void:
	var model = base()
	for q in range(8): model.cells[Vector2i(q,0)] = model.make_cell(0)
	for r in range(-4,0): model.cells[Vector2i(3,r)] = model.make_cell(1)
	model.cells[Vector2i.ZERO]["capital"] = 0
	model.cells[Vector2i(3,-4)]["capital"] = 1
	model.cells[Vector2i(6,0)]["unit"] = 2
	model.cells[Vector2i(3,-1)]["unit"] = 1
	finish(model)
	var query = Analysis.Queries.new(model)
	expect(query.supply_risk(Vector2i(3,0)) > 12,"Identify the AI's own threatened starvation neck")
	expect(query.supply_risk(Vector2i(7,0)) == 0,"Do not exaggerate ordinary endpoint exposure")
	for backend in [Planner,Strategy]:
		var copy = Analysis.snapshot(model)
		var buy: Dictionary = backend.new(model,0,true).run()
		expect(not buy.is_empty() and Candidates.apply(copy,buy,0),"Choose a legal funded response to the cut threat")
		expect(not copy.can_move(Vector2i(3,-1),Vector2i(3,0)),"Purchased defence prevents the enemy Scout from cutting the army off")
func reserve_checks() -> void:
	var model = base()
	for q in range(12): model.cells[Vector2i(q,0)] = model.make_cell(0 if q < 8 else -1 if q == 8 else 1)
	for q in range(8): model.cells[Vector2i(q,0)]["value"] = 6
	model.cells[Vector2i.ZERO]["capital"] = 0
	model.cells[Vector2i(11,0)]["capital"] = 1
	model.cells[Vector2i(6,0)]["building"] = "city" # Deploy the reserve within reach of the frontier.
	model.cells[Vector2i(2,0)]["unit"] = 1
	model.cells[Vector2i(11,0)]["unit"] = 3
	finish(model)
	for backend in [Planner,Strategy]:
		var buy: Dictionary = backend.new(model,0,true).run()
		expect(buy.get("tier") == 3,"Buy one reserve against the Knight beyond the neutral frontier (chosen %s)" % buy)
		var copy = Analysis.snapshot(model)
		expect(Candidates.apply(copy,buy,0),"The anticipatory Knight is affordable and legal")
		var next: Dictionary = backend.new(copy,0,true).run()
		expect(next.get("tier",0) != 3,"Do not keep buying the same combat reserve after its role is filled")
	model.kingdom_at(Vector2i(11,0))["gold"] = 0
	var doomed: Dictionary = Planner.new(model,0,true).run()
	expect(doomed.get("tier",0) != 3,"Do not buy an expensive reserve against troops already due to starve")
	model.cells[Vector2i(11,0)]["unit"] = 1
	var cheap: Dictionary = Planner.new(model,0,true).run()
	expect(cheap.get("tier",0) != 3,"No Knight reserve against an army of Scouts")
func replay_checks() -> void:
	var path := "res://tests/fixtures/ai_replays/followup-557.json"
	expect(FileAccess.file_exists(path), "Required AI follow-up replay fixture exists")
	if not FileAccess.file_exists(path): return
	var restore = Restore.new()
	var model = restore.restore(JSON.parse_string(FileAccess.get_file_as_string(path)))
	for backend in [Planner,Strategy]:
		var buy: Dictionary = backend.new(model,2,true).run()
		expect(buy.get("kind") == "city","Tide establishes forward recruitment instead of buying Scouts at its distant capital")
		var copy = Analysis.snapshot(model)
		expect(Candidates.apply(copy,buy,2) and copy.can_recruit(buy.coord,2,1),"Tide creates a legal forward deployment site through current rules")
	restore.free()
func expiry_checks() -> void:
	var model = base()
	for q in range(8): model.cells[Vector2i(q,0)] = model.make_cell(0 if q < 3 else -1 if q == 3 else 1)
	model.cells[Vector2i.ZERO]["capital"] = 0
	model.cells[Vector2i(7,0)]["capital"] = 1
	model.cells[Vector2i(2,0)]["unit"] = 1
	model.cells[Vector2i(6,0)]["unit"] = 2
	model.cells[Vector2i(5,0)]["barrier_by"] = 1
	# Keep the Scout solvent: losing an unsupported army is a different decision.
	model.cells[Vector2i.ZERO]["value"] = 6
	finish(model)
	var before: Dictionary = model.cells.duplicate(true)
	expect(not model.can_move(Vector2i(6,0),Vector2i(3,0)),"The barrier blocks the enemy's current route")
	expect(Analysis.Queries.new(model).reply_strength(Vector2i(3,0),0) == 2,"Retaliation predicts the Soldier's route after its own barrier expires")
	for backend in [Planner,Strategy]:
		var move: Dictionary = backend.new(model,0).run()
		expect(move.get("coord",model.NONE) != Vector2i(3,0),"Hard checks retaliation through an expiring barrier (chosen %s)" % move)
	expect(model.cells == before,"Predicting barrier expiry never changes the current board")
	model.cells[Vector2i(5,0)]["barrier_by"] = 2
	expect(Analysis.Queries.new(model).reply_strength(Vector2i(3,0),0) == 0,"Another faction's barrier still blocks the Soldier after its settlement")
func run() -> void:
	core_checks()
	supply_checks()
	reserve_checks()
	replay_checks()
	expiry_checks()
	print("AI follow-up checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
