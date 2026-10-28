extends SceneTree
## New encounter structures on the production board and in the status dock.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1400, 960)
	root.get_node("Sound").set_muted(true, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var rules = game.rules
	rules.cells.clear()
	for q in range(-3, 8):
		for r in range(-1, 2): rules.cells[Vector2i(q, r)] = rules.make_cell(0)
	rules.cells[Vector2i(-3, 0)].capital = 0
	var sources := ["builders_guild", "barracks", "scout_lodge", "watchtower", "stainless_steel"]
	var bonuses := ["development_discount", "soldier_discount", "scout_discount", "defense_aura", ""]
	for index in range(sources.size()):
		var coord := Vector2i(index * 2 - 2, 0)
		var properties := {}
		if bonuses[index] != "": properties[bonuses[index]] = true
		load("res://src/game/event_sites.gd").create(rules, coord, sources[index], 0, 0, index == 4, properties)
	rules.rebuild_kingdoms()
	game.view.render_cells(rules.cells)
	game.view.focus = game.view.coord_position(Vector2i(2, 0))
	game.view.zoom = 17.0
	game.view.pitch = 0.92
	game.view.yaw = 0.12
	game.view.update_camera()
	game.refresh_ui()
	game.view.birds.clear()
	game.view.wildlife.clear()
	game.inspect_province(Vector2i(-2, 0))
	game.province_view.reveal = 1
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/new-landmarks.png")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	quit()
