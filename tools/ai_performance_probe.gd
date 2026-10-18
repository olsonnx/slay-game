extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Planner = preload("res://src/game/ai_planner.gd")

class Host extends Node:
	var closing := false
	var frames := 0
	func _process(_delta: float) -> void:
		frames += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var label := ""
	var samples := 1
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
		if argument.begins_with("--samples="):
			samples = clampi(int(argument.trim_prefix("--samples=")), 1, 10)
	if label != "" and not label.is_valid_filename():
		push_error("Invalid benchmark label")
		quit(1)
		return
	var model = Rules.new()
	model.rule_mode = "modern"
	model.generate(42, "large")
	for kingdom in model.kingdoms.values():
		kingdom["gold"] = 100
		var placed := 0
		for coord in kingdom["hexes"]:
			model.cells[coord]["value"] = 6
			if placed < 5:
				model.cells[coord]["unit"] = 1 if placed < 3 else 2
				placed += 1
	var report: Array = []
	for difficulty in ["easy", "normal", "hard"]:
		model.ai_difficulty = difficulty
		var totals: Array[float] = []
		var initializations: Array[float] = []
		var peaks: Array[float] = []
		var planner
		Planner.new(model, 1).run()
		for sample in range(samples):
			var started := Time.get_ticks_usec()
			planner = Planner.new(model, 1)
			initializations.append((Time.get_ticks_usec() - started) / 1000.0)
			planner.run()
			totals.append((Time.get_ticks_usec() - started) / 1000.0)
			peaks.append(planner.max_step_usec / 1000.0)
		var item := {"difficulty": difficulty, "initialization_ms": median(initializations),
			"total_ms": median(totals), "max_step_ms": median(peaks), "samples": totals,
			"evaluated": planner.evaluated, "sequence": planner.best_sequence, "score": planner.best_score,
			"sequence_length": planner.best_sequence.size()}
		report.append(item)
		print(JSON.stringify(item))
	var host := Host.new()
	root.add_child(host)
	model.ai_difficulty = "hard"
	var opponent = model.KingdomAI.new(model)
	var actions: Array = await opponent.movements_async(host, 1)
	var responsiveness := {"yielded_frames": host.frames, "committed_actions": actions.size()}
	print(JSON.stringify(responsiveness))
	var suffix := "" if label == "" else "_" + label
	var file := FileAccess.open("res://artifacts/ai_performance%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify({"scenario": "Large, 30 units, fixed seed 42", "search": report, "asynchronous": responsiveness}, "\t"))
	host.queue_free()
	quit()

func median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	return sorted[middle] if sorted.size() % 2 else (sorted[middle - 1] + sorted[middle]) * 0.5
