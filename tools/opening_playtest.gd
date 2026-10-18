extends SceneTree
## Paired opening comparison with identical stock-AI continuation policies.
const Harness = preload("res://tools/balance_playtest.gd")
const OPENINGS := ["stock_ai", "paid_soldier_plus_summon", "free_soldier_develop", "two_scouts_develop"]

func _initialize() -> void:
	call_deferred("run")

func outcome(state) -> String:
	if state.territory(0) == 0:
		return "loss"
	for cell in state.cells.values():
		if cell["owner"] > 0 and cell["capital"] == cell["owner"]:
			return "ongoing"
	return "win"

func opening(state, kind: String) -> Dictionary:
	if kind == "stock_ai":
		state.ai_turn(0)
		return {}
	state.begin_turn(0)
	var bank: Dictionary = state.kingdoms.values()[0]
	var scout := state.NONE as Vector2i
	for coord in bank["hexes"]:
		if state.cells[coord]["unit"] == 1:
			scout = coord
	if kind == "paid_soldier_plus_summon":
		assert(state.recruit(scout, 0, 2, bank["capital"]))
	assert(state.cast_spell("summon", bank["capital"], 0))
	if kind == "free_soldier_develop":
		assert(state.move_unit(scout, bank["capital"]))
	if kind in ["free_soldier_develop", "two_scouts_develop"]:
		for coord in bank["hexes"]:
			if state.cells[coord]["value"] == 1:
				assert(state.develop(coord, 0))
	var data := {"gold": bank["gold"], "income": state.income(bank), "upkeep": state.upkeep(bank)}
	var moves: Array = state.ai_movements(0)
	while not moves.is_empty() and outcome(state) == "ongoing":
		moves = state.ai_movements(0)
	return data

func run() -> void:
	var results: Array = []
	for size_id in ["very_small", "small"]:
		for seed_value in range(16):
			for policy in OPENINGS:
				var state = Harness.MatchRules.new()
				state.rule_mode = "modern"
				state.generate(seed_value, size_id)
				var starting: Dictionary = opening(state, policy)
				var result := outcome(state)
				var rounds := 1
				for round_index in range(25):
					rounds = round_index + 1
					if round_index > 0 and result == "ongoing":
						state.ai_turn(0)
						result = outcome(state)
					if result != "ongoing":
						break
					for faction in range(1, state.faction_count):
						state.ai_turn(faction)
						result = outcome(state)
						if result != "ongoing":
							break
					if result != "ongoing":
						break
					state.spread_trees()
				results.append({"size": size_id, "seed": seed_value, "opening": policy, "result": result, "rounds": rounds, "opening_resources": starting})
				await process_frame
	var file := FileAccess.open("res://artifacts/opening_matches.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	for size_id in ["very_small", "small"]:
		for policy in OPENINGS:
			var wins := 0
			var losses := 0
			var unfinished := 0
			var winning_rounds := 0
			for row in results:
				if row["size"] != size_id or row["opening"] != policy:
					continue
				if row["result"] == "win":
					wins += 1
					winning_rounds += row["rounds"]
				elif row["result"] == "loss":
					losses += 1
				else:
					unfinished += 1
			print("%s %s: %dW %dL %d unresolved; mean winning rounds %.2f" % [size_id, policy, wins, losses, unfinished, winning_rounds / float(maxi(1, wins))])
	print("Opening matches: %d completed" % results.size())
	quit()
