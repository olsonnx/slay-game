extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Grid = preload("res://src/game/hex_grid.gd")
const Fixtures = preload("res://tests/test_fixtures.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func land_fixture(rules) -> void:
	rules.cells.clear()
	rules.kingdoms.clear()
	for coord in [Vector2i(0, 0), Vector2i(0, 1)]:
		rules.cells[coord] = rules.make_cell(0)
	for coord in [Vector2i(2, 0), Vector2i(3, 0)]:
		rules.cells[coord] = rules.make_cell(1)
	rules.cells[Vector2i(1, 0)] = rules.make_cell()
	rules.cells[Vector2i(0, 0)]["capital"] = 0
	rules.cells[Vector2i(3, 0)]["capital"] = 1
	rules.cells[Vector2i(0, 1)]["unit"] = 2
	rules.rebuild_kingdoms()
	for kingdom in rules.kingdoms.values():
		kingdom["gold"] = 50
		Fixtures.fund_mana(rules, kingdom["owner"], 30)

func bridge_fixture(rules) -> void:
	rules.cells.clear()
	rules.kingdoms.clear()
	for coord in [Vector2i(-3, 0), Vector2i(-2, 0)]:
		rules.cells[coord] = rules.make_cell(0)
	for coord in [Vector2i(2, 0), Vector2i(3, 0)]:
		rules.cells[coord] = rules.make_cell(1)
	rules.cells[Vector2i(-3, 0)]["capital"] = 0
	rules.cells[Vector2i(3, 0)]["capital"] = 1
	rules.cells[Vector2i(-2, 0)]["unit"] = 2
	rules.cells[Vector2i(2, 0)]["unit"] = 1
	rules.rebuild_kingdoms()
	for kingdom in rules.kingdoms.values():
		kingdom["gold"] = 100
		Fixtures.fund_mana(rules, kingdom["owner"], 30)

func build_chain(rules) -> void:
	for coord in [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]:
		expect(rules.build_structure(coord, 0, "bridge", Vector2i(-3, 0)), "Bridge chain can extend through empty water")

func seed_legacy_ward(model, coord: Vector2i, faction: int) -> bool:
	# Older replay positions may still contain wards; no spell creates them now.
	model.cells[coord]["fortified"] = true
	model.cells[coord]["fortified_by"] = faction
	return true

func shatter_cost_checks() -> void:
	var rules = Rules.new()
	rules.rule_mode = "modern"
	for coord in [Vector2i.ZERO,Vector2i.RIGHT]: rules.cells[coord] = rules.make_cell(0)
	rules.cells[Vector2i.ZERO]["capital"] = 0
	rules.cells[Vector2i.ZERO]["mana_source"] = true
	rules.rebuild_kingdoms()
	rules.kingdom_at(Vector2i.ZERO)["gold"] = 15
	expect(rules.build_structure(Vector2i.LEFT,0,"bridge",Vector2i.ZERO), "A starting kingdom can build an adjacent crossing")
	expect(rules.mana_capacity(0) == 2, "An ordinary capital source has two mana capacity")
	rules.set_mana(0,1)
	expect(not rules.cast_spell("shatter",Vector2i.LEFT,0,Vector2i.ZERO) and rules.get_mana(0) == 1 and rules.is_bridge(Vector2i.LEFT), "One mana cannot destroy a bridge or charge a rejected cast")
	rules.set_mana(0,2)
	expect(rules.cast_spell("shatter",Vector2i.LEFT,0,Vector2i.ZERO) and rules.get_mana(0) == 0 and not rules.cells.has(Vector2i.LEFT), "A capital's two mana can pay for bridge demolition")

func run() -> void:
	shatter_cost_checks()
	var rules = Rules.new()
	rules.rule_mode = "modern"
	var source := Vector2i(0, 1)
	var tree := Vector2i(1, 0)
	land_fixture(rules)
	rules.cells[tree]["tree"] = true
	var action: Dictionary = rules.perform_move(source, tree)
	expect(rules.kingdom_at(tree)["gold"] == 51 and action["gold_reward"] == 1 and not rules.cells[tree]["tree"], "Capturing and chopping a neutral tree gives exactly one local gold")
	land_fixture(rules)
	rules.cells[source]["unit"] = 0
	rules.cells[source]["tree"] = true
	expect(rules.recruit(source, 0) and rules.kingdom_at(source)["gold"] == 41, "Recruitment clearing a tree pays its normal cost and gives one gold")
	expect(rules.recruit(source, 0, 2) and rules.kingdom_at(source)["gold"] == 31, "Upgrading after clearing cannot claim a second tree reward")
	land_fixture(rules)
	rules.cells[source]["unit"] = 0
	rules.cells[source]["tree"] = true
	expect(rules.cast_spell("summon", source, 0) and rules.kingdom_at(source)["gold"] == 51, "Summon clearing a tree gives one gold")
	var mana: int = rules.get_mana(0)
	expect(not rules.cast_spell("summon", source, 0) and rules.get_mana(0) == mana, "Summon cannot spawn again on an occupied tile or collect repeated rewards")
	rules.cells[source]["unit"] = 0
	rules.cells[source]["grave"] = true
	expect(rules.cast_spell("summon", source, 0) and rules.kingdom_at(source)["gold"] == 51, "Clearing a grave gives no tree reward")
	land_fixture(rules)
	rules.cells[tree]["grave"] = true
	rules.perform_move(source, tree)
	expect(rules.kingdom_at(tree)["gold"] == 50, "Walking onto a grave also gives no gold")
	rules.rule_mode = "modern"
	land_fixture(rules)
	land_fixture(rules)
	rules.cells[tree]["owner"] = 1
	rules.cells[tree]["building"] = "house"
	rules.cells[Vector2i(2, 0)]["unit"] = 1
	rules.rebuild_kingdoms()
	rules.set_mana(1, 30)
	rules.kingdom_at(tree)["gold"] = 50
	expect(seed_legacy_ward(rules, tree, 1), "Legacy enemy wards remain supported in stored positions")
	rules.cells[source]["unit"] = 1
	expect(not rules.can_move(source, tree) and rules.cells[tree]["fortified"], "Insufficient strength cannot damage a ward")
	rules.cells[source]["unit"] = 2
	var enemy_income: int = rules.income(rules.kingdom_at(tree))
	action = rules.perform_move(source, tree)
	expect(action["kind"] == "blocked_attack" and not action["capture"] and action["annexed"].is_empty(), "First successful hit is recorded as a blocked attack")
	expect(rules.cells[source]["unit"] == 2 and rules.cells[source]["moved"] and rules.cells[tree]["owner"] == 1 and rules.cells[tree]["building"] == "house", "Blocked attacker stays on its source and spends its action; structure remains intact")
	expect(not rules.cells[tree]["fortified"] and rules.income(rules.kingdom_at(tree)) == enemy_income and rules.cells[Vector2i(2, 0)]["unit"] == 1, "Absorbed hit removes only the ward, retaining defenders and income")
	rules.cells[Vector2i(0, 0)]["unit"] = 2
	expect(rules.move_unit(Vector2i(0, 0), tree) and rules.cells[tree]["owner"] == 0 and rules.cells[tree]["building"] == "", "A second valid hit captures and destroys the structure normally")
	bridge_fixture(rules)
	var capital := Vector2i(-3, 0)
	build_chain(rules)
	var bridge_target := Vector2i(0, 0)
	var bridge_source := Vector2i(-2, 0)
	expect(rules.move_unit(Vector2i(2, 0), bridge_target), "Enemy Scout can garrison the bridge before fortification")
	rules.begin_turn(1)
	expect(seed_legacy_ward(rules, bridge_target, 1), "Legacy bridge ward fixture is restored")
	rules.cells[bridge_source]["unit"] = 1
	expect(not rules.can_move(bridge_source, bridge_target) and rules.cells[bridge_target]["fortified"], "Insufficient bridge attack strength cannot consume the ward")
	rules.cells[bridge_source]["unit"] = 2
	var bridge_attack: Dictionary = rules.perform_move(bridge_source, bridge_target)
	expect(bridge_attack["kind"] == "blocked_attack" and not bridge_attack["capture"], "Fortified bridge attack uses the same blocked action as owned structures")
	expect(rules.cells[bridge_source]["unit"] == 2 and rules.cells[bridge_source]["moved"] and rules.unit_faction(bridge_target) == 1 and rules.cells[bridge_target]["unit"] == 1, "First bridge hit spends the attacker's move while preserving the defender and both positions")
	expect(not rules.cells[bridge_target]["fortified"] and rules.cells[bridge_target]["fortified_by"] == -1 and rules.cells[bridge_target]["building"] == "bridge", "First bridge hit removes only the ward")
	expect(rules.perform_move(bridge_source, bridge_target).is_empty(), "Spent bridge attacker cannot immediately make the second hit")
	rules.cells[capital]["unit"] = 2
	expect(rules.move_unit(capital, bridge_target) and rules.unit_faction(bridge_target) == 0 and rules.cells[bridge_target]["unit"] == 2 and rules.cells[bridge_target]["owner"] == -1, "Second valid hit takes the garrison's place while keeping the bridge neutral")
	bridge_fixture(rules)
	build_chain(rules)
	expect(seed_legacy_ward(rules, bridge_target, 0) and rules.move_unit(bridge_source, bridge_target) and rules.cells[bridge_target]["fortified"], "Moving onto an empty fortified bridge does not spend its ward")
	bridge_fixture(rules)
	build_chain(rules)
	rules.cells[bridge_source]["unit"] = 1
	rules.cells[bridge_target]["unit"] = 1
	rules.cells[bridge_target]["unit_owner"] = 0
	expect(seed_legacy_ward(rules, bridge_target, 0) and rules.move_unit(bridge_source, bridge_target) and rules.cells[bridge_target]["unit"] == 2 and rules.cells[bridge_target]["fortified"], "Friendly merging on a fortified bridge does not spend its ward")
	bridge_fixture(rules)
	expect(not rules.can_build(Vector2i(0, 0), 0, "bridge", capital) and not rules.can_build(Vector2i(-2, 0), 0, "bridge", capital), "Bridges require adjacent empty water and cannot replace land")
	var owned_before: int = rules.territory(0)
	build_chain(rules)
	expect(rules.kingdom_at(capital)["gold"] == 55 and rules.territory(0) == owned_before and rules.income(rules.kingdom_at(capital)) == 2, "Three bridges cost forty-five gold and add neither owned territory nor income")
	for coord in [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]:
		expect(rules.cells[coord]["owner"] == -1 and rules.cells[coord]["value"] == 0 and rules.cells[coord]["kingdom"] == rules.NONE, "Bridge tiles stay neutral and have no province value or kingdom membership")
	var route: Array = rules.movement_path(Vector2i(-2, 0), Vector2i(2, 0))
	expect(route == [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "Units can cross a bridge chain and attack the opposite shore in one action")
	expect(not rules.can_build(Vector2i(20, 0), 0, "bridge", capital), "Bridge sites stay within camera navigation bounds")
	rules.perform_move(Vector2i(-2, 0), Vector2i(2, 0))
	expect(rules.unit_kingdom(Vector2i(2, 0))["capital"] == capital and rules.upkeep(rules.kingdom_at(capital)) == 12, "A soldier on a newly captured isolated shore is supported and charged through the bridge route")
	rules.begin_turn(0)
	expect(rules.cells[Vector2i(2, 0)]["unit"] == 2 and not rules.cells[Vector2i(2, 0)]["moved"], "A connected soldier across a neutral bridge does not starve")
	expect(rules.move_unit(Vector2i(2, 0), Vector2i(0, 0)), "Units can stop on bridge tiles")
	expect(rules.cells[Vector2i(0, 0)]["owner"] == -1 and rules.unit_faction(Vector2i(0, 0)) == 0 and rules.upkeep(rules.kingdom_at(capital)) == 12, "Bridge soldier retains its faction and contributes local upkeep without claiming the bridge")
	expect(not rules.recruit(Vector2i(0, 0), 0) and not rules.can_develop(Vector2i(0, 0), 0), "Bridges cannot recruit units or develop")
	expect(seed_legacy_ward(rules, Vector2i(0, 0), 0), "Legacy bridge ward survives position loading")
	var remaining_mana: int = rules.get_mana(0)
	expect(rules.cast_spell("shatter", Vector2i(0, 0), 0, capital) and rules.cells.has(Vector2i(0, 0)) and rules.cells[Vector2i(0, 0)]["unit"] == 2 and not rules.cells[Vector2i(0, 0)]["fortified"], "First Shatter breaks the ward without destroying the bridge or its soldier")
	expect(rules.get_mana(0) == remaining_mana - 2, "Absorbed Shatter still spends two mana")
	expect(rules.cast_spell("shatter", Vector2i(0, 0), 0, capital) and not rules.cells.has(Vector2i(0, 0)) and rules.upkeep(rules.kingdom_at(capital)) == 0, "Second Shatter removes the bridge tile and its soldier from economy and topology")
	expect(not rules.can_cast("shatter", capital, 0, capital) and not rules.can_cast("fortify", Vector2i(3, 0), 0, capital), "Demolition cannot destroy owned structures, and removed Fortify rejects")
	bridge_fixture(rules)
	build_chain(rules)
	expect(rules.can_cast("shatter", Vector2i(1, 0), 1, Vector2i(3, 0)), "Opponents can demolish a neutral bridge connected to their shore")
	rules.move_unit(Vector2i(-2, 0), Vector2i(1, 0))
	expect(rules.cast_spell("shatter", Vector2i(0, 0), 0, capital), "Neutral bridge demolition can cut a route behind a soldier")
	expect(rules.unit_kingdom(Vector2i(1, 0)).is_empty(), "Destroyed bridge can sever a soldier's support route")
	rules.begin_turn(0)
	expect(rules.cells[Vector2i(1, 0)]["unit"] == 0 and not rules.cells[Vector2i(1, 0)]["grave"] and not rules.cells[Vector2i(1, 0)]["tree"], "Stranded bridge soldiers starve without planting graves or trees on wood")
	bridge_fixture(rules)
	build_chain(rules)
	rules.move_unit(Vector2i(-2, 0), Vector2i(0, 0))
	rules.kingdom_at(capital)["gold"] = 0
	rules.cells[capital]["tree"] = true
	rules.cells[Vector2i(-2, 0)]["tree"] = true
	rules.begin_turn(0)
	expect(rules.cells[Vector2i(0, 0)]["unit"] == 0, "Local bankruptcy includes soldiers supported on neutral bridges")
	bridge_fixture(rules)
	build_chain(rules)
	rules.move_unit(Vector2i(-2, 0), Vector2i(0, 0))
	for cell in rules.cells.values():
		if cell["owner"] == 0:
			cell["owner"] = 1
			cell["capital"] = -1
	rules.rebuild_kingdoms()
	var death_actions: Array = rules.prepare_ai_turn(0)
	expect(not rules.has_units(0) and death_actions.size() == 1 and death_actions[0]["kind"] == "death", "Factions without land still resolve stranded bridge soldiers rather than leaving permanent ghost armies")
	for q in range(-8, 9):
		for r in range(-8, 9):
			var coord := Vector2i(q, r)
			expect(Grid.from_world(Grid.to_world(coord)) == coord, "Water picking rounds world coordinates back to the correct hex")
	var game = load("res://scenes/main.tscn").instantiate()
	bridge_fixture(rules)
	for coord in [Vector2i(2, 0), Vector2i(3, 0)]:
		rules.cells[coord]["owner"] = 0
		rules.cells[coord]["unit"] = 0
		rules.cells[coord]["capital"] = -1
	rules.cells[Vector2i(3, 0)]["capital"] = 0
	rules.cells[Vector2i(-2, 0)]["unit"] = 3
	rules.rebuild_kingdoms()
	rules.kingdom_at(capital)["gold"] = 100
	rules.kingdom_at(Vector2i(3, 0))["gold"] = 0
	expect(not rules.recruit(Vector2i(2, 0), 0, 1, capital) and not rules.can_build(Vector2i(2, 0), 0, "tower", capital), "Disconnected kingdoms cannot spend the selected kingdom's treasury")
	build_chain(rules)
	var united: Dictionary = rules.kingdom_at(capital)
	expect(rules.kingdom_at(Vector2i(3, 0))["capital"] == united["capital"] and united["gold"] == 55 and united["hexes"].size() == 4, "Neutral bridges unite friendly provinces and combine remaining gold without counting wooden tiles as land")
	expect(rules.can_build(Vector2i(2, 0), 0, "tower", united["capital"]), "Construction can use the shared treasury on the far shore")
	expect(rules.move_unit(Vector2i(-2, 0), Vector2i(2, 0)), "Knight can cross into the reunited kingdom")
	expect(rules.begin_turn(0) == 0 and rules.cells[Vector2i(2, 0)]["unit"] == 3 and united["gold"] == 23, "Crossing Knight draws wages from shared reserves instead of starving in a separate empty treasury")
	Fixtures.fund_mana(rules, 0, 3)
	expect(rules.cast_spell("shatter", Vector2i(0, 0), 0, united["capital"]), "Destroying the crossing removes its economic connection")
	expect(rules.kingdom_at(capital)["capital"] != rules.kingdom_at(Vector2i(2, 0))["capital"] and rules.kingdom_at(Vector2i(2, 0))["gold"] == 0, "Breaking a bridge separates kingdoms and leaves reserves with the surviving capital")
	rules.begin_turn(0)
	expect(rules.cells[Vector2i(2, 0)]["unit"] == 0, "A separated shore must again sustain its own army")
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	bridge_fixture(game.rules)
	for coord in [Vector2i(2, 0), Vector2i(3, 0)]:
		game.cells[coord]["owner"] = 0
		game.cells[coord]["unit"] = 0
		game.cells[coord]["capital"] = -1
	game.cells[Vector2i(3, 0)]["capital"] = 0
	# Keep a real opponent alive: singleton mana fixtures no longer prevent victory.
	for coord in [Vector2i(8, 0), Vector2i(9, 0)]:
		game.cells[coord] = game.rules.make_cell(1)
	game.cells[Vector2i(9, 0)]["capital"] = 1
	game.rules.rebuild_kingdoms()
	for bank in game.rules.kingdoms.values():
		bank["gold"] = 100
	game.active_hex = capital
	game.view.render_cells(game.cells)
	game.choose_unit(1)
	expect(not game.valid_targets.has(Vector2i(2, 0)), "Recruitment highlights only the selected connected kingdom")
	game.click_hex(Vector2i(2, 0), "terrain")
	expect(game.cells[Vector2i(2, 0)]["unit"] == 0 and game.active_hex == capital and game.rules.kingdom_at(Vector2i(2, 0))["gold"] == 100, "Clicking another kingdom during recruitment neither purchases nor silently switches treasury")
	game.choose_building("tower")
	expect(not game.valid_targets.has(Vector2i(2, 0)), "Building highlights only the selected connected kingdom")
	game.click_hex(Vector2i(2, 0), "terrain")
	expect(game.cells[Vector2i(2, 0)]["building"] == "" and game.active_hex == capital, "A building order cannot silently act in another kingdom")
	game.cancel_action()
	bridge_fixture(game.rules)
	game.active_hex = capital
	game.view.render_cells(game.cells)
	game.refresh_ui()
	build_chain(game.rules)
	game.rules.move_unit(Vector2i(2, 0), bridge_target)
	game.rules.begin_turn(1)
	seed_legacy_ward(game.rules, bridge_target, 1)
	game.view.render_cells(game.cells)
	game.refresh_ui()
	var bridge_start: Vector3 = game.view.unit_actors[bridge_source].global_position
	game.click_hex(bridge_source, "unit")
	await game.click_hex(bridge_target, "unit")
	expect(game.view.unit_actors[bridge_source].global_position.is_equal_approx(bridge_start) and game.rules.unit_faction(bridge_target) == 1, "Player's fortified bridge attack jabs and returns while its defender remains")
	expect(not game.view.tile_nodes[bridge_target].has_node("Fortification") and game.view.cells == game.cells and not game.busy, "Fortified bridge playback removes the ward and synchronizes without killing the garrison")
	game.rules.begin_turn(0)
	seed_legacy_ward(game.rules, bridge_target, 1)
	game.view.render_cells(game.cells)
	game.refresh_ui()
	var bridge_rollback: Dictionary = game.cells.duplicate(true)
	var bridge_blocked := [false]
	var bridge_callback := func(_action: Dictionary, stage: String):
		if stage == "blocked":
			bridge_blocked[0] = true
	game.view.motion_stage.connect(bridge_callback)
	game.click_hex(bridge_source, "unit")
	game.click_hex(bridge_target, "unit")
	while game.busy and not bridge_blocked[0]:
		await process_frame
	game.cancel_action()
	game.view.motion_stage.disconnect(bridge_callback)
	await create_timer(0.5).timeout
	expect(bridge_blocked[0] and game.cells == bridge_rollback and game.view.cells == bridge_rollback, "Cancelling after the bridge ward absorbs a hit restores its ward, garrison and attacker action")
	bridge_fixture(game.rules)
	game.active_hex = capital
	game.view.render_cells(game.cells)
	game.refresh_ui()
	game.open_shop("build")
	expect(game.shop_items.get_child_count() == 3 and game.shop_items.get_child(2).get_node("Cost").text == "15 G", "Build menu shows bridge choice and price beside Tower and House")
	game.choose_building("bridge")
	var water := Vector2i(-1, 0)
	expect(game.valid_targets.has(water) and not game.cells.has(water), "Bridge preview highlights water spaces rather than land")
	game.hovered = water
	game.refresh_ui()
	expect(game.view.intent_preview.get_meta("kind") == "bridge" and game.view.intent_preview.has_node("GhostBuilding"), "Hovered bridge destination shows a wooden ghost on water")
	var point: Vector2 = game.view.camera.unproject_position(game.view.coord_position(water))
	expect(game.view.pick_at_screen(point, true)["coord"] == water and game.view.hex_at_screen(point) == game.NONE, "Only bridge placement enables picking empty water")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	game._unhandled_input(click)
	expect(game.cells.has(water) and game.rules.is_bridge(water) and game.money_label.text == "85 G" and game.action_mode == "", "Player click builds a neutral bridge and spends the selected kingdom's gold")
	expect(game.view.tile_nodes[water].has_node("BridgeDeck") and game.view.tile_nodes[water].get_meta("surface").material_override.albedo_color == Color("88613e"), "Built bridge is visibly wooden and brown rather than faction terrain")
	game.click_hex(Vector2i(-2, 0), "unit")
	await game.click_hex(water)
	expect(game.rules.unit_faction(water) == 0 and game.view.unit_actors.has(water) and game.active_capital() == capital, "Player unit stays selectable and its home treasury stays active while standing on a neutral bridge")
	var bridge_actor: Node3D = game.view.unit_actors[water]
	for child in bridge_actor.get_children():
		if child is Sprite3D:
			expect(child.texture == game.view.soldier_texture(2, 0), "Bridge soldier retains its faction's sprite colors")
	game.rules.set_mana(0, 30)
	seed_legacy_ward(game.rules, water, 0)
	game.view.render_cells(game.cells)
	expect(game.view.tile_nodes[water].has_node("Fortification"), "Legacy replay wards remain visible")
	game.choose_spell("shatter")
	game.click_hex(water)
	expect(game.cells.has(water) and not game.cells[water]["fortified"] and not game.view.tile_nodes[water].has_node("Fortification"), "Shatter's first hit removes the visual ward")
	game.choose_spell("shatter")
	game.click_hex(water)
	expect(not game.cells.has(water) and not game.view.tile_nodes.has(water), "Destroying a bridge removes its pickable tile and renderer node")
	land_fixture(game.rules)
	game.active_hex = Vector2i(0, 0)
	game.cells[source]["unit"] = 0
	game.cells[source]["tree"] = true
	game.view.render_cells(game.cells)
	game.refresh_ui()
	game.choose_spell("summon")
	game.click_hex(source)
	expect(game.money_label.text == "51 G" and game.gold_delta_label.text == "+1 G", "Magic clearing shows the one-gold reward in currency feedback")
	land_fixture(game.rules)
	game.cells[tree]["owner"] = 1
	game.cells[tree]["capital"] = 1
	game.cells[Vector2i(3, 0)]["capital"] = -1
	game.cells[tree]["unit"] = 1
	game.rules.rebuild_kingdoms()
	game.rules.kingdom_at(tree)["gold"] = 50
	game.rules.set_mana(1, 30)
	seed_legacy_ward(game.rules, tree, 1)
	game.active_hex = Vector2i(0, 0)
	game.view.render_cells(game.cells)
	game.refresh_ui()
	var attacker: Node3D = game.view.unit_actors[source]
	var defender: Node3D = game.view.unit_actors[tree]
	var original_position := attacker.global_position
	var stages: Dictionary = {}
	var stage_callback := func(action_data: Dictionary, stage: String):
		if action_data["kind"] == "blocked_attack":
			if stage == "jab":
				stages["jab"] = attacker.global_position != original_position
			if stage == "blocked":
				stages["defender_alive"] = defender.visible
	game.view.motion_stage.connect(stage_callback)
	game.click_hex(source, "unit")
	await game.click_hex(tree)
	game.view.motion_stage.disconnect(stage_callback)
	expect(stages.get("jab", false) and stages.get("defender_alive", false), "Blocked attack visibly jabs and preserves its defender at impact")
	expect(game.view.unit_actors[source].global_position.is_equal_approx(original_position) and game.cells[source]["moved"] and game.cells[tree]["capital"] == 1, "Blocked attacker visibly returns to its original hex without taking the castle")
	expect(game.view.cells == game.cells and game.player_move_snapshot.is_empty() and not game.busy, "Blocked attack playback ends with a synchronized board and released controls")
	game.rules.begin_turn(0)
	seed_legacy_ward(game.rules, tree, 1)
	game.view.render_cells(game.cells)
	game.refresh_ui()
	var rollback_cells: Dictionary = game.cells.duplicate(true)
	var rollback_kingdoms: Dictionary = game.rules.kingdoms.duplicate(true)
	game.click_hex(source, "unit")
	game.click_hex(tree)
	await create_timer(0.30).timeout
	game.cancel_action()
	await process_frame
	expect(game.cells == rollback_cells and game.rules.kingdoms == rollback_kingdoms and game.cells[tree]["fortified"], "Cancelling a blocked attack restores the ward, move and all local resources")
	game.cancel_action()
	game.rules.cells[tree]["owner"] = -1
	game.rules.cells[tree]["capital"] = -1
	game.rules.cells[tree]["unit"] = 0
	game.rules.cells[tree]["fortified"] = false
	game.rules.cells[tree]["tree"] = true
	game.rules.rebuild_kingdoms()
	game.view.render_cells(game.cells)
	game.refresh_ui()
	rollback_kingdoms = game.rules.kingdoms.duplicate(true)
	game.click_hex(source, "unit")
	game.click_hex(tree)
	await create_timer(0.05).timeout
	game.cancel_action()
	await process_frame
	expect(game.rules.kingdoms == rollback_kingdoms and game.cells[tree]["tree"], "Cancelled chopping refunds the tree reward rather than allowing gold farming")
	expect(game.recruit_button.position.y < game.gold_control.position.y and game.spell_button.position.y < game.mana_control.position.y, "Action buttons are above the gold and mana resource row")
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Expansion checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
