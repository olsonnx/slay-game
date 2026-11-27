extends SceneTree
var game
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/030-"+label+".png")
func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"fullscreen",false,false)
	video.set_preference(&"level_transitions",false,false)
	video.set_preference(&"depth_of_field",false,false)
	video.set_preference(&"resolution",Vector2i(1280,720),false)
	root.get_node("Sound").set_muted(true,false)
	game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.view.cancel_level_transition()
	game.view.navigation.stop_camera_pan()
	game.rules.cells.clear()
	for q in range(-3,4):
		for r in range(-2,3):
			if game.rules.distance(Vector2i.ZERO,Vector2i(q,r)) > 3: continue
			var cell: Dictionary = game.rules.make_cell(0 if q <= 1 else -1)
			cell.value = 1 + posmod(q+r,6)
			game.rules.cells[Vector2i(q,r)] = cell
	var capitals := [Vector2i(-2,0),Vector2i(0,0),Vector2i(1,1)]
	game.rules.cells[capitals[0]].capital = 0
	game.rules.cells[capitals[0]].capital_tier = 3
	game.rules.cells[capitals[0]].value = 6
	game.rules.cells[capitals[0]].mana_source = true
	game.rules.cells[capitals[0]].ore_source = true
	game.rules.cells[capitals[0]].unit = 3
	for index in range(3):
		var at := Vector2i(index-1,-1)
		game.rules.cells[at].building = "city"
		game.rules.cells[at].building_tier = index+1
		game.rules.cells[at].value = index+1
		at = Vector2i(index-1,1)
		game.rules.cells[at].building = "tower"
		game.rules.cells[at].building_tier = index+1
		game.rules.cells[at].value = index+4
	game.rules.cells[Vector2i(2,0)].ore_source = true
	game.rules.cells[Vector2i(2,-1)].mana_source = true
	game.rules.rebuild_kingdoms()
	for bank in game.rules.kingdoms.values(): bank.gold = 120
	game.rules.ore_by_faction[0] = 8
	game.rules.set_mana(0,2)
	game.view.render_cells(game.cells)
	game.view.navigation.focus = Vector3(0,0,0)
	game.view.navigation.yaw = 0.0
	game.view.navigation.pitch = 1.1
	game.view.navigation.zoom = 12
	game.view.navigation.update_camera()
	game.refresh_ui()
	game.inspect_province(capitals[0])
	game.province_view.reveal = 1
	await capture("capital")
	game.close_province()
	await capture("board")
	game.open_shop("build")
	game.shop_panel.reveal = 1
	await capture("build")
	game.cancel_action()
	game.inspect_province(Vector2i(1,1))
	game.province_view.reveal = 1
	DisplayServer.window_set_size(Vector2i(960,620))
	root.size = Vector2i(960,620)
	await capture("tower-small")
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit()
