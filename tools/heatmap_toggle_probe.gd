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
	game.initial_map_size = "large"
	game.initial_kingdom_count = 6
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var manager = game.view.static_batches
	var timings: Array[float] = []
	for cycle in range(101):
		var started := Time.get_ticks_usec()
		game.toggle_value_heatmap()
		game.toggle_value_heatmap()
		var elapsed := (Time.get_ticks_usec() - started) / 1000.0
		if cycle > 0:
			timings.append(elapsed)
		if cycle % 10 == 0:
			print(JSON.stringify({"cycle": cycle, "pair_ms": elapsed, "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "props": game.view.value_heatmap.prop_materials.size(), "features": manager.material_features.size(), "materials": manager.materials.size(), "sources": manager.source_material_keys.size(), "material_scans": manager.material_scan_count}))
		await process_frame
	timings.sort()
	print("Repeated toggle pair median: %.3f ms" % timings[timings.size() / 2])
	game.shutdown()
	game.queue_free()
	await process_frame
	quit()
