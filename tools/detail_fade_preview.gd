extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"level_transitions", false, false)
	video.set_preference(&"fullscreen", false, false)
	video.set_preference(&"resolution", Vector2i(1280, 820), false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	var board = game.view
	board.zoom = 7
	for coord in board.tile_nodes:
		if board.tile_nodes[coord].has_node("Features/GrassDetail"):
			board.focus = board.coord_position(coord)
			break
	board.update_camera()
	board.static_batches.advance_detail_fade(1.0)
	await create_timer(0.3).timeout
	board.static_batches.set_detail_visible(false)
	board.static_batches.set_process(false)
	for index in range(5):
		if index > 0:
			board.static_batches.advance_detail_fade(0.055)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/detail_fade_%d.png" % index)
	game.shutdown()
	root.get_node("Sound").stop_all()
	quit()
