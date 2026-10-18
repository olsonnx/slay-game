extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_map_size = "large"
	game.initial_seed = 42
	root.add_child(game)
	game.set_process(false)
	game.view.controls_enabled = false
	game.view.cancel_level_transition()
	var site: Vector2i = game.NONE
	var chest: Vector2i = game.NONE
	for coord in game.cells:
		if game.rules.can_relocate_capital(coord, 0): site = coord
		if game.cells[coord].get("treasure", 0) > 0: chest = coord
	game.active_kingdom()["gold"] = 100
	game.cells[site]["value"] = 6
	game.view.render_cells(game.cells)
	game.refresh_ui()
	game.view.focus = game.view.coord_position(site)
	game.view.zoom = 9.0
	game.view.update_camera()
	for window_size in [Vector2i(1280, 816), Vector2i(960, 620)]:
		root.size = window_size
		game.inspect_province(site)
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/capital_relocation_%d.png" % window_size.x)
		game.relocate_province_capital()
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/capital_confirmation_%d.png" % window_size.x)
		game.resolve_capital_relocation(1)
	root.size = Vector2i(1280, 816)
	game.view.focus = game.view.coord_position(chest)
	game.view.zoom = 7.0
	game.view.update_camera()
	game.inspect_province(chest)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/treasure_chest.png")
	game.shutdown()
	game.queue_free()
	await process_frame
	quit()
