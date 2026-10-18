extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Replay = preload("res://src/game/replay_log.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var results: Array = []
	for seed_value in [42, 71]:
		var model = Rules.new()
		model.rule_mode = "modern"
		model.generate(seed_value, "small", 4)
		model.human_factions = []
		var path := "res://artifacts/replay-v2-smoke-%d.jsonl" % seed_value
		model.replay_log = Replay.new()
		assert(model.replay_log.start(model, {"purpose":"AI housing / replay smoke"}, path))
		var played := 0
		var winner := -1
		var started := Time.get_ticks_usec()
		for round_index in range(20):
			for faction in range(model.faction_count):
				if model.territory(faction) == 0 and not model.has_units(faction): continue
				model.ai_turn(faction)
				model.record_replay("turn_end", faction)
				await process_frame
			played += 1
			var surviving: Dictionary = {}
			for bank in model.kingdoms.values(): surviving[bank["owner"]] = true
			if surviving.size() <= 1:
				winner = surviving.keys()[0] if not surviving.is_empty() else -1
				break
			model.spread_trees()
		var restored := Replay.read_records(model.replay_log.records)
		assert(restored["error"] == "" and Replay.encode(restored["position"]) == Replay.position(model))
		model.replay_log.finish(model, "completed" if winner >= 0 else "round_limit", winner)
		if winner >= 0: model.replay_log.save_completed(model)
		if winner >= 0:
			restored = Replay.read_replay(path)
			assert(restored["error"] == "" and Replay.encode(restored["position"]) == Replay.position(model))
		else: assert(model.replay_log.path == "" and not FileAccess.file_exists(path))
		var result := {"seed":seed_value, "rounds":played, "winner":winner, "commands":model.replay_log.sequence,
			"saved":winner >= 0, "bytes":FileAccess.get_file_as_bytes(path).size() if winner >= 0 else 0, "ms":(Time.get_ticks_usec()-started)/1000.0}
		results.append(result)
		print(JSON.stringify(result))
	var report := FileAccess.open("res://artifacts/replay-v2-smoke-results.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(results, "\t"))
	quit()
