extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Fixture = preload("res://tools/heavy_strain_probe.gd")
var results: Array = []
func _initialize() -> void: call_deferred("run")
func clone(model):
	var copy = Analysis.snapshot(model)
	copy.cells = model.cells.duplicate(true)
	copy.rng.seed = model.rng.seed
	copy.rng.state = model.rng.state
	return copy
func persist() -> void:
	var file := FileAccess.open("res://artifacts/ai_strategy_comparison.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
func metrics(model, faction: int) -> Dictionary:
	var income := 0
	var wages := 0
	var gold := 0
	var units := 0
	for bank in model.kingdoms.values():
		if bank["owner"] != faction: continue
		income += model.income(bank)
		wages += model.upkeep(bank)
		gold += bank["gold"]
	for coord in model.cells: units += int(model.cells[coord]["unit"] > 0 and model.unit_faction(coord) == faction)
	return {"land": model.territory(faction), "income": income, "upkeep": wages, "gold": gold, "units": units, "evaluation": Analysis.evaluate(model, faction)}
func run() -> void:
	for seed_value in [42, 71]:
		var original = Fixture.crowded("huge", seed_value, 120)
		for algorithm in ["legacy", "strategic"]:
			var model = clone(original)
			model.ai_algorithm = algorithm
			var before := metrics(model, 1)
			var started := Time.get_ticks_usec()
			var records: Array = model.ai_turn(1)
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			var result := {"case": "matched_huge_faction_turn", "seed": seed_value, "algorithm": algorithm, "ms": elapsed, "actions": records.size(), "before": before, "after": metrics(model, 1)}
			results.append(result)
			print(JSON.stringify(result))
			persist()
			await process_frame
	# Both backends face the same opponents; rotate the strategic player through
	# every start. These short matches are evidence, not a strength certification.
	for seed_value in [0, 1]:
		for rotation in range(4):
			var model = Rules.new()
			model.rule_mode = "modern"
			model.generate(seed_value, "small", 4)
			var deaths: Dictionary = {"legacy": 0, "strategic": 0}
			var started := Time.get_ticks_usec()
			var played := 0
			for round_index in range(10):
				for faction in range(4):
					model.ai_algorithm = "strategic" if faction == rotation else "legacy"
					var records: Array = model.ai_turn(faction)
					for record in records: deaths[model.ai_algorithm] += int(record.get("kind", "") == "death")
				played += 1
				model.spread_trees()
			var scores: Array = []
			for faction in range(4): scores.append(metrics(model, faction))
			var result := {"case": "rotated_small_match", "seed": seed_value, "strategic_faction": rotation, "rounds": played, "turns": played * 4, "starvation": deaths, "factions": scores, "ms": (Time.get_ticks_usec() - started) / 1000.0}
			results.append(result)
			print(JSON.stringify(result))
			persist()
			await process_frame
	quit()
