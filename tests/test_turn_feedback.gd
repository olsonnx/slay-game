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
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var a := Vector2i(0, 0)
	var house := Vector2i(1, 0)
	var province := Vector2i(2, 0)
	var f := Vector2i(1, -1)
	var g := Vector2i(2, -1)
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for coord in [a, house, province, Vector2i(0, 1), Vector2i(1, 1)]:
		game.cells[coord] = game.rules.make_cell(0)
	for coord in [f, g]:
		game.cells[coord] = game.rules.make_cell(1)
	game.rules.rebuild_kingdoms()
	game.cells[house]["building"] = "house"
	game.cells[f]["unit"] = 3
	game.cells[g]["unit"] = 2
	for kingdom in game.rules.kingdoms.values():
		kingdom["gold"] = 50
	game.active_hex = a
	game.view.render_cells(game.cells)
	game.refresh_ui()
	expect(game.income_label.text == "+9 G", "Forecast initially includes owned provinces and the house bonus")
	# Let scene construction finish before timing concurrent tweens. Otherwise a
	# large first-frame delta can process both arrivals in insertion order.
	await process_frame
	await process_frame
	game.busy = true
	game.active_faction = 1
	game.playback_kingdoms = game.rules.kingdoms.duplicate(true)
	var attack: Dictionary = game.rules.perform_move(f, house)
	var capture: Dictionary = game.rules.perform_move(g, province)
	expect(game.income_label.text == "+9 G", "Preplanned AI commands do not reveal future losses before playback")
	var observed: Dictionary = {}
	game.view.motion_stage.connect(func(action: Dictionary, stage: String):
		if action["target"] == house and stage == "impact":
			observed["house_impact"] = game.income_label.text)
	game.view.action_finished.connect(func(action: Dictionary):
		if action.has("target"):
			observed[action["target"]] = game.income_label.text)
	await game.view.animate_moves([attack, capture], game.cells)
	expect(observed.get(province) == "+8 G", "Province loss updates forecast immediately on visible arrival (observed %s)" % observed.get(province))
	expect(observed.get("house_impact") == "+4 G", "Destroyed house removes its income bonus at jab impact (observed %s)" % observed.get("house_impact"))
	expect(observed.get(house) == "+3 G" and game.income_label.text == "+3 G", "House province capture removes base income and final forecast matches surviving land")
	expect(game.money_label.text == "50 G", "Losing income does not invent an immediate treasury deduction")
	var video = root.get_node("Video")
	var original_follow: bool = video.follow_turn_camera
	var original_path: String = video.settings_path
	video.set_preference(&"follow_turn_camera", false, false)
	game.view.reset_camera()
	game.camera_follow_suspended = false
	var initial_focus: Vector3 = game.view.focus
	game.follow_active_faction()
	await create_timer(0.12).timeout
	expect(game.view.focus == initial_focus, "Disabled camera following leaves focus unchanged")
	video.set_preference(&"follow_turn_camera", true, false)
	var yaw: float = game.view.yaw
	var pitch: float = game.view.pitch
	var zoom: float = game.view.zoom
	game.follow_active_faction()
	expect(game.view.focus == initial_focus and game.view.camera_pan_tween.is_running(), "Following starts a gentle tween without snapping")
	await create_timer(0.12).timeout
	expect(game.view.focus != initial_focus, "Camera visibly advances toward the active faction")
	var midway: Vector3 = game.view.focus
	paused = true
	await create_timer(0.18, true).timeout
	expect(game.view.focus == midway, "Pause freezes camera following")
	paused = false
	await create_timer(0.60).timeout
	var center := Vector3.ZERO
	var count := 0
	for coord in game.cells:
		if game.cells[coord]["owner"] == 1:
			center += game.view.coord_position(coord)
			count += 1
	expect(game.view.focus.is_equal_approx(center / count), "Camera settles at the active faction's territory center")
	expect(game.view.yaw == yaw and game.view.pitch == pitch and game.view.zoom == zoom, "Following preserves angle and zoom")
	game.view.smooth_pan_to(Vector3(8, 0, 6))
	game.view.pan(Vector2(1, 0), 0.1)
	var manual_focus: Vector3 = game.view.focus
	game.follow_active_faction()
	await create_timer(0.18).timeout
	expect(game.camera_follow_suspended and game.view.focus == manual_focus, "Manual navigation overrides automatic following for the current turn")
	game.camera_follow_suspended = false
	game.follow_active_faction()
	video.set_preference(&"follow_turn_camera", false, false)
	var disabled_focus: Vector3 = game.view.focus
	await create_timer(0.18).timeout
	expect(game.view.focus == disabled_focus, "Turning the setting off stops an existing camera pan")
	video.settings_path = "res://artifacts/follow_camera_test.cfg"
	video.set_preference(&"follow_turn_camera", false)
	expect(video.flush_settings() == OK, "Camera preference saves with video options")
	video.set_preference(&"follow_turn_camera", true, false)
	expect(video.load_settings(video.settings_path) == OK and not video.follow_turn_camera, "Camera preference survives a reload")
	var options = load("res://src/ui/options_view.gd").new()
	root.add_child(options)
	expect(options.camera_follow_toggle.text == "Follow active kingdom" and not options.camera_follow_toggle.button_pressed, "Video options exposes the saved follow toggle")
	game.busy = false
	game.view.stop_camera_pan()
	var original_active: int = game.session.active_faction
	for faction in range(3):
		game.session.active_faction = faction
		game.refresh_ui()
		var color: Color = game.session.colors[faction]
		expect(game.hud.end_button.get_theme_stylebox("normal").bg_color == color,"Turn button follows the active faction, including opponents")
		expect(game.hud.end_button.get_theme_stylebox("disabled").bg_color == color.darkened(0.16),"Disabled turn button retains the active kingdom colour")
	game.session.active_faction = original_active
	game.refresh_ui()
	video.set_preference(&"follow_turn_camera", original_follow, false)
	video.settings_path = original_path
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.20).timeout
	print("Turn feedback checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
