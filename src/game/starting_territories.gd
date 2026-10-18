extends RefCounted
## Connected starting footprints; territory varies, starting economic value does not.
const Grid = preload("res://src/game/hex_grid.gd")
const MIN_TILES := 6
const MAX_TILES := 9
# Prefixes of each footprint remain connected and have no single-tile tendrils.
# The capital is always at zero with at least three friendly neighbours.
const SHAPES := [
	[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,1), Vector2i(-1,0), Vector2i(0,-1), Vector2i(1,-1), Vector2i(2,-1), Vector2i(1,1)],
	[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,1), Vector2i(-1,0), Vector2i(1,1), Vector2i(-2,1), Vector2i(-2,2), Vector2i(0,2)],
	[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(2,-1), Vector2i(-1,2), Vector2i(2,0), Vector2i(-2,2)]
]

static func footprint(center: Vector2i, shape: Array, count: int, orientation: int) -> Array:
	var result := []
	for offset in shape.slice(0, count):
		var coord: Vector2i = Vector2i(offset.y, offset.x) if orientation >= 6 else offset
		for step in range(orientation % 6): coord = Vector2i(-coord.y, coord.x + coord.y)
		result.append(center + coord)
	return result

static func fits(state, candidate: Array, center: Vector2i, centers: Array, occupied: Array) -> bool:
	for coord in candidate:
		if not state.cells.has(coord): return false
		# Reserve every other capital's original home ring as a safe fallback.
		for other in centers:
			if other != center and Grid.distance(coord, other) < 4: return false
		for other in occupied:
			if Grid.distance(coord, other) < 3: return false
	return true

static func plan(state, centers: Array) -> Array:
	var result := []
	result.resize(centers.size())
	var occupied := []
	var minimum := MIN_TILES if state.is_modern() else 7
	var reserve := mini(10, state.cells.size() - centers.size() * minimum)
	var remaining := centers.size()
	# Randomize assignment so crowded starts do not consistently penalize a colour.
	for index in state.shuffled(range(centers.size())):
		remaining -= 1
		var available: int = state.cells.size() - reserve - occupied.size() - remaining * minimum
		var desired: int = mini(state.rng.randi_range(MIN_TILES, MAX_TILES), available) if state.is_modern() else 7
		var selected := []
		for count in range(desired, minimum - 1, -1):
			for shape in state.shuffled(SHAPES):
				for orientation in state.shuffled(range(12)):
					var candidate := footprint(centers[index], shape, count, orientation)
					if fits(state, candidate, centers[index], centers, occupied):
						selected = candidate
						break
				if not selected.is_empty(): break
			if not selected.is_empty(): break
		# Complete reserved rings guarantee a safe shape when larger ones cannot fit.
		assert(not selected.is_empty(), "A reserved home must fit a starting footprint")
		result[index] = selected
		occupied.append_array(selected)
	return result

static func protect_expansion(state, homes: Array, protected: Dictionary) -> void:
	var membership := {}
	var regions: Array = preload("res://src/game/archipelago.gd").components(state.cells)
	for index in range(regions.size()):
		for coord in regions[index]: membership[coord] = index
	for home in homes:
		var frontier := {}
		for coord in home:
			for next in state.neighbors(coord):
				if state.cells[next]["owner"] == -1: frontier[next] = true
		# A coastal home can otherwise fill its peninsula and have only one exit.
		# Add a small neutral coastal tile rather than increasing starting ownership.
		while frontier.size() < 2:
			var candidates := {}
			for coord in home:
				for direction in Grid.DIRECTIONS:
					var next: Vector2i = coord + direction
					if state.cells.has(next) or not state.inside_map(next): continue
					var at: Vector3 = Grid.to_world(next)
					if Vector2(at.x, at.z).length() >= state.MapSizes.generation_bounds(state.map_size).x - 4.0: continue
					var separate := true
					for neighbor in state.neighbors(next):
						if membership[neighbor] != membership[home[0]]: separate = false
					if separate: candidates[next] = true
			if candidates.is_empty():
				push_error("No safe neutral expansion tile fits beside a starting kingdom")
				return
			var next: Vector2i = state.shuffled(candidates.keys())[0]
			state.cells[next] = state.make_cell()
			membership[next] = membership[home[0]]
			frontier[next] = true
		# Reserve two independent first captures before placing impassable terrain.
		for coord in state.shuffled(frontier.keys()).slice(0, 2): protected[coord] = true
