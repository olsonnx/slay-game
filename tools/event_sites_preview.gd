extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,800)
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	var rules = load("res://src/game/kingdom_rules.gd").new()
	rules.rule_mode = "modern"
	for q in range(-4,5):
		for r in range(-3,4):
			var coord := Vector2i(q,r)
			if rules.distance(coord,Vector2i.ZERO) > 4: continue
			rules.cells[coord] = rules.make_cell(0 if q < 1 else 1)
	rules.cells[Vector2i(-3,0)].capital = 0
	rules.cells[Vector2i(3,0)].capital = 1
	rules.cells[Vector2i(-1,2)].building = "house"
	rules.cells[Vector2i(-2,-2)].building = "tower"
	rules.cells[Vector2i(2,-2)].building = "house"
	load("res://src/game/event_sites.gd").create(rules,Vector2i(-1,-1),"economist",1)
	load("res://src/game/event_sites.gd").create(rules,Vector2i(2,1),"wolf",0,1)
	rules.rebuild_kingdoms()
	var board = load("res://src/rendering/board_view.gd").new()
	root.add_child(board)
	board.render_cells(rules.cells)
	board.focus = Vector3.ZERO
	board.pitch = 0.94
	board.yaw = 0.1
	board.zoom = 15.0
	board.update_camera()
	await create_timer(1.0).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/event-sites-preview.png")
	var roads := 0
	for tile in board.tile_nodes.values():
		if tile.has_node("RoadPaint"): roads += 1
	print("Preview road tiles: ",roads)
	board.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit(0 if roads > 0 else 1)
