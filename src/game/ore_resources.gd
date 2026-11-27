extends RefCounted
## Source placement uses a separate seeded stream so existing generated landmarks stay stable.
const Catalog = preload("res://src/game/game_catalog.gd")
static func generate(state) -> void:
	state.ore_by_faction.clear()
	var source_count := 0
	var sites: Array = []
	for coord in state.cells:
		var cell: Dictionary = state.cells[coord]
		cell["ore_source"] = false
		if cell.get("mana_source", false): source_count += 1
		if not state.is_mountain(coord) and not state.is_bridge(coord) and not cell.get("mana_source", false) and not state.has_wildlife(coord) and cell.get("event", "") == "" and cell.get("treasure", 0) == 0 and cell.building == "" and cell.capital < 0:
			sites.append(coord)
	var random := RandomNumberGenerator.new()
	random.seed = state.level_seed ^ 0x0A3E
	for index in range(sites.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var swap = sites[index]
		sites[index] = sites[other]
		sites[other] = swap
	var target := mini(sites.size(), ceili(source_count * Catalog.ORE_SOURCE_MULTIPLIER))
	var placed: Array = []
	# Prefer separated deposits, then fill sparse maps without losing abundance.
	for spacing in [3, 2, 0]:
		for coord in sites:
			if placed.size() >= target: return
			if coord in placed: continue
			var clear := true
			for other in placed:
				if state.distance(coord, other) < spacing: clear = false; break
			if not clear: continue
			state.cells[coord]["ore_source"] = true
			state.cells[coord]["tree"] = false
			placed.append(coord)
