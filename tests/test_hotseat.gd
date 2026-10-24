extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func run() -> void:
	var initial_rules: String = root.get_node("Gameplay").rule_mode
	root.get_node("Gameplay").set_rules("modern",false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await process_frame
	var menus = app.menus
	menus.show_screen(menus.Screen.MULTIPLAYER)
	expect(menus.multiplayer_panel.visible and not menus.setup_panel.visible, "Multiplayer has its own setup screen")
	menus.show_screen(menus.Screen.SETUP)
	expect(menus.setup_panel.visible and not menus.multiplayer_panel.visible and not menus.difficulty_choice.disabled, "Quick Play remains solo with editable difficulty")
	await app.start_new_game(123, "very_small", "easy", 3, {}, 3)
	var game = app.game
	expect(game.rules.human_factions == [0, 1, 2] and not game.commands_locked(), "A hotseat session is immediately playable")
	var starting_cells: Dictionary = game.cells.duplicate(true)
	var starting_kingdoms: Dictionary = game.rules.kingdoms.duplicate(true)
	await game.end_turn()
	expect(game.player_faction == 1 and game.active_faction == 1 and game.round_number == 1, "Ending Fern's turn hands off to Ember within the same round")
	expect(game.active_kingdom()["owner"] == 1 and game.level_label.text == "Ember" and game.hud.country_flag.design.field == game.COLORS[1].to_html(false) and game.round_label.text.contains("Hotseat"), "HUD and treasury follow Ember")
	var capital: Vector2i = game.active_capital()
	game.rules.kingdoms[capital]["gold"] = 100
	var fern_gold: int = 0
	for kingdom in game.rules.kingdoms.values():
		if kingdom["owner"] == 0: fern_gold += kingdom["gold"]
	game.develop_province() # No inspected tile: harmless.
	var target: Vector2i = game.NONE
	for coord in game.active_kingdom()["hexes"]:
		if game.rules.can_recruit(coord, 1, 1, capital):
			target = coord
			break
	game.choose_unit(1)
	await game.click_hex(target)
	expect(target != game.NONE and game.cells[target]["unit"] > 0 and game.rules.unit_faction(target) == 1, "Ember recruits its own soldier")
	var fern_after := 0
	for kingdom in game.rules.kingdoms.values():
		if kingdom["owner"] == 0: fern_after += kingdom["gold"]
	expect(fern_after == fern_gold and game.rules.kingdoms[capital]["gold"] == 90, "Ember purchases spend only Ember's local gold")
	game.inspected_hex = capital
	game.develop_province()
	expect(game.cells[capital]["value"] > starting_cells[capital]["value"], "Ember can develop its province")
	game.rules.set_effect(1, "free_spell", true)
	game.choose_spell("trailblaze")
	await game.click_hex(capital)
	expect(game.rules.has_effect(1, "trailblaze") and not game.rules.has_effect(0, "trailblaze"), "Spells and gifts belong to the seated human")
	game.open_shop("recruit")
	await game.end_turn()
	expect(game.player_faction == 2 and game.selected == game.NONE and game.action_mode == "" and not game.shop_panel.visible, "Handoff clears selection, purchases and menus")
	var source: Vector2i = game.NONE
	for coord in game.active_kingdom()["hexes"]:
		if game.cells[coord]["unit"] > 0:
			source = coord
	await game.click_hex(source)
	var destination: Vector2i = game.NONE
	for coord in game.valid_targets:
		if game.cells[coord]["owner"] == 2 and game.cells[coord]["unit"] == 0:
			destination = coord
			break
	var before_move: Dictionary = game.cells.duplicate(true)
	game.click_hex(destination)
	expect(game.busy, "A non-Fern human can start a move")
	game.cancel_action()
	expect(not game.busy and game.active_faction == 2 and game.player_faction == 2 and game.cells == before_move, "Cancelling a non-Fern move restores its board and preserves its seat")
	# Let the cancelled animation's awaiting command unwind before retiring it.
	await process_frame
	await process_frame
	await game.end_turn()
	expect(game.player_faction == 0 and game.round_number == 2, "A full human rotation advances exactly one round")
	app.pause_game()
	expect(paused, "A local turn can be paused")
	app.continue_game()
	expect(not game.commands_locked(), "Resume restores the active local player")
	await app.restart_current_level()
	game = app.game
	expect(game.initial_human_count == 3, "Restart preserves player count")
	expect(game.cells == starting_cells and game.rules.kingdoms == starting_kingdoms, "Restart reproduces the initial hotseat map and economy")
	await app.return_to_main_menu()
	await app.start_new_game(123, "very_small", "easy", 3, {}, 2)
	game = app.game
	expect(not game.commands_locked(), "Local turns are playable without a handoff screen")
	game.view.playback.set_speed_scale(6.0)
	await game.end_turn()
	expect(game.player_faction == 1 and game.round_number == 1, "Mixed games stop at the next human")
	await game.end_turn()
	expect(game.player_faction == 0 and game.round_number == 2 and not game.busy, "AI completes its phase between humans and the next round")
	# Eliminate Fern while Ember and AI still retain capitals.
	for cell in game.cells.values():
		if cell["owner"] == 0:
			cell["owner"] = -1
			cell["capital"] = -1
			cell["unit"] = 0
	game.rules.rebuild_kingdoms()
	game.cells[Vector2i(40, 0)] = game.rules.make_cell(0)
	game.cells[Vector2i(40, 0)]["building"] = "house"
	game.cells[Vector2i(40, 0)]["unit"] = 1
	game.rules.rebuild_kingdoms()
	game.check_winner()
	expect(not game.game_over, "One eliminated human does not end the other players' match")
	await game.end_turn()
	expect(game.player_faction == 1, "The surviving human continues")
	await game.end_turn()
	expect(game.player_faction == 1 and game.round_number == 3, "The next rotation skips the eliminated human")
	expect(not game.rules.has_units(0), "Stranded armies settle without handing an empty turn to an eliminated player")
	for cell in game.cells.values():
		if cell["owner"] == 2:
			cell["capital"] = -1
	game.check_winner()
	expect(game.game_over and game.winner_faction == 1 and game.message == "Victory for Ember!", "The surviving capital owner wins, including non-Fern players")
	expect(paused and menus.defeat_description.text == "Victory for Ember!", "Match results offer restart and main menu")
	await app.return_to_main_menu()
	await app.start_new_game(123, "very_small", "easy", 4, {}, 2)
	game = app.game
	for cell in game.cells.values():
		if cell["owner"] in [0, 1]:
			cell["owner"] = -1
			cell["capital"] = -1
			cell["unit"] = 0
	game.rules.rebuild_kingdoms()
	for faction in [0, 1]:
		var remnant := Vector2i(40 + faction * 4, 0)
		game.cells[remnant] = game.rules.make_cell(faction)
		game.cells[remnant]["building"] = "house"
	game.rules.rebuild_kingdoms()
	game.check_winner()
	expect(game.game_over and game.message.contains("all local kingdoms"), "Isolated human houses cannot keep the match in an endless AI loop")
	await app.return_to_main_menu()
	var gameplay = root.get_node("Gameplay")
	var original_rules: String = gameplay.rule_mode
	gameplay.set_rules("modern", false)
	await app.start_new_game(456, "small", "easy", 6, {}, 6)
	game = app.game
	expect(game.rules.human_factions.size() == 6 and game.rules.is_modern(), "The current rules support six local players")
	for seat in range(1, 7):
		await game.end_turn()
		expect(game.player_faction == seat % 6 and not game.busy, "Every local seat receives a controllable turn")
	expect(game.round_number == 2, "Six seats form one round")
	gameplay.set_rules(original_rules, false)
	await app.return_to_main_menu()
	await app.start_new_game(123, "very_small", "easy", 2)
	expect(not app.game.is_hotseat() and not app.game.commands_locked(), "Solo sessions retain their existing flow")
	await app.return_to_main_menu()
	app.queue_free()
	await process_frame
	check_encounters()
	check_settings()
	root.get_node("Gameplay").set_rules(initial_rules,false)
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Hotseat checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

func check_encounters() -> void:
	for human in [true, false]:
		var rules = Rules.new()
		rules.rule_mode = "modern"
		rules.human_factions = [0, 1] if human else [0]
		for q in range(4):
			rules.cells[Vector2i(q, 0)] = rules.make_cell(1 if q < 3 else -1)
		rules.cells[Vector2i(0, 0)]["capital"] = 1
		rules.cells[Vector2i(1, 0)]["unit"] = 1
		rules.cells[Vector2i(3, 0)]["event"] = "wizard"
		rules.rebuild_kingdoms()
		rules.perform_move(Vector2i(1, 0), Vector2i(3, 0))
		expect(rules.pending_events.size() == (1 if human else 0), "Encounters await a choice only for human-controlled factions")
		if human:
			rules.resolve_event(rules.pending_events[0], 0)
			expect(rules.has_effect(1, "free_spell") and not rules.has_effect(0, "free_spell"), "Encounter rewards go to the capturing human")

func check_settings() -> void:
	var settings = load("res://src/settings/gameplay_settings.gd").new()
	settings.settings_path = "res://artifacts/hotseat_settings_test.cfg"
	var config := preload("res://src/game/match_setup.gd").normalize({"count":6})
	settings.set_multiplayer_setup(config)
	var restored = load("res://src/settings/gameplay_settings.gd").new()
	restored.load_settings(settings.settings_path)
	expect(restored.multiplayer_setup == config, "The complete multiplayer configuration persists")
	settings.free()
	restored.free()
	DirAccess.remove_absolute("res://artifacts/hotseat_settings_test.cfg")
