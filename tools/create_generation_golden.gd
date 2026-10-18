extends SceneTree
## Explicitly refresh v10 determinism fixtures after an intentional generator change.
const Rules = preload("res://src/game/kingdom_rules.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
static func digest(rules) -> String:
	var coords: Array = rules.cells.keys()
	coords.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	var state: Array = []
	for coord in coords: state.append([str(coord), rules.cells[coord]])
	state.append(rules.kingdoms)
	state.append(str(rules.rng.state))
	return JSON.stringify(state).sha256_text()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if "--update-generation-v10" not in OS.get_cmdline_user_args():
		print("Pass -- --update-generation-v10 to replace the intentional v10 baseline.")
		quit(1)
		return
	var samples: Array = []
	for mode in ["classic", "modern"]:
		for size_id in Sizes.IDS:
			for count in [0, 2, 6]:
				for seed_value in [42, 71, 123, 7, 999, 0, 1, 2, 3, 4]:
					var rules = Rules.new()
					rules.rule_mode = mode
					rules.generate(seed_value, size_id, count)
					samples.append({"generation_version":Rules.MapGenerator.GENERATION_VERSION, "mode":mode, "size":size_id, "count":count, "seed":seed_value, "digest":digest(rules)})
	var file := FileAccess.open("res://tests/fixtures/generation_golden.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(samples, "\t") + "\n")
	print("Recorded generation v10 fixtures: ", samples.size())
	quit()
