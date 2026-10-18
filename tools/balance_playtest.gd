extends SceneTree
## Repeatable strategy probes against the current AI; does not change balance.
const Rules = preload("res://src/game/kingdom_rules.gd")
const POLICIES := ["stock_ai", "swarm", "develop_swarm", "knight_rush", "free_soldier"]
const ROUND_LIMIT := 25
var assertions := 0
var violations := 0

class MatchRules extends "res://src/game/kingdom_rules.gd":
	var first_player_turn := true
	func begin_turn(faction: int) -> int:
		# A new game gives the player the initial treasury without an income tick.
		if faction == 0 and first_player_turn:
			first_player_turn = false
			return 0
		return super.begin_turn(faction)

func _initialize() -> void:
	call_deferred("run")

func outcome(state) -> String:
	if state.territory(0) == 0:
		return "loss"
	for cell in state.cells.values():
		if cell["owner"] > 0 and cell["capital"] == cell["owner"]:
			return "ongoing"
	return "win"

func net(state, bank: Dictionary) -> int:
	return state.income(bank) - state.upkeep(bank)

func summon(state, bank: Dictionary) -> bool:
	if net(state, bank) < 3:
		return false
	for coord in bank["hexes"]:
		if state.cells[coord]["tree"] and state.cast_spell("summon", coord, 0, bank["capital"]):
			return true
	for coord in bank["hexes"]:
		if state.cast_spell("summon", coord, 0, bank["capital"]):
			return true
	return false

func invest(state, bank: Dictionary, metrics: Dictionary) -> void:
	# Develop cheap value-1 provinces rather than spending on higher tiers.
	for coord in bank["hexes"]:
		if state.cells[coord]["value"] == 1 and not state.cells[coord]["tree"] and not state.cells[coord]["grave"] and state.develop(coord, 0):
			metrics["developments"] += 1

func prepare(state, policy: String, metrics: Dictionary) -> void:
	metrics["starvations"] += state.begin_turn(0)
	var opening: bool = metrics.get("player_turns", 0) == 0
	metrics["player_turns"] = metrics.get("player_turns", 0) + 1
	for capital in state.kingdoms.keys():
		var bank: Dictionary = state.kingdoms.get(capital, {})
		if bank.is_empty() or bank["owner"] != 0:
			continue
		if summon(state, bank):
			metrics["summons"] += 1
		if policy == "free_soldier" and opening:
			var scouts: Array = []
			for coord in bank["hexes"]:
				if state.cells[coord]["unit"] == 1:
					scouts.append(coord)
			if scouts.size() == 2 and state.move_unit(scouts[0], scouts[1]):
				metrics["free_merges"] = metrics.get("free_merges", 0) + 1
			invest(state, bank, metrics)
		if policy == "develop_swarm":
			invest(state, bank, metrics)
		var wanted := 3 if policy == "knight_rush" else 2
		var champion := false
		var border_threat := policy == "knight_rush"
		for coord in bank["hexes"]:
			champion = champion or state.cells[coord]["unit"] >= wanted
			for next in state.neighbors(coord):
				border_threat = border_threat or state.cells[next]["owner"] > 0
		if border_threat and not champion:
			for coord in bank["hexes"]:
				var tier: int = state.cells[coord]["unit"]
				if tier > 0 and tier < wanted and net(state, bank) >= state.Catalog.unit_upkeep(wanted, true) - state.Catalog.unit_upkeep(tier, true):
					if state.recruit(coord, 0, wanted, capital):
						metrics["upgrades"] += 1
						break
		if policy != "knight_rush" or champion:
			for purchase in range(3):
				if net(state, bank) < 5:
					break
				var bought := false
				for coord in bank["hexes"]:
					if state.cells[coord]["unit"] == 0 and state.recruit(coord, 0, 1, capital):
						metrics["recruits"] += 1
						bought = true
						break
				if not bought:
					break

func move_army(state) -> void:
	# Reconsider ready merged troops. Cap commands to expose accidental loops.
	for command in range(100):
		var best_source := state.NONE as Vector2i
		var best_target := state.NONE as Vector2i
		var best_score := 0.0
		for source in state.cells:
			if state.unit_faction(source) != 0 or state.cells[source]["unit"] == 0 or state.cells[source]["moved"]:
				continue
			for target in state.reachable_targets(source):
				var cell: Dictionary = state.cells[target]
				var score := 0.0
				if cell["owner"] != 0 and not state.is_bridge(target):
					score = 12 + cell["value"] * 2
					if cell["capital"] > 0:
						score += 100
					if cell["mana_source"]:
						score += 18
				elif cell["unit"] > 0 and state.unit_faction(target) == 0:
					# Only merge when it unlocks a nearby enemy province.
					for border in state.friendly_routes(source):
						for next in state.neighbors(border):
							if state.cells[next]["owner"] > 0 and state.defense(next) == cell["unit"]:
								score = 7
				elif cell["tree"] or cell["grave"]:
					score = 3
				if score > best_score:
					best_score = score
					best_source = source
					best_target = target
		if best_source == state.NONE:
			break
		assertions += 1
		if not state.move_unit(best_source, best_target):
			violations += 1
			break
		if outcome(state) != "ongoing":
			break

func run() -> void:
	var seed_count := 4
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			seed_count = int(argument.trim_prefix("--seeds="))
	var results: Array = []
	for size_id in ["very_small", "small"]:
		for seed_value in range(seed_count):
			for policy in POLICIES:
				var state = MatchRules.new()
				state.rule_mode = "modern"
				state.generate(seed_value, size_id)
				var metrics := {"developments": 0, "summons": 0, "recruits": 0, "upgrades": 0, "starvations": 0}
				var result := "ongoing"
				var rounds := 0
				for round_index in range(ROUND_LIMIT):
					rounds = round_index + 1
					if policy == "stock_ai":
						state.ai_turn(0)
					else:
						prepare(state, policy, metrics)
						move_army(state)
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
				var bank_gold := 0
				var income := 0
				var wages := 0
				for bank in state.kingdoms.values():
					if bank["owner"] == 0:
						bank_gold += bank["gold"]
						income += state.income(bank)
						wages += state.upkeep(bank)
				results.append({"size": size_id, "seed": seed_value, "policy": policy, "outcome": result, "rounds": rounds, "land": state.territory(0), "gold": bank_gold, "income": income, "wages": wages, "metrics": metrics})
				print(JSON.stringify(results[-1]))
				await process_frame
	var file := FileAccess.open("res://artifacts/balance_matches.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"round_limit": ROUND_LIMIT, "seeds": seed_count, "results": results, "legal_moves": assertions, "rejected_moves": violations}, "\t"))
	print("Balance matches: %d completed; %d validated moves, %d rejected" % [results.size(), assertions, violations])
	quit(1 if violations else 0)
