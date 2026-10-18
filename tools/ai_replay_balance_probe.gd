extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Planner = preload("res://src/game/ai_planner.gd")
const Strategy = preload("res://src/game/ai_strategist.gd")
const Restore = preload("res://tools/player_replay_position_probe.gd")
const Fixture = preload("res://tools/heavy_strain_probe.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var label := "after"
	var turns_only := "--turns-only" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	assert(label.is_valid_filename())
	var results := {"positions": [], "turns": [], "matches": []}
	var restore = Restore.new()
	for path in ([] if turns_only else DirAccess.get_files_at(Restore.DIRECTORY)):
		if not path.begins_with("position-") or not path.ends_with(".json") or path.get_basename().split("-").size() != 3: continue
		var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Restore.DIRECTORY.path_join(path)))
		var model = restore.restore(sample)
		var start := Time.get_ticks_usec()
		var planner = Strategy.new(model,int(sample["faction"]),true) if model.uses_strategic_ai() else Planner.new(model,int(sample["faction"]),true)
		var action: Dictionary = planner.run()
		results["positions"].append({"id": sample["id"], "ms": (Time.get_ticks_usec()-start)/1000.0, "choice": action, "evaluated": planner.evaluated})
		await process_frame
	restore.free()
	for seed_value in [42,71]:
		var model = Fixture.crowded("huge",seed_value,120)
		model.ai_difficulty = "hard"
		var start := Time.get_ticks_usec()
		var actions: Array = model.ai_turn(1)
		results["turns"].append({"seed":seed_value,"map":"huge","ms":(Time.get_ticks_usec()-start)/1000.0,"actions":actions.size(),"land":model.territory(1)})
		await process_frame
	for seed_value in ([] if turns_only else [42,71]):
		var model = Rules.new()
		model.rule_mode = "modern"
		model.ai_difficulty = "hard"
		model.generate(seed_value,"small",4)
		var start := Time.get_ticks_usec()
		var actions := 0
		for turn in range(8):
			for faction in range(4): actions += model.ai_turn(faction).size()
			model.spread_trees()
			await process_frame
		var armies := [0,0,0,0]
		for cell in model.cells.values():
			if cell["unit"] > 0: armies[cell["unit"]] += 1
		var land := []
		for faction in range(4): land.append(model.territory(faction))
		results["matches"].append({"seed":seed_value,"rounds":8,"ms":(Time.get_ticks_usec()-start)/1000.0,"actions":actions,"land":land,"army_ranks":armies})
	FileAccess.open("res://artifacts/ai-replay-balance-%s.json" % label,FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("Balance probe complete: ",label," positions=",results["positions"].size()," turns=",results["turns"]," matches=",results["matches"])
	quit()
