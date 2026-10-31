extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool,message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func country_center(game, faction: int) -> Vector3:
	var center := Vector3.ZERO
	var count := 0
	for coord in game.cells:
		if game.cells[coord].owner == faction:
			center += game.view.coord_position(coord)
			count += 1
	return center/maxi(1,count)
func capture(label: String) -> void:
	if "--preview" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/opening-camera-%s.png" % label)
func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"depth_of_field",false,false)
	video.set_preference(&"reduced_motion",false,false)
	video.set_preference(&"level_transitions",true,false)
	root.get_node("Sound").set_muted(true,false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await app.start_new_game(42,"large","easy",4)
	var game = app.game
	var nav = game.view.navigation
	var center := country_center(game,game.player_faction)
	var wide: float = nav.default_zoom
	expect(nav.opening_camera_active and game.view.level_transitioning,"Opening camera starts immediately while the island arrives")
	expect(game.commands_locked() and not game.view.controls_enabled,"The zoom overlaps the existing island-arrival input lock")
	await capture("wide")
	await create_timer(0.15).timeout
	expect(nav.zoom < wide and not nav.focus.is_equal_approx(center),"Opening camera gradually pans and zooms instead of snapping")
	await capture("mid")
	paused = true
	var frozen_focus: Vector3 = nav.focus
	var frozen_zoom: float = nav.zoom
	await create_timer(0.12,true).timeout
	expect(nav.focus == frozen_focus and nav.zoom == frozen_zoom,"Pause freezes the opening camera")
	paused = false
	await create_timer(0.75).timeout
	expect(nav.focus.is_equal_approx(center) and nav.zoom < wide and is_equal_approx(nav.zoom,nav.zoom_target),"Opening camera settles over the player's country within 0.85 seconds")
	while game.view.level_transitioning: await process_frame
	await capture("settled")
	for coord in game.cells:
		if game.cells[coord].owner == game.player_faction:
			var point: Vector2 = game.view.camera.unproject_position(game.view.coord_position(coord)+Vector3(0,2,0))
			expect(root.get_visible_rect().grow(-40).has_point(point),"Country and tall scenery remain comfortably inside the frame")
	nav.reset_camera()
	game.begin_opening_camera()
	var start_focus: Vector3 = nav.focus
	var start_zoom: float = nav.zoom
	var start_yaw: float = nav.yaw
	for operation in [func(): nav.pan(Vector2.RIGHT,0.1),func(): nav.drag_pan(Vector2(30,20)),func(): nav.orbit(Vector2(30,20)),func(): nav.change_zoom(2),func(): nav.toggle_top_down(),func(): nav.reset_camera(),func(): nav.stop_camera_pan(),func(): nav.smooth_pan_to(Vector3(100,0,100))]:
		operation.call()
		expect(nav.opening_camera_active and nav.focus == start_focus and nav.zoom == start_zoom and nav.yaw == start_yaw,"Camera input and turn-follow changes cannot interrupt the opening")
	await create_timer(0.95).timeout
	expect(not nav.opening_camera_active and nav.focus.is_equal_approx(center),"The camera unlocks at the correct country after the shortened opening")
	nav.pan(Vector2.RIGHT,0.1)
	expect(not nav.focus.is_equal_approx(center),"Camera controls resume after the opening finishes")
	nav.reset_camera()
	video.set_preference(&"reduced_motion",true,false)
	game.begin_opening_camera(1)
	expect(nav.focus.is_equal_approx(country_center(game,1)) and nav.zoom < wide,"A local online seat can frame its own country, with no animation under reduced motion")
	nav.reset_camera()
	expect(nav.focus == nav.map_center and nav.zoom == nav.default_zoom,"The reset gesture still restores the complete island")
	await app.return_to_main_menu()
	await app.start_tutorial("armies")
	expect(not app.game.view.navigation.opening_camera_active,"Guided tutorials retain their authored camera framing")
	app.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Opening camera checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
