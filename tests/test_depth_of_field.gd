extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func check_focus(camera: Camera3D, focus: Vector3) -> void:
	var attributes := camera.attributes as CameraAttributesPractical
	expect(attributes != null, "World camera has native depth of field attributes")
	if attributes == null: return
	var depth := (camera.position - focus).dot(camera.basis.z)
	expect(attributes.dof_blur_near_enabled == (attributes.dof_blur_amount > 0.0) and attributes.dof_blur_far_enabled == (attributes.dof_blur_amount > 0.0), "Depth passes run only while zoom calls for blur")
	expect(attributes.dof_blur_near_distance < depth and attributes.dof_blur_far_distance > depth, "The camera target remains inside the sharp focus band")
	expect(attributes.dof_blur_near_transition > 0 and attributes.dof_blur_far_transition > 0, "Defocus has a gradual falloff")
func zoom_checks(board) -> void:
	board.focus = Vector3.ZERO
	board.pitch = 0.82
	board.yaw = 0.0
	board.zoom = 8.0
	board.update_camera()
	var lens: CameraAttributesPractical = board.camera.attributes
	var close_amount := lens.dof_blur_amount
	expect(close_amount > 0.0 and lens.dof_blur_near_enabled and lens.dof_blur_far_enabled, "Close zoom enables foreground and background diorama blur")
	var previous := close_amount
	for step in range(81, 401):
		board.zoom = step / 10.0
		board.update_camera()
		expect(lens.dof_blur_amount <= previous + 0.000001, "Blur decreases continuously as the camera zooms out")
		expect(absf(lens.dof_blur_amount - previous) < 0.01, "Zoom fade has no visible strength jump")
		previous = lens.dof_blur_amount
	expect(lens.dof_blur_amount == 0.0 and not lens.dof_blur_near_enabled and not lens.dof_blur_far_enabled, "Wide overview disables depth blur entirely")
	board.zoom = board.navigation.default_zoom
	board.update_camera()
	expect(lens.dof_blur_amount == 0.0, "Small-map default overview is also completely sharp")
	for zoom in [16.0, 18.0, 22.0]:
		board.zoom = zoom
		board.update_camera()
		expect(lens.dof_blur_amount == 0.0, "Moderate zoom stays completely sharp with the later blur onset")
	board.zoom = 12.0
	board.update_camera()
	expect(lens.dof_blur_amount > 0.0, "Returning to close zoom restores the diorama effect")
	var before := Vector3(lens.dof_blur_amount, lens.dof_blur_near_distance, lens.dof_blur_far_distance)
	for position in [Vector2(10, 10), Vector2(600, 400), Vector2(1100, 750)]:
		var motion := InputEventMouseMotion.new()
		motion.position = position
		root.push_input(motion, true)
		board._process(1.0 / 60.0)
		expect(before == Vector3(lens.dof_blur_amount, lens.dof_blur_near_distance, lens.dof_blur_far_distance), "Cursor motion cannot change focus or blur strength")
	board.focus = Vector3(5, 0, -3)
	board.update_camera()
	check_focus(board.camera, board.focus)
	expect(is_equal_approx(lens.dof_blur_amount, before.x), "Panning retains zoom-dependent blur strength")
func run() -> void:
	var board = load("res://src/rendering/board_view.gd").new()
	root.add_child(board)
	board.set_process(false)
	board.navigation.set_process(false)
	expect(not board.has_node("ScreenEdgeSoftening"), "The old screen-edge blur overlay is removed")
	check_focus(board.camera, board.focus)
	var retained: CameraAttributes = board.camera.attributes
	for settings in [[8.0, 0.44], [22.0, 0.92], [80.0, 0.44], [38.0, 1.37]]:
		board.zoom = settings[0]
		board.pitch = settings[1]
		board.yaw += 0.3
		board.focus += Vector3(3, 0, -2)
		board.update_camera()
		check_focus(board.camera, board.focus)
		expect(board.camera.attributes == retained, "Panning, orbiting and zooming retain the camera resource")
	zoom_checks(board)
	board.navigation.toggle_top_down()
	check_focus(board.camera, board.focus)
	var attributes := board.camera.attributes as CameraAttributesPractical
	for coord in [Vector2.ZERO, Vector2(0, root.size.y), Vector2(root.size.x, root.size.y)]:
		var point: Vector3 = board.navigation._ground_at(coord)
		var depth: float = (board.camera.position - point).dot(board.camera.basis.z)
		expect(depth > attributes.dof_blur_near_distance and depth < attributes.dof_blur_far_distance, "Overhead ground stays sharp across the viewport")
	var menu = load("res://src/rendering/decorative_map.gd").new()
	menu.initial_seed = 42
	root.add_child(menu)
	menu.layout_camera(1.5)
	var target: Vector3 = menu.camera.position - menu.camera.basis.z * 52.0
	check_focus(menu.camera, target)
	var menu_attributes: CameraAttributes = menu.camera.attributes
	menu.camera_time = 12.0
	menu.update_cinematic_camera()
	expect(menu.camera.attributes == menu_attributes, "Menu orbit retains its own depth of field resource")
	expect(menu.camera.attributes != board.camera.attributes, "Menu and gameplay have independent focus settings")
	menu.queue_free()
	board.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("Depth of field checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
