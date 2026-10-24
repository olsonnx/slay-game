extends SceneTree
## Unlocked native A/B of streamed menu batching; does not save preferences.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var video = root.get_node("Video")
	video.set_preference(&"vsync", false, false)
	video.set_preference(&"fullscreen", false, false)
	video.set_preference(&"resolution", Vector2i(1280, 820), false)
	root.get_node("Sound").set_muted(true, false)
	Engine.max_fps = 0
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	var background = app.menus.menu_background
	var viewport: RID = background.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	await create_timer(2.0).timeout
	var results: Array = []
	for enabled in [false, true, true, false]:
		background.map.static_batches.set_enabled(enabled)
		if enabled:
			background.map.sync_menu_batches()
		await create_timer(0.7).timeout
		var samples: Array = []
		var started := Time.get_ticks_usec()
		var previous := started
		while Time.get_ticks_usec() - started < 2000000:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append((now - previous) / 1000.0)
			previous = now
		samples.sort()
		var result := {"batched": enabled, "fps_mean": samples.size() * 1000000.0 / (previous - started), "p50_ms": samples[int(samples.size() * 0.5)], "p99_ms": samples[int(samples.size() * 0.99)], "draws": RenderingServer.viewport_get_render_info(viewport, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME), "cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(viewport), "gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(viewport)}
		results.append(result)
		print(JSON.stringify(result))
	var file := FileAccess.open("res://artifacts/menu_batch_performance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	quit()
