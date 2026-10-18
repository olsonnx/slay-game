extends SceneTree
const Restore = preload("res://tools/player_replay_position_probe.gd")
const OldPlanner = preload("res://artifacts/ai-followup-baseline/ai_planner.gd")
const OldAI = preload("res://artifacts/ai-followup-baseline/kingdom_ai.gd")
const Planner = preload("res://src/game/ai_planner.gd")
const NewAI = preload("res://src/game/kingdom_ai.gd")
const Fixture = preload("res://tools/heavy_strain_probe.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var results := {"positions":[],"huge_turns":[]}
	var restore = Restore.new()
	for seq in [557,644,937,1087,1089]:
		var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/ai-followup-positions/%d.json" % seq))
		for variant in ["old","new"]:
			var samples := []
			var planner
			for repetition in range(3):
				var model = restore.restore(sample)
				var start := Time.get_ticks_usec()
				planner = OldPlanner.new(model,int(sample["faction"])) if variant == "old" else Planner.new(model,int(sample["faction"]))
				planner.run()
				samples.append((Time.get_ticks_usec()-start)/1000.0)
				await process_frame
			samples.sort()
			var row := {"seq":seq,"variant":variant,"median_ms":samples[1],"samples":samples,"evaluated":planner.evaluated,"move":planner.best}
			results["positions"].append(row)
			print(JSON.stringify(row))
	restore.free()
	for seed_value in [42,71]:
		for variant in ["old","new"]:
			var model = Fixture.crowded("huge",seed_value,120)
			model.ai_difficulty = "hard"
			var start := Time.get_ticks_usec()
			var ai = OldAI.new(model) if variant == "old" else NewAI.new(model)
			var records: Array = ai.ai_turn(1)
			var row := {"seed":seed_value,"variant":variant,"ms":(Time.get_ticks_usec()-start)/1000.0,"actions":records.size(),"land":model.territory(1)}
			results["huge_turns"].append(row)
			print(JSON.stringify(row))
			await process_frame
	FileAccess.open("res://artifacts/ai-followup-timing.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	quit()
