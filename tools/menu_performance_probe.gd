extends SceneTree
## Native menu ablations; does not save display preferences.
var app
var background
var results: Array = []
var sample_usec := 2000000

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Menu FPS profiling requires a native graphics window.")
		quit(1)
		return
	var video = root.get_node("Video")
	video.set_preference(&"vsync", false, false)
	video.set_preference(&"fullscreen", false, false)
	video.set_preference(&"resolution", Vector2i(1280, 820), false)
	root.get_node("Sound").set_muted(true, false)
	Engine.max_fps = 0
	app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	background = app.menus.menu_background
	background.profile_updates = true
	background.map.static_batches.profile_sync = true
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(background.viewport.get_viewport_rid(), true)
	await create_timer(2).timeout
	var cases := ["current", "freeze_rows", "freeze_camera", "freeze_updates", "current"]
	if "--final" in OS.get_cmdline_user_args():
		cases = ["current", "current", "current"]
		sample_usec = 5000000
		background.profile_updates = false
		background.map.static_batches.profile_sync = false
	for name_value in cases:
		background.map.freeze_row_motion = false
		background.map.freeze_camera_motion = false
		background.set_process(true)
		background.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		background.viewport.msaa_3d = video.antialiasing
		background.viewport.size = Vector2i(1280, 820)
		background.map.sun.shadow_enabled = true
		background.map.water.show()
		background.get_child(2).show()
		match name_value:
			"freeze_rows": background.map.freeze_row_motion = true
			"freeze_camera": background.map.freeze_camera_motion = true
			"mute_source_notifications":
				for record in background.map.static_batches.suppressed.values():
					record[0].set_notify_transform(false)
			"freeze_updates": background.set_process(false)
			"no_shadows": background.map.sun.shadow_enabled = false
			"no_msaa": background.viewport.msaa_3d = Viewport.MSAA_DISABLED
			"no_world": background.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			"half_resolution": background.viewport.size = Vector2i(640, 410)
			"no_water": background.map.water.hide()
			"no_vignette": background.get_child(2).hide()
		await create_timer(0.8).timeout
		var samples: Array = []
		var main_cpu: Array = []
		var scene_cpu: Array = []
		var scene_gpu: Array = []
		var main_gpu: Array = []
		var setup: Array = []
		var update_times: Array = []
		var started := Time.get_ticks_usec()
		var previous := started
		while Time.get_ticks_usec() - started < sample_usec:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append((now - previous) / 1000.0)
			previous = now
			main_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			main_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			scene_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(background.viewport.get_viewport_rid()))
			scene_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(background.viewport.get_viewport_rid()))
			setup.append(RenderingServer.get_frame_setup_time_cpu())
			update_times.append(background.last_update_usec / 1000.0 if background.is_processing() else 0.0)
		for values in [samples, main_cpu, scene_cpu, scene_gpu, main_gpu, setup, update_times]:
			values.sort()
		var middle := int(samples.size() / 2)
		var result := {"case": name_value, "fps": samples.size() * 1000000.0 / (previous - started), "p50_ms": samples[middle], "p99_ms": samples[int(samples.size() * 0.99)], "menu_cpu_ms": scene_cpu[middle], "menu_gpu_ms": scene_gpu[middle], "main_cpu_ms": main_cpu[middle], "main_gpu_ms": main_gpu[middle], "setup_ms": setup[middle]}
		results.append(result)
		if background.profile_updates:
			result["update_ms"] = update_times[middle]
		if background.map.static_batches.profile_sync:
			result["batch_scan_ms"] = background.map.static_batches.last_scan_usec / 1000.0
			result["batch_build_ms"] = background.map.static_batches.last_build_usec / 1000.0
			result["rebuilt_chunks"] = background.map.static_batches.last_rebuilt
		print(JSON.stringify(result))
	var output := "menu_final_performance" if "--final" in OS.get_cmdline_user_args() else "menu_ablation"
	var file := FileAccess.open("res://artifacts/%s.json" % output, FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	quit()
