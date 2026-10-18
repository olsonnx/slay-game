extends SceneTree
## Matched tooltip CPU probe; headless measurements do not measure GPU time.

func _initialize() -> void:
	call_deferred("run")

func measure(task: Callable) -> float:
	task.call()
	var samples: Array[float] = []
	for sample in range(5):
		var started := Time.get_ticks_usec()
		for index in range(1000):
			task.call()
		samples.append(float(Time.get_ticks_usec() - started) / 1000)
	samples.sort()
	return samples[2]

func run() -> void:
	var label := "current"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var sites: Array[Vector2i] = []
	for coord in game.cells:
		if game.rules.is_mountain(coord):
			sites.append(coord)
			break
	for coord in game.cells:
		if game.cells[coord]["owner"] < 0 and not game.rules.is_mountain(coord):
			sites.append(coord)
			break
	game.hovered = sites[0]
	var metrics := {"label": label}
	metrics["unchanged_tooltip_us"] = measure(func(): game.show_world_tip())
	var counter := [0]
	metrics["changed_tooltip_us"] = measure(func():
		counter[0] += 1
		game.hovered = sites[counter[0] % sites.size()]
		game.show_world_tip())
	print(JSON.stringify(metrics))
	var file := FileAccess.open("res://artifacts/ui_layout_%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics, "\t"))
	game.queue_free()
	await process_frame
	quit()
