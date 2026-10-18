extends SceneTree
const Fixture = preload("res://tools/heavy_strain_probe.gd")
func _initialize() -> void:
	call_deferred("run")
func median(values: Array) -> float:
	values.sort()
	return values[values.size() / 2]
func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 71
	game.initial_map_size = "huge"
	game.initial_rule_mode = "modern"
	game.initial_kingdom_count = 6
	root.add_child(game)
	game.rules = Fixture.crowded("huge", 71, 300)
	game.new_game(71, true, false)
	game.set_process(false)
	game.view.set_process(false)
	var source: Vector2i = game.NONE
	for coord in game.cells:
		if game.cells[coord]["owner"] == 0 and game.cells[coord]["unit"] > 0:
			source = coord
			break
	var valid: Dictionary = game.rules.reachable_targets(source)
	var longest: Array = []
	for target in valid:
		var path: Array = game.rules.movement_path(source, target, valid)
		if path.size() > longest.size(): longest = path
	var report := {"tiles": game.cells.size(), "units": 300, "legal_targets": valid.size(), "longest_path_hexes": longest.size(), "headless": true}
	for operation in ["reachable_area", "longest_route", "kingdom_outline_hover"]:
		var times: Array = []
		for repetition in range(5):
			for child in game.view.overlay_root.get_children(): child.free()
			game.view.overlays.signature.clear()
			var started := Time.get_ticks_usec()
			match operation:
				"reachable_area": game.view.overlays.show_reachable_area(source, valid)
				"longest_route": game.view.overlays.show_route(longest, Color.WHITE)
				"kingdom_outline_hover": game.view.overlays.show_overlays(game.NONE, source, {}, [], game.active_capital())
			times.append((Time.get_ticks_usec() - started) / 1000.0)
			await process_frame
		report[operation + "_ms"] = median(times)
	print(JSON.stringify(report))
	FileAccess.open("res://artifacts/heavy_overlay_profile.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	game.shutdown()
	game.queue_free()
	await process_frame
	quit()
