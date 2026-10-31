extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool,message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"clouds",true,false)
	video.set_preference(&"depth_of_field",false,false)
	root.get_node("Sound").set_muted(true,false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	root.add_child(game)
	game.set_process(false)
	var board = game.view
	var clouds = board.clouds
	var cells: Dictionary = game.cells.duplicate(true)
	var rng_state: int = game.rules.rng.state
	for distance in [20.0,32.0,42.0,52.0,100.0]:
		board.zoom = distance
		board.update_camera()
		expect(is_equal_approx(clouds.strength,smoothstep(32.0,52.0,distance)),"Clouds fade in smoothly with camera distance")
		expect(clouds.surface.visible == (distance > 32),"Close views draw no cloud overlay")
		expect(clouds.viewport.render_target_update_mode == (SubViewport.UPDATE_ALWAYS if distance > 32 else SubViewport.UPDATE_DISABLED),"Close views stop the volume rendering work")
	var elapsed: float = clouds.elapsed
	video.set_preference(&"reduced_motion",false,false)
	clouds._process(1.0)
	expect(clouds.elapsed > elapsed and clouds.volume.get_shader_parameter("cloud_time") == clouds.elapsed,"The entire cloud volume drifts together over time")
	video.set_preference(&"reduced_motion",true,false)
	elapsed = clouds.elapsed
	clouds._process(1.0)
	expect(clouds.elapsed == elapsed and clouds.volume.get_shader_parameter("cloud_time") == elapsed,"Reduced motion freezes cloud movement including the edge")
	clouds.set_loading(true)
	expect(not clouds.surface.visible and clouds.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Loading hides clouds and stops the volume viewport")
	clouds.set_loading(false)
	video.set_preference(&"clouds",false,false)
	clouds.update_camera()
	expect(not clouds.surface.visible,"The video preference disables clouds immediately")
	video.set_preference(&"clouds",true,false)
	clouds.update_camera()
	expect(clouds.surface.visible,"Clouds can be re-enabled without rebuilding the board")
	board.set_active(false)
	expect(not clouds.surface.visible and clouds.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Retired boards stop cloud rendering")
	board.set_active(true)
	clouds.update_camera()
	var island_center: Vector3 = clouds.clearing_center
	var planes: PackedVector3Array = clouds.clearing_planes.duplicate()
	for coord in board.cells:
		var offset: Vector3 = board.coord_position(coord)-island_center
		var clearance := INF
		for plane in planes:
			clearance = minf(clearance,plane.z-Vector2(plane.x,plane.y).dot(Vector2(offset.x,offset.z)))
		expect(clearance > 5.0,"The asymmetric envelope encloses every tile with offshore clearance")
	for pose in [Vector2(0.18,0.92),Vector2(1.25,0.60),Vector2(0.0,1.569)]:
		board.yaw = pose.x
		board.pitch = pose.y
		board.focus = island_center + Vector3(10,0,6)
		board.update_camera()
		var origin: Vector2 = clouds.volume.get_shader_parameter("ground_origin")
		var right: Vector2 = clouds.volume.get_shader_parameter("ground_right")
		var down: Vector2 = clouds.volume.get_shader_parameter("ground_down")
		for coord in board.cells:
			var world: Vector3 = board.coord_position(coord)
			var point: Vector2 = board.camera.unproject_position(world)/root.get_visible_rect().size
			var ground := origin + right*point.x + down*point.y
			expect(ground.distance_to(Vector2(world.x,world.z)) < 0.001,"Rotated and panned views map tiles back into the clearing on their plane")
		expect(clouds.clearing_center == island_center and clouds.clearing_planes == planes,"Camera motion keeps the asymmetric envelope anchored to the island")
	for size_value in [Vector2i(1280,720),Vector2i(3840,2160),Vector2i(800,1200)]:
		root.size = size_value
		await process_frame
		clouds.update_camera()
		expect(clouds.viewport.size.x <= 640 and clouds.viewport.size.y <= 360,"Cloud raymarch resolution stays bounded even at 4K")
	var path := "res://artifacts/cloud-settings.cfg"
	var original_path: String = video.settings_path
	video.settings_path = path
	video.set_preference(&"clouds",false,false)
	expect(video.flush_settings() == OK,"Cloud preference can be saved")
	video.set_preference(&"clouds",true,false)
	expect(video.load_settings(path) == OK and not video.clouds,"Cloud preference survives a reload")
	video.settings_path = original_path
	video.set_preference(&"clouds",true,false)
	video.set_preference(&"clouds",false,false)
	var options = load("res://src/ui/options_view.gd").new()
	root.add_child(options)
	expect(not options.preferences.clouds.control.button_pressed,"Video options shows the saved cloud preference")
	options.restore_tab(1)
	expect(video.clouds and options.preferences.clouds.control.button_pressed,"Video defaults restore clouds along with the other graphics preferences")
	options.free()
	expect(game.cells == cells and game.rules.rng.state == rng_state,"Clouds never alter game state or consume game RNG")
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Cloud checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
