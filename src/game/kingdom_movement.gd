extends RefCounted
const Grid = preload("res://src/game/hex_grid.gd")
## Movement, defence, routes and recorded commands operate on supplied rule state.
## Stateless helpers avoid retaining a RefCounted model or UI dependencies.

static func castle_neighbors(state, source: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var cells: Dictionary = state.cells
	var result: Array[Vector2i] = []
	if not state.is_modern() or cells[target]["capital"] < 0 or state.unit_faction(source) == cells[target]["owner"]:
		return result
	var kingdom_key: Vector2i = cells[target]["kingdom"]
	for coord in state.neighbors(target):
		if cells[coord]["owner"] == cells[target]["owner"] and cells[coord]["kingdom"] == kingdom_key:
			result.append(coord)
	return result

static func local_defense(state, coord: Vector2i) -> int:
	var cells: Dictionary = state.cells
	var cell: Dictionary = cells[coord]
	var strength: int = cell["unit"]
	if cell["capital"] >= 0:
		strength = maxi(strength, 1)
	if cell["building"] == "tower":
		strength = maxi(strength, 2)
	return strength

static func defense(state, coord: Vector2i) -> int:
	var cells: Dictionary = state.cells
	var strength: int = local_defense(state, coord)
	if cells[coord]["owner"] < 0:
		return strength
	for direction in Grid.DIRECTIONS:
		var next: Vector2i = coord + direction
		if not cells.has(next):
			continue
		if cells[next]["owner"] == cells[coord]["owner"]:
			# Knights defend their own hex at 3, but lend at most 2 to neighbours.
			strength = maxi(strength, mini(2, local_defense(state, next)))
	return strength

static func unit_protection(cells: Dictionary, source: Vector2i) -> Dictionary:
	# Defence spreads only across adjacent land with the same terrain owner.
	# Neutral bridge garrisons defend their own bridge, never nearby shores.
	if not cells.has(source) or cells[source].get("unit", 0) <= 0:
		return {}
	var region: Dictionary = {source: true}
	var owner: int = cells[source]["owner"]
	if owner >= 0:
		for direction in Grid.DIRECTIONS:
			var target: Vector2i = source + direction
			if cells.has(target) and cells[target]["owner"] == owner:
				region[target] = true
	return region

static func friendly_routes(state, source: Vector2i) -> Dictionary:
	var cells: Dictionary = state.cells
	if not cells.has(source) or state.is_mountain(source) or state.is_barrier(source):
		return {}
	var faction: int = state.unit_faction(source) if cells[source]["unit"] > 0 else cells[source]["owner"]
	if faction < 0:
		return {}
	var parents: Dictionary = {source: Grid.NONE}
	var queue := [source]
	var index := 0
	var modern: bool = state.is_modern()
	while index < queue.size():
		var coord: Vector2i = queue[index]
		index += 1
		for direction in Grid.DIRECTIONS:
			var next: Vector2i = coord + direction
			if parents.has(next) or not cells.has(next):
				continue
			var cell: Dictionary = cells[next]
			var accessible: bool = cell["owner"] == faction or (modern and cell["building"] == "bridge" and (cell["unit"] == 0 or cell.get("unit_owner", -1) == faction))
			if accessible and not cell.get("mountain", false) and cell.get("barrier_by", -1) < 0:
				parents[next] = coord
				queue.append(next)
	return parents

static func knight_duel(state, source: Vector2i, target: Vector2i) -> bool:
	var cells: Dictionary = state.cells
	return cells[source]["unit"] == 3 and cells[target]["unit"] == 3 and state.unit_faction(source) != state.unit_faction(target)

static func reachable_targets(state, source: Vector2i) -> Dictionary:
	var cells: Dictionary = state.cells
	var targets: Dictionary = {}
	if not cells.has(source) or cells[source]["unit"] == 0 or cells[source]["moved"]:
		return targets
	var parents: Dictionary = friendly_routes(state, source)
	var faction: int = state.unit_faction(source)
	var strength: int = cells[source]["unit"]
	var checked_border: Dictionary = {}
	for coord in parents:
		if coord != source and (cells[coord]["building"] == "" or state.is_bridge(coord)):
			if cells[coord]["unit"] == 0 or (cells[coord]["unit"] == cells[source]["unit"] and cells[source]["unit"] < 3):
				targets[coord] = parents
		for direction in Grid.DIRECTIONS:
			var next: Vector2i = coord + direction
			if not cells.has(next):
				continue
			if parents.has(next) or checked_border.has(next):
				continue
			checked_border[next] = true
			if not state.is_mountain(next) and not state.is_barrier(next) and (cells[next]["owner"] != faction or state.is_bridge(next)) and (strength > defense(state, next) or knight_duel(state, source, next)):
				targets[next] = parents
	return targets

static func can_move(state, source: Vector2i, target: Vector2i) -> bool:
	return reachable_targets(state, source).has(target)

static func movement_path(state, source: Vector2i, target: Vector2i, known_targets: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var targets: Dictionary = reachable_targets(state, source) if known_targets.is_empty() else known_targets
	if not targets.has(target):
		return result
	var parents: Dictionary = targets[target]
	var endpoint := target
	if not parents.has(target):
		var shortest := 1000000
		for next in state.neighbors(target):
			if parents.has(next):
				var steps := 0
				var cursor: Vector2i = next
				while cursor != state.NONE:
					steps += 1
					cursor = parents[cursor]
				if steps < shortest:
					shortest = steps
					endpoint = next
		result.append(target)
	while endpoint != state.NONE:
		result.append(endpoint)
		endpoint = parents[endpoint]
	result.reverse()
	return result

static func kill_unit(state, coord: Vector2i) -> void:
	state.cells[coord].erase("entrenched_by")
	state.cells[coord]["unit"] = 0
	state.cells[coord]["moved"] = false
	state.cells[coord]["tree"] = false
	state.cells[coord]["grave"] = not state.is_bridge(coord)
	state.cells[coord]["unit_owner"] = -1
	state.cells[coord]["unit_home"] = state.NONE

static func move_unit(state, source: Vector2i, target: Vector2i) -> bool:
	if not can_move(state, source, target):
		return false
	apply_move(state, source, target)
	return true

static func fortification_blocks_attack(state, source: Vector2i, target: Vector2i) -> bool:
	if not state.cells[target].get("fortified", false) and not state.is_entrenched(target):
		return false
	if state.is_bridge(target):
		# Crossing or merging on neutral wood is not an attack on its garrison.
		return state.cells[target]["unit"] > 0 and state.unit_faction(target) != state.unit_faction(source)
	return state.cells[target]["owner"] != state.unit_faction(source)

static func blocked_landing(state, source: Vector2i, target: Vector2i, path: Array = []) -> Vector2i:
	# Legacy structure wards retain their recorded behavior. Entrenchment lets
	# the attacker hold the nearest available square on its actual approach.
	if not state.is_entrenched(target): return source
	if path.is_empty(): path = movement_path(state, source, target)
	for index in range(path.size() - 2, -1, -1):
		var coord: Vector2i = path[index]
		if coord == source: return source
		var cell: Dictionary = state.cells[coord]
		if cell["unit"] == 0 and (cell["building"] == "" or state.is_bridge(coord)):
			return coord
	return source

static func apply_move(state, source: Vector2i, target: Vector2i, path: Array = []) -> void:
	# Internal mutation; public commands validate their route before calling this.
	var unit: Dictionary = state.cells[source]
	var destination: Dictionary = state.cells[target]
	var faction: int = state.unit_faction(source)
	unit.erase("entrenched_by")
	var trailblazing: bool = state.has_effect(faction, "trailblaze")
	state.set_effect(faction, "trailblaze", false)
	var neutral_capture: bool = destination["owner"] == -1 and not state.is_bridge(target)
	if fortification_blocks_attack(state, source, target):
		var landing := blocked_landing(state, source, target, path)
		destination.erase("entrenched_by")
		destination["fortified"] = false
		destination["fortified_by"] = -1
		if landing == source:
			unit["moved"] = true
		else:
			apply_move(state, source, landing)
		return
	if knight_duel(state, source, target):
		kill_unit(state, source)
		kill_unit(state, target)
		return
	var support: Dictionary = state.unit_kingdom(source)
	var support_capital: Vector2i = support.get("capital", state.NONE)
	var reward: int = 1 if state.is_modern() and destination["tree"] else 0
	var surrendered: Array[Vector2i] = castle_neighbors(state, source, target)
	var capturing: bool = not state.is_bridge(target) and destination["owner"] != faction
	if capturing:
		reward += int(destination.get("treasure", 0))
		destination.erase("treasure")
	var former_owner: int = destination["owner"]
	var merging: bool = destination["unit"] > 0 and state.unit_faction(target) == faction
	destination.erase("entrenched_by")
	destination["unit"] = unit["unit"] + 1 if merging else unit["unit"]
	if not state.is_bridge(target):
		destination["owner"] = faction
	destination["unit_owner"] = faction
	destination["unit_home"] = support_capital if state.is_modern() else state.NONE
	destination["moved"] = destination["moved"] if merging else true
	if trailblazing and neutral_capture:
		destination["moved"] = false
	destination["tree"] = false
	destination["grave"] = false
	if capturing:
		destination["capital"] = -1
		destination["building"] = ""
	unit["unit"] = 0
	unit["moved"] = false
	unit["unit_owner"] = -1
	unit["unit_home"] = state.NONE
	for coord in surrendered:
		var cell: Dictionary = state.cells[coord]
		cell["owner"] = destination["owner"]
		cell["capital"] = -1
		cell["fortified"] = false
		cell["fortified_by"] = -1
		if cell["unit"] > 0:
			kill_unit(state, coord)
	if capturing:
		state.rebuild_kingdoms({faction: true, former_owner: true})
	if destination.get("event", "") != "": state.magic.trigger_event(state, target, faction)
	state.clamp_mana()
	if reward > 0:
		var beneficiary: Dictionary = state.kingdom_at(support_capital) if support_capital != state.NONE else state.unit_kingdom(target)
		if not beneficiary.is_empty():
			beneficiary["gold"] += reward

static func perform_move(state, source: Vector2i, target: Vector2i) -> Dictionary:
	# Record the route and participants before the authoritative move changes them.
	var path: Array[Vector2i] = movement_path(state, source, target)
	if path.is_empty():
		return {}
	return record_validated_move(state, source, target, path)

static func record_validated_move(state, source: Vector2i, target: Vector2i, path: Array) -> Dictionary:
	# Internal only: caller validated this route on the owning thread immediately
	# before this call, with no intervening await or mutation.
	# Any marker can redraw into an area effect, so AI playback must track all of them.
	var event_before: Dictionary = state.cells.duplicate(true) if state.cells[target].get("event", "") != "" and state.unit_faction(source) not in state.human_factions else {}
	var source_cell: Dictionary = state.cells[source].duplicate(true)
	var target_cell: Dictionary = state.cells[target].duplicate(true)
	var faction: int = state.unit_faction(source)
	var support: Dictionary = state.unit_kingdom(source)
	var blocked: bool = fortification_blocks_attack(state, source, target)
	var landing: Vector2i = blocked_landing(state, source, target, path) if blocked else target
	var before_landing: Dictionary = state.cells[landing].duplicate(true) if blocked else {}
	var blocked_reward: int = 1 if blocked and landing != source and state.is_modern() and before_landing["tree"] else 0
	var duel: bool = not blocked and knight_duel(state, source, target)
	var capturing: bool = not blocked and not duel and not state.is_bridge(target) and faction != target_cell["owner"]
	var attacking: bool = blocked or capturing and (target_cell["unit"] > 0 or target_cell["building"] != "" or target_cell["capital"] >= 0) or state.is_bridge(target) and target_cell["unit"] > 0 and state.unit_faction(target) != faction
	var kind = "blocked_attack" if blocked else "knight_duel" if duel else "attack" if attacking else "merge" if target_cell["unit"] > 0 and state.unit_faction(target) == faction else "move"
	var surrendered: Array[Vector2i] = []
	if not blocked and not duel:
		surrendered = castle_neighbors(state, source, target)
	apply_move(state, source, target, path)
	var annexed: Dictionary = {}
	for coord in surrendered:
		annexed[coord] = state.cells[coord].duplicate(true)
	for coord in event_before:
		if coord not in [source, target] and event_before[coord] != state.cells[coord]: annexed[coord] = state.cells[coord].duplicate(true)
	var arguments := {"source":source, "target":target, "tier":source_cell["unit"], "outcome":kind, "path":path}
	if blocked: arguments["landing"] = landing
	state.record_replay("move", faction, arguments)
	var record := {"kind": kind, "faction": faction, "source": source,
		"target": target, "path": path, "before_source": source_cell,
		"before_target": target_cell, "after_target": state.cells[target].duplicate(true),
		"capture": capturing, "annexed": annexed, "after_source": state.cells[source].duplicate(true),
		"payer_capital": support.get("capital", state.NONE), "gold_reward": blocked_reward + (int(target_cell.get("treasure", 0)) if capturing else 0) + (1 if state.is_modern() and target_cell["tree"] and not blocked and not duel else 0)}
	if blocked:
		record["landing"] = landing
		record["before_landing"] = before_landing
		record["after_landing"] = state.cells[landing].duplicate(true)
	return record
