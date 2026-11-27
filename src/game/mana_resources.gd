extends RefCounted
## A bounded land-area bonus, placed after terrain and encounters on a separate RNG stream.
const Catalog = preload("res://src/game/game_catalog.gd")

static func extra_source_budget(neutral_land: int) -> int:
	if neutral_land <= 0: return 0
	return mini(Catalog.MAX_EXTRA_MANA_SOURCES, Catalog.EXTRA_MANA_SOURCE_BASE + floori(float(neutral_land) / Catalog.NEUTRAL_LAND_PER_EXTRA_MANA_SOURCE))

static func generate(state) -> int:
	var neutral_land := 0
	var sources: Array = []
	var candidates: Array = []
	for coord in state.cells:
		var cell: Dictionary = state.cells[coord]
		if cell.get("mana_source", false): sources.append(coord)
		if cell.owner >= 0 or state.is_mountain(coord) or state.is_bridge(coord): continue
		neutral_land += 1
		if cell.get("mana_source", false) or state.has_wildlife(coord) or cell.get("event", "") != "" or cell.get("treasure", 0) > 0 or cell.building != "" or cell.capital >= 0: continue
		candidates.append(coord)
	var variation := RandomNumberGenerator.new()
	variation.seed = state.level_seed ^ 0x6D4E41
	for index in range(candidates.size() - 1, 0, -1):
		var other := variation.randi_range(0, index)
		var swap = candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = swap
	var budget := extra_source_budget(neutral_land)
	var placed := 0
	for coord in candidates:
		if placed >= budget: break
		var spaced := true
		for source in sources:
			if state.distance(coord, source) < 3: spaced = false; break
		if not spaced: continue
		state.cells[coord]["mana_source"] = true
		state.cells[coord]["tree"] = false
		sources.append(coord)
		placed += 1
	return placed
