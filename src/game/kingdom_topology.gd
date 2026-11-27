extends RefCounted
## Connected kingdoms, treasury inheritance and deterministic capital replacement.
## Receives authoritative state per call; never retains a model or UI.
const Grid = preload("res://src/game/hex_grid.gd")
const NONE = Grid.NONE

static func rebuild_kingdoms(state, affected_owners: Dictionary = {}) -> void:
	var cells: Dictionary = state.cells
	var partial: bool = state.incremental_kingdoms and not affected_owners.is_empty()
	# Gold belongs to a surviving capital, never to an entire faction.
	var old_by_capital: Dictionary = {}
	for kingdom in state.kingdoms.values():
		var capital: Vector2i = kingdom["capital"]
		if cells.has(capital) and cells[capital]["capital"] == kingdom["owner"] and cells[capital]["owner"] == kingdom["owner"]:
			old_by_capital[capital] = kingdom
	var rebuilt: Dictionary = {}
	if partial:
		for capital in state.kingdoms:
			if not affected_owners.has(state.kingdoms[capital]["owner"]):
				rebuilt[capital] = state.kingdoms[capital]
				# Full reconstruction also clears graves/trees at surviving
				# capitals, including those left by a duel in another faction.
				cells[capital]["tree"] = false
				cells[capital]["grave"] = false
				if not preload("res://src/game/event_sites.gd").protected(cells[capital]): cells[capital]["building"] = ""
	var visited: Dictionary = {}
	for start in cells:
		if not partial or affected_owners.has(cells[start]["owner"]): cells[start]["kingdom"] = NONE
	for start in cells:
		var owner: int = cells[start]["owner"]
		if partial and not affected_owners.has(owner): continue
		if owner < 0 or state.is_mountain(start) or visited.has(start):
			continue
		var component: Array[Vector2i] = []
		var pending := [start]
		var connected := {start: true}
		visited[start] = true
		while not pending.is_empty():
			var coord: Vector2i = pending.pop_back()
			if cells[coord]["owner"] == owner:
				component.append(coord)
				visited[coord] = true
			for next in state.neighbors(coord):
				if (cells[next]["owner"] == owner or (state.is_bridge(next))) and not state.is_mountain(next) and not connected.has(next):
					connected[next] = true
					pending.append(next)
		var capital := NONE
		var capital_tier := 1
		var gold := 0
		for coord in component:
			if cells[coord]["capital"] == owner and component.size() >= 2:
				if capital == NONE:
					capital = coord
					capital_tier = int(cells[coord].get("capital_tier", 1))
				if old_by_capital.has(coord):
					gold += old_by_capital[coord]["gold"]
			cells[coord]["capital"] = -1
			cells[coord]["capital_tier"] = 1
		if component.size() == 1:
			continue
		if capital == NONE:
			capital = replacement_capital(state, component, owner)
		cells[capital]["capital"] = owner
		cells[capital]["capital_tier"] = capital_tier
		cells[capital]["tree"] = false
		cells[capital]["grave"] = false
		if not preload("res://src/game/event_sites.gd").protected(cells[capital]): cells[capital]["building"] = ""
		rebuilt[capital] = {"capital": capital, "owner": owner, "gold": gold, "hexes": component}
		for coord in component:
			cells[coord]["kingdom"] = capital
	if partial:
		# Match the full rebuild's board-order insertion, including newly split
		# banks. Stable ordering affects capital choice, UI and deterministic AI.
		var ordered: Dictionary = {}
		for cell in cells.values():
			var capital: Vector2i = cell["kingdom"]
			if rebuilt.has(capital): ordered[capital] = rebuilt[capital]
		state.kingdoms = ordered
	else:
		state.kingdoms = rebuilt
	state.clamp_mana()

static func replacement_capital(state, component: Array[Vector2i], owner: int) -> Vector2i:
	var cells: Dictionary = state.cells
	# Avoid deleting a house/tower when any structure-free site exists. Units
	# can share a capital, so an interior garrison is preferable to an open border.
	var candidates: Array[Vector2i] = []
	for coord in component:
		if cells[coord]["building"] == "": candidates.append(coord)
	if candidates.is_empty(): candidates = component
	var best := candidates[0]
	var best_score := 1000000
	for coord in candidates:
		var rivals := 0
		for next in state.neighbors(coord):
			if state.is_mountain(next): continue
			var neighbor_owner: int = cells[next]["owner"]
			var hostile_bridge: bool = state.is_bridge(next) and cells[next]["unit"] > 0 and state.unit_faction(next) != owner
			if (neighbor_owner >= 0 and neighbor_owner != owner) or hostile_bridge: rivals += 1
		var occupied := int(cells[coord]["unit"] > 0) + int(cells[coord]["grave"])
		var score := rivals * 3 + occupied
		# Stable board traversal breaks ties, preserving replay and search determinism.
		if score < best_score:
			best = coord
			best_score = score
	return best
