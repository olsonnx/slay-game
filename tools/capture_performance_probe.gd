extends SceneTree
## Real capture playback on a seeded large/six-kingdom board, plus sync costs.
class Frames extends Node:
	var collecting := false
	var samples: Array[float] = []
	var previous := 0
	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		if collecting and previous != 0:
			samples.append((now - previous) / 1000.0)
		previous = now

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var label := "before"
	var enemy := "--enemy" in OS.get_cmdline_user_args()
	var owner := 1 if enemy else 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
	root.get_node("Video").set_preference(&"vsync", false, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	Engine.max_fps = 0
	root.size = Vector2i(1280, 820)
	var observer := Frames.new()
	root.add_child(observer)
	var reports: Array = []
	for count in [1, 3]:
		var game = load("res://scenes/main.tscn").instantiate()
		game.initial_seed = 42
		game.initial_map_size = "large"
		game.initial_kingdom_count = 6
		game.initial_rule_mode = "modern"
		root.add_child(game)
		game.set_process(false)
		game.view.camera.size = 45
		for coord in game.rules.cells:
			if game.rules.cells[coord]["owner"] == owner:
				game.rules.cells[coord]["unit"] = 1
				game.rules.cells[coord]["moved"] = false
		game.view.render_cells(game.rules.cells)
		for frame in range(60):
			await process_frame
		var actions: Array = []
		game.busy = enemy
		game.active_faction = owner
		game.playback_kingdoms = game.rules.kingdoms.duplicate(true)
		game.playback_mana = game.rules.mana_by_faction.duplicate()
		var commit_started := Time.get_ticks_usec()
		for source in game.rules.cells:
			if game.rules.unit_faction(source) != owner or game.rules.cells[source]["unit"] == 0 or game.rules.cells[source]["moved"]:
				continue
			for target in game.rules.reachable_targets(source):
				if game.rules.cells[target]["owner"] == -1 and game.rules.cells[target]["event"] == "" and game.rules.cells[target]["unit"] == 0:
					actions.append(game.rules.perform_move(source, target))
					break
			if actions.size() == count:
				break
		assert(actions.size() == count)
		var commit_ms := (Time.get_ticks_usec() - commit_started) / 1000.0
		var manager = game.view.static_batches
		manager.profile_sync = true
		observer.samples.clear()
		observer.collecting = true
		await game.view.animate_moves(actions, game.rules.cells)
		for frame in range(3):
			await process_frame
		observer.collecting = false
		var frames := observer.samples.duplicate()
		frames.sort()
		var started := Time.get_ticks_usec()
		game.view.render_cells(game.rules.cells)
		var unchanged_ms := (Time.get_ticks_usec() - started) / 1000.0
		var result := {"captures": count, "enemy": enemy, "commit_ms": commit_ms, "frames": frames.size(), "median_ms": frames[frames.size() / 2], "p99_ms": frames[mini(frames.size() - 1, int(frames.size() * 0.99))], "max_ms": frames[-1], "syncs": manager.profile_samples, "unchanged_render_ms": unchanged_ms}
		reports.append(result)
		print(JSON.stringify(result))
		game.busy = false
		game.shutdown()
		game.queue_free()
		await process_frame
	FileAccess.open("res://artifacts/capture_performance_%s.json" % label, FileAccess.WRITE).store_string(JSON.stringify(reports, "\t"))
	quit()
