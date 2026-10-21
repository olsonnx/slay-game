extends "res://src/game/ai_strategist.gd"
## Experiment-only objective preferences. Combat/exposure/reply checks stay shared.
var approach := "aggressive"
var war_ready := true

func defensive_target(coord: Vector2i) -> bool:
	if state.cells[coord].unit == 0: return false
	for bank in state.kingdoms.values():
		if bank.owner == faction and state.distance(bank.capital,coord) <= 2: return true
	return false

func objective(coord: Vector2i) -> Dictionary:
	if approach == "neutral": return super.objective(coord)
	var cell: Dictionary = state.cells[coord]
	if cell.owner >= 0 and cell.owner != faction and not war_ready and not defensive_target(coord):
		return {"priority":-1000.0,"reason":"wait for economic advantage","kind":"wait"}
	var result := super.objective(coord)
	if cell.owner == -1 and not state.is_bridge(coord) and result.kind == "capture":
		result.priority += 6.0 if approach == "aggressive" else 2.0
	if cell.owner >= 0 and cell.owner != faction and approach == "aggressive": result.priority *= 1.15
	if approach == "defensive" and cell.owner == faction and cell.unit == 0 and cell.building == "" and not cell.tree and not cell.grave:
		var contact := false
		for next in queries.neighbors(coord):
			if state.cells[next].owner >= 0 and state.cells[next].owner != faction: contact = true
		if contact:
			result = {"priority":23.0,"reason":"block hostile frontier","kind":"block"}
	return result

func tactical_score(source: Vector2i, target: Vector2i, goal: Dictionary) -> float:
	if approach != "neutral" and state.cells[target].unit > 0 and state.unit_faction(target) == faction and state.cells[target].unit == state.cells[source].unit:
		var rank: int = state.cells[source].unit
		var bank: Dictionary = queries.support(source)
		if bank.is_empty(): return -1000.0
		var finance: Dictionary = queries.bank_summary(bank)
		var extra: int = state.unit_upkeep(rank+1,faction)-2*state.unit_upkeep(rank,faction) if rank < 3 else 100000
		if finance.upkeep+extra > finance.income: return -1000.0
	if goal.kind == "block":
		var rank: int = state.cells[source].unit
		var improves := false
		for next in [target] + queries.neighbors(target):
			if state.cells[next].owner != faction: continue
			var strength: int = rank if next == target else mini(rank,2)
			if queries.defense(next) < strength:
				for hostile in queries.neighbors(next):
					if state.cells[hostile].owner >= 0 and state.cells[hostile].owner != faction: improves = true
		if not improves: return -1000.0
	return super.tactical_score(source,target,goal)
