extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, text_value: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(text_value)

func run() -> void:
	var video_preferences = root.get_node("Video")
	var original_transitions: bool = video_preferences.level_transitions
	video_preferences.set_preference(&"level_transitions", false, false)
	var gameplay = root.get_node("Gameplay")
	var original_mode: String = gameplay.rule_mode
	gameplay.set_rules("classic", false)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await app.start_new_game(42)
	var game = app.game
	var original_cells: Dictionary = game.cells.duplicate(true)
	var original_kingdoms: Dictionary = game.rules.kingdoms.duplicate(true)
	var original_random_state: int = game.rules.rng.state
	expect(game.pause_button.text == "" and game.pause_button.icon != null, "In-game menu button is an icon-only cogwheel")
	for menu in [app.menus.main_panel, app.menus.pause_panel]:
		var options_found := false
		for node in menu.find_children("*", "Button", true, false):
			if node.text == "Options":
				options_found = node.icon == null
		expect(options_found, "Main and pause menu Options buttons have text and no cogwheel")
	game.toggle_stats()
	var restart_found := false
	for node in game.stats_panel.find_children("*", "Button", true, false):
		restart_found = restart_found or node.text == "New island"
	expect(not restart_found, "Stats contains no New island action")
	game.toggle_stats()
	expect(game.money_label.text == "16 G" and game.income_label.text == "+6 G", "Current gold and next-turn net income include currency units")
	expect(game.money_label.position.y == game.income_label.position.y and game.money_label.get_theme_font_size("font_size") == game.income_label.get_theme_font_size("font_size"), "Gold and expected income share a visual baseline and font size")
	for amount in [3, 16, 1234]:
		game.update_gold(amount, 7, game.active_kingdom()["capital"])
		expect(is_equal_approx(game.income_label.position.x - game.money_label.position.x - game.money_label.get_minimum_size().x, 10), "Gold values retain a small fixed gap for short and long amounts")
	game.reset_gold_feedback()
	game.refresh_ui()
	game.open_shop("recruit")
	for index in range(3):
		expect(game.shop_items.get_child(index).get_node("Cost").text == "%d G" % [10, 20, 40][index], "Each recruitment card shows its purchase price")
	game.open_shop("build")
	expect(game.shop_items.get_child(0).get_node("Cost").text == "15 G" and game.shop_items.get_child(1).get_node("Cost").text == "20 G", "Building cards show tower and house costs")
	game.cancel_action()
	game.choose_unit(1)
	var destination := game.NONE as Vector2i
	for coord in game.active_kingdom()["hexes"]:
		if game.cells[coord]["unit"] == 0 and game.cells[coord]["capital"] < 0:
			destination = coord
			break
	game.click_hex(destination)
	var ripple: MeshInstance3D = game.view.animation_root.get_node("ActionRipple")
	expect(ripple.material_override.albedo_color == game.view.PLACEMENT_COLOR and ripple.position.x == game.view.coord_position(destination).x, "Player recruitment uses the same tile ripple and color as enemy recruitment")
	expect(game.money_label.text == "6 G" and game.gold_delta_label.text == "-10 G" and game.gold_tween.is_running(), "Buying a unit updates gold immediately and triggers spending feedback")
	game.rules.begin_turn(0)
	game.refresh_ui()
	expect(game.money_label.text == "11 G" and game.gold_delta_label.text == "+5 G", "New-turn income triggers positive gold feedback")
	await create_timer(0.75).timeout
	expect(game.money_label.scale.is_equal_approx(Vector2.ONE) and game.gold_delta_label.modulate.a < 0.01, "Gold pulse and floating delta settle automatically")
	expect(not game.view.animation_root.has_node("ActionRipple"), "Recruitment ripple clears itself after fading")
	game.active_kingdom()["gold"] = 100
	game.refresh_ui()
	game.choose_unit(2)
	game.click_hex(destination)
	expect(game.view.animation_root.has_node("ActionRipple") and game.cells[destination]["unit"] == 2 and not game.busy, "Player upgrade produces the ripple without blocking movement")
	var upgrade_ripple: Node = game.view.animation_root.get_node("ActionRipple")
	game.cells[destination]["moved"] = true
	game.choose_unit(3)
	game.click_hex(destination)
	expect(game.view.animation_root.get_node("ActionRipple") == upgrade_ripple, "Failed upgrade does not create another ripple")
	app.pause_game()
	expect(app.menus.restart_button.get_parent() == app.menus.pause_panel and app.menus.restart_button.is_visible_in_tree(), "Pause menu exposes Restart")
	app.menus.open_options(app.menus.Screen.PAUSE)
	expect(not app.menus.restart_button.is_visible_in_tree() and app.menus.options_back.size.x == 432, "Options contains only its full-width Back footer")
	app.menus.close_options()
	var before_restart: Dictionary = game.cells.duplicate(true)
	app.menus.restart_button.pressed.emit()
	expect(app.menus.screen == app.menus.Screen.CONFIRM and app.game == game and game.cells == before_restart, "Restart asks for confirmation without changing the level")
	var cancel_restart := InputEventKey.new()
	cancel_restart.keycode = KEY_ESCAPE
	cancel_restart.pressed = true
	app.menus._unhandled_input(cancel_restart)
	expect(app.menus.screen == app.menus.Screen.PAUSE and app.game == game and paused, "Cancelling restart returns to Pause and preserves progress")
	app.menus.restart_button.pressed.emit()
	app.menus.confirm_action_button.pressed.emit()
	while app.transitioning:
		await process_frame
	game = app.game
	expect(not paused and app.menus.screen == app.menus.Screen.HIDDEN, "Restart returns directly to unpaused gameplay")
	expect(game.rules.level_seed == 42 and game.cells == original_cells and game.rules.kingdoms == original_kingdoms and game.rules.rng.state == original_random_state, "Restart restores the same map, ownership, troops, treasuries and RNG state")
	expect(game.round_number == 1 and not game.busy, "Restart resets the turn and input state")
	game.end_turn()
	await create_timer(0.03).timeout
	app.pause_game()
	app.menus.open_options(app.menus.Screen.PAUSE)
	await app.restart_current_level()
	game = app.game
	expect(game.cells == original_cells and not game.busy, "Restart during an opponent phase leaves no old actions in the new level")
	var source := Vector2i(0, 0)
	var target := Vector2i(1, 0)
	var next := Vector2i(2, 0)
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for coord in [source, target, next]:
		game.cells[coord] = game.rules.make_cell(0)
	game.cells[Vector2i(5, 0)] = game.rules.make_cell(1)
	game.cells[Vector2i(6, 0)] = game.rules.make_cell(1)
	game.rules.rebuild_kingdoms()
	game.cells[source]["unit"] = 1
	game.cells[target]["unit"] = 1
	game.active_hex = source
	game.view.render_cells(game.cells)
	game.refresh_ui()
	game.click_hex(source)
	await game.click_hex(target)
	expect(game.cells[target]["unit"] == 2 and not game.cells[target]["moved"] and game.selected == target, "Merged unit is immediately ready and selected")
	await game.click_hex(next)
	expect(game.cells[next]["unit"] == 2 and game.cells[next]["moved"], "Merged unit can make one subsequent normal move")
	game.cells[source]["unit"] = 1
	game.cells[target]["unit"] = 1
	game.cells[target]["moved"] = true
	game.view.render_cells(game.cells)
	game.refresh_ui()
	game.click_hex(source)
	await game.click_hex(target)
	expect(game.cells[target]["unit"] == 2 and game.cells[target]["moved"] and game.selected == game.NONE, "Merge into a moved ally stays spent and is not automatically selected")
	expect(not game.rules.can_move(target, source), "Player cannot move the merged unit after receiving a moved ally")
	var rules = load("res://src/game/kingdom_rules.gd").new()
	for coord in [source, target, next]:
		rules.cells[coord] = rules.make_cell(1)
	# Give the merged Soldier a useful defended target rather than expecting
	# the new holding policy to reposition on an entirely friendly island.
	rules.cells[Vector2i(3, 0)] = rules.make_cell(0)
	rules.cells[Vector2i(4, 0)] = rules.make_cell(0)
	rules.rebuild_kingdoms()
	rules.cells[source]["unit"] = 1
	rules.cells[target]["unit"] = 1
	var first_wave: Array = rules.ai_movements(1)
	expect(first_wave.size() == 1 and first_wave[0]["kind"] == "merge", "AI merges are isolated from their dependent movement in the same batch")
	var second_wave: Array = rules.ai_movements(1)
	expect(second_wave.size() == 1 and second_wave[0]["before_source"]["unit"] == 2, "AI can move its merged unit in a later batch of the same turn")
	app.return_to_main_menu()
	while app.retiring_games > 0:
		await process_frame
	app.menus.open_options(app.menus.Screen.MAIN)
	expect(not app.menus.restart_button.is_visible_in_tree(), "Main-menu options do not offer a restart without a current level")
	root.get_node("Sound").stop_all()
	gameplay.set_rules(original_mode, false)
	await create_timer(1.20).timeout
	print("Economy and restart checks: %d passed, %d failed" % [checks - failures, failures])
	video_preferences.set_preference(&"level_transitions", original_transitions, false)
	quit(1 if failures else 0)
