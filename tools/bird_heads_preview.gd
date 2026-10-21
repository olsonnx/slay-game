extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1200, 800)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await create_timer(0.4).timeout
	var birds = game.view.birds
	birds.set_process(false)
	var coord: Vector2i = game.view.unit_actors.keys()[0]
	for rank in [1, 2, 3]:
		game.cells[coord]["unit"] = rank
		game.view.render_cells(game.cells)
		birds.set_round(birds.round_number + 3)
		var resident: Dictionary = birds.flocks[0]
		resident["coord"] = coord
		resident["root"].position = game.view.coord_position(coord)
		resident["state"] = "landing"
		resident["time"] = 0.0
		resident["direction"] = Vector3.RIGHT
		birds.assign_perch(resident)
		game.view.focus = game.view.coord_position(coord)
		game.view.zoom = 8.0
		game.view.update_camera()
		birds._process(1.0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/bird-head-rank%d.png" % rank)
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	quit()
