extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Strategy = preload("res://src/game/ai_strategist.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func fixture(tier := 2):
	var model = Rules.new()
	model.rule_mode = "modern"
	model.faction_count = 2
	for x in range(5):
		model.cells[Vector2i(x,0)] = model.make_cell(0 if x < 2 else 1)
		model.cells[Vector2i(x,0)]["value"] = 6
	model.cells[Vector2i.ZERO]["capital"] = 0
	model.cells[Vector2i(4,0)]["capital"] = 1
	model.cells[Vector2i(1,0)]["unit"] = tier
	model.cells[Vector2i(2,0)]["unit"] = 3
	model.cells[Vector2i(3,0)]["unit"] = 3
	model.rebuild_kingdoms()
	for bank in model.kingdoms.values(): bank["gold"] = 200
	return model
func rules_checks() -> void:
	for tier in [1,2,3]:
		var model = fixture(tier)
		var log = Replay.new()
		model.replay_log = log
		log.start(model)
		var target := Vector2i(1,0)
		var gold: int = model.kingdom_at(target)["gold"]
		expect(model.entrench(target,0) and model.is_entrenched(target) and model.cells[target]["moved"], "Every ready rank can spend its action to entrench")
		expect(model.get_mana(0) == 0 and model.kingdom_at(target)["gold"] == gold, "Entrenching costs no gold or mana")
		expect(not model.entrench(target,0) and not model.move_unit(target,Vector2i.ZERO) and not model.recruit(target,0,tier+1), "An entrenched unit cannot stack protection, move or upgrade")
		expect(not model.entrench(Vector2i(2,0),0) and not model.entrench(Vector2i.ZERO,0) and not model.entrench(Vector2i(99,99),0), "Enemy units, empty tiles and invalid coordinates reject")
		model.cells[Vector2i(2,0)]["unit"] = tier
		if tier < 3:
			expect(not model.move_unit(Vector2i(2,0),target) and model.is_entrenched(target), "An insufficient attack cannot consume entrenchment")
		model.cells[Vector2i(2,0)]["unit"] = 3
		var attack: Dictionary = model.perform_move(Vector2i(2,0),target)
		expect(attack.get("kind") == "blocked_attack" and model.cells[target]["unit"] == tier and model.cells[target]["owner"] == 0 and model.cells[Vector2i(2,0)]["moved"] and not model.is_entrenched(target), "First valid attack spends the attacker and only breaks entrenchment")
		expect(model.perform_move(Vector2i(3,0),target).get("kind") == ("knight_duel" if tier == 3 else "attack"), "A second attacker can break through, including an equal Knight duel")
		# Direct fixture edits above are not replay commands; verify a separate clean sequence.
		model = fixture(tier)
		log = Replay.new()
		model.replay_log = log
		log.start(model)
		model.entrench(target,0)
		model.perform_move(Vector2i(2,0),target)
		var rebuilt := Replay.read_records(log.records)
		expect(rebuilt.get("error") == "" and Replay.encode(rebuilt["position"]) == Replay.position(model), "Entrench and blocked attack reconstruct exactly from replay")
	var model = fixture()
	expect(Candidates.preparation(model,0).any(func(a):return a["kind"] == "entrench"), "AI can entrench a threatened ready defender")
	model.entrench(Vector2i(1,0),0)
	model.begin_turn(1)
	expect(model.is_entrenched(Vector2i(1,0)), "Protection lasts through enemy turns")
	model.begin_turn(0)
	expect(not model.is_entrenched(Vector2i(1,0)) and not model.cells[Vector2i(1,0)]["moved"], "Owner's next turn clears protection and readies the unit")
	model.cells[Vector2i(1,0)]["moved"] = true
	expect(not model.entrench(Vector2i(1,0),0), "A unit that already moved cannot entrench")
	model.cells[Vector2i(1,0)]["moved"] = false
	model = fixture(1)
	model.cells[Vector2i.ZERO]["unit"] = 1
	model.entrench(Vector2i(1,0),0)
	expect(model.move_unit(Vector2i.ZERO,Vector2i(1,0)) and not model.is_entrenched(Vector2i(1,0)) and model.cells[Vector2i(1,0)]["moved"], "Merging into an entrenched unit removes its protection and retains its spent action")
	model = fixture()
	var protection: int = model.defense(Vector2i.ZERO)
	model.entrench(Vector2i(1,0),0)
	expect(model.defense(Vector2i.ZERO) == protection, "Entrenchment does not raise adjacent defense")
	model.kill_unit(Vector2i(1,0))
	expect(not model.cells[Vector2i(1,0)].has("entrenched_by"), "Unit death removes its entrenchment")
	model.cells[Vector2i(9,9)] = model.make_cell(0)
	model.cells[Vector2i(9,9)]["unit"] = 1
	expect(model.entrench(Vector2i(9,9),0), "An isolated ready unit can entrench without a treasury")
	model = fixture()
	for spell in ["fortify","grove","barrier"]:
		expect(not model.Spells.SPELLS.has(spell) and not model.cast_spell(spell,Vector2i.ZERO,0) and model.spell_targets(spell,0).is_empty(), "Removed spell rejects in every public entry point")
	expect(model.Spells.SPELLS.keys() == ["trailblaze","summon","shatter"], "Exactly three spells remain in menu order")
	# Entrenchment follows the unit's defense, not the bridge structure.
	model.cells[Vector2i(1,0)]["owner"] = -1
	model.cells[Vector2i(1,0)]["building"] = "bridge"
	model.cells[Vector2i(1,0)]["unit_owner"] = 0
	model.cells[Vector2i(1,0)]["unit_home"] = Vector2i.ZERO
	model.cells[Vector2i(-1,0)] = model.make_cell(0)
	model.rebuild_kingdoms()
	model.cells[Vector2i.ZERO]["mana_source"] = true
	model.set_mana(0,2)
	expect(model.entrench(Vector2i(1,0),0) and model.cast_spell("shatter",Vector2i(1,0),0,Vector2i.ZERO) and not model.cells.has(Vector2i(1,0)), "Shatter destroys an entrenched bridge garrison normally")
func key(code: int, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	return event

# Three steps keep the attack inside the Knight movement budget.
func approach_fixture(scenario: String):
	var model = Rules.new()
	model.rule_mode = "modern"
	model.faction_count = 2
	for x in range(5):
		model.cells[Vector2i(x,0)] = model.make_cell(0 if x < 3 else 1)
		model.cells[Vector2i(x,0)]["value"] = 6
	model.cells[Vector2i.ZERO]["capital"] = 0
	model.cells[Vector2i(4,0)]["capital"] = 1
	model.cells[Vector2i.ZERO]["unit"] = 3
	model.cells[Vector2i(3,0)]["unit"] = 2
	if scenario == "occupied": model.cells[Vector2i(2,0)]["unit"] = 1
	if scenario == "building": model.cells[Vector2i(2,0)]["building"] = "city"
	if scenario == "blocked_suffix":
		for x in range(1,3): model.cells[Vector2i(x,0)]["unit"] = 1
	if scenario == "bridge":
		model.cells[Vector2i(2,0)]["owner"] = -1
		model.cells[Vector2i(2,0)]["building"] = "bridge"
	if scenario == "capital":
		model.cells[Vector2i.ZERO]["capital"] = -1
		model.cells[Vector2i(2,0)]["capital"] = 0
	if scenario == "tree": model.cells[Vector2i(2,0)]["tree"] = true
	model.rebuild_kingdoms()
	for bank in model.kingdoms.values(): bank["gold"] = 200
	model.entrench(Vector2i(3,0),1)
	return model

func approach_checks() -> void:
	for scenario in ["free","occupied","building","blocked_suffix","bridge","capital","tree"]:
		var model = approach_fixture(scenario)
		var before := Replay.position(model)
		var simulation = Analysis.snapshot(model)
		var log = Replay.new()
		model.replay_log = log
		log.start(model)
		var action: Dictionary = model.perform_move(Vector2i.ZERO,Vector2i(3,0))
		var landing := Vector2i(1 if scenario == "occupied" else 0 if scenario == "blocked_suffix" else 2,0)
		expect(action.get("kind") == "blocked_attack" and action.get("landing") == landing, "Blocked attack chooses the nearest free approach tile: "+scenario)
		expect(model.cells[landing]["unit"] == 3 and model.cells[landing]["moved"] and (landing == Vector2i.ZERO or model.cells[Vector2i.ZERO]["unit"] == 0), "Attacker occupies its recorded approach without duplication: "+scenario)
		expect(model.cells[Vector2i(3,0)]["owner"] == 1 and model.cells[Vector2i(3,0)]["unit"] == 2 and not model.is_entrenched(Vector2i(3,0)), "The defender survives and only loses entrenchment: "+scenario)
		if scenario == "occupied": expect(model.cells[Vector2i(2,0)]["unit"] == 1, "Fallback never overwrites a friendly unit")
		if scenario == "building": expect(model.cells[Vector2i(2,0)]["building"] == "city", "Fallback preserves structures passed along the route")
		if scenario == "bridge": expect(model.unit_faction(landing) == 0 and model.cells[landing]["unit_home"] == Vector2i.ZERO, "A stopped bridge attacker keeps its faction and supporting treasury")
		if scenario == "tree": expect(not model.cells[landing]["tree"] and action["gold_reward"] == 1 and model.kingdom_at(landing)["gold"] == 201, "Stopping on a tree clears it and pays its normal reward once")
		expect(simulation.move_unit(Vector2i.ZERO,Vector2i(3,0)) and simulation.cells == model.cells and simulation.kingdoms == model.kingdoms, "AI simulation and authoritative commands use the same approach landing: "+scenario)
		var rebuilt := Replay.read_records(log.records)
		expect(rebuilt.get("error") == "" and Replay.encode(rebuilt["position"]) == Replay.position(model), "Replays reconstruct the stopped attacker exactly: "+scenario)
		expect(before["rng"] == Replay.position(model)["rng"], "Blocked movement does not consume gameplay RNG")
	var exposed = approach_fixture("free")
	for coord in [Vector2i(-1,0),Vector2i(-2,0)]: exposed.cells[coord] = exposed.make_cell(1)
	exposed.cells[Vector2i(-2,0)]["unit"] = 3
	exposed.rebuild_kingdoms()
	for bank in exposed.kingdoms.values(): bank["gold"] = 200
	var strategy = Strategy.new(exposed,0)
	strategy.danger = strategy.queries.defense_needs(0)
	expect(strategy.exposure(Vector2i.ZERO,Vector2i(3,0)) > 0, "Strategic AI accounts for the capital guard leaving after an absorbed attack")
func ui_checks() -> void:
	root.size = Vector2i(960,620)
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var coord: Vector2i = game.NONE
	for site in game.cells:
		if game.cells[site]["owner"] == 0 and game.cells[site]["unit"] > 0: coord = site
	game.rules.kingdom_at(coord)["gold"] = 1000
	game.inspect_province(coord)
	await process_frame
	expect(game.province_view.entrench_button.visible and not game.province_view.entrench_button.disabled, "Province screen offers Entrench for an owned ready unit")
	var value: int = game.cells[coord]["value"]
	game._input(key(KEY_G))
	expect(game.cells[coord]["value"] == value+1 and game.inspected_hex == coord, "G develops the inspected province and keeps it open")
	game._input(key(KEY_G,true))
	expect(game.cells[coord]["value"] == value+1, "Held-key echoes do not spend more gold")
	game.event_shade.show()
	game._input(key(KEY_G))
	game.event_shade.hide()
	expect(game.cells[coord]["value"] == value+1, "Modal dialogs block the development shortcut")
	game.busy = true
	game._input(key(KEY_G))
	game.busy = false
	expect(game.cells[coord]["value"] == value+1, "Opponent playback blocks the development shortcut")
	game.province_view.entrench_button.pressed.emit()
	expect(game.rules.is_entrenched(coord) and game.province_view.entrench_button.disabled and game.view.tile_nodes[coord].has_node("Fortification"), "Entrench button commits, disables and shows protection")
	game.cells[coord]["value"] = 6
	var gold: int = game.rules.kingdom_at(coord)["gold"]
	game._input(key(KEY_G))
	expect(game.rules.kingdom_at(coord)["gold"] == gold and game.cells[coord]["value"] == 6, "G respects maximum development")
	game.cells[coord]["value"] = 2
	game.get_tree().paused = true
	game._input(key(KEY_G))
	game.get_tree().paused = false
	expect(game.cells[coord]["value"] == 2, "G cannot develop during pause")
	game.close_province()
	game._input(key(KEY_G))
	expect(game.cells[coord]["value"] == 2, "G is inactive without a province screen")
	game.open_shop("spells")
	expect(game.shop_items.get_child_count() == 3 and game.shop_panel.panel_height == 188, "Spells occupy one row of three")
	game.cancel_action()
	game.rules = fixture()
	game.rules.entrench(Vector2i(1,0),0)
	game.view.render_cells(game.cells)
	var attack: Dictionary = game.rules.perform_move(Vector2i(2,0),Vector2i(1,0))
	await game.view.animate_moves([attack],game.cells)
	expect(game.view.unit_actors.has(Vector2i(1,0)) and game.view.unit_actors.has(Vector2i(2,0)) and not game.view.tile_nodes[Vector2i(1,0)].has_node("Fortification"), "Blocked-attack playback keeps both units and removes the defense visual")
	for scenario in ["free","occupied","bridge","capital","tree"]:
		game.rules = approach_fixture(scenario)
		game.view.render_cells(game.cells)
		var actor: Node3D = game.view.unit_actors[Vector2i.ZERO]
		attack = game.rules.perform_move(Vector2i.ZERO,Vector2i(3,0))
		var landing: Vector2i = attack["landing"]
		await game.view.animate_moves([attack],game.cells)
		var expected: Vector3 = game.view.coord_position(landing)
		if game.cells[landing]["capital"] >= 0: expected += Vector3(0.35,0,0.30)
		expect(game.view.unit_actors.get(landing) == actor and not game.view.unit_actors.has(Vector2i.ZERO) and actor.global_position.is_equal_approx(expected), "Playback retains the attacker on its actual landing tile: "+scenario)
		expect(game.view.cells == game.cells and game.view.unit_actors.has(Vector2i(3,0)), "Playback synchronizes the new landing and surviving defender: "+scenario)
	game.rules = approach_fixture("occupied")
	game.active_hex = Vector2i.ZERO
	game.view.render_cells(game.cells)
	game.refresh_ui()
	var restored := Replay.position(game.rules)
	var blocked := [false]
	var callback := func(_action,stage):
		if stage == "blocked": blocked[0] = true
	game.view.motion_stage.connect(callback)
	game.click_hex(Vector2i.ZERO,"unit")
	game.click_hex(Vector2i(3,0),"unit")
	while game.busy and not blocked[0]: await process_frame
	game.cancel_action()
	await process_frame
	await process_frame
	game.view.motion_stage.disconnect(callback)
	expect(blocked[0] and Replay.position(game.rules) == restored and game.view.cells == game.cells and game.view.unit_actors.has(Vector2i.ZERO), "Cancelling after impact restores the original positions and entrenchment")
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
func run() -> void:
	rules_checks()
	approach_checks()
	await ui_checks()
	print("Entrench checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
