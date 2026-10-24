extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Planner = preload("res://src/game/ai_planner.gd")
const Strategist = preload("res://src/game/ai_strategist.gd")
const DIRECTORY := "res://artifacts/player-replay-analysis"
func _initialize() -> void: call_deferred("run")
func restore(sample: Dictionary):
	var model = Rules.new()
	var state: Dictionary = Replay.decode(sample["position"])
	var header: Dictionary = sample["header"]
	model.cells = state["cells"]
	model.kingdoms = state["kingdoms"]
	model.mana_by_faction = state["mana"]
	model.effects_by_faction = state["effects"]
	model.capital_relocations = state.get("capital_relocations", {}).duplicate()
	model.pending_events.assign(state["events"])
	model.rng.state = int(state["rng"])
	model.rule_mode = header["rules"]
	model.map_size = header["map_size"]
	model.level_seed = int(header["seed"])
	model.faction_count = int(header["factions"])
	model.ai_difficulty = state["difficulty"]
	model.ai_algorithm = header["metadata"]["algorithm"]
	return Analysis.snapshot(model) # Hide encounter identities exactly as live AI does.
func probe(sample: Dictionary) -> Dictionary:
	var model = restore(sample)
	var faction := int(sample["faction"])
	var queries = Analysis.Queries.new(model)
	var baseline: float = Analysis.evaluate(model,faction,queries)
	var options: Array = Candidates.preparation(model,faction,queries)
	var planner = Strategist.new(model,faction,true) if model.uses_strategic_ai() else Planner.new(model,faction,true)
	var chosen: Dictionary = planner.run()
	var already_reachable := {}
	for source in model.cells:
		if model.cells[source]["unit"] == 0 or model.unit_faction(source) != faction: continue
		for target in queries.candidate_targets(source):
			if model.cells[target]["owner"] != faction and not model.is_bridge(target) and not model.knight_duel(source,target): already_reachable[target] = true
	var bridge_access := {}
	if chosen.get("kind") == "bridge":
		var capital: Vector2i = chosen["capital"]
		var old_front: Dictionary = queries.frontier(capital)
		var old_banks := 0
		for bank in model.kingdoms.values(): old_banks += int(bank["owner"] == faction)
		var bridge_model = Analysis.snapshot(model)
		assert(Candidates.apply(bridge_model,chosen,faction))
		var new_banks := 0
		for bank in bridge_model.kingdoms.values(): new_banks += int(bank["owner"] == faction)
		var new_front: Dictionary = Analysis.Queries.new(bridge_model).frontier(bridge_model.cells[capital]["kingdom"])
		var gained := 0
		for target in new_front:
			if not old_front.has(target) and bridge_model.cells[target]["owner"] != faction and not bridge_model.is_bridge(target): gained += 1
		bridge_access = {"new_targets":gained,"merged_banks":old_banks > new_banks}
	var purchases: Array = []
	for bank in model.kingdoms.values():
		if bank["owner"] != faction: continue
		var capital: Vector2i = bank["capital"]
		for rank in [1,2,3]:
			var site: Vector2i = model.NONE
			var cheapest := 100000
			for coord in bank["hexes"]:
				var price: int = model.recruitment_cost(coord,faction,rank,capital)
				var wages: int = model.Catalog.unit_upkeep(rank) - model.Catalog.unit_upkeep(model.cells[coord]["unit"])
				if price >= 0 and price < cheapest and Analysis.sustainable(model,bank,wages,price,queries):
					site = coord
					cheapest = price
			if site == model.NONE: continue
			var copy = Analysis.snapshot(model)
			assert(copy.recruit(site,faction,rank,capital))
			var gain: float = Analysis.evaluate(copy,faction) - baseline
			var legal: Dictionary = copy.reachable_targets(site)
			var enemy_targets := 0
			var new_enemy_targets := 0
			var capital_targets := 0
			var ranked: Array = []
			for target in legal:
				var cell: Dictionary = copy.cells[target]
				if cell["owner"] == faction or copy.is_bridge(target) or copy.knight_duel(site,target): continue
				if cell["owner"] >= 0:
					enemy_targets += 1
					if not already_reachable.has(target): new_enemy_targets += 1
				if cell["capital"] >= 0: capital_targets += 1
				var priority: float = (1000 if cell["capital"] >= 0 else 150 if cell["owner"] >= 0 and not already_reachable.has(target) else 100 if cell["owner"] >= 0 else 0) + cell["value"] + cell["unit"] * 10
				ranked.append([priority,target])
			ranked.sort_custom(func(a,b):return a[0] > b[0])
			var with_capture := gain
			var followup: Vector2i = model.NONE
			for option in ranked.slice(0,3):
				var after = Analysis.snapshot(copy)
				assert(after.move_unit(site,option[1]))
				var score: float = Analysis.evaluate(after,faction) - baseline
				if score > with_capture:
					with_capture = score
					followup = option[1]
			var shortlisted := false
			for option in options:
				if option["kind"] == "recruit" and option["tier"] == rank: shortlisted = true
			purchases.append({"rank":rank,"site":site,"cost":cheapest,"capital":capital,"gold":bank["gold"],
				"net":model.income(bank)-model.upkeep(bank),"static_gain":gain,"with_immediate_capture":with_capture,
				"followup":followup,"enemy_targets":enemy_targets,"new_enemy_targets":new_enemy_targets,"capital_targets":capital_targets,"shortlisted_rank":shortlisted})
	return Replay.encode({"id":sample["id"],"map":sample["header"]["map_size"],"round":sample["round"],"faction":faction,
		"algorithm":"strategic" if model.uses_strategic_ai() else "legacy", "chosen":chosen,"choice_score":planner.best_score,
		"options":options,"purchases":purchases,"bridge_access":bridge_access})
func run() -> void:
	var paths := DirAccess.get_files_at(DIRECTORY)
	paths.sort()
	var results: Array = []
	for path in paths:
		if not path.begins_with("position-") or not path.ends_with(".json"): continue
		if path.get_basename().split("-").size() != 3: continue
		var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY.path_join(path)))
		var result := probe(sample)
		results.append(result)
		print(JSON.stringify({"id":result["id"],"chosen":result["chosen"].get("kind","hold"),"alternatives":result["purchases"]}))
		await process_frame
	FileAccess.open(DIRECTORY.path_join("counterfactual-results.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	quit()
