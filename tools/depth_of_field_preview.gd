extends SceneTree
## Close, medium and wide captures of the zoom-driven diorama effect.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1400, 960)
	root.get_node("Sound").set_muted(true, false)
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
	for entry in [["close", 12.0], ["medium", 19.0], ["wide", 32.0]]:
		board.zoom = entry[1]
		board.update_camera()
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/diorama-dof-%s.png" % entry[0])
	board.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit()
