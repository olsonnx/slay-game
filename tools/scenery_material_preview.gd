extends SceneTree
## Production-board scenery, including batching and the value overlay.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1400, 960)
	root.get_node("Sound").set_muted(true, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	var board = load("res://src/rendering/board_view.gd").new()
	root.add_child(board)
	var rules = load("res://src/game/kingdom_rules.gd").new()
	rules.generate(42, "small", 4)
	var center: Vector2i = rules.kingdoms.keys()[0]
	var index := 0
	for coord in rules.cells:
		if (coord - center).length() > 3: continue
		var cell: Dictionary = rules.cells[coord]
		cell["tree"] = index % 3 == 0
		cell["mountain"] = index % 3 == 1
		cell["unit"] = 0
		cell["building"] = ""
		cell["event"] = ""
		cell["grave"] = false
		index += 1
	board.configure_map("small", load("res://src/game/map_sizes.gd").spec("small").bounds)
	board.render_cells(rules.cells)
	board.focus = board.coord_position(center)
	board.pitch = 0.82
	board.yaw = 0.15
	board.zoom = 10.0
	board.update_camera()
	var suffix := "-compatibility" if RenderingServer.get_current_rendering_method() == "gl_compatibility" else ""
	for style in ["atmospheric", "simple"]:
		board.lighting.apply_style(style)
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/scenery-material-%s%s.png" % [style, suffix])
	board.value_heatmap.set_active(true)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/scenery-material-value%s.png" % suffix)
	board.value_heatmap.set_active(false)
	board.static_batches.set_suspended(true)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/scenery-material-source%s.png" % suffix)
	board.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	quit()
