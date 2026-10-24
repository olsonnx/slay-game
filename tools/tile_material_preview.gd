extends SceneTree
## Close production-board view for reviewing the molded tile finish.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1400, 960)
	root.get_node("Sound").set_muted(true, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Video").set_preference(&"plastic_tiles", true, false)
	root.get_node("Video").set_preference(&"internal_borders", 0.5, false)
	var board = load("res://src/rendering/board_view.gd").new()
	root.add_child(board)
	var rules = load("res://src/game/kingdom_rules.gd").new()
	rules.generate(42, "small", 4)
	board.configure_map("small", load("res://src/game/map_sizes.gd").spec("small").bounds)
	board.render_cells(rules.cells)
	board.focus = board.coord_position(rules.kingdoms.keys()[0])
	board.pitch = 0.82
	board.yaw = 0.15
	board.zoom = 15.0
	board.update_camera()
	for style in ["atmospheric", "simple"]:
		board.lighting.apply_style(style)
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/tile-material-%s.png" % style)
	board.lighting.apply_style("atmospheric")
	board.static_batches.set_suspended(true)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/tile-material-source.png")
	board.static_batches.set_suspended(false)
	root.get_node("Video").set_preference(&"plastic_tiles", false, false)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/tile-material-original.png")
	board.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit()
