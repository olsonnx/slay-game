extends RefCounted
## Recruitment, development, capital relocation and building validation/mutation.
## Receives authoritative state per call; never retains a model or UI.
const Grid = preload("res://src/game/hex_grid.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const NONE = Grid.NONE
const DIRECTIONS = Grid.DIRECTIONS

static func development_cost(state, coord: Vector2i) -> int:
	var cells: Dictionary = state.cells
	if not cells.has(coord) or state.is_bridge(coord) or state.is_mountain(coord):
		return 0
	var value: int = cells[coord].get("value", 1)
	var cost: int = state.DEVELOPMENT_BASE_COST * value * value
	return ceili(cost * 0.5) if preload("res://src/game/event_sites.gd").has_aura(state, coord, "development_discount") else cost

static func capital_relocation_cost(state, faction: int) -> int:
	return 10 * (1 + int(state.capital_relocations.get(faction, 0)))

static func can_relocate_capital(state, coord: Vector2i, faction: int) -> bool:
	var cells: Dictionary = state.cells
	var bank: Dictionary = state.kingdom_at(coord)
	if bank.is_empty() or bank["owner"] != faction:
		return false
	var cell: Dictionary = cells[coord]
	return cell["owner"] == faction and cell["capital"] < 0 and not state.has_wildlife(coord) and not state.is_mountain(coord) and not state.is_bridge(coord) and not state.is_barrier(coord) and cell["building"] == "" and not cell["tree"] and not cell["grave"] and bank["gold"] >= capital_relocation_cost(state, faction)

static func relocate_capital(state, coord: Vector2i, faction: int) -> bool:
	var cells: Dictionary = state.cells
	if not can_relocate_capital(state, coord, faction): return false
	var bank: Dictionary = state.kingdom_at(coord)
	var former: Vector2i = bank["capital"]
	var cost := capital_relocation_cost(state, faction)
	bank["gold"] -= cost
	cells[former]["capital"] = -1
	cells[coord]["fortified"] = cells[former]["fortified"]
	cells[coord]["fortified_by"] = cells[former]["fortified_by"]
	cells[former]["fortified"] = false
	cells[former]["fortified_by"] = -1
	cells[coord]["capital"] = faction
	bank["capital"] = coord
	state.kingdoms.erase(former)
	state.kingdoms[coord] = bank
	for cell in cells.values():
		if cell.get("bridge_home", NONE) == former and cell.get("bridge_owner", -1) == faction: cell["bridge_home"] = coord
		if cell.get("unit_home", NONE) == former and cell.get("unit_owner", -1) == faction:
			cell["unit_home"] = coord
	state.capital_relocations[faction] = int(state.capital_relocations.get(faction, 0)) + 1
	state.rebuild_kingdoms({faction: true})
	state.record_replay("relocate_capital", faction, {"coord":coord, "former":former, "cost":cost})
	return true

static func can_develop(state, coord: Vector2i, faction: int) -> bool:
	var cells: Dictionary = state.cells
	var kingdom: Dictionary = state.kingdom_at(coord)
	return not state.has_wildlife(coord) and not state.is_mountain(coord) and not kingdom.is_empty() and kingdom["owner"] == faction and cells[coord].get("value", 1) < state.MAX_VALUE and kingdom["gold"] >= development_cost(state, coord)

static func develop(state, coord: Vector2i, faction: int) -> bool:
	var cells: Dictionary = state.cells
	if not can_develop(state, coord, faction):
		return false
	var kingdom: Dictionary = state.kingdom_at(coord)
	kingdom["gold"] -= development_cost(state, coord)
	cells[coord]["value"] += 1
	state.record_replay("develop", faction, {"coord":coord})
	return true

static func construction_kingdom(state, coord: Vector2i, faction: int, capital := NONE) -> Dictionary:
	var candidates: Array = [state.kingdoms[capital]] if state.kingdoms.has(capital) else state.kingdoms.values() if capital == NONE else []
	for kingdom in candidates:
		if kingdom["owner"] != faction:
			continue
		var routes: Dictionary = state.friendly_routes(kingdom["capital"])
		for next in state.neighbors(coord):
			if routes.has(next):
				return kingdom
	return {}

static func bridge_targets(state, faction: int, capital := NONE) -> Dictionary:
	var cells: Dictionary = state.cells
	var targets: Dictionary = {}
	var bounds: Vector2 = state.bridge_bounds()
	var candidates: Array = [state.kingdoms[capital]] if state.kingdoms.has(capital) else state.kingdoms.values() if capital == NONE else []
	for kingdom in candidates:
		if kingdom["owner"] != faction or kingdom["gold"] < state.BRIDGE_COST:
			continue
		# One flood fill per kingdom, rather than recomputing routes for every site.
		var routes: Dictionary = state.friendly_routes(kingdom["capital"])
		for coord in routes:
			for direction in DIRECTIONS:
				var next: Vector2i = coord + direction
				var position := Grid.to_world(next)
				if not cells.has(next) and absf(position.x) <= bounds.x and absf(position.z) <= bounds.y:
					targets[next] = true
	return targets

static func recruit(state, coord: Vector2i, faction: int, requested_tier := 0, capital := NONE) -> bool:
	var cells: Dictionary = state.cells
	var cost := recruitment_cost(state, coord, faction, requested_tier, capital)
	if cost < 0:
		return false
	var kingdom: Dictionary = state.kingdom_at(coord)
	var cell: Dictionary = cells[coord]
	var spent: bool = cell["unit"] > 0 and cell["moved"]
	kingdom["gold"] -= cost
	cell["unit"] = cell["unit"] + 1 if requested_tier == 0 else requested_tier
	state.clear_terrain(coord, kingdom)
	# A fresh recruit can move; upgrading never restores a spent action.
	cell["moved"] = spent
	state.record_replay("recruit", faction, {"coord":coord, "tier":cell["unit"], "cost":cost, "capital":kingdom["capital"]})
	return true

static func can_recruit(state, coord: Vector2i, faction: int, requested_tier := 0, capital := NONE) -> bool:
	return recruitment_cost(state, coord, faction, requested_tier, capital) >= 0

static func recruitment_cost(state, coord: Vector2i, faction: int, requested_tier := 0, capital := NONE) -> int:
	var cells: Dictionary = state.cells
	if state.is_mountain(coord) or state.is_barrier(coord) or state.has_wildlife(coord):
		return -1
	var kingdom: Dictionary = state.kingdom_at(coord)
	if kingdom.is_empty() or kingdom["owner"] != faction or (capital != NONE and kingdom["capital"] != capital):
		return -1
	var cell: Dictionary = cells[coord]
	if not preload("res://src/game/logistics.gd").recruitment_zone(state, coord, faction) or cell["unit"] >= 3 or state.is_entrenched(coord):
		return -1
	var target_tier: int = cell["unit"] + 1 if requested_tier == 0 else requested_tier
	if target_tier <= cell["unit"] or target_tier > 3:
		return -1
	var cost: int = Catalog.unit_price(target_tier) - Catalog.unit_price(cell["unit"])
	return cost if kingdom["gold"] >= cost else -1

static func can_build(state, coord: Vector2i, faction: int, kind: String, capital := NONE) -> bool:
	var cells: Dictionary = state.cells
	if state.is_mountain(coord) or state.is_barrier(coord) or state.has_wildlife(coord):
		return false
	if kind == "bridge":
		var position := Grid.to_world(coord)
		var bounds: Vector2 = state.bridge_bounds()
		if cells.has(coord) or absf(position.x) > bounds.x or absf(position.z) > bounds.y:
			return false
		var payer := construction_kingdom(state, coord, faction, capital)
		return not payer.is_empty() and payer["gold"] >= state.BRIDGE_COST
	if kind not in ["tower", "city"]:
		return false
	var kingdom: Dictionary = state.kingdom_at(coord)
	if kingdom.is_empty() or kingdom["owner"] != faction:
		return false
	if capital != NONE and kingdom["capital"] != capital:
		return false
	var cell: Dictionary = cells[coord]
	var cost: int = state.tower_cost(faction) if kind == "tower" else state.CITY_COST
	return kingdom["gold"] >= cost and cell["unit"] == 0 and cell["capital"] < 0 and cell["building"] == "" and not cell["tree"] and not cell["grave"]

static func build_structure(state, coord: Vector2i, faction: int, kind: String, capital := NONE) -> bool:
	var cells: Dictionary = state.cells
	if not can_build(state, coord, faction, kind, capital):
		return false
	if kind == "bridge":
		var payer := construction_kingdom(state, coord, faction, capital)
		payer["gold"] -= state.BRIDGE_COST
		cells[coord] = state.make_cell()
		cells[coord]["building"] = "bridge"
		cells[coord]["value"] = 0
		cells[coord]["bridge_owner"] = faction
		cells[coord]["bridge_home"] = payer["capital"]
		state.rebuild_kingdoms()
		state.record_replay("build", faction, {"coord":coord, "building":kind, "capital":capital})
		return true
	var kingdom: Dictionary = state.kingdom_at(coord)
	kingdom["gold"] -= state.tower_cost(faction) if kind == "tower" else state.CITY_COST
	cells[coord]["building"] = kind
	state.record_replay("build", faction, {"coord":coord, "building":kind, "capital":kingdom["capital"]})
	return true
