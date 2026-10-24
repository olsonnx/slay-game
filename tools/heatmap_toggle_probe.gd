extends SceneTree
## Repeated value-filter switches on the actual large-board renderer.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Video").set_preference(&"vsync", false, false)
	root.get_node("Sound").set_muted(true, false)
	Engine.max_fps = 0
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_map_size = "huge" if "--huge" in OS.get_cmdline_user_args() else "large"
	game.initial_kingdom_count = 6
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	var preparation_started := Time.get_ticks_usec()
	if "--cold" not in OS.get_cmdline_user_args(): await game.view.value_heatmap.prepare()
	print(JSON.stringify({"preparation_ms":(Time.get_ticks_usec()-preparation_started)/1000.0,"tiles":game.cells.size(),"headless":DisplayServer.get_name() == "headless"}))
	var manager = game.view.static_batches
	var prepared_syncs: int = manager.sync_count
	var prepared_rebuilds: int = manager.terrain_rebuild_count
	var timings: Array[float] = []
	for cycle in range(101):
		var started := Time.get_ticks_usec()
		game.toggle_value_heatmap()
		game.toggle_value_heatmap()
		var elapsed := (Time.get_ticks_usec() - started) / 1000.0
		if cycle > 0:
			timings.append(elapsed)
		if cycle % 10 == 0:
			print(JSON.stringify({"cycle": cycle, "pair_ms": elapsed, "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "props": game.view.value_heatmap.prop_materials.size(), "features": manager.material_features.size(), "materials": manager.materials.size(), "sources": manager.source_material_keys.size(), "material_scans": manager.material_scan_count,"toggle_syncs":manager.sync_count-prepared_syncs,"toggle_terrain_rebuilds":manager.terrain_rebuild_count-prepared_rebuilds,"retained_views":manager.presentation_banks.size()+1}))
		await process_frame
	timings.sort()
	print("Repeated toggle pair median: %.3f ms" % timings[timings.size() / 2])
	game.shutdown()
	game.queue_free()
	await process_frame
	await create_timer(1.1).timeout
	quit()
