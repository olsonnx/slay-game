extends SceneTree
## Matched policy comparisons, rotating both difficulty profiles through starts.
const Rules = preload("res://src/game/kingdom_rules.gd")
var results: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var seeds := 2
	var rounds := 16
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			seeds = int(argument.trim_prefix("--seeds="))
		if argument.begins_with("--rounds="):
			rounds = int(argument.trim_prefix("--rounds="))
	for pair in [["easy", "normal"], ["normal", "hard"], ["easy", "hard"]]:
		for seed_value in range(seeds):
			for rotation in range(2):
				var model = Rules.new()
				model.rule_mode = "modern"
				model.generate(seed_value, "very_small")
				var policies: Array = []
				for faction in range(model.faction_count):
					policies.append(pair[(faction + rotation) % 2])
				var started := Time.get_ticks_usec()
				var turns := 0
				var actions := 0
				var winner := -1
				var deaths := 0
				for round_index in range(rounds):
					for faction in range(model.faction_count):
						model.ai_difficulty = policies[faction]
						var records: Array = model.ai_turn(faction)
						turns += 1
						actions += records.size()
						for record in records:
							deaths += int(record.get("kind", "") == "death")
						var surviving: Dictionary = {}
						for kingdom in model.kingdoms.values():
							surviving[kingdom["owner"]] = true
						if surviving.size() == 1:
							winner = surviving.keys()[0]
							break
					if winner >= 0:
						break
					model.spread_trees()
				var elapsed: float = (Time.get_ticks_usec() - started) / 1000.0
				var result := {"seed": seed_value, "policies": policies, "winner": winner,
					"winning_policy": policies[winner] if winner >= 0 else "unresolved", "turns": turns,
					"actions": actions, "preparation_deaths": deaths, "ms": elapsed}
				results.append(result)
				print(JSON.stringify(result))
				await process_frame
	var file := FileAccess.open("res://artifacts/ai_playtest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	print("AI playtests completed: ", results.size())
	quit()
