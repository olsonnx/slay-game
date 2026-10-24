extends RefCounted
## Pure board analysis and independent search snapshots. Never consumes game RNG.
const Queries = preload("res://src/game/ai_queries.gd")
const PROFILES := {
	"easy": {"depth": 1, "width": 1, "candidates": 5, "spending": 4, "risk": 0.7},
	"normal": {"depth": 3, "width": 2, "candidates": 7, "spending": 8, "risk": 1.0},
	"hard": {"depth": 5, "width": 3, "candidates": 9, "spending": 12, "risk": 1.15}
}
const UNIT_VALUE := [0.0, 10.0, 21.0, 38.0]

static func profile(model) -> Dictionary:
	return PROFILES.get(model.ai_difficulty, PROFILES["normal"])

static func snapshot(model):
	return preload("res://src/game/state_snapshot.gd").simulation(model)

static func threats(model, faction: int) -> Dictionary:
	return Queries.new(model).threats(faction)

static func endangered(model, coord: Vector2i, danger: Dictionary) -> bool:
	if not danger.has(coord):
		return false
	var strength: int = danger[coord]["strength"]
	return strength > model.defense(coord) or (strength == 3 and model.cells[coord]["unit"] == 3)

static func frontier(model, capital: Vector2i) -> Dictionary:
	return Queries.new(model).frontier(capital)

static func evaluate(model, faction: int, queries = null) -> float:
	queries = Queries.new(model) if queries == null else queries
	var score := 0.0
	var land := 0
	var enemy_capitals := 0
	var own_capitals := 0
	var danger: Dictionary = queries.defense_needs(faction)
	var risk: float = profile(model)["risk"]
	for coord in model.cells:
		var cell: Dictionary = model.cells[coord]
		if cell["owner"] == faction:
			land += 1
			score += 2.5
			if cell["mana_source"]:
				score += 7.0
			if cell["capital"] >= 0:
				own_capitals += 1
			if endangered(model, coord, danger):
				var loss: float = 1.5 + (0.0 if cell["tree"] or cell["grave"] else cell["value"] * 0.8) + UNIT_VALUE[cell["unit"]] * 0.8
				loss += queries.supply_risk(coord)
				var duel_only: bool = cell["unit"] == 3 and danger[coord]["strength"] == 3
				if duel_only:
					# Mutual attrition retains land/capital and also costs the attacker.
					loss = UNIT_VALUE[3] * 0.2
				if cell["capital"] >= 0 and not duel_only:
					loss += 85.0
				if cell["building"] != "":
					loss += 12.0
				if (cell["fortified"] or model.is_entrenched(coord)) and danger[coord]["sources"].size() == 1:
					loss *= 0.3
				score -= loss * risk * (0.55 if danger[coord].get("projected",false) else 1.0)
		elif cell["owner"] >= 0:
			score -= 0.6
			if cell["capital"] >= 0:
				enemy_capitals += 1
				score -= 15.0
		if cell["unit"] > 0:
			if model.unit_faction(coord) == faction:
				score += UNIT_VALUE[cell["unit"]]
				if queries.support(coord).is_empty():
					score -= UNIT_VALUE[cell["unit"]] + 5.0
			else:
				score -= UNIT_VALUE[cell["unit"]] * 0.65
	for kingdom in model.kingdoms.values():
		var summary: Dictionary = queries.bank_summary(kingdom)
		if kingdom["owner"] != faction:
			score -= (summary["income"] - summary["upkeep"]) * 0.6 + kingdom["gold"] * 0.025
			continue
		var net: int = summary["income"] - summary["upkeep"]
		score += net * 2.2 + kingdom["gold"] * 0.12
		if kingdom["gold"] + net < 0:
			score -= 150.0
		elif net < 0:
			score -= absf(net) * 2.0
	score += model.get_mana(faction) * 1.5
	if own_capitals > 0:
		score += 25.0 + (own_capitals - 1) * 2.0
	if land == 0:
		return -10000.0
	if enemy_capitals == 0:
		score += 500.0
	return score

static func sustainable(model, kingdom: Dictionary, added_wages: int, cost: int, queries = null) -> bool:
	queries = Queries.new(model) if queries == null else queries
	var summary: Dictionary = queries.bank_summary(kingdom)
	var net: int = summary["income"] - summary["upkeep"] - added_wages
	if net >= 0:
		return true
	# Hard may bridge a short deficit, but cannot buy a predictable bankruptcy.
	return model.ai_difficulty == "hard" and kingdom["gold"] - cost >= -net * 3 + 10

static func safe_spending(kingdom: Dictionary, cost: int, income_gain: int, queries) -> bool:
	var summary: Dictionary = queries.bank_summary(kingdom)
	return kingdom["gold"] - cost + summary["income"] + income_gain - summary["upkeep"] >= 0

static func variation(model, source: Vector2i, target: Vector2i) -> float:
	var key: int = posmod(hash([model.level_seed, model.ai_revision, source, target]), 104729)
	return key / 104729.0 * (0.65 if model.ai_difficulty == "easy" else 0.08)

static func event_choice(model, event: Dictionary) -> int:
	var entry: Dictionary = model.Events.EVENTS.get(event.id,{})
	if entry.has("authored"): return preload("res://src/game/authored_event_runtime.gd").ai_choice(model,entry.authored,event)
	var bank: Dictionary = model.kingdom_at(event["coord"])
	match event["id"]:
		"regroup": return 0 if not bank.is_empty() and bank["gold"] + model.income(bank) < model.upkeep(bank) else 1
		"revolt": return 1
		"economist": return 1 if not bank.is_empty() and bank["gold"] >= 10 and bank["gold"] - 10 + model.income(bank) + 1 >= model.upkeep(bank) else 0
	if event["id"] not in ["altar", "duel"]:
		return 0
	var coord: Vector2i = event["coord"]
	var tier: int = model.cells[coord]["unit"]
	var faction: int = event["faction"]
	var danger := threats(model, faction)
	# Never gamble a defender protecting a reachable capital.
	for next in [coord] + model.neighbors(coord):
		if model.cells[next]["owner"] == faction and model.cells[next]["capital"] >= 0 and danger.has(next):
			return 1
	var benefit: float = 15.0 if event["id"] == "altar" else (UNIT_VALUE[tier + 1] - UNIT_VALUE[tier] if tier < 3 else 2.4)
	var loss: float = UNIT_VALUE[tier] * profile(model)["risk"]
	return 0 if 0.6 * benefit > 0.4 * loss else 1
