extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func key(code: int, physical := 0) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = physical
	event.pressed = true
	return event

func run() -> void:
	var keys = root.get_node("Keys")
	var original: Dictionary = keys.bindings.duplicate()
	var original_path: String = keys.settings_path
	keys.settings_path = "res://artifacts/key_test.cfg"
	keys.reset_defaults(false)
	var sound = root.get_node("Sound")
	var muted: bool = sound.is_muted()
	sound.set_muted(true, false)
	expect(keys.bindings["recruit"] == KEY_Q and keys.bindings["build"] == KEY_E and keys.bindings["spells"] == KEY_R and keys.bindings["view"] == KEY_TAB, "Requested menu and view defaults")
	expect(keys.matches(key(KEY_Z, KEY_Q), "recruit"), "Shortcuts use physical positions on alternate keyboard layouts")
	expect(keys.set_binding("view", KEY_Q, false) != "", "Global shortcuts cannot conflict with menus or choices")
	expect(keys.set_binding("choice_2", KEY_Q, false) != "", "Choice keys cannot conflict with each other")
	expect(keys.set_binding("recruit", KEY_ESCAPE, false) != "", "Escape remains available for cancellation")
	expect(keys.set_binding("end_turn", KEY_F3, false) != "", "The global FPS shortcut cannot become an unusable gameplay binding")
	expect(keys.set_binding("recruit", KEY_J) == "", "Binding change saves successfully")
	keys.load_settings(keys.settings_path)
	expect(keys.bindings["recruit"] == KEY_J, "Saved binding survives reload")
	var permutation := ConfigFile.new()
	permutation.set_value("keys", "view", KEY_SPACE)
	permutation.set_value("keys", "end_turn", KEY_TAB)
	permutation.save(keys.settings_path)
	keys.load_settings(keys.settings_path)
	expect(keys.bindings["view"] == KEY_SPACE and keys.bindings["end_turn"] == KEY_TAB, "Valid saved permutations are loaded together without losing either binding")
	var config := ConfigFile.new()
	config.set_value("keys", "recruit", KEY_G)
	config.save(keys.settings_path)
	keys.load_settings(keys.settings_path)
	expect(keys.bindings["recruit"] == KEY_G and keys.bindings["develop"] != KEY_G and keys.conflict("develop",keys.bindings["develop"]) == "", "Introducing G development preserves older custom G bindings with a free fallback")
	config.clear()
	config.set_value("keys", "recruit", "invalid")
	config.set_value("keys", "build", KEY_TAB)
	config.set_value("keys", "speed", -1)
	config.set_value("keys", "end_turn", KEY_F3)
	config.save(keys.settings_path)
	keys.load_settings(keys.settings_path)
	expect(keys.bindings == keys.DEFAULTS, "Malformed and conflicting saved keys safely fall back")
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	for index in range(3):
		game.cancel_action()
		game._unhandled_input(key(KEY_Q))
		expect(game.shop_panel.visible and game.shop_kind == "recruit", "Q opens recruitment")
		game._unhandled_input(key([KEY_Q, KEY_E, KEY_R][index]))
		expect(game.action_mode == "recruit" and game.recruit_tier == index + 1 and not game.shop_panel.visible, "Contextual unit shortcut selects the matching card")
	for index in range(3):
		game.cancel_action()
		game._unhandled_input(key(KEY_E))
		expect(game.shop_panel.visible and game.shop_kind == "build", "E opens building")
		game._unhandled_input(key([KEY_Q, KEY_E, KEY_R][index]))
		expect(game.action_mode == ["tower", "city", "bridge"][index], "Contextual build shortcut selects the matching card")
	for index in range(3):
		game.cancel_action()
		game._unhandled_input(key(KEY_R))
		expect(game.shop_panel.visible and game.shop_kind == "spells", "R opens spells")
		game._unhandled_input(key([KEY_Q, KEY_E, KEY_R][index]))
		expect(game.chosen_spell == game.Spells.SPELLS.keys()[index] and game.action_mode == "spell", "Spell shortcuts follow the single Q/E/R row")
	game.cancel_action()
	keys.set_binding("recruit", KEY_1, false)
	game._unhandled_input(key(KEY_1))
	game._unhandled_input(key(KEY_1))
	expect(not game.shop_panel.visible, "Inactive upper-spell shortcuts do not swallow a rebound recruitment opening key")
	keys.reset_defaults(false)
	var before_view: bool = game.view.top_down
	game._input(key(KEY_TAB))
	expect(game.view.top_down != before_view, "Tab switches view before GUI focus navigation")
	keys.set_binding("view", KEY_V, false)
	before_view = game.view.top_down
	game._input(key(KEY_TAB))
	expect(game.view.top_down == before_view, "Old view binding stops working immediately")
	game._input(key(KEY_V))
	expect(game.view.top_down != before_view and game.view_button.tooltip_text.get_slice("\n", 0).ends_with("· V"), "Rebound view and tooltip update immediately")
	keys.set_binding("recruit", KEY_J, false)
	game._unhandled_input(key(KEY_Q))
	expect(not game.shop_panel.visible, "Old menu-opening key is inactive outside a menu")
	game._unhandled_input(key(KEY_J))
	expect(game.shop_panel.visible and game.recruit_button.tooltip_text.contains("Shortcut: J"), "Rebound menu key and tooltip update immediately")
	keys.set_binding("choice_1", KEY_Y, false)
	expect(game.shop_items.get_child(0).tooltip_text.contains("Shortcut: Y"), "Open card tooltip follows rebinding")
	game._unhandled_input(key(KEY_Y))
	expect(game.recruit_tier == 1 and not game.shop_panel.visible, "Rebound contextual choice works")
	keys.set_binding("cancel", KEY_BACKSPACE, false)
	game._unhandled_input(key(KEY_BACKSPACE))
	expect(game.action_mode == "", "Rebound cancellation clears the active targeting action")
	keys.set_binding("cancel", KEY_ESCAPE, false)
	keys.set_binding("speed", KEY_SHIFT, false)
	game.busy = true
	game.active_faction = 1
	game.playback_speed._input(key(KEY_SHIFT))
	expect(game.view.playback.speed_scale == 6, "Speed-up hold can be rebound")
	keys.set_binding("speed", KEY_CTRL, false)
	expect(game.view.playback.speed_scale == 1, "Rebinding clears a currently held speed key")
	game.busy = false
	game.active_faction = 0
	game.refresh_ui()
	var menus = load("res://src/ui/session_menus.gd").new()
	root.add_child(menus)
	menus.open_options(menus.Screen.MAIN)
	menus.options_view.get_child(0).current_tab = 3
	var controls = menus.options_view.controls_page
	var fps = preload("res://src/ui/fps_counter.gd").new(menus.menu_background)
	fps.binding_capture_active = func(): return controls.pending != ""
	root.add_child(fps)
	paused = true
	controls.begin_capture("recruit")
	controls._input(key(KEY_H))
	expect(controls.pending == "" and keys.bindings["recruit"] == KEY_H and paused, "Options capture works while game is paused without resuming")
	controls.begin_capture("build")
	var fps_was_shown: bool = fps.shown
	Input.parse_input_event(key(KEY_F3))
	await process_frame
	expect(controls.pending == "build" and controls.note.text.contains("reserved") and fps.shown == fps_was_shown, "FPS overlay yields real input to the reserved-key explanation during capture")
	controls._input(key(KEY_H))
	expect(controls.pending == "build" and controls.note.text.contains("Already used"), "Conflicting key is explained and capture remains active")
	controls._input(key(KEY_ESCAPE))
	expect(controls.pending == "" and menus.screen == menus.Screen.OPTIONS, "Escape cancels capture without leaving Options")
	controls.begin_capture("build")
	menus.options_view.get_child(0).current_tab = 0
	expect(controls.pending == "", "Switching tabs cancels key capture")
	menus.options_view.get_child(0).current_tab = 3
	controls.begin_capture("build")
	menus.close_options()
	expect(controls.pending == "", "Leaving Options cancels key capture")
	paused = false
	keys.reset_defaults(false)
	expect(keys.bindings == keys.DEFAULTS, "Restore defaults reinstates the requested layout")
	game.shutdown()
	game.queue_free()
	menus.queue_free()
	fps.queue_free()
	await process_frame
	keys.bindings = original
	keys.settings_path = original_path
	keys.changed.emit()
	sound.stop_all()
	sound.set_muted(muted, false)
	print("Key binding checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
