extends RefCounted
## Component queries and substantial, bridge-reachable landmasses.
const Grid = preload("res://src/game/hex_grid.gd")
const MIN_ISLAND_TILES := 13

static func components(cells: Dictionary, passable := false) -> Array:
	var result: Array = []
	var seen := {}
	for start in cells:
		if seen.has(start) or passable and cells[start].get("mountain", false): continue
		var component: Array = [start]
		seen[start] = true
		var index := 0
		while index < component.size():
			var coord: Vector2i = component[index]
			index += 1
			for direction in Grid.DIRECTIONS:
				var next: Vector2i = coord + direction
				if cells.has(next) and not seen.has(next) and not (passable and cells[next].get("mountain", false)):
					seen[next] = true
					component.append(next)
		result.append(component)
	result.sort_custom(func(a, b): return a.size() > b.size())
	return result

static func starting_land_connected(state) -> bool:
	var regions := components(state.cells, true)
	if regions.is_empty(): return false
	var mainland := {}
	for coord in regions[0]: mainland[coord] = true
	for bank in state.kingdoms.values():
		if not mainland.has(bank["capital"]): return false
	return true

static func starting_land_reachable(state) -> bool:
	# Include buildable one-water-hex crossings, but never impassable mountains.
	var regions := components(state.cells, true)
	if regions.is_empty(): return false
	var membership := {}
	for index in range(regions.size()):
		for coord in regions[index]: membership[coord] = index
	var reached := {0:true}
	var pending := [0]
	while not pending.is_empty():
		var index: int = pending.pop_back()
		for coord in regions[index]:
			for direction in Grid.DIRECTIONS:
				var gap: Vector2i = coord + direction
				if state.cells.has(gap) or not state.inside_map(gap): continue
				for edge in Grid.DIRECTIONS:
					var other: int = membership.get(gap + edge, -1)
					if other >= 0 and not reached.has(other):
						reached[other] = true
						pending.append(other)
	return reached.size() == regions.size()

static func island_plans(state) -> Array:
	if state.rng.randf() < 0.35: return []
	var total: int = preload("res://src/game/map_sizes.gd").APPROX_TILES[state.map_size]
	var count := 1
	if total >= 150 and state.faction_count >= 3 and state.rng.randf() < 0.5: count = 2
	# Leave room for the mainland homes and meaningful neutral expansion.
	var available: int = total - ((state.faction_count - count) * 12 + 6)
	if available < count * 19: return []
	var share: float = state.rng.randf_range(0.36, 0.49) if count == 1 else state.rng.randf_range(0.27, 0.33)
	var desired := mini(roundi(total * share), available / count)
	var plans: Array = []
	for index in range(count): plans.append(desired)
	return plans

static func home_site(state, island: Dictionary, homes: Array) -> Vector2i:
	var best := Grid.NONE
	var best_score := -1
	for coord in island:
		var full := true
		for direction in Grid.DIRECTIONS:
			if not island.has(coord + direction): full = false
		if not full: continue
		var nearest := 10000
		for home in homes: nearest = mini(nearest, state.distance(coord, home))
		if nearest >= 5 and nearest > best_score:
			best = coord
			best_score = nearest
	return best

static func open_site(state, coord: Vector2i) -> bool:
	if state.cells.has(coord): return false
	for direction in Grid.DIRECTIONS:
		if state.cells.has(coord + direction): return false
	return true

static func add_islands(state, plans: Array, protected: Dictionary, homes: Array) -> Array:
	var mainland: Array = state.cells.keys()
	var result: Array = []
	# Try exposed coasts in deterministic shuffled order, without committing any
	# partial island. Every accepted island stays separate and has a short crossing.
	var coasts: Array = mainland.filter(func(coord): return state.neighbors(coord).size() < 6)
	coasts = state.shuffled(coasts)
	for desired in plans:
		var placed := false
		for shore in coasts:
			if placed: break
			for direction in state.shuffled(Grid.DIRECTIONS.duplicate()):
				var gap: Vector2i = shore + direction
				var landing: Vector2i = gap + direction
				if state.cells.has(gap) or not open_site(state, landing): continue
				var island := {landing:true}
				var frontier := {}
				var axis: float = state.rng.randf_range(0.0, TAU)
				var last := landing
				while island.size() < desired:
					var best := Grid.NONE
					var score := INF
					for edge in Grid.DIRECTIONS:
						var candidate: Vector2i = last + edge
						if candidate != gap and not island.has(candidate) and not frontier.has(candidate) and open_site(state, candidate):
							var at: Vector3 = Grid.to_world(candidate - landing)
							var angle := atan2(at.z, at.x) - axis
							var stretch := 1.0 + 0.22 * cos(2.0 * angle) + 0.12 * sin(3.0 * angle)
							frontier[candidate] = state.distance(landing, candidate) / stretch + state.rng.randf_range(0.0, 2.4)
					for candidate in frontier:
						if frontier[candidate] < score:
							score = frontier[candidate]
							best = candidate
					if best == Grid.NONE: break
					frontier.erase(best)
					island[best] = true
					last = best
				if island.size() < desired: continue
				var inside := true
				for coord in island:
					var at: Vector3 = Grid.to_world(coord)
					if Vector2(at.x, at.z).length() >= preload("res://src/game/map_sizes.gd").generation_bounds(state.map_size).x - 4.0: inside = false
				if not inside: continue
				var home := home_site(state, island, homes)
				if home == Grid.NONE: continue
				homes.append(home)
				for coord in island: state.cells[coord] = state.make_cell()
				protected[shore] = true
				protected[landing] = true
				result.append({"shore":shore, "gap":gap, "landing":landing, "hexes":island.keys()})
				placed = true
				break
	return result

