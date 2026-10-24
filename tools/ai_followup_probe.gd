extends SceneTree
const Restore = preload("res://tools/player_replay_position_probe.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Planner = preload("res://src/game/ai_planner.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var label := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	assert(label.is_valid_filename())
	var restore = Restore.new()
	var results := []
	for path in DirAccess.get_files_at("res://artifacts/ai-followup-positions"):
		var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/ai-followup-positions/"+path))
		var model = restore.restore(sample)
		var faction := int(sample["faction"])
		var queries = Analysis.Queries.new(model)
		var options := Candidates.preparation(model,faction,queries)
		var result := {"seq":int(sample["id"]),"round":sample["round"],"faction":faction,"options":options,"banks":[]}
		if int(sample["id"]) == 557:
			var ring := []
			for bank in model.kingdoms.values():
				if bank["owner"] != faction: continue
				for target in queries.frontier(bank["capital"]):
					for next in queries.neighbors(target):
						if model.cells[next]["owner"] >= 0 and model.cells[next]["owner"] != faction:
							ring.append({"front":target,"beyond":next,"owner":model.cells[next]["owner"],"defense":queries.defense(next),"capital":model.cells[next]["capital"]})
			result["ring"] = ring
		for bank in model.kingdoms.values():
			if bank["owner"] != faction: continue
			var best := {}
			for coord in bank["hexes"]:
				for rank in [1,2,3]:
					var cost: int = model.recruitment_cost(coord,faction,rank,bank["capital"])
					if cost < 0: continue
					var wages: int = model.Catalog.unit_upkeep(rank)-model.Catalog.unit_upkeep(model.cells[coord]["unit"])
					if not Analysis.sustainable(model,bank,wages,cost,queries): continue
					var value: float = queries.recruitment_value(coord,rank)-wages*0.85-cost*0.16
					if not best.has(str(rank)) or value > best[str(rank)]["value"]: best[str(rank)] = {"site":coord,"value":value,"cost":cost}
			result["banks"].append({"capital":bank["capital"],"gold":bank["gold"],"economy":queries.bank_summary(bank),"military":best})
		if int(sample["id"]) in [937,1087,1089] or faction == 2 and int(sample["round"]) in [6,7]:
			var started := Time.get_ticks_usec()
			var planner = Planner.new(model,faction)
			result["move"] = planner.run()
			result["move_ms"] = (Time.get_ticks_usec()-started)/1000.0
			result["evaluated"] = planner.evaluated
		results.append(result)
		print(JSON.stringify(result))
		await process_frame
	restore.free()
	FileAccess.open("res://artifacts/ai-followup-%s.json" % label,FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	quit()
