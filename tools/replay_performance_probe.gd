extends SceneTree
const Replay = preload("res://src/game/replay_log.gd")
const Fixture = preload("res://tools/heavy_strain_probe.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var label := "after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	var script = load("res://artifacts/replay_log_before_performance.gd") if label == "before" else Replay
	var reports: Array = []
	for size_id in ["large", "huge"]:
		var model = Fixture.crowded(size_id, 71, 120)
		var coord: Vector2i = model.cells.keys()[0]
		for kind in ["move", "ai_decision"]:
			var recorder = script.new()
			recorder.start(model)
			var samples: Array = []
			for index in range(40):
				if kind == "move": model.cells[coord]["moved"] = not model.cells[coord]["moved"]
				var started := Time.get_ticks_usec()
				recorder.record(model, kind, 1, {"source":coord, "target":coord})
				samples.append((Time.get_ticks_usec() - started) / 1000.0)
				await process_frame
			samples.sort()
			var result := {"label":label, "tiles":model.cells.size(), "kind":kind, "median_ms":samples[20], "p95_ms":samples[38], "max_ms":samples[-1], "commands":recorder.sequence}
			recorder.finish(model, "closed")
			reports.append(result)
			print(JSON.stringify(result))
	FileAccess.open("res://artifacts/replay-performance-%s.json" % label, FileAccess.WRITE).store_string(JSON.stringify(reports, "\t"))
	quit()
