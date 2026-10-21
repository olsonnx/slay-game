extends RefCounted
## Read-only finances projected from the board currently shown during playback.
## Input records are borrowed; rebuilding operates exclusively on private copies.
const Rules = preload("res://src/game/kingdom_rules.gd")
var cached_context: Array = []
var cached_signature: Array = []
var cached_cells: Dictionary = {}

func scoped_signature(visible_cells: Dictionary, banks: Dictionary, player: int, inspected: Vector2i, active_hex: Vector2i, active_faction: int, round_number: int, changed_coords: Dictionary) -> Array:
	var inspected_owner: int = visible_cells.get(inspected, {}).get("owner", -2)
	var context: Array = [player, inspected, inspected_owner, active_hex, active_faction, round_number]
	for bank in banks.values():
		if bank["owner"] == player or bank["owner"] == inspected_owner:
			context.append([bank["capital"], bank["gold"]])
	# Most enemy movement leaves the player's readout unchanged. Compare only
	# notified records, including formerly relevant land that was just captured.
	var unchanged: bool = not changed_coords.is_empty() and context == cached_context
	if unchanged:
		for coord in changed_coords:
			var cell: Dictionary = visible_cells.get(coord, {})
			var included: bool = not cell.is_empty() and relevant(coord, cell, player, inspected, inspected_owner)
			if included != cached_cells.has(coord) or (included and cell != cached_cells[coord]):
				unchanged = false
				break
	if unchanged: return cached_signature
	cached_context = context
	cached_signature = signature(visible_cells, banks, player, inspected, active_hex, active_faction, round_number)
	cached_cells.clear()
	for record in cached_signature.slice(3):
		if record[1] is Dictionary: cached_cells[record[0]] = record[1]
	return cached_signature

static func relevant(coord: Vector2i, cell: Dictionary, player: int, inspected: Vector2i, inspected_owner: int) -> bool:
	return cell["owner"] == player or cell["owner"] == inspected_owner or coord == inspected or cell["building"] == "bridge" or (cell["unit"] > 0 and cell.get("unit_owner", -1) == player)

static func signature(visible_cells: Dictionary, banks: Dictionary, player: int, inspected: Vector2i, active_hex: Vector2i, active_faction: int, round_number: int) -> Array:
	var result: Array = [active_hex, active_faction, round_number]
	var inspected_owner: int = visible_cells.get(inspected, {}).get("owner", -2)
	for coord in visible_cells:
		var cell: Dictionary = visible_cells[coord]
		if relevant(coord, cell, player, inspected, inspected_owner):
			result.append([coord, cell.duplicate()])
	for bank in banks.values():
		if bank["owner"] == player or bank["owner"] == inspected_owner:
			result.append([bank["capital"], bank["gold"]])
	return result

static func project(rules, visible_cells: Dictionary, banks: Dictionary, mana: Dictionary, player: int, inspected: Vector2i):
	var economy = Rules.new()
	preload("res://src/game/state_snapshot.gd").presentation_metadata(rules, economy)
	# Player and inspected land need complete territories. Bridges and player
	# garrisons on them are retained for support and connectivity.
	var inspected_owner: int = visible_cells.get(inspected, {}).get("owner", -2)
	for coord in visible_cells:
		var cell: Dictionary = visible_cells[coord]
		if relevant(coord, cell, player, inspected, inspected_owner):
			economy.cells[coord] = cell.duplicate(true)
	economy.kingdoms = banks.duplicate(true)
	economy.mana_by_faction = mana.duplicate()
	economy.rebuild_kingdoms()
	return economy
