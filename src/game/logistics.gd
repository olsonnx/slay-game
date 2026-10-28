extends RefCounted
## Infrastructure costs and stable bridge sponsorship; movement uses half-steps.
const Catalog = preload("res://src/game/game_catalog.gd")
const Grid = preload("res://src/game/hex_grid.gd")

static func recruitment_hub(cell: Dictionary) -> bool:
	return cell.get("capital", -1) >= 0 or cell.get("building", "") == "city"

static func recruitment_zone(state, coord: Vector2i, faction: int) -> bool:
	if not state.cells.has(coord) or state.cells[coord].owner != faction: return false
	var bank: Dictionary = state.kingdom_at(coord)
	if bank.is_empty(): return false
	for site in [coord] + state.neighbors(coord):
		if state.cells[site].owner == faction and recruitment_hub(state.cells[site]): return true
	return false

static func tower_cost(state, faction: int) -> int:
	var count := 0
	for cell in state.cells.values():
		if cell.owner == faction and cell.building == "tower": count += 1
	return Catalog.TOWER_COST + count * Catalog.TOWER_INCREMENT

static func bridge_bank(state, cell: Dictionary) -> Dictionary:
	var faction: int = cell.get("bridge_owner", -1)
	if faction < 0: return {}
	var home: Vector2i = cell.get("bridge_home", Grid.NONE)
	if state.kingdoms.has(home) and state.kingdoms[home].owner == faction: return state.kingdoms[home]
	if state.cells.has(home) and state.cells[home].owner == faction:
		var merged: Dictionary = state.kingdom_at(home)
		if not merged.is_empty(): return merged
	# A lost/merged capital transfers the bill to a surviving bank of its builder.
	for bank in state.kingdoms.values():
		if bank.owner == faction: return bank
	return {}

static func infrastructure_upkeep(state, bank: Dictionary) -> int:
	var total := 0
	for coord in bank.hexes:
		if state.cells[coord].building == "tower": total += Catalog.TOWER_UPKEEP
	for cell in state.cells.values():
		if cell.building != "bridge": continue
		var payer := bridge_bank(state, cell)
		if not payer.is_empty() and payer.capital == bank.capital: total += Catalog.BRIDGE_UPKEEP
	return total

static func step_cost(state, source: Vector2i, target: Vector2i, faction: int) -> int:
	var a: Dictionary = state.cells[source]
	var b: Dictionary = state.cells[target]
	if a.owner == faction and b.owner == faction and road_connected(a, b, source, target) and not state.has_wildlife(target): return 1
	return 2

static func road_connected(a: Dictionary, b: Dictionary, source: Vector2i, target: Vector2i) -> bool:
	if not a.get("road", false) or not b.get("road", false): return false
	# Earlier experimental maps contain paved tiles without explicit route edges.
	return (not a.has("road_links") or target in a.road_links) and (not b.has("road_links") or source in b.road_links)

static func routes(state, source: Vector2i, tier := -1) -> Dictionary:
	var parents := {source: Grid.NONE}
	var costs := {source: 0}
	var faction: int = state.unit_faction(source) if state.cells[source].unit > 0 else state.cells[source].owner
	if tier < 0: tier = state.cells[source].unit
	var budget: int = Catalog.MOVEMENT[tier] * 2
	var pending = preload("res://src/game/integer_frontier.gd").new()
	pending.push(source, 0)
	while not pending.is_empty():
		var current: Vector2i = pending.pop()
		if costs[current] != pending.cost: continue
		for next in state.neighbors(current):
			var cell: Dictionary = state.cells[next]
			var accessible: bool = cell.owner == faction or cell.building == "bridge" and (cell.unit == 0 or cell.get("unit_owner", -1) == faction)
			if not accessible or state.is_mountain(next) or state.is_barrier(next) or state.has_wildlife(next): continue
			var cost: int = costs[current] + step_cost(state, current, next, faction)
			if cost > budget or cost >= costs.get(next, 2147483647): continue
			costs[next] = cost
			parents[next] = current
			pending.push(next, cost)
	return {"parents": parents, "costs": costs, "budget": budget}
