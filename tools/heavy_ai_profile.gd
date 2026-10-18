extends SceneTree
const Fixture = preload("res://tools/heavy_strain_probe.gd")
const Rules = preload("res://artifacts/heavy_profile_source/kingdom_rules.gd")
const Planner = preload("res://artifacts/heavy_profile_source/ai_planner.gd")
const Meter = preload("res://artifacts/heavy_profile_source/meter.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var reports: Array = []
	for difficulty in ["normal", "hard"]:
		var fixture = Fixture.crowded("huge", 71, 300)
		var model = Rules.new()
		model.cells = fixture.cells
		model.kingdoms = fixture.kingdoms
		model.map_size = "huge"
		model.rule_mode = "modern"
		model.faction_count = 6
		model.mana_by_faction = fixture.mana_by_faction
		model.ai_difficulty = difficulty
		Meter.counters.clear()
		var started := Time.get_ticks_usec()
		var planner = Planner.new(model, 1)
		planner.run()
		var report := {"difficulty": difficulty, "wall_ms": (Time.get_ticks_usec() - started) / 1000.0,
			"evaluated": planner.evaluated, "inclusive_counters": Meter.counters.duplicate(true)}
		reports.append(report)
		print(JSON.stringify(report))
	FileAccess.open("res://artifacts/heavy_ai_profile.json", FileAccess.WRITE).store_string(JSON.stringify(reports, "\t"))
	quit()
