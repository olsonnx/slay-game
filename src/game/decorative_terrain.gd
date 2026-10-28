extends RefCounted
## Pack complete Modern islands by their real height; cache nearby streamed bands.
const Grid = preload("res://src/game/hex_grid.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const Tile = preload("res://src/rendering/terrain_tile.gd")
const MAX_ISLAND_ROWS := 16 # Keep new kingdoms arriving within the visible span.
const MIN_BAND_ROWS := 10
const HALF_COLUMNS := 8
var seed_value: int
var chunks: Dictionary = {}

func _init(seed_id: int) -> void:
	seed_value = seed_id

static func coord_at(column: int, row: int) -> Vector2i:
	return Vector2i(column - floori(row / 2.0), row)

static func column_at(coord: Vector2i) -> int:
	return coord.x + floori(coord.y / 2.0)

static func placed_coord(coord: Vector2i, placement: Dictionary) -> Vector2i:
	for step in range(placement["rotation"]):
		coord = Vector2i(-coord.y, coord.x + coord.y)
	return coord + placement["offset"]

static func fit_placement(cells: Dictionary) -> Dictionary:
	# Fit complete islands, with water beside the pool and before chunk seams.
	# Translation and hex rotation preserve every coastline and terrain feature.
	var best := {}
	var best_height := 999
	for rotation in range(6):
		var rotated: Array[Vector2i] = []
		var first_row := 999
		var last_row := -999
		for source in cells:
			var coord := placed_coord(source, {"rotation":rotation, "offset":Vector2i.ZERO})
			rotated.append(coord)
			first_row = mini(first_row, coord.y)
			last_row = maxi(last_row, coord.y)
		var row_offset := 1 - first_row
		if last_row - first_row + 1 > MAX_ISLAND_ROWS: continue
		var first_column := 999
		var last_column := -999
		for coord in rotated:
			var column := column_at(coord + Vector2i(0, row_offset))
			first_column = mini(first_column, column)
			last_column = maxi(last_column, column)
		var column_offset := -floori((first_column + last_column) / 2.0)
		if first_column + column_offset < -HALF_COLUMNS + 1 or last_column + column_offset > HALF_COLUMNS - 1: continue
		var height := last_row - first_row + 1
		if height < best_height:
			best_height = height
			best = {"rotation":rotation, "offset":Vector2i(column_offset, row_offset)}
	return best

func joined_mask(column: int, row: int) -> int:
	var coord := coord_at(column, row)
	var cell := cell_for(column, row)
	if cell["owner"] < 0: return 0
	var adjacent := {coord:cell}
	for direction in Grid.DIRECTIONS:
		var next: Vector2i = coord + direction
		var other := cell_for(column_at(next), next.y)
		if other["island"] == cell["island"]: adjacent[next] = other
	return Tile.joined_mask(adjacent, coord)

static func stream_coord(coord: Vector2i, data: Dictionary) -> Vector2i:
	# Even origins preserve offset-column parity, width and natural coastlines.
	return coord + Vector2i(-data["origin"] / 2, data["origin"])

func chunk_for_row(row: int) -> int:
	if chunks.is_empty(): chunk(0)
	while true:
		for index in chunks:
			if row >= chunks[index]["start"] and row < chunks[index]["end"]: return index
		var first: int = chunks.keys().min()
		var last: int = chunks.keys().max()
		chunk(first - 1 if row < chunks[first]["start"] else last + 1)
	return 0

func chunk(index: int) -> Dictionary:
	if chunks.is_empty():
		var initial := build_chunk(0)
		initial["origin"] = 0
		initial["start"] = 0
		initial["end"] = initial["band_rows"]
		chunks[0] = initial
	while not chunks.has(index):
		var first: int = chunks.keys().min()
		var last: int = chunks.keys().max()
		var incoming: int = first - 1 if index < first else last + 1
		var data := build_chunk(incoming)
		if index < first:
			data["end"] = chunks[first]["start"]
			data["origin"] = data["end"] - data["band_rows"]
			data["start"] = data["origin"]
		else:
			data["origin"] = chunks[last]["end"]
			data["start"] = data["origin"]
			data["end"] = data["start"] + data["band_rows"]
		chunks[incoming] = data
	return chunks[index]

func build_chunk(index: int) -> Dictionary:
	var seed_id := posmod(seed_value + index * 49663, 2147483647)
	var rules = Rules.new()
	rules.rule_mode = "modern"
	var placement := {}
	var size_id := "small"
	# Keep generation bounded if a future layout cannot fit in any rotation.
	# A complete smaller map is preferable to slicing a wider map's coast.
	for attempt in range(9):
		size_id = "very_small" if attempt == 8 else "small"
		rules.generate(posmod(seed_id + attempt * 104729, 2147483647), size_id)
		placement = fit_placement(rules.cells)
		if not placement.is_empty(): break
	assert(not placement.is_empty(), "Decorative island must fit before streaming")
	dress_kingdoms(rules)
	var cells := {}
	var source_coords := {}
	for source in rules.cells:
		var coord := placed_coord(source, placement)
		var cell: Dictionary = rules.cells[source].duplicate(true)
		for field in ["kingdom", "unit_home"]:
			if cell.get(field, Grid.NONE) != Grid.NONE: cell[field] = placed_coord(cell[field], placement)
		cells[coord] = cell
		source_coords[coord] = source
	# Cosmetic single-hex lake filling; all original generated cells are preserved.
	var fills: Dictionary = {}
	for coord in cells:
		for direction in Grid.DIRECTIONS:
			var candidate: Vector2i = coord + direction
			if cells.has(candidate) or fills.has(candidate):
				continue
			var enclosed := true
			for side in Grid.DIRECTIONS:
				if not cells.has(candidate + side):
					enclosed = false
					break
			if enclosed:
				fills[candidate] = rules.make_cell()
	cells.merge(fills)
	var first_row := 999
	var last_row := -999
	for coord in cells:
		first_row = mini(first_row, coord.y)
		last_row = maxi(last_row, coord.y)
	return {"first_row":first_row, "last_row":last_row,
		"band_rows":maxi(MIN_BAND_ROWS, 2 * ceili((last_row - first_row + 2) / 2.0)), "seed":rules.level_seed, "size":size_id, "placement":placement,
		"source_coords":source_coords, "cells":cells, "filled":fills.keys()}

func dress_kingdoms(rules) -> void:
	# A bounded cosmetic pass when a chunk is created; no per-frame simulation.
	# Grow from existing borders so each capital keeps one connected kingdom.
	var neutral := 0
	for cell in rules.cells.values():
		if cell["owner"] < 0 and not cell["mountain"]: neutral += 1
	var budget := floori(neutral * 0.45)
	var growth := {}
	for faction in range(rules.faction_count): growth[faction] = rules.rng.randi_range(2, 10)
	for step in range(10):
		for faction in rules.shuffled(growth.keys()):
			if step >= growth[faction] or budget <= 0: continue
			var frontier := {}
			for coord in rules.cells:
				if rules.cells[coord]["owner"] != faction: continue
				for direction in Grid.DIRECTIONS:
					var next: Vector2i = coord + direction
					if rules.cells.has(next) and rules.cells[next]["owner"] < 0 and not rules.cells[next]["mountain"]:
						frontier[next] = true
			if frontier.is_empty(): continue
			var choices: Array = frontier.keys()
			var target: Vector2i = choices[rules.rng.randi_range(0, choices.size() - 1)]
			rules.cells[target]["owner"] = faction
			rules.cells[target]["tree"] = false
			# Cosmetic expansion represents a capture, which collects the chest.
			rules.cells[target].erase("treasure")
			budget -= 1
	rules.rebuild_kingdoms()
	for kingdom in rules.kingdoms.values():
		var sites: Array = []
		for coord in kingdom["hexes"]:
			var cell: Dictionary = rules.cells[coord]
			if cell["capital"] < 0 and cell["unit"] == 0 and not cell["mountain"] and not cell["mana_source"] and cell["building"] == "":
				sites.append(coord)
		sites = rules.shuffled(sites)
		# Sparse settlement: one tower and one or two houses per kingdom.
		for index in range(mini(sites.size(), rules.rng.randi_range(2, 3))):
			var cell: Dictionary = rules.cells[sites[index]]
			cell["building"] = "tower" if index == 0 else "city"
			cell["tree"] = false

func cell_for(column: int, row: int) -> Dictionary:
	var index := chunk_for_row(row)
	var data := chunk(index)
	var coord := coord_at(column, row - data["origin"])
	var cell: Dictionary = data["cells"].get(coord, {}).duplicate(true)
	if cell.is_empty():
		cell = {"owner":-1, "unit":0, "moved":false, "capital":-1, "tree":false,
			"grave":false, "building":"", "mana_source":false, "mountain":false, "event":"", "land":false}
	else:
		cell["land"] = true
	cell["unit"] = 0
	cell["moved"] = false
	cell["event"] = ""
	cell["island"] = index
	cell["decoration_coord"] = data.get("source_coords", {}).get(coord, coord)
	return cell

func prune(first_row: int, last_row: int) -> void:
	var first := chunk_for_row(first_row) - 1
	var last := chunk_for_row(last_row) + 1
	for index in chunks.keys():
		if index < first or index > last: chunks.erase(index)
