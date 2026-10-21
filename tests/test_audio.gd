extends SceneTree

const Manager = preload("res://src/audio/audio_manager.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func run() -> void:
	var sound := Manager.new()
	sound.load_saved_settings = false
	sound.bank = Manager.DEFAULT_BANK.duplicate(true)
	root.add_child(sound)
	var original: Dictionary = {}
	for bus in sound.BUSES:
		original[bus] = sound.get_volume(bus)
	var original_mute := sound.is_muted()
	sound.set_muted(false, false)
	sound.set_volume(&"Master", 1.0, false)
	sound.set_volume(&"UI", 1.0, false)
	sound.set_volume(&"SFX", 1.0, false)
	expect(sound.bank.cues.size() == 4 and sound.voices.size() == sound.VOICE_COUNT, "Registry loads all four assets and a fixed voice pool")
	for id in sound.bank.cues:
		var cue: Resource = sound.bank.cues[id]
		expect(cue.streams.size() == 1 and cue.streams[0].get_length() > 0, "Registered MP3 is playable")
		expect(AudioServer.get_bus_index(cue.bus) >= 0, "Cue routes to an existing mix bus")
		expect(sound.play(id), "Registered cue starts playback")
		sound.stop_all()
	expect(sound.play(&"ui_hover") and not sound.play(&"ui_hover"), "Hover cooldown suppresses rapid retriggers")
	sound.stop_all()
	sound.bank.cues[&"ui_hover"].cooldown_seconds = 0
	expect(sound.play(&"ui_hover") and not sound.play(&"ui_hover"), "Single hover voice avoids stacking lengthy hover effects")
	sound.stop_all()
	sound.bank.cues[&"action_place"].cooldown_seconds = 0
	for index in range(20):
		sound.play(&"action_place")
	var playing := 0
	for voice in sound.voices:
		if voice.playing:
			playing += 1
	expect(playing == 4 and sound.voices.size() == sound.VOICE_COUNT, "Repeated actions stay within the cue and global voice limits")
	sound.stop_all()
	var cue: Resource = sound.bank.cues[&"ui_click"]
	for index in range(sound.VOICE_COUNT):
		var variant: Resource = cue.duplicate(true)
		variant.cooldown_seconds = 0
		variant.priority = 90
		sound.bank.cues[StringName("busy%d" % index)] = variant
		sound.play(StringName("busy%d" % index))
	expect(not sound.play(&"ui_hover"), "Low-priority hover cannot steal an important voice")
	sound.stop_all()
	var button := Button.new()
	root.add_child(button)
	var played: Array = []
	sound.sound_started.connect(func(id: StringName, _voice: int): played.append(id))
	sound.bind_button(button)
	sound.bind_button(button)
	button.mouse_entered.emit()
	expect(played == [&"ui_hover"], "Button hover binding is reusable and idempotent")
	sound.stop_all()
	played.clear()
	button.pressed.emit()
	expect(played == [&"ui_click"], "Button activation uses the UI click cue")
	sound.stop_all()
	played.clear()
	button.disabled = true
	button.mouse_entered.emit()
	button.pressed.emit()
	expect(played.is_empty(), "Disabled controls remain silent")
	sound.set_muted(true, false)
	expect(not sound.play(&"ui_click"), "Master mute prevents new sounds and clears old ones")
	sound.set_muted(false, false)
	sound.set_volume(&"UI", 0, false)
	expect(not sound.play(&"ui_click"), "Zero category volume suppresses playback")
	sound.set_volume(&"UI", 0.37, false)
	sound.set_volume(&"SFX", 0.62, false)
	sound.set_volume(&"Ambience", 0.28, false)
	var path := "res://artifacts/audio_test.cfg"
	expect(sound.save_settings(path) == OK, "Mix settings can be saved")
	sound.set_volume(&"UI", 1.0, false)
	expect(sound.load_settings(path) == OK and is_equal_approx(sound.get_volume(&"UI"), 0.37) and is_equal_approx(sound.get_volume(&"SFX"), 0.62), "Saved category volumes are restored")
	sound.set_volume(&"Ambience", 0.9, false)
	sound.load_settings(path)
	expect(is_equal_approx(sound.get_volume(&"Ambience"), 0.28), "Ambience volume persists independently")
	sound.set_volume(&"UI", 10, false)
	expect(is_equal_approx(sound.get_volume(&"UI"), 1), "Volume values are clamped")
	sound.stop_all()
	var global_sound = root.get_node("Sound")
	global_sound.stop_all()
	var events: Array = []
	var on_sound := func(id: StringName, _voice: int): events.append(id)
	global_sound.sound_started.connect(on_sound)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var board = game.view
	var ambience = board.land_ambience
	ambience.set_process(false)
	var saved_focus: Vector3 = board.focus
	var saved_zoom: float = board.zoom
	board.zoom = 8.0
	board.focus = board.coord_position(board.cells.keys()[0])
	board.update_camera()
	expect(ambience.target_gain() > 0.0, "Close land view enables nature ambience")
	ambience._process(0.15)
	expect(ambience.player.playing and ambience.gain > 0.0 and ambience.gain <= 0.1, "Nature starts with a gentle fade")
	expect(ambience.player.stream.loop and ambience.player.bus == &"Ambience", "Dedicated nature player loops on ambience bus")
	root.get_node("Sound").stop_all()
	expect(ambience.player.playing, "One-shot cleanup does not interrupt the nature loop")
	# Hold land coverage constant so this measures the audible zoom curve.
	var zoom_test_cells: Dictionary = board.cells
	board.cells = {}
	for q in range(-20, 21):
		for r in range(-20, 21):
			board.cells[Vector2i(q, r)] = {"building": ""}
	board.focus = Vector3.ZERO
	var zoom_volumes: Array[float] = []
	for size in [13.0, 11.0, 8.0]:
		board.zoom = size
		board.update_camera()
		ambience._process(1.5)
		zoom_volumes.append(ambience.player.volume_db)
		expect(is_zero_approx(ambience.overview_target_gain()), "Close zoom never enables overview ambience")
	expect(zoom_volumes[0] < zoom_volumes[1] and zoom_volumes[1] < zoom_volumes[2], "Nature keeps getting louder through medium, close and closest zoom")
	expect(is_equal_approx(zoom_volumes[2], -26.0), "Closest zoom uses the quieter nature mix")
	expect(not ambience.overview_player.playing, "Closest zoom leaves only the close nature layer")
	expect(ambience.overview_player.stream.loop and ambience.overview_player.stream.get_length() > 0.0 and ambience.overview_player.bus == &"Ambience", "Overview recording is playable and loops on the ambience bus")
	for size in [14.0, maxf(14.0, board.max_zoom * 0.35)]:
		board.zoom = size
		board.update_camera()
		ambience._process(1.5)
		expect(not ambience.player.playing and not ambience.overview_player.playing, "Middle zoom range settles to complete ambience silence")
	var wide_volumes: Array[float] = []
	for ratio in [0.15, 0.5, 1.0]:
		board.zoom = lerpf(maxf(14.0, board.max_zoom * 0.35), board.max_zoom, ratio)
		board.update_camera()
		ambience._process(1.5)
		wide_volumes.append(ambience.overview_player.volume_db)
		expect(not ambience.player.playing, "Far zoom never enables close nature")
	expect(wide_volumes[0] < wide_volumes[1] and wide_volumes[1] < wide_volumes[2], "Overview gradually gets louder across the wider zoom range")
	expect(is_equal_approx(wide_volumes[2], -34.0), "Farthest view uses the quieter overview mix")
	board.cells = zoom_test_cells
	board.focus = board.coord_position(board.cells.keys()[0])
	board.zoom = 24.0
	board.update_camera()
	expect(is_zero_approx(ambience.target_gain()), "Distant map view is silent")
	ambience._process(1.5)
	expect(not ambience.player.playing, "Nature stops after fading out")
	expect(ambience.overview_player.playing, "Wind already fades in at normal overview zoom")
	board.zoom = board.max_zoom
	board.focus = Vector3(1000, 0, 1000)
	board.update_camera()
	expect(is_equal_approx(ambience.overview_target_gain(), 1.0), "Overview ambience remains present at maximum zoom over water")
	board.zoom = 8.0
	board.focus = Vector3(1000, 0, 1000)
	board.update_camera()
	expect(is_zero_approx(ambience.target_gain()), "Close open-water view stays silent")
	board.focus = board.coord_position(board.cells.keys()[0])
	board.update_camera()
	var saved_cells: Dictionary = board.cells
	board.cells = {}
	for coord in saved_cells:
		board.cells[coord] = {"building": "bridge"}
	expect(is_zero_approx(ambience.target_gain()), "Bridges do not enable nature ambience")
	board.cells = saved_cells
	paused = true
	ambience._process(0.15)
	expect(ambience.can_process() and ambience.player.playing, "Nature continues while the game is paused")
	paused = false
	global_sound.set_muted(true, false)
	ambience._process(0.15)
	expect(not ambience.player.playing and is_zero_approx(ambience.gain), "Master mute immediately silences nature")
	expect(not ambience.overview_player.playing and is_zero_approx(ambience.overview_gain), "Master mute also stops the overview layer")
	global_sound.set_muted(false, false)
	ambience._process(0.15)
	expect(ambience.player.playing, "Nature fades back in after unmuting")
	var saved_ambience: float = global_sound.get_volume(&"Ambience")
	global_sound.set_volume(&"Ambience", 0.0, false)
	ambience._process(0.15)
	expect(not ambience.player.playing, "Zero ambience volume stops the nature loop")
	board.zoom = board.max_zoom
	board.update_camera()
	ambience._process(1.5)
	expect(not ambience.overview_player.playing, "Zero ambience volume also stops the overview loop")
	global_sound.set_volume(&"Ambience", saved_ambience, false)
	var saved_sfx: float = global_sound.get_volume(&"SFX")
	global_sound.set_volume(&"SFX", 0.0, false)
	ambience._process(1.5)
	expect(ambience.overview_player.playing, "Game-effects volume leaves the independent ambience category audible")
	global_sound.set_volume(&"SFX", saved_sfx, false)
	board.hide()
	expect(is_zero_approx(ambience.target_gain()), "Hidden board is silent")
	expect(is_zero_approx(ambience.overview_target_gain()), "Hidden board also silences the overview layer")
	board.show()
	board.set_active(false)
	expect(is_zero_approx(ambience.target_gain()), "Inactive board is silent")
	board.zoom = 24.0
	expect(is_zero_approx(ambience.overview_target_gain()), "Inactive board suppresses wide-view ambience")
	ambience._process(1.5)
	expect(not ambience.player.playing and not ambience.overview_player.playing, "Leaving the board fades out both loops")
	board.set_active(true)
	board.focus = saved_focus
	board.zoom = saved_zoom
	board.update_camera()
	ambience._process(1.5)
	global_sound.stop_all()
	events.clear()
	game.recruit_button.mouse_entered.emit()
	expect(events == [&"ui_hover"], "Actual game control plays hover feedback")
	global_sound.stop_all()
	events.clear()
	game.recruit_button.pressed.emit()
	expect(events == [&"ui_click"] and game.shop_panel.visible, "Recruit button opening plays a single click")
	global_sound.stop_all()
	events.clear()
	game.recruit_button.pressed.emit()
	expect(events == [&"ui_close"] and not game.shop_panel.visible, "Closing a menu uses close instead of duplicate click feedback")
	game.active_kingdom()["gold"] = 100
	game.choose_building("house")
	global_sound.stop_all()
	events.clear()
	var empty: Vector2i = game.NONE
	for coord in game.active_kingdom()["hexes"]:
		if game.rules.can_build(coord, 0, "house"):
			empty = coord
			break
	game.click_hex(empty)
	expect(events == [&"action_place"], "Successful construction plays placement once")
	global_sound.stop_all()
	events.clear()
	game.choose_building("tower")
	game.click_hex(empty)
	expect(events.is_empty(), "Invalid placement stays silent")
	game.cancel_action()
	expect(events == [&"ui_close"], "Cancellation plays close feedback")
	global_sound.stop_all()
	events.clear()
	game.cancel_action()
	expect(events.is_empty(), "No-op cancellation stays silent")
	game.rules.rule_mode = "modern"
	var neutral := game.NONE as Vector2i
	for coord in game.cells:
		if game.cells[coord]["owner"] == -1:
			neutral = coord
			break
	global_sound.stop_all()
	events.clear()
	game.click_hex(neutral, "terrain")
	expect(events == [&"ui_click"] and game.province_view.visible, "Neutral province inspection plays one selection cue")
	global_sound.stop_all()
	events.clear()
	for child in game.province_view.get_children():
		if child is Button and child.text == "×":
			child.pressed.emit()
	expect(events == [&"ui_close"] and not game.province_view.visible, "Province X uses the same close cue as cancellation")
	game.open_shop("recruit")
	global_sound.stop_all()
	events.clear()
	for child in game.shop_panel.get_children():
		if child is Button and child.text == "×":
			child.pressed.emit()
	expect(events == [&"ui_close"] and not game.shop_panel.visible, "Purchase menu X closes with one close cue")
	var menus = load("res://src/ui/session_menus.gd").new()
	root.add_child(menus)
	menus.open_options(menus.Screen.MAIN)
	var options = menus.options_view
	expect(menus.options_panel.visible and options.sound_sliders.size() == 4, "Shared Options exposes all four audio sliders")
	var previous_path: String = global_sound.settings_path
	global_sound.settings_path = path
	var before_master: float = global_sound.get_volume(&"Master")
	options.sound_sliders[&"UI"].value_changed.emit(24.0)
	expect(is_equal_approx(global_sound.get_volume(&"UI"), 0.24) and is_equal_approx(global_sound.get_volume(&"Master"), before_master), "Interface slider adjusts only its own audio bus")
	var before_sfx: float = global_sound.get_volume(&"SFX")
	options.sound_sliders[&"Ambience"].value_changed.emit(17.0)
	expect(is_equal_approx(global_sound.get_volume(&"Ambience"), 0.17) and is_equal_approx(global_sound.get_volume(&"SFX"), before_sfx), "Ambience slider adjusts its own category without changing game effects")
	options.sound_mute.toggled.emit(true)
	expect(global_sound.is_muted(), "Mute control changes the master mute state")
	options.sound_mute.toggled.emit(false)
	expect(not global_sound.save_timer.is_stopped(), "Settings writes are debounced while controls change")
	expect(global_sound.flush_settings() == OK, "Debounced settings can be flushed before changing a profile")
	global_sound.settings_path = previous_path
	menus.close_options()
	expect(menus.main_panel.visible and not menus.options_panel.visible, "Closing Options returns to its originating menu")
	global_sound.sound_started.disconnect(on_sound)
	global_sound.stop_all()
	game.free()
	for bus in original:
		sound.set_volume(bus, original[bus], false)
	sound.set_muted(original_mute, false)
	print("Audio checks: %d passed, %d failed" % [checks - failures, failures])
	# The dummy driver retires MP3 playback on its own mixing clock.
	await create_timer(1.20).timeout
	quit(1 if failures else 0)
