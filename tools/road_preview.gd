extends SceneTree
## Native preview and first-use pipeline check through production startup warmup.
func _initialize() -> void: call_deferred("run")

func pipelines() -> Dictionary:
	var result := {}
	for key in ClassDB.class_get_integer_constant_list("RenderingServer"):
		if key.begins_with("RENDERING_INFO_") and "PIPELINE_COMPILATIONS" in key:
			result[key] = RenderingServer.get_rendering_info(ClassDB.class_get_integer_constant("RenderingServer", key))
	return result

func settle() -> void:
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw

func run() -> void:
	root.size = Vector2i(1400, 960)
	root.get_node("Sound").set_muted(true, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	while not app.startup_complete: await process_frame
	await app.start_new_game(42, "small")
	var game = app.game
	game.set_process(false)
	game.rules.cells.clear()
	for q in range(-4, 6):
		for r in range(-1, 3): game.rules.cells[Vector2i(q, r)] = game.rules.make_cell(0)
	var home := Vector2i(-3, 0)
	var source := Vector2i(3, 1)
	var target := Vector2i(-1, 0)
	game.rules.cells[home].capital = 0
	game.rules.cells[Vector2i(1, 0)].building = "city"
	game.rules.cells[source].building = "city"
	game.rules.rebuild_kingdoms()
	for bank in game.rules.kingdoms.values(): bank.gold = 200
	game.configure_players()
	game.view.render_cells(game.cells)
	game.view.focus = game.view.coord_position(Vector2i(0, 1))
	game.view.zoom = 17.0
	game.view.pitch = 0.92
	game.view.yaw = 0.12
	game.view.update_camera()
	game.view.birds.clear()
	game.view.wildlife.clear()
	game.refresh_ui()
	await settle()
	var before := pipelines()
	var start := Time.get_ticks_usec()
	game.rules.build_road(home, Vector2i(1, 0), 0)
	game.view.render_cells(game.cells)
	var first_placement_ms := (Time.get_ticks_usec() - start) / 1000.0
	await settle()
	var after_placement := pipelines()
	game.inspect_province(source)
	game.province_view.road_button.pressed.emit()
	# Exercise the same hover callback as _process, without depending on which
	# desktop window currently owns the physical mouse.
	game.update_hover(target, 0.0)
	await settle()
	assert(game.view.overlay_root.has_node("RoadPreview"), "Hover must show the road")
	assert(game.hud.world_tip.visible and game.tip_label.get_parsed_text().contains("Build road"), "Hover must immediately show the price")
	root.get_texture().get_image().save_png("res://artifacts/road-preview.png")
	var report := {"first_placement_cpu_ms":first_placement_ms, "before":before, "after_first_placement":after_placement, "after_preview":pipelines(), "real_road_material_warmed":app.startup_warmup.get_node("WarmupRoadSurface").material_override == game.view.roads.material}
	var file := FileAccess.open("res://artifacts/road-preview-pipelines.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print(JSON.stringify(report))
	await app.return_to_main_menu()
	app.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	quit()
