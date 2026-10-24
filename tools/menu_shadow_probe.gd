extends SceneTree
## Same seeded scenery and frame-by-frame camera path, capped and uncapped.
const FRAMES := 360
const STEP := 1.0 / 75.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var video = root.get_node("Video")
	var saved := {"shadows": video.shadows, "vsync": video.vsync, "background": video.background}
	var reports: Array = []
	var suffix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			suffix = "_" + arg.trim_prefix("--label=")
	video.set_preference(&"background", "water", false)
	for capped in [true, false]:
		video.set_preference(&"vsync", capped, false)
		for repetition in range(2):
			for shadows in ([false, true] if repetition == 0 else [true, false]):
				video.set_preference(&"shadows", shadows, false)
				var app = load("res://scenes/app.tscn").instantiate()
				app.onboarding_enabled = false
				root.add_child(app)
				await app.startup_finished
				var background = app.menus.menu_background
				background.set_process(false)
				var old = background.map
				background.viewport.remove_child(old)
				old.queue_free()
				var map = load("res://src/rendering/decorative_map.gd").new()
				map.initial_seed = 42
				background.viewport.add_child(map)
				background.map = map
				map.active = true
				background.update_resolution()
				# Warm resources without changing the path measured in each trial.
				for frame in range(75):
					await process_frame
					await RenderingServer.frame_post_draw
				var intervals: Array[float] = []
				var calls := 0.0
				var previous := Time.get_ticks_usec()
				for frame in range(FRAMES):
					await process_frame
					map.advance(STEP)
					await RenderingServer.frame_post_draw
					var now := Time.get_ticks_usec()
					intervals.append((now - previous) / 1000.0)
					previous = now
					calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
					if capped and repetition == 0 and frame == 179:
						root.get_texture().get_image().save_png("res://artifacts/menu_shadows_%s%s.png" % [("on" if shadows else "off"), suffix])
				var total := 0.0
				for interval in intervals:
					total += interval
				intervals.sort()
				var report := {"vsync": capped, "shadows": shadows, "trial": repetition + 1, "fps": FRAMES * 1000.0 / total, "mean_ms": total / FRAMES, "p95_ms": intervals[int(FRAMES * 0.95)], "mean_draw_calls": calls / FRAMES, "resolution": str(background.viewport.size), "aa": video.antialiasing}
				reports.append(report)
				print(JSON.stringify(report))
				app.queue_free()
				await process_frame
	for key in saved:
		video.set_preference(key, saved[key], false)
	FileAccess.open("res://artifacts/menu_shadow_comparison%s.json" % suffix, FileAccess.WRITE).store_string(JSON.stringify(reports, "\t"))
	quit()
