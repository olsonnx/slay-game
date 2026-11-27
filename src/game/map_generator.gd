extends RefCounted
## Seeded island geometry, resources and terrain; mutates only the supplied rules.
const Grid = preload("res://src/game/hex_grid.gd")
const MapSizes = preload("res://src/game/map_sizes.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const StartingTerritories = preload("res://src/game/starting_territories.gd")
const Archipelago = preload("res://src/game/archipelago.gd")
const DIRECTIONS = Grid.DIRECTIONS
const NONE = Grid.NONE
const GENERATION_VERSION := 16
var state
var adjacency: Dictionary = {}
var protected_landings: Dictionary = {}
var shape_angle := 0.0
var lake_budget := 0
var protected_passes: Dictionary = {}

func neighbors(coord: Vector2i) -> Array[Vector2i]:
	return adjacency[coord] if adjacency.has(coord) else state.neighbors(coord)

# Before each deletion, the relevant graph is connected. It remains connected
# iff every surviving neighbour is reachable from the others. Stop early.
func removal_preserves_connections(coord: Vector2i, passable_only := false) -> bool:
	var wanted: Dictionary = {}
	for next in neighbors(coord):
		if not passable_only or not state.is_mountain(next):
			wanted[next] = true
	if wanted.size() <= 1:
		return true
	var first: Vector2i = wanted.keys()[0]
	wanted.erase(first)
	var seen := {first: true}
	var queue := [first]
	var index := 0
	while index < queue.size():
		var current: Vector2i = queue[index]
		index += 1
		for next in neighbors(current):
			if seen.has(next) or (passable_only and state.is_mountain(next)):
				continue
			seen[next] = true
			queue.append(next)
			wanted.erase(next)
			if wanted.is_empty():
				return true
	return false

func _init(rules) -> void:
	state = rules

func add_land(coord: Vector2i) -> void:
	if state.inside_map(coord) and not state.cells.has(coord):
		state.cells[coord] = state.make_cell()

func connected_land() -> bool:
	if state.cells.is_empty():
		return false
	var first: Vector2i = state.cells.keys()[0]
	var visited := {first: true}
	var pending := [first]
	while not pending.is_empty():
		var coord: Vector2i = pending.pop_back()
		for next in state.neighbors(coord):
			if not visited.has(next):
				visited[next] = true
				pending.append(next)
	return visited.size() == state.cells.size()

func starting_sites() -> Array:
	# Reserve safe home rings; later footprints can extend into neutral land.
	var candidates: Array = []
	var bounds: Vector2 = MapSizes.spec(state.map_size)["bounds"]
	var axes: Vector2 = bounds * state.rng.randf_range(0.65, 0.78)
	var radius := maxf(axes.x, axes.y)
	var q_limit := ceili(radius / sqrt(3.0) + radius / 3.0)
	var r_limit := ceili(radius / 1.5)
	for q in range(-q_limit, q_limit + 1):
		for r in range(-r_limit, r_limit + 1):
			var coord := Vector2i(q, r)
			var point := Grid.to_world(coord)
			var local: Vector2 = Vector2(point.x, point.z).rotated(-shape_angle) / axes
			if local.length_squared() > 1.0:
				continue
			candidates.append(coord)
	# Restart greedy packing rather than relaxing separation for crowded profiles.
	for attempt in range(128):
		var sites: Array = []
		for coord in state.shuffled(candidates):
			var separated := true
			for site in sites:
				if state.distance(coord, site) < 5:
					separated = false
					break
			if separated:
				sites.append(coord)
				if sites.size() == state.faction_count:
					return state.shuffled(sites)
	# Dense selections cannot trigger an exhaustive combinatorial search.
	return state.shuffled(MapSizes.fallback_sites(state.map_size, state.faction_count)).slice(0, state.faction_count)

func join_land(start: Vector2i, finish: Vector2i, width: int) -> void:
	var cursor := start
	while true:
		add_land(cursor)
		if width > 0:
			for direction in DIRECTIONS:
				add_land(cursor + direction)
		if cursor == finish:
			break
		var choices: Array[Vector2i] = []
		for direction in DIRECTIONS:
			var next: Vector2i = cursor + direction
			if state.inside_map(next) and state.distance(next, finish) < state.distance(cursor, finish):
				choices.append(next)
		cursor = choices[state.rng.randi_range(0, choices.size() - 1)]

func grow_lobe(center: Vector2i, radius: int, core: int) -> void:
	var phase: float = state.rng.randf_range(0.0, TAU)
	var secondary: float = state.rng.randf_range(0.0, TAU)
	var extent := maxi(core + 1, roundi(radius * 0.85))
	for q in range(-extent - 2, extent + 3):
		for r in range(-extent - 2, extent + 3):
			var delta := Vector2i(q, r)
			var at: Vector3 = Grid.to_world(delta)
			var angle := atan2(at.z, at.x)
			var distance := Vector2(at.x, at.z).length() / sqrt(3.0)
			# Correlated coast variation gives solid interiors and rounded coves,
			# rather than independently punching holes through every large lobe.
			var edge := extent * (0.94 + 0.10 * sin(angle * 3.0 + phase) + 0.07 * sin(angle * 5.0 + secondary))
			if distance <= core or distance < edge - 0.45 or distance < edge and state.rng.randf() < 0.7:
				add_land(center + delta)

func generate(seed_value: int = -1, size_id := "small", kingdom_count := 0, allow_islands := true) -> void:
	adjacency.clear()
	protected_landings.clear()
	protected_passes.clear()
	state.map_size = size_id if MapSizes.SPECS.has(size_id) else "small"
	var profile := MapSizes.spec(state.map_size)
	if seed_value >= 0:
		state.level_seed = seed_value
	else:
		state.rng.randomize()
		state.level_seed = state.rng.randi()
	state.rng.seed = state.level_seed
	shape_angle = state.rng.randf_range(0.0, TAU)
	state.cells.clear()
	state.kingdoms.clear()
	state.mana_by_faction.clear()
	state.initial_kingdom_count = 0 if kingdom_count == 0 else MapSizes.clamp_kingdom_count(state.map_size, kingdom_count)
	if state.initial_kingdom_count == 0:
		# Compatibility for existing tools/callers; Quick Play always sends a count.
		state.faction_count = profile["min_factions"] if profile["min_factions"] == profile["max_factions"] else state.rng.randi_range(profile["min_factions"], profile["max_factions"])
	else:
		state.faction_count = state.initial_kingdom_count
	var minimum_land: int = profile["min_land"] if kingdom_count == 0 else maxi(profile["min_land"], state.faction_count * 7 + 10)
	var total_minimum := minimum_land
	var island_plans: Array = Archipelago.island_plans(state) if allow_islands else []
	# Some worlds stay open. Others reserve space for a few substantial lakes.
	lake_budget = 0
	var nominal: int = MapSizes.APPROX_TILES[state.map_size]
	if nominal >= 80 and state.rng.randf() < 0.7:
		lake_budget = maxi(6, roundi(nominal * state.rng.randf_range(0.05, 0.10)))
	minimum_land += lake_budget
	var total_target: int = maxi(minimum_land, roundi(nominal * state.rng.randf_range(0.92, 1.10)))
	var mainland_factions: int = state.faction_count - island_plans.size()
	var mainland_target := total_target
	for count in island_plans:
		minimum_land -= count
		mainland_target -= count
	minimum_land = maxi(minimum_land, mainland_factions * 7 + 10)
	mainland_target = maxi(mainland_target, minimum_land)
	var seeds := starting_sites().slice(0, mainland_factions)
	connect_mainland(seeds)
	grow_home_regions(profile, seeds)
	retain_connected_mainland(seeds)
	if not ensure_mainland_budget(minimum_land):
		return
	erode_mainland(seeds, minimum_land)
	trim_mainland(seeds, mainland_target)
	var mainland: Array = state.cells.keys()
	var islands := Archipelago.add_islands(state, island_plans, protected_landings, seeds)
	if islands.size() != island_plans.size():
		# Retry the same seed as a connected world if no fair offshore home fits.
		generate(state.level_seed, size_id, kingdom_count, false)
		return
	grow_around_offshore(mainland, islands, total_minimum)
	generate_lakes(seeds, total_minimum)
	seeds = state.shuffled(seeds)
	var homes := StartingTerritories.plan(state, seeds)
	for faction in range(state.faction_count):
		for coord in homes[faction]: state.cells[coord]["owner"] = faction
		state.cells[seeds[faction]]["capital"] = faction
	StartingTerritories.protect_expansion(state, homes, protected_landings)
	for coord in state.cells: adjacency[coord] = state.neighbors(coord)
	for coord in state.cells:
		state.cells[coord]["tree"] = state.cells[coord]["owner"] == -1 and state.rng.randf() < 0.16
	for faction in range(state.faction_count):
		for coord in state.neighbors(seeds[faction]):
			if state.cells[coord]["owner"] == faction:
				state.cells[coord]["unit"] = 1
				break
	state.rebuild_kingdoms()
	for kingdom in state.kingdoms.values():
		kingdom["gold"] = Catalog.START_GOLD
	generate_province_resources()
	generate_mountains()
	for faction in range(state.faction_count):
		state.set_mana(faction, 1)

func connect_mainland(seeds: Array) -> void:
	# A randomized spanning tree replaces the fixed central hub. Extra links make
	# some islands compact and others branching, with different approach routes.
	var reached: Array = [seeds[0]]
	var remaining: Array = seeds.slice(1)
	while not remaining.is_empty():
		var best_from: Vector2i = reached[0]
		var best_to: Vector2i = remaining[0]
		var best_score := INF
		for origin in reached:
			for target in remaining:
				var score: float = state.distance(origin, target) * state.rng.randf_range(0.7, 1.4)
				if score < best_score:
					best_score = score
					best_from = origin
					best_to = target
		join_land(best_from, best_to, state.rng.randi_range(0, 1))
		reached.append(best_to)
		remaining.erase(best_to)
	if state.rng.randf() < 0.5:
		join_land(seeds[0], seeds[-1], state.rng.randi_range(0, 1))

func grow_home_regions(profile: Dictionary, seeds: Array) -> void:
	for seed_coord in seeds:
		var radius: int = state.rng.randi_range(profile["radius_min"], profile["radius_max"])
		grow_lobe(seed_coord, radius, profile["core"])
		# Offset neutral bulges change the outline independently of home locations.
		var offset: Vector2i = DIRECTIONS[state.rng.randi_range(0, 5)] * state.rng.randi_range(1, radius)
		var center: Vector2i = seed_coord + offset
		if state.inside_map(center) and state.rng.randf() < 0.7:
			join_land(seed_coord, center, 0)
			grow_lobe(center, state.rng.randi_range(2, radius), 1)
		# Keep complete rings as safe fallbacks for later footprint selection.
		add_land(seed_coord)
		for direction in DIRECTIONS:
			add_land(seed_coord + direction)

func retain_connected_mainland(seeds: Array) -> void:
	# Remove any detached coastal specks, keeping the connected mainland.
	var visited := {seeds[0]: true}
	var pending := [seeds[0]]
	while not pending.is_empty():
		var coord: Vector2i = pending.pop_back()
		for next in state.neighbors(coord):
			if not visited.has(next):
				visited[next] = true
				pending.append(next)
	for coord in state.cells.keys():
		if not visited.has(coord):
			state.cells.erase(coord)

func ensure_mainland_budget(minimum_land: int) -> bool:
	# Guarantee expansion space even when random homes cluster on one side.
	var frontier: Dictionary = {}
	var land_order: Array = state.cells.keys() if state.cells.size() < minimum_land else []
	for index in range(land_order.size()):
		var coord: Vector2i = land_order[index]
		for edge in range(6):
			var next: Vector2i = coord + DIRECTIONS[edge]
			if state.inside_map(next) and not state.cells.has(next) and not frontier.has(next):
				frontier[next] = index * 6 + edge
	while state.cells.size() < minimum_land:
		# Stable priorities preserve the old full-scan insertion/shuffle order.
		var ordered: Array = frontier.keys()
		ordered.sort_custom(func(a, b): return frontier[a] < frontier[b])
		var additions: Array = state.shuffled(ordered)
		if additions.is_empty():
			push_error("Map bounds cannot accommodate the requested minimum land")
			return false
		for index in range(mini(additions.size(), minimum_land - state.cells.size())):
			add_land(additions[index])
			frontier.erase(additions[index])
			var order: int = state.cells.size() - 1
			for edge in range(6):
				var next: Vector2i = additions[index] + DIRECTIONS[edge]
				if state.inside_map(next) and not state.cells.has(next) and not frontier.has(next):
					frontier[next] = order * 6 + edge
	return true

func erode_mainland(seeds: Array, minimum_land: int) -> void:
	# Cut bays and interior lakes only where the remaining island stays connected.
	var erosion: float = state.rng.randf_range(0.08, 0.24)
	for coord in state.shuffled(state.cells.keys()):
		if coord in seeds or state.cells.size() <= minimum_land:
			continue
		if state.neighbors(coord).size() == 6: continue
		var near_start := false
		for seed_coord in seeds:
			if state.distance(coord, seed_coord) <= 1:
				near_start = true
		if near_start or state.rng.randf() > erosion:
			continue
		var old_cell: Dictionary = state.cells[coord]
		state.cells.erase(coord)
		if not removal_preserves_connections(coord):
			state.cells[coord] = old_cell

func trim_mainland(seeds: Array, mainland_target: int) -> void:
	# Keep the advertised land budget after removing the old clipping rectangle.
	# Trim exposed coast, never home rings or the routes connecting them.
	for pass_index in range(6):
		if state.cells.size() <= mainland_target: break
		var removed := 0
		for coord in state.shuffled(state.cells.keys()):
			if state.cells.size() <= mainland_target: break
			if state.neighbors(coord).size() >= 6: continue
			var home := false
			for capital in seeds:
				if state.distance(coord, capital) <= 1: home = true
			if home: continue
			var original: Dictionary = state.cells[coord]
			state.cells.erase(coord)
			if removal_preserves_connections(coord): removed += 1
			else: state.cells[coord] = original
		if removed == 0: break

func grow_around_offshore(mainland: Array, islands: Array, total_minimum: int) -> void:
	# A bounded fallback if an unusual coastline cannot fit the planned islands.
	# Grow only the mainland, leaving at least one water hex around offshore land.
	var offshore := {}
	for island in islands:
		for coord in island["hexes"]: offshore[coord] = true
	while state.cells.size() < total_minimum:
		var additions := {}
		for coord in mainland:
			for direction in DIRECTIONS:
				var next: Vector2i = coord + direction
				if state.cells.has(next) or not state.inside_map(next): continue
				var safe := true
				for edge in DIRECTIONS:
					if offshore.has(next + edge): safe = false
				if safe: additions[next] = true
		if additions.is_empty(): break
		for coord in state.shuffled(additions.keys()):
			if state.cells.size() >= total_minimum: break
			add_land(coord)
			mainland.append(coord)

func passable_land_connected() -> bool:
	var first := NONE
	var total := 0
	for coord in state.cells:
		if not state.is_mountain(coord):
			total += 1
			first = coord
	if first == NONE:
		return false
	var visited := {first: true}
	var pending := [first]
	while not pending.is_empty():
		var coord: Vector2i = pending.pop_back()
		for next in neighbors(coord):
			if not state.is_mountain(next) and not visited.has(next):
				visited[next] = true
				pending.append(next)
	return visited.size() == total

func generate_lakes(homes: Array, minimum_land: int) -> void:
	var budget := mini(lake_budget, state.cells.size() - minimum_land)
	if budget < 5: return
	var eligible := {}
	for coord in state.cells:
		if protected_landings.has(coord) or state.neighbors(coord).size() != 6: continue
		var safe := true
		for home in homes:
			if state.distance(coord, home) <= 2: safe = false
		if safe: eligible[coord] = true
	var used := 0
	var lake_count := 0
	var maximum := maxi(6, roundi(state.cells.size() * 0.07))
	for center in state.shuffled(eligible.keys()):
		if budget - used < 5 or lake_count >= 3: break
		if not eligible.has(center): continue
		var desired: int = state.rng.randi_range(5, mini(maximum, budget - used))
		var lake := {center:true}
		var frontier := {}
		var last: Vector2i = center
		while lake.size() < desired:
			for direction in DIRECTIONS:
				var next: Vector2i = last + direction
				if eligible.has(next) and not lake.has(next) and not frontier.has(next):
					frontier[next] = state.distance(center, next) + state.rng.randf_range(0.0, 1.8)
			var best := NONE
			var score := INF
			for coord in frontier:
				if frontier[coord] < score:
					score = frontier[coord]
					best = coord
			if best == NONE: break
			frontier.erase(best)
			lake[best] = true
			last = best
		if lake.size() < desired: continue
		# Commit whole lakes only, keeping their rim and every route intact.
		var backups := {}
		var safe := true
		for coord in lake:
			backups[coord] = state.cells[coord]
			state.cells.erase(coord)
			if not removal_preserves_connections(coord):
				safe = false
				break
		if not safe:
			for coord in backups: state.cells[coord] = backups[coord]
			continue
		for coord in lake:
			eligible.erase(coord)
			for direction in DIRECTIONS: eligible.erase(coord + direction)
		used += lake.size()
		lake_count += 1

func ridge_peak(coord: Vector2i, expected_neighbors: int, backups: Dictionary) -> bool:
	if not mountain_site(coord): return false
	var touching := 0
	for next in neighbors(coord):
		if state.is_mountain(next): touching += 1
	# A thin, non-intersecting path: no triangles, blobs or joins to other ridges.
	if touching != expected_neighbors: return false
	var original: Dictionary = state.cells[coord].duplicate(true)
	state.cells[coord]["mountain"] = true
	if not removal_preserves_connections(coord, true):
		state.cells[coord] = original
		return false
	backups[coord] = original
	state.cells[coord]["value"] = 0
	state.cells[coord]["tree"] = false
	return true

func extend_ridge(path: Array[Vector2i], heading: int, desired: int, backups: Dictionary) -> void:
	while path.size() < desired:
		var choices := [heading, (heading + 1) % 6, (heading + 5) % 6]
		var scores := {}
		for direction in choices:
			scores[direction] = state.rng.randf() + (0.0 if direction == heading else 0.55)
		choices.sort_custom(func(a, b): return scores[a] < scores[b])
		var extended := false
		for direction in choices:
			var next: Vector2i = path[-1] + DIRECTIONS[direction]
			if ridge_peak(next, 1, backups):
				path.append(next)
				heading = direction
				extended = true
				break
		if not extended: break

func generate_mountains() -> void:
	# Moderate coverage, concentrated into winding ridges with broad open regions.
	var budget := roundi(state.cells.size() * state.rng.randf_range(0.05, 0.085))
	var group_limit: int = maxi(2, ceili(sqrt(state.cells.size()) / 2.5))
	var maximum := clampi(roundi(sqrt(state.cells.size()) * 0.55), 5, 18)
	var groups := 0
	var placed := 0
	for seed_coord in state.shuffled(state.cells.keys()):
		if groups >= group_limit or budget - placed < 2: break
		var backups := {}
		if not ridge_peak(seed_coord, 0, backups): continue
		var path: Array[Vector2i] = [seed_coord]
		var heading: int = state.rng.randi_range(0, 5)
		var desired: int = state.rng.randi_range(mini(4, budget - placed), mini(budget - placed, maximum))
		extend_ridge(path, heading, desired, backups)
		# Continue from the other end if shore, homes or a narrow route stop growth.
		path.reverse()
		extend_ridge(path, (heading + 3) % 6, desired, backups)
		if path.size() < 2:
			for coord in backups: state.cells[coord] = backups[coord]
			continue
		# Some long ridges have an inland pass, leaving at least two peaks either side.
		if path.size() >= 7 and state.rng.randf() < 0.65:
			var options := []
			for index in range(2, path.size() - 2):
				if neighbors(path[index]).size() == 6: options.append(index)
			if not options.is_empty():
				var index: int = options[state.rng.randi_range(0, options.size() - 1)]
				var pass_coord: Vector2i = path[index]
				state.cells[pass_coord] = backups[pass_coord]
				protected_passes[pass_coord] = true
				path.remove_at(index)
		groups += 1
		placed += path.size()

func mountain_site(coord: Vector2i) -> bool:
	return not protected_passes.has(coord) and not protected_landings.has(coord) and state.cells.has(coord) and state.cells[coord]["owner"] == -1 and not state.is_mountain(coord) and not state.cells[coord]["mana_source"] and state.cells[coord]["building"] == ""

func generate_province_resources() -> void:
	for cell in state.cells.values():
		cell["value"] = state.rng.randi_range(1, 3)
	for kingdom in state.kingdoms.values():
		# Distribute the same total starting value across different territory sizes.
		for coord in kingdom["hexes"]:
			state.cells[coord]["value"] = 1
		var remaining: int = Catalog.MODERN_START_VALUE - kingdom["hexes"].size()
		while remaining > 0:
			for coord in state.shuffled(kingdom["hexes"]):
				if remaining > 0 and state.cells[coord]["value"] < 3:
					state.cells[coord]["value"] += 1
					remaining -= 1
		state.cells[kingdom["capital"]]["mana_source"] = true
	var sources: Array = state.kingdoms.keys()
	var neutral_sources := 0
	for coord in state.shuffled(state.cells.keys()):
		if state.cells[coord]["owner"] >= 0:
			continue
		var spaced := true
		for source in sources:
			if state.distance(coord, source) < 3:
				spaced = false
		if spaced:
			state.cells[coord]["mana_source"] = true
			state.cells[coord]["tree"] = false
			sources.append(coord)
			neutral_sources += 1
			if neutral_sources >= maxi(1, state.faction_count - 1):
				break
	# Small islands can lack three-hex spacing; still offer one neutral objective.
	if neutral_sources == 0:
		var best := NONE
		var best_distance := -1
		for coord in state.cells:
			if state.cells[coord]["owner"] >= 0:
				continue
			var nearest := 1000
			for source in sources:
				nearest = mini(nearest, state.distance(coord, source))
			if nearest > best_distance:
				best = coord
				best_distance = nearest
		if best != NONE:
			state.cells[best]["mana_source"] = true
			state.cells[best]["tree"] = false

