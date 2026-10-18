extends SceneTree
const Analysis = preload("res://src/game/ai_analysis.gd")
const Planner = preload("res://src/game/ai_planner.gd")
class Host extends Node:
	var closing := false
	var measuring := false
	var previous := 0
	var samples: Array[float] = []
	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		if measuring and previous:
			samples.append((now - previous) / 1000.0)
		previous = now

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.get_node("Video").set_preference(&"vsync", false, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	root.size = Vector2i(1280, 820)
	Engine.max_fps = 0
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 42
	game.initial_map_size = "large"
	game.initial_kingdom_count = 6
	root.add_child(game)
	game.set_process(false)
	game.view.camera.size = 45
	for kingdom in game.rules.kingdoms.values():
		kingdom["gold"] = 100
		var placed := 0
		for coord in kingdom["hexes"]:
			game.rules.cells[coord]["value"] = 6
			if placed < 5:
				game.rules.cells[coord]["unit"] = 1 if placed < 3 else 2
				placed += 1
	game.rules.ai_difficulty = "hard"
	game.view.render_cells(game.rules.cells)
	var host := Host.new()
	root.add_child(host)
	var reports: Array = []
	var sequence: Array = []
	for variant in ["main_thread", "worker"]:
		for frame in range(60):
			await process_frame
		host.samples.clear()
		host.measuring = true
		var started := Time.get_ticks_usec()
		var planner
		if variant == "main_thread":
			planner = Planner.new(game.rules, 1)
			var slice_start := Time.get_ticks_usec()
			while not planner.step():
				if Time.get_ticks_usec() - slice_start >= 4000:
					await process_frame
					slice_start = Time.get_ticks_usec()
			sequence = planner.best_sequence
		else:
			var opponent = game.rules.KingdomAI.new(game.rules)
			planner = await opponent.search_async(host, 1)
			assert(planner.best_sequence == sequence)
		var wall_ms := (Time.get_ticks_usec() - started) / 1000.0
		await process_frame
		host.measuring = false
		var frames := host.samples.duplicate()
		frames.sort()
		var report := {"variant": variant, "wall_ms": wall_ms, "median_frame_ms": frames[frames.size() / 2], "p99_frame_ms": frames[mini(frames.size() - 1, int(frames.size() * 0.99))], "max_frame_ms": frames[-1], "frames": frames.size(), "evaluated": planner.evaluated, "same_sequence": true}
		reports.append(report)
		print(JSON.stringify(report))
	FileAccess.open("res://artifacts/ai_frame_probe.json", FileAccess.WRITE).store_string(JSON.stringify(reports, "\t"))
	game.shutdown()
	game.queue_free()
	await process_frame
	quit()
