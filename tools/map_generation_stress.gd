extends SceneTree
const Baseline = preload("res://artifacts/map_stress_before_source/kingdom_rules.gd")
const Optimized = preload("res://artifacts/map_stress_source/kingdom_rules.gd")
const Sizes = preload("res://artifacts/map_stress_source/map_sizes.gd")
const Probe = preload("res://tools/map_stress_probe.gd")
var results: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var failures := 0
	for target in [210, 500, 1000, 2000, 4000]:
		Sizes.stress_profile = Probe.profile(target)
		for seed_value in [42, 71, 123, 7, 999]:
			var base = Baseline.new()
			var optimized = Optimized.new()
			base.rule_mode = "modern"
			optimized.rule_mode = "modern"
			var started := Time.get_ticks_usec()
			base.generate(seed_value, "stress", 6)
			var base_ms := (Time.get_ticks_usec() - started) / 1000.0
			started = Time.get_ticks_usec()
			optimized.generate(seed_value, "stress", 6)
			var opt_ms := (Time.get_ticks_usec() - started) / 1000.0
			var identical: bool = base.cells == optimized.cells and base.kingdoms == optimized.kingdoms and base.rng.state == optimized.rng.state
			var valid: bool = base.connected_land() and base.MapGenerator.new(base).passable_land_connected()
			valid = valid and base.kingdoms.size() == 6
			for bank in base.kingdoms.values():
				valid = valid and bank["hexes"].size() == 7
			failures += int(not identical or not valid)
			var result := {"target": target, "tiles": base.cells.size(), "seed": seed_value,
				"baseline_ms": base_ms, "optimized_ms": opt_ms, "baseline_stages": base.generation_stages,
				"optimized_stages": optimized.generation_stages, "identical": identical, "connected": valid}
			results.append(result)
			var file := FileAccess.open("res://artifacts/map_generation_implemented.json", FileAccess.WRITE)
			file.store_string(JSON.stringify({"results": results, "failures": failures}, "\t"))
			print(JSON.stringify(result))
	print("Generation comparisons: %d passed, %d failed" % [results.size() - failures, failures])
	quit(1 if failures else 0)
