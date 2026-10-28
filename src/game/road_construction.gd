extends RefCounted
## Connect structures to structures or roads. Prices count newly paved land, including endpoints.
const Grid = preload("res://src/game/hex_grid.gd")
const Catalog = preload("res://src/game/game_catalog.gd")

static func endpoint(state, coord: Vector2i, faction: int) -> bool:
	if not state.cells.has(coord): return false
	var cell: Dictionary = state.cells[coord]
	return cell.owner == faction and (cell.capital >= 0 or cell.building != "") and not state.is_mountain(coord) and not state.is_barrier(coord) and not state.has_wildlife(coord) and not state.kingdom_at(coord).is_empty()

static func destination(state, coord: Vector2i, faction: int) -> bool:
	if endpoint(state, coord, faction): return true
	if not state.cells.has(coord): return false
	var cell: Dictionary = state.cells[coord]
	return cell.owner == faction and cell.get("road", false) and not cell.tree and not cell.grave and not state.is_mountain(coord) and not state.is_barrier(coord) and not state.has_wildlife(coord) and not state.kingdom_at(coord).is_empty()

static func options(state, source: Vector2i, faction: int, affordable := true) -> Dictionary:
	if not endpoint(state, source, faction): return {}
	var bank: Dictionary = state.kingdom_at(source)
	var parents := {source: Grid.NONE}
	var queue := [source]
	var cursor := 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for next in state.neighbors(current):
			if parents.has(next) or state.is_mountain(next) or state.is_barrier(next) or state.has_wildlife(next): continue
			var cell: Dictionary = state.cells[next]
			var bridge: bool = state.is_bridge(next) and (cell.unit == 0 or state.unit_faction(next) == faction)
			if not bridge and (cell.owner != faction or cell.tree or cell.grave): continue
			parents[next] = current
			queue.append(next)
	var result := {}
	for target in parents:
		if target == source or not destination(state, target, faction): continue
		var path: Array[Vector2i] = []
		var at: Vector2i = target
		var cost := 0
		while at != Grid.NONE:
			path.push_front(at)
			if not state.is_bridge(at) and not state.cells[at].get("road", false): cost += Catalog.ROAD_COST
			at = parents[at]
		var changes := cost > 0
		for index in range(path.size() - 1):
			if path[index + 1] not in state.cells[path[index]].get("road_links", []): changes = true
		if changes and (not affordable or bank.gold >= cost): result[target] = {"path":path, "cost":cost}
	return result

static func build(state, source: Vector2i, target: Vector2i, faction: int) -> bool:
	var plan: Dictionary = options(state, source, faction).get(target, {})
	if plan.is_empty(): return false
	var bank: Dictionary = state.kingdom_at(source)
	bank.gold -= plan.cost
	var path: Array = plan.path
	for coord in path:
		if not state.is_bridge(coord): state.cells[coord]["road"] = true
		if not state.cells[coord].has("road_links"): state.cells[coord]["road_links"] = []
	for index in range(path.size() - 1):
		var a: Vector2i = path[index]
		var b: Vector2i = path[index + 1]
		if b not in state.cells[a].road_links: state.cells[a].road_links.append(b)
		if a not in state.cells[b].road_links: state.cells[b].road_links.append(a)
	state.record_replay("build_road", faction, {"source":source, "coord":target, "path":path, "cost":plan.cost, "capital":bank.capital})
	return true
