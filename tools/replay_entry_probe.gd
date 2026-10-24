extends SceneTree
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await create_timer(0.5).timeout
	var samples: Array = []
	for cycle in range(5):
		var before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var memory_before := OS.get_static_memory_usage()
		var started := Time.get_ticks_usec()
		app.open_replays()
		var sample := {"cycle":cycle, "entry_ms":(Time.get_ticks_usec()-started)/1000.0, "startup":app.replay_viewer.startup_timings.duplicate()}
		for frame in range(3): await process_frame
		app.replay_viewer.request_close()
		for frame in range(3): await process_frame
		sample["retained_nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - before
		sample["retained_memory_bytes"] = OS.get_static_memory_usage() - memory_before
		samples.append(sample)
		print(JSON.stringify(sample))
	var file := FileAccess.open("res://artifacts/replay_entry_probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(samples,"\t"))
	app.free()
	await process_frame
	quit()
