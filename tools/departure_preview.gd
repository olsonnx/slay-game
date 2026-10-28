extends SceneTree
## Step real departure batches through several camera angles for visual review.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 820)
	root.get_node("Sound").set_muted(true, false)
	root.get_node("Video").set_preference(&"level_transitions", true, false)
	var board = load("res://src/rendering/board_view.gd").new()
	root.add_child(board)
	board.navigation.set_process(false)
	var rules = load("res://src/game/kingdom_rules.gd").new()
	for q in range(-2, 3):
		for r in range(-2, 3):
			var coord := Vector2i(q, r)
			rules.cells[coord] = rules.make_cell(posmod(q + r, 3))
			rules.cells[coord]["mountain"] = posmod(q * 3 + r, 4) == 0
			rules.cells[coord]["tree"] = not rules.cells[coord]["mountain"] and posmod(q + r, 3) == 0
	rules.rebuild_kingdoms()
	board.render_cells(rules.cells)
	board.zoom = 17.0
	board.yaw = 0.18
	var label := "after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
	for angle in [53, 79, 90]:
		board.pitch = deg_to_rad(minf(angle, 89.9))
		board.update_camera()
		board.start_level_transition(false)
		board.island_transition.tween.pause()
		for amount in [0.35, 0.55, 0.75, 1.0]:
			for tile in board.island_transition.destinations:
				board.island_transition._departing_position(amount, tile, board.island_transition.destinations[tile])
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/departure-%s-%d-%d.png" % [label, angle, int(amount * 100)])
		print("DEPARTURE angle=%d far=%.2f" % [angle, board.camera.far])
		board.cancel_level_transition()
	board.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit()
