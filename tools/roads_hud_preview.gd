extends SceneTree
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/%s.png" % name)
func run() -> void:
	root.size = Vector2i(960,620)
	root.get_node("Sound").set_muted(true,false)
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_profile = preload("res://src/settings/player_profile.gd").default_identity()
	game.initial_profile.name = "Kingdom of the Silver Oak"
	game.initial_profile.flag.symbol = "tree"
	game.initial_profile.flag.pattern = "vertical"
	root.add_child(game)
	game.set_process(false)
	game.rules.cells.clear()
	for q in range(-3,4):
		for r in range(-3,4):
			if maxi(absi(q),maxi(absi(r),absi(q+r))) > 3: continue
			var coord := Vector2i(q,r)
			game.cells[coord] = game.rules.make_cell(0)
			game.cells[coord].tree = false
	game.cells[Vector2i.ZERO].capital = 0
	game.cells[Vector2i(2,-1)].building = "house"
	game.cells[Vector2i(0,2)].building = "house"
	game.cells[Vector2i(-2,2)].building = "tower"
	game.cells[Vector2i(-2,0)].tree = true
	game.cells[Vector2i(1,-2)].tree = true
	game.cells[Vector2i(1,1)].unit = 2
	game.rules.rebuild_kingdoms()
	game.view.render_cells({})
	game.view.render_cells(game.cells)
	game.view.focus = Vector3.ZERO
	game.view.pitch = 1.05
	game.view.yaw = 0.18
	game.view.zoom = 14
	game.view.update_camera()
	game.refresh_ui()
	await capture("roads-single-path-custom-hud")
	game.session.active_faction = 1
	game.refresh_ui()
	await capture("country-hud-default")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	quit()
