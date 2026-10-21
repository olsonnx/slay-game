extends SceneTree
## Native hover verification for the spectator's custom icon tooltips.
var failures := 0
func _initialize() -> void: call_deferred("run")
func tooltip_texts(node: Node) -> Array:
	var result: Array = []
	if node is RichTextLabel and node.is_visible_in_tree(): result.append(node.get_parsed_text())
	for child in node.get_children(true): result.append_array(tooltip_texts(child))
	return result
func run() -> void:
	root.size = Vector2i(960, 620)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await create_timer(0.5).timeout
	app.open_replays()
	var viewer = app.replay_viewer
	while viewer.library_loading: await process_frame
	if viewer.paths.is_empty():
		push_error("This probe needs a saved recording in its selected user directory")
		quit(1)
		return
	viewer.load_recording(viewer.paths[0])
	while viewer.worker != null or viewer.building: await process_frame
	viewer.speed_choice.select(5)
	viewer.select_speed(5)
	viewer.movement_checkbox.button_pressed = true
	for control in [viewer.play_button, viewer.camera_button, viewer.movement_checkbox, viewer.speed_choice]:
		var move := InputEventMouseMotion.new()
		move.position = Vector2(3, 3)
		root.push_input(move, true)
		await create_timer(0.1).timeout
		move = InputEventMouseMotion.new()
		move.position = control.get_global_rect().get_center()
		root.push_input(move, true)
		await create_timer(0.85).timeout
		var texts := tooltip_texts(root)
		var visible := false
		for text in texts:
			if text.contains(control.tooltip_text.split("\n")[0]): visible = true
		if not visible: failures += 1
		print(JSON.stringify({"control":control.name,"tooltip":control.tooltip_text,"rendered_text":texts,"passed":visible}))
		if control == viewer.camera_button:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/replay-controls-tooltip.png")
	var clear := InputEventMouseMotion.new()
	clear.position = Vector2(3, 3)
	root.push_input(clear, true)
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/replay-controls.png")
	viewer.toggle_ui()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/replay-controls-hidden.png")
	app.free()
	await process_frame
	print("Replay tooltip checks: %d passed, %d failed" % [4 - failures, failures])
	quit(1 if failures else 0)
