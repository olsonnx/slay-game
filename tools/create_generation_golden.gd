extends SceneTree
## Explicitly refresh determinism fixtures after an intentional generator change.
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
	if "--update-generation-v14" not in OS.get_cmdline_user_args():
		print("Pass -- --update-generation-v14 to replace the intentional v14 baseline.")
		quit(1)
		return
	var samples: Array = []
	# Match the fixed lottery used by test_scaling, independent of pack edits.
	Rules.Events.WEIGHTS.assign(Rules.Events.BUILTIN_WEIGHTS)
	for mode in ["modern"]:
		for size_id in Sizes.IDS:
			var counts := [0, 2, mini(6, Sizes.MAX_KINGDOMS[size_id])]
			if Sizes.MAX_KINGDOMS[size_id] > 6: counts.append(Sizes.MAX_KINGDOMS[size_id])
			for count in counts:
				for seed_value in [42, 71, 123, 7, 999, 0, 1, 2, 3, 4]:
					var rules = Rules.new()
					rules.rule_mode = mode
					rules.generate(seed_value, size_id, count)
					samples.append({"generation_version":Rules.MapGenerator.GENERATION_VERSION, "mode":mode, "size":size_id, "count":count, "seed":seed_value, "digest":digest(rules)})
	var file := FileAccess.open("res://tests/fixtures/generation_golden.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(samples, "\t") + "\n")
	print("Recorded generation v14 fixtures: ", samples.size())
	quit()
