extends SceneTree
const Replay = preload("res://src/game/replay_log.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Fixture = preload("res://tools/heavy_strain_probe.gd")
class Sampler extends Node:
	var active := false
	var previous := 0
	var samples: Array = []
	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		if active and previous > 0: samples.append((now - previous) / 1000.0)
		previous = now
func _initialize() -> void: call_deferred("run")
func stats(samples: Array) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	if sorted.is_empty(): return {}
	return {"median_ms":sorted[sorted.size()/2], "p95_ms":sorted[mini(sorted.size()-1, int(sorted.size()*0.95))],
		"p99_ms":sorted[mini(sorted.size()-1, int(sorted.size()*0.99))], "max_ms":sorted[-1], "samples":sorted.size()}
func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"vsync", false, false)
	video.set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	root.size = Vector2i(1280,820)
	Engine.max_fps = 0
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_map_size = "huge"
	game.initial_kingdom_count = 6
	game.initial_seed = 71
	root.add_child(game)
	game.set_process(false)
	var base = Fixture.crowded("huge",71,120)
	var sampler := Sampler.new()
	root.add_child(sampler)
	var baseline: Array = []
	var reports: Array = []
	var before_script = load("res://artifacts/replay_log_before_performance.gd")
	for variant in ["off", "before", "after"]:
		game.busy = false
		game.rules.replay_log.finish(game.rules, "closed") if game.rules.replay_log != null else null
		game.rules = Analysis.snapshot(base)
		game.rules.rng.state = base.rng.state
		game.new_game(71,true,false)
		if variant != "after":
			game.rules.replay_log.finish(game.rules, "closed")
			game.rules.replay_log = before_script.new() if variant == "before" else null
			if variant == "before": game.rules.replay_log.start(game.rules)
		game.view.camera.size = 45
		game.active_faction = 1
		game.busy = true
		for frame in range(45): await process_frame
		game.view.profile_capture = true
		game.view.capture_samples.clear()
		sampler.samples.clear()
		sampler.previous = Time.get_ticks_usec()
		sampler.active = true
		var opponent = game.rules.KingdomAI.new(game.rules)
		var orders: Array = []
		for batch in range(4):
			game.playback_kingdoms = game.rules.kingdoms.duplicate(true)
			game.playback_mana = game.rules.mana_by_faction.duplicate()
			var movements: Array = await opponent.movements_async(game,1)
			if movements.is_empty(): break
			for movement in movements: orders.append([movement["source"], movement["target"], movement["kind"]])
			await game.view.animate_moves(movements,game.cells)
		await process_frame
		sampler.active = false
		var commits: Array = []
		for sample in game.view.capture_samples:
			if sample["stage"] == "rules_commit": commits.append(sample["ms"])
		var report := {"variant":variant, "display":DisplayServer.get_name(), "tiles":game.cells.size(),
			"orders":orders.size(), "frames":stats(sampler.samples), "commits":stats(commits)}
		if variant == "off": baseline = orders
		else: assert(orders == baseline, "Replay recording must not change AI orders")
		report["same_orders"] = true
		reports.append(report)
		print(JSON.stringify(report))
		game.view.profile_capture = false
		game.busy = false
	FileAccess.open("res://artifacts/replay-frame-comparison.json",FileAccess.WRITE).store_string(JSON.stringify(reports,"\t"))
	game.shutdown()
	game.queue_free()
	await process_frame
	quit()
