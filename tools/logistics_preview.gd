extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1400, 960)
	root.get_node("Sound").set_muted(true, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.rules.cells.clear()
	for q in range(-4, 5):
		for r in range(-1, 2): game.rules.cells[Vector2i(q, r)] = game.rules.make_cell(0)
	game.rules.cells[Vector2i(-3, 0)].capital = 0
	game.rules.cells[Vector2i(-3, 0)].mana_source = true

	for coord in [Vector2i(0, 0), Vector2i(3, 0)]: game.rules.cells[coord].building = "city"
	game.rules.cells[Vector2i(0, 0)].unit = 1
	game.rules.cells[Vector2i(2, 1)].building = "tower"
	game.rules.rebuild_kingdoms()
	game.rules.rename_settlement(Vector2i(-3, 0), 0, "Crown's Reach")
	game.rules.rename_settlement(Vector2i(0, 0), 0, "New Harbour")
	for bank in game.rules.kingdoms.values(): bank.gold = 200
	game.rules.build_road(Vector2i(-3, 0), Vector2i(0, 0), 0)
	game.rules.build_road(Vector2i(0, 0), Vector2i(3, 0), 0)
	game.configure_players()
	game.view.render_cells(game.rules.cells)
	game.view.focus = game.view.coord_position(Vector2i.ZERO)
	game.view.zoom = 16.0
	game.view.pitch = 0.92
	game.view.yaw = 0.12
	game.view.update_camera()
	game.view.birds.clear()
	game.view.wildlife.clear()
	game.refresh_ui()
	game.inspect_province(Vector2i(0, 0))
	game.province_view.reveal = 1
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/cities-and-logistics.png")
	game.inspect_province(Vector2i(0, 0))
	game.province_view.reveal = 1
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/city-details.png")
	game.province_view.name_input.grab_focus()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/city-name-edit.png")
	game.choose_unit(1)
	game.update_hover(Vector2i(3, 0), 0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/recruitment-area.png")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	quit()
