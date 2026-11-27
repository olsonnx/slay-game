extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
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

func castle_fixture(rules) -> void:
	rules.cells.clear()
	rules.kingdoms.clear()
	for coord in [Vector2i(-2, 0), Vector2i(-1, 0)]:
		rules.cells[coord] = rules.make_cell(0)
	for coord in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, -1), Vector2i(2, 0), Vector2i(3, 0)]:
		rules.cells[coord] = rules.make_cell(1)
	for coord in [Vector2i(-1, 1), Vector2i(-2, 1)]:
		rules.cells[coord] = rules.make_cell(2)
	rules.cells[Vector2i(0, -1)] = rules.make_cell()
	rules.cells[Vector2i(-2, 0)]["capital"] = 0
	rules.cells[Vector2i(0, 0)]["capital"] = 1
	rules.cells[Vector2i(-2, 1)]["capital"] = 2
	rules.cells[Vector2i(-1, 0)]["unit"] = 3
	rules.cells[Vector2i(0, 1)]["unit"] = 1
	rules.cells[Vector2i(1, -1)]["building"] = "house"
	rules.cells[Vector2i(0, 0)]["mana_source"] = true
	rules.rebuild_kingdoms()
	for kingdom in rules.kingdoms.values():
		kingdom["gold"] = 50
		Fixtures.fund_mana(rules, kingdom["owner"], 5)

func run() -> void:
	var video_preferences = root.get_node("Video")
	var original_transitions: bool = video_preferences.level_transitions
	video_preferences.set_preference(&"level_transitions", false, false)
	var opening = Rules.new()
	opening.rule_mode = "modern"
	opening.generate(42)
	var opening_kingdom: Dictionary = opening.kingdoms.values()[0]
	var opening_owner: int = opening_kingdom["owner"]
	var placements: Array = []
	for coord in opening_kingdom["hexes"]:
		if opening.can_recruit(coord,opening_owner,1) and opening.cells[coord]["unit"] == 0 and not opening.cells[coord]["tree"]:
			placements.append(coord)
	expect(not opening.cast_spell("summon", placements[1], opening_owner), "Starting one mana cannot pay the two-mana Summon cost")
	opening.set_mana(opening_owner, 2)
	expect(opening.recruit(placements[0], opening_owner) and opening.cast_spell("summon", placements[1], opening_owner), "A funded Summon and paid recruit create two ready Scouts")
	expect(opening_kingdom["gold"] == 0 and opening.income(opening_kingdom) - opening.upkeep(opening_kingdom) == -1, "Three-Scout opening spends starting gold and exceeds initial income by one")
	expect(opening.begin_turn(opening_owner) == 3 and opening_kingdom["gold"] == 0, "An unfunded three-Scout opening bankrupts at settlement")
	for mode in ["modern"]:
		var wages = Rules.new()
		wages.rule_mode = mode
		wages.generate(42)
		var bank: Dictionary = wages.kingdoms.values()[0]
		for coord in bank["hexes"]:
			wages.cells[coord]["unit"] = 0
		for tier in range(1, 4):
			wages.cells[bank["hexes"][tier - 1]]["unit"] = tier
			expect(wages.Catalog.unit_tooltip(tier).contains("upkeep −%d G / turn" % [0, 4, 12, 36][tier]), "Recruitment descriptions show the active ruleset's wages")
		expect(wages.upkeep(bank) == 52, "Army upkeep uses the current rates")
		if mode == "modern":
			for coord in bank["hexes"]:
				wages.cells[coord]["unit"] = 0
			wages.cells[bank["capital"]]["unit"] = 3
			bank["gold"] = 1
			expect(wages.begin_turn(bank["owner"]) == 1 and bank["gold"] == 0 and wages.cells[bank["capital"]]["grave"], "A Knight bankrupts an eleven-income kingdom once its reserve cannot cover wages")
	for seed_value in range(100):
		var rules = Rules.new()
		rules.rule_mode = "modern"
		rules.generate(seed_value)
		expect(rules.starting_land_reachable(), "Modern resource generation preserves reachable land")
		var sources: Array = []
		var neutral_land := 0
		for coord in rules.cells:
			var cell: Dictionary = rules.cells[coord]
			expect(cell["value"] == 0 if cell["mountain"] else cell["value"] >= 1 and cell["value"] <= 3, "Mountains have no value; initial habitable province values range from one to three")
			if cell.owner < 0 and not cell.mountain and cell.building != "bridge": neutral_land += 1
			if cell["mana_source"]:
				sources.append(coord)
		expect(sources.size() >= 5 and sources.size() <= 2 * rules.faction_count - 1 + preload("res://src/game/mana_resources.gd").extra_source_budget(neutral_land), "Mana sources are sparse with at least one neutral source to contest")
		for kingdom in rules.kingdoms.values():
			var value := 0
			var source_count := 0
			for coord in kingdom["hexes"]:
				value += rules.cells[coord]["value"]
				if rules.cells[coord]["mana_source"]:
					source_count += 1
			expect(value == 11 and rules.income(kingdom) == 11 and rules.income(kingdom) - rules.upkeep(kingdom) == 7, "Each starting kingdom has eleven province value and preserves seven net income")
			expect(source_count == 1 and rules.cells[kingdom["capital"]]["mana_source"], "Each kingdom starts with one mana source in its castle")
			expect(kingdom["gold"] == 10 and rules.get_mana(kingdom["owner"]) == 1, "Starting gold and faction mana are equal")
		var copy = Rules.new()
		copy.rule_mode = "modern"
		copy.generate(seed_value)
		expect(copy.cells == rules.cells and copy.rng.state == rules.rng.state, "Modern same-seed generation is deterministic")
		if seed_value < 5:
			for turn in range(15):
				for faction in range(4):
					rules.ai_turn(faction)
					expect(rules.territory(faction) <= rules.cells.size(), "Territory counts provinces rather than values")
					rules.rebuild_kingdoms()
					for kingdom in rules.kingdoms.values():
						expect(kingdom["gold"] >= 0 and rules.get_mana(kingdom["owner"]) <= rules.mana_capacity(kingdom["owner"]), "AI leaves valid kingdom gold and capped faction mana")
				rules.spread_trees()
	var rules = Rules.new()
	rules.rule_mode = "modern"
	rules.generate(42)
	var kingdom: Dictionary = rules.kingdoms.values()[0]
	var target: Vector2i = kingdom["capital"]
	var owner: int = kingdom["owner"]
	kingdom["gold"] = 1000
	var value: int = rules.cells[target]["value"]
	var cost: int = rules.development_cost(target)
	var income: int = rules.income(kingdom)
	expect(rules.develop(target, owner), "Owned connected provinces can be developed")
	expect(rules.cells[target]["value"] == value + 1 and kingdom["gold"] == 1000 - cost and rules.income(kingdom) == income + 1, "Development spends local gold and increases income by one")
	expect(rules.development_cost(target) == 2 * (value + 1) * (value + 1), "Development costs scale quadratically with value")
	kingdom["gold"] = 0
	expect(not rules.develop(target, owner), "Development cannot overspend")
	kingdom["gold"] = 100000
	while rules.develop(target, owner):
		pass
	expect(rules.cells[target]["value"] == rules.MAX_VALUE, "Development has a finite maximum")
	expect(not rules.develop(target, (owner + 1) % 4), "Cannot develop enemy land")
	rules.cells[target]["tree"] = true
	rules.set_mana(owner, 2)
	var blocked_income: int = rules.income(kingdom)
	expect(rules.cast_spell("summon", target, owner), "Summon creates a Scout on empty friendly land")
	expect(rules.get_mana(owner) == 0 and rules.cells[target]["unit"] == 1 and not rules.cells[target]["tree"] and rules.income(kingdom) == blocked_income + rules.MAX_VALUE, "Summon consumes mana and clears the target's tree")
	rules.cells[target]["unit"] = 0
	rules.cells[target]["grave"] = true
	expect(not rules.cast_spell("summon", target, owner) and rules.cells[target]["grave"], "Spells cannot overspend mana")
	rules.set_mana(owner, 2)
	expect(not rules.cast_spell("unknown", target, owner) and not rules.cast_spell("summon", target, (owner + 1) % 4), "Unknown spells and enemy targets are rejected")
	expect(rules.cast_spell("summon", target, owner) and not rules.cells[target]["grave"], "Summon also clears graves")
	rules.begin_turn(owner)
	expect(rules.get_mana(owner) == 1, "Faction regenerates one mana at the start of its turn")
	rules.rebuild_kingdoms()
	expect(rules.get_mana(owner) == 1, "Rebuilding borders preserves capped faction mana")
	castle_fixture(rules)
	var attacker := Vector2i(-1, 0)
	var castle := Vector2i(0, 0)
	var action: Dictionary = rules.perform_move(attacker, castle)
	expect(action.get("annexed", {}).size() == 3, "Castle capture records only adjacent provinces of its kingdom")
	for coord in action.get("annexed", {}):
		expect(rules.cells[coord]["owner"] == 0, "Adjacent provinces surrender to the attacker")
	expect(rules.cells[Vector2i(2, 0)]["owner"] == 1 and rules.cells[Vector2i(0, -1)]["owner"] == -1 and rules.cells[Vector2i(-1, 1)]["owner"] == 2, "Distant, neutral and other kingdoms' provinces do not surrender")
	expect(rules.cells[Vector2i(0, 1)]["unit"] == 0 and rules.cells[Vector2i(0, 1)]["grave"], "Surrender defeats enemy garrisons and leaves graves")
	expect(rules.cells[Vector2i(1, -1)]["building"] == "house" and rules.cells[castle]["mana_source"], "Surrender preserves neighboring buildings and captured mana sources")
	expect(rules.kingdom_at(Vector2i(2, 0))["gold"] == 0 and rules.get_mana(1) == 3, "Destroyed castle loses gold; lost double-capacity source reduces shared mana")
	expect(rules.kingdom_at(castle)["gold"] == 50 and rules.get_mana(0) == 5, "Attacker's existing gold and shared mana are preserved")
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	castle_fixture(game.rules)
	game.active_hex = Vector2i(-2, 0)
	game.view.render_cells(game.cells)
	game.refresh_ui()
	expect(game.spell_button.visible and game.mana_label.visible, "Modern HUD includes mana and a spell button beside Build")
	game.click_hex(Vector2i(0, -1))
	expect(game.province_view.visible and game.province_view.reveal < 1 and game.province_view.develop_button.disabled, "Neutral province inspector slides up and does not permit development")
	await create_timer(0.30).timeout
	expect(is_equal_approx(game.province_view.reveal, 1), "Province inspector finishes its slide")
	game.click_hex(Vector2i(-2, 0))
	game.develop_province()
	expect(game.cells[Vector2i(-2, 0)]["value"] == 2 and game.money_label.text == "48 G", "Inspector development updates gold and province value")
	game.cancel_action()
	expect(not game.province_view.visible and not game.has_cancellable_action(), "Cancellation closes province details")
	game.open_shop("spells")
	expect(game.shop_title.text == "Spells" and game.shop_items.get_child_count() == 3, "Spells menu exposes the three-spell catalog")
	game.cells[Vector2i(-2, 0)]["tree"] = true
	game.choose_spell("summon")
	expect(game.valid_targets.has(Vector2i(-2, 0)) and not game.valid_targets.has(castle), "Spell tiles show only valid friendly targets")
	game.click_hex(Vector2i(-2, 0))
	expect(not game.cells[Vector2i(-2, 0)]["tree"] and game.cells[Vector2i(-2, 0)]["unit"] == 1 and game.rules.get_mana(0) == 3 and game.action_mode == "", "Player Summon creates a Scout and updates faction mana immediately")
	game.cancel_action()
	game.view.render_cells(game.cells)
	var stages: Dictionary = {}
	game.view.motion_stage.connect(func(_action: Dictionary, stage: String):
		if stage == "occupy":
			stages["before_surrender"] = game.view.cells[Vector2i(1, 0)]["owner"]
		if stage == "surrender":
			stages["after_surrender"] = game.view.cells[Vector2i(1, 0)]["owner"])
	await game.click_hex(attacker)
	await game.click_hex(castle)
	expect(stages.get("before_surrender") == 1 and stages.get("after_surrender") == 0, "Castle takeover visibly precedes the surrender wave")
	expect(game.view.cells == game.cells and not game.busy and game.view.active_motions.is_empty(), "Surrender animation ends at authoritative state and releases gameplay")
	expect(game.view.tile_nodes[castle].has_node("ManaSource"), "Captured castle keeps its visible mana crystals")
	expect(game.view.material(Color("ffe5a2"), true).albedo_color.a == 1, "Castle effect fade does not poison the shared material cache")
	castle_fixture(game.rules)
	game.view.render_cells(game.cells)
	game.active_hex = Vector2i(-2, 0)
	game.refresh_ui()
	var rollback_cells: Dictionary = game.cells.duplicate(true)
	game.click_hex(attacker)
	game.click_hex(castle)
	await create_timer(0.56).timeout
	game.cancel_action()
	await process_frame
	expect(game.cells == rollback_cells and not game.busy and game.view.active_motions.is_empty(), "Cancellation during surrender restores all provinces and resources")
	game.shutdown()
	game.queue_free()
	await process_frame
	var settings = root.get_node("Gameplay")
	var old_mode: String = settings.rule_mode
	var old_path: String = settings.settings_path
	settings.settings_path = "res://artifacts/gameplay_test.cfg"
	settings.set_rules("modern", false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await app.start_new_game(42)
	expect(app.game.rules.is_modern(), "Application starts with the selected Modern rules")
	app.pause_game()
	app.menus.open_options(app.menus.Screen.PAUSE)
	var modern_cells: Dictionary = app.game.cells.duplicate(true)
	var modern_seed: int = app.game.rules.level_seed
	app.restart_current_level()
	while app.transitioning:
		await process_frame
	expect(app.game.rules.level_seed == modern_seed and app.game.cells == modern_cells and app.game.rules.is_modern(), "Modern Restart preserves seed, province values and mana sources")
	app.return_to_main_menu()
	while app.retiring_games > 0:
		await process_frame
	app.menus.open_options(app.menus.Screen.MAIN)
	settings.set_rules(old_mode, false)
	settings.settings_path = old_path
	root.get_node("Sound").stop_all()
	await create_timer(1.2, true).timeout
	print("Modern rules checks: %d passed, %d failed" % [checks - failures, failures])
	video_preferences.set_preference(&"level_transitions", original_transitions, false)
	quit(1 if failures else 0)
