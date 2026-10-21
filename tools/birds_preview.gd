extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	root.size = Vector2i(1200, 800)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await create_timer(0.4).timeout
	var birds = game.view.birds
	birds.set_process(false)
	var flock: Dictionary = birds.flocks[0]
	var coord: Vector2i = flock["coord"]
	game.cells[coord]["tree"] = true
	game.view.render_cells(game.cells)
	for resident in birds.flocks:
		resident["coord"] = coord
		resident["root"].position = game.view.coord_position(coord)
	game.view.focus = game.view.coord_position(coord)
	game.view.zoom = 8.0
	game.view.update_camera()
	birds._process(0.01)
	await create_timer(0.3).timeout
	await capture("res://artifacts/birds-perched.png")
	birds.scatter(coord, game.view.coord_position(coord) + Vector3(0, 0, 2))
	birds._process(0.45)
	await capture("res://artifacts/birds-taking-flight.png")
	birds._process(1.0)
	birds.set_round(flock["return_round"])
	game.view.focus = game.view.coord_position(flock["coord"])
	game.view.update_camera()
	birds._process(0.3)
	await capture("res://artifacts/birds-landing.png")
	print("Bird preview captures saved")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	quit()
