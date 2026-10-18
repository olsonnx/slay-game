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

func escape(target: Node) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	target._unhandled_input(event)

func run() -> void:
	var video_preferences = root.get_node("Video")
	var original_transitions: bool = video_preferences.level_transitions
	video_preferences.set_preference(&"level_transitions", false, false)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	expect(app.game == null and app.menus.screen == app.menus.Screen.MAIN and not paused, "Application starts in a basic main menu")
	app.menus.open_options(app.menus.Screen.MAIN)
	expect(app.menus.options_panel.visible, "Options is accessible before a game exists")
	escape(app.menus)
	expect(app.menus.screen == app.menus.Screen.MAIN, "Escape backs out of main menu options")
	await app.start_new_game()
	var game = app.game
	expect(is_instance_valid(game) and not app.menus.backdrop.visible, "New Game creates a gameplay session and hides the main menu")
	game.choose_unit(1)
	escape(game)
	expect(game.action_mode == "" and not paused, "Escape cancels placement before opening pause")
	game.open_shop("build")
	escape(game)
	expect(not game.shop_panel.visible and not paused, "Escape closes action menus first")
	game.toggle_stats()
	escape(game)
	expect(not game.stats_shade.visible and not paused, "Escape closes Stats before pausing")
	escape(game)
	expect(paused and app.menus.screen == app.menus.Screen.PAUSE and not game.ui_root.visible, "Escape with no pending action opens a full pause screen")
	var camera_before: Vector3 = game.view.camera.position
	var round_before: int = game.round_number
	game.choose_unit(1)
	game.end_turn()
	expect(game.action_mode == "" and not game.busy, "Gameplay commands cannot execute underneath the pause screen")
	await create_timer(0.15, true).timeout
	expect(game.view.camera.position == camera_before and game.round_number == round_before, "Paused game leaves camera and turn state frozen")
	app.menus.open_options(app.menus.Screen.PAUSE)
	expect(paused and app.menus.options_view.video_page != null, "Pause options contains audio and video controls")
	escape(app.menus)
	expect(paused and app.menus.screen == app.menus.Screen.PAUSE, "Escape from pause options returns to Pause without resuming")
	escape(app.menus)
	expect(not paused and game.ui_root.visible, "Escape from Pause continues the game")
	var owned: Array = game.active_kingdom()["hexes"]
	var source := game.NONE as Vector2i
	for coord in owned:
		if game.cells[coord]["unit"] > 0:
			source = coord
	game.click_hex(source)
	var destination := game.NONE as Vector2i
	for coord in game.valid_targets:
		# This test exercises pause/resume, so use friendly land without an encounter.
		if game.cells[coord]["owner"] == 0 and game.cells[coord]["unit"] == 0:
			destination = coord
			break
	game.click_hex(destination)
	await create_timer(0.04, true).timeout
	game.pause_button.pressed.emit()
	expect(paused and game.busy and game.view.is_animating, "Pause button can freeze an in-flight player move without cancelling it")
	var actor: Node3D = game.view.active_motions[source]["actor"]
	var position_before := actor.global_position
	await create_timer(0.16, true).timeout
	expect(actor.global_position == position_before and game.busy, "Entire moving actor stays frozen while paused")
	app.continue_game()
	while game.busy:
		await process_frame
	expect(game.cells[destination]["unit"] > 0, "Continue completes the original movement")
	game.end_turn()
	await create_timer(0.03, true).timeout
	app.pause_game()
	var phase_before: int = game.active_faction
	await create_timer(0.50, true).timeout
	expect(paused and game.active_faction == phase_before and game.busy, "Pause also freezes opponent phase timers and animations")
	app.continue_game()
	while game.busy:
		await process_frame
	expect(game.round_number == round_before + 1, "Opponent turn resumes and completes normally")
	var video = root.get_node("Video")
	var values: Dictionary = {}
	for key in [&"fullscreen", &"resolution", &"vsync", &"antialiasing", &"shadows", &"background", &"stylized_water", &"internal_borders"]:
		values[key] = video.get(key)
	var old_path: String = video.settings_path
	video.settings_path = "res://artifacts/video_test.cfg"
	var board_before: Dictionary = game.cells.duplicate(true)
	var camera_focus: Vector3 = game.view.focus
	var camera_zoom: float = game.view.zoom
	app.pause_game()
	app.menus.open_options(app.menus.Screen.PAUSE)
	var background_choice: OptionButton = app.menus.options_view.background_choice
	var borders: HSlider = app.menus.options_view.internal_borders_slider
	var water_toggle: CheckButton = app.menus.options_view.stylized_water_toggle
	var water_factory = load("res://src/rendering/water_surface.gd")
	water_toggle.button_pressed = true
	expect(video.stylized_water and game.view.water.material_override.shader == water_factory.ShaderSource, "Stylized water applies immediately while paused")
	expect(app.menus.menu_background.map.water.material_override.shader == water_factory.ShaderSource, "Water style also updates the menu background")
	water_toggle.button_pressed = false
	expect(not video.stylized_water and game.view.water.material_override.shader == water_factory.OriginalShader, "Disabling stylized water restores the original shader")
	water_toggle.button_pressed = true
	borders.value = 75
	expect(paused and is_equal_approx(video.internal_borders, 0.75) and is_equal_approx(game.view.internal_border_visibility, 0.75), "Internal-border slider applies immediately while paused")
	expect(app.menus.options_view.internal_borders_value.text == "75%", "Internal-border slider shows its current percentage")
	expect(game.cells == board_before and game.view.focus == camera_focus and game.view.zoom == camera_zoom, "Border changes preserve gameplay and camera framing")
	expect(background_choice.get_item_text(0) == "Water" and background_choice.get_item_text(1) == "Sky", "Video options expose Water and Sky")
	background_choice.item_selected.emit(1)
	expect(paused and game.view.sky_backdrop.visible and not game.view.water.visible and game.view.background_environment.background_mode == Environment.BG_CANVAS, "Sky applies immediately while paused")
	background_choice.item_selected.emit(0)
	expect(paused and not game.view.sky_backdrop.visible and game.view.water.visible and game.view.background_environment.background_mode == Environment.BG_COLOR, "Water switches back immediately while paused")
	expect(game.cells == board_before and game.view.focus == camera_focus and game.view.zoom == camera_zoom, "Background changes preserve game state and camera framing")
	video.set_preference(&"background", "invalid", false)
	expect(video.background == "water", "Unsupported backgrounds are rejected")
	video.set_preference(&"background", "sky")
	app.menus.options_view.refresh()
	expect(background_choice.selected == 1, "Options refresh reflects the saved background choice")
	app.continue_game()
	video.set_preference(&"antialiasing", 0)
	video.set_preference(&"shadows", false)
	expect(root.msaa_3d == 0 and not game.view.sun.shadow_enabled, "Video settings update viewport quality and scene shadows")
	video.set_preference(&"resolution", Vector2i(100, 100))
	expect(video.resolution == values[&"resolution"], "Unsupported window sizes are rejected")
	expect(video.flush_settings() == OK, "Video settings are persisted")
	video.set_preference(&"stylized_water", false, false)
	video.set_preference(&"shadows", true, false)
	video.set_preference(&"background", "water", false)
	expect(video.load_settings(video.settings_path) == OK and not video.shadows and video.background == "sky", "Saved video preferences restore the chosen background")
	expect(is_equal_approx(video.internal_borders, 0.75), "Internal-border visibility is persisted with other Video preferences")
	expect(video.stylized_water, "Water style survives a settings save and reload")
	var legacy_config := ConfigFile.new()
	legacy_config.set_value("video", "background", "invalid")
	legacy_config.save("res://artifacts/video_invalid_test.cfg")
	expect(video.load_settings("res://artifacts/video_invalid_test.cfg") == OK and video.background == "sky", "Malformed saved backgrounds preserve a valid preference")
	legacy_config.erase_section_key("video", "background")
	legacy_config.save("res://artifacts/video_legacy_test.cfg")
	var fresh_video = load("res://src/settings/video_settings.gd").new()
	expect(fresh_video.load_settings("res://artifacts/video_legacy_test.cfg") == OK and fresh_video.background == "water", "Older preference files default to original Water")
	expect(is_equal_approx(fresh_video.internal_borders, 0.5), "Older preference files default internal borders to 50 percent")
	legacy_config.set_value("video", "internal_borders", "invalid")
	legacy_config.save("res://artifacts/video_invalid_test.cfg")
	expect(fresh_video.load_settings("res://artifacts/video_invalid_test.cfg") == OK and is_equal_approx(fresh_video.internal_borders, 0.5), "Malformed border preferences safely default to 50 percent")
	video.set_preference(&"internal_borders", 2.0, false)
	expect(video.internal_borders == 1.0, "Border visibility clamps to 100 percent")
	video.set_preference(&"internal_borders", -1.0, false)
	expect(video.internal_borders == 0.0, "Border visibility clamps to zero percent")
	video.set_preference(&"internal_borders", NAN, false)
	expect(video.internal_borders == 0.0, "Non-finite border visibility is rejected")
	expect(not fresh_video.stylized_water, "Legacy settings default to original water")
	legacy_config.set_value("video", "stylized_water", "invalid")
	legacy_config.save("res://artifacts/video_invalid_test.cfg")
	expect(fresh_video.load_settings("res://artifacts/video_invalid_test.cfg") == OK and not fresh_video.stylized_water, "Malformed water preferences use original water")
	fresh_video.free()
	for key in values:
		video.set_preference(key, values[key], false)
	video.settings_path = old_path
	app.pause_game()
	app.menus.show_screen(app.menus.Screen.QUIT)
	app.menus.confirm_quit("main")
	expect(paused and app.menus.confirm_panel.visible, "Leaving a session asks before discarding it")
	escape(app.menus)
	expect(app.menus.screen == app.menus.Screen.QUIT and is_instance_valid(app.game), "Backing out of quit confirmation keeps the session")
	app.return_to_main_menu()
	while app.retiring_games > 0:
		await process_frame
	expect(not paused and app.game == null and app.menus.screen == app.menus.Screen.MAIN, "Main Menu safely discards the session and clears pause")
	await app.start_new_game()
	game = app.game
	game.end_turn()
	await create_timer(0.03, true).timeout
	app.pause_game()
	app.return_to_main_menu()
	while app.retiring_games > 0:
		await process_frame
	expect(app.game == null and not paused, "Returning during enemy preparation cleans up without stale coroutines")
	await app.start_new_game()
	expect(app.game.round_number == 1 and not app.game.busy, "Starting again creates a fresh session")
	expect(app.menus.quit_requested.is_connected(app.quit_game), "Desktop quit is wired to application exit")
	app.menus.quit_requested.disconnect(app.quit_game)
	var quit_called := [false]
	app.menus.quit_requested.connect(func(): quit_called[0] = true)
	app.menus.confirm_quit("desktop")
	app.menus.confirm_leave()
	expect(quit_called[0], "Desktop confirmation requests application quit")
	app.return_to_main_menu()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.20, true).timeout
	print("Menu checks: %d passed, %d failed" % [checks - failures, failures])
	video_preferences.set_preference(&"level_transitions", original_transitions, false)
	quit(1 if failures else 0)
