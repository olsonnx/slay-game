extends SceneTree
## Native rendering probe: preparation cost and drawn arrival/idle frames.
func _initialize() -> void:
	call_deferred("run")

func sample(seconds: float) -> Dictionary:
	var intervals: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec() - started < seconds * 1000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
	intervals.sort()
	return {"fps": intervals.size() * 1000000.0 / (previous - started), "p95_ms": intervals[int(intervals.size() * 0.95)], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}

func run() -> void:
	if "--app" in OS.get_cmdline_user_args():
		await probe_app()
		return
	var results: Array = []
	var video = root.get_node("Video")
	var saved_shadows: bool = video.shadows
	for size_id in ["very_small", "large"]:
		for shadows in [true, false]:
			video.set_preference(&"shadows", shadows, false)
			var game = load("res://scenes/main.tscn").instantiate()
			game.initial_rule_mode = "modern"
			game.initial_seed = 42
			game.initial_map_size = size_id
			game.deferred_startup = "--batched" in OS.get_cmdline_user_args()
			var started := Time.get_ticks_usec()
			root.add_child(game)
			if game.deferred_startup:
				await game.prepare_board()
			var build_ms := (Time.get_ticks_usec() - started) / 1000.0
			if game.deferred_startup:
				for frame in range(3):
					await process_frame
					await RenderingServer.frame_post_draw
				await process_frame
			game.play_level_entry()
			var arrival: Dictionary = await sample(1.0)
			var idle: Dictionary = await sample(1.0)
			results.append({"size": size_id, "shadows": shadows, "build_ms": build_ms, "preparation": game.startup_timings, "tiles": game.cells.size(), "arrival": arrival, "idle": idle})
			game.shutdown()
			game.queue_free()
			await process_frame
	video.set_preference(&"shadows", saved_shadows, false)
	var label := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			label = arg.trim_prefix("--label=")
	FileAccess.open("res://artifacts/startup_%s.json" % label, FileAccess.WRITE).store_string(JSON.stringify(results, "\t"))
	print(JSON.stringify(results))
	quit()

func probe_app() -> void:
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await create_timer(1.0).timeout
	app.start_new_game(42, "large")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/startup_preparation.png")
	while app.transitioning:
		await process_frame
	var metrics: Dictionary = app.game.startup_timings.duplicate()
	metrics["arrival"] = await sample(1.0)
	metrics["idle"] = await sample(1.0)
	root.get_texture().get_image().save_png("res://artifacts/startup_settled.png")
	FileAccess.open("res://artifacts/startup_app.json", FileAccess.WRITE).store_string(JSON.stringify(metrics, "\t"))
	print(JSON.stringify(metrics))
	await app.return_to_main_menu()
	app.queue_free()
	await process_frame
	quit()
