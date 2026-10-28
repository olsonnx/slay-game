extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## Editable starting positions. Gameplay receives a private, rebuilt copy.
const Events = preload("res://src/game/event_catalog.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
const FIELDS := ["owner", "unit", "capital", "tree", "grave", "building", "value", "mana_source", "mountain", "event", "road"]
const TOOLS := ["Land", "Water", "Owner", "Value", "Mountain", "Tree", "Grave", "Mana source", "Capital", "Scout", "Soldier", "Knight", "City", "Road", "Tower", "Bridge", "Clear objects", "Event", "Player start", "Bear cave", "Wolf den", "Boar burrow"]
const LAIR_TOOLS := {"Bear cave":"bear", "Wolf den":"wolf", "Boar burrow":"boar"}
const MODERN_TOOLS := ["Mountain", "Mana source", "Bridge", "Event", "Bear cave", "Wolf den", "Boar burrow"]
const TILE_TOOLS := ["Land", "Water", "Mountain", "Bridge"]
const MAX_CELLS := 4000
var cells: Dictionary = {}
var map_size := "small"
var rule_mode: String:
	get: return "modern"
	set(_value): pass
var seed_value := 1
var title := "My island"
var starting_gold := 10
var player_start := Rules.NONE
var factions: Array = default_factions()
# Compatibility for older callers; new files identify the start by province.
var player_faction: int:
	get: return int(cells.get(player_start, {}).get("owner", -1))
	set(value): player_start = start_for_faction(value)
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var saved_state := ""

func state() -> Dictionary:
	var rows: Array = []
	var coords := cells.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	for coord in coords:
		var row := {"q": coord.x, "r": coord.y}
		for field in FIELDS:
			row[field] = cells[coord].get(field, false) if field == "road" else cells[coord][field]
		if cells[coord].has("road_links"):
			row["road_links"] = []
			for next in cells[coord].road_links: row.road_links.append([next.x, next.y])
		if cells[coord].get("lair", "") != "": row["lair"] = cells[coord].lair
		if cells[coord].get("settlement_name", "") != "": row["settlement_name"] = cells[coord].settlement_name
		if cells[coord].get("treasure", 0) > 0: row["treasure"] = cells[coord].treasure
		rows.append(row)
	return {"format": "slay-level", "version": 1, "title": title, "size": map_size,
		"rules": rule_mode, "seed": seed_value, "gold": starting_gold, "player_start": null if player_start == Rules.NONE else [player_start.x, player_start.y],
		"factions": factions.duplicate(true), "cells": rows}

func dirty() -> bool:
	return JSON.stringify(state()) != saved_state

func mark_saved() -> void:
	saved_state = JSON.stringify(state())

func save_file(path: String) -> Error:
	# Keep the last saved draft intact until the complete replacement is ready.
	var temporary := path + ".%d.tmp" % Time.get_ticks_usec()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state(), "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return error
	mark_saved()
	return OK

func checkpoint() -> void:
	commit_stroke(state())

func commit_stroke(previous_state: Dictionary) -> void:
	undo_stack.append(previous_state)
	if undo_stack.size() > 60:
		undo_stack.pop_front()
	redo_stack.clear()

func undo() -> void:
	if undo_stack.is_empty(): return
	redo_stack.append(state())
	restore(undo_stack.pop_back())

func redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(state())
	restore(redo_stack.pop_back())

func generate(size_id: String, mode: String, blank := false) -> void:
	player_start = Rules.NONE
	factions = default_factions()
	map_size = size_id
	rule_mode = mode
	seed_value = int(Time.get_ticks_usec() % 2147483647)
	starting_gold = Rules.Catalog.START_GOLD
	cells = {}
	if not blank:
		var rules = Rules.new()
		rules.rule_mode = mode
		rules.generate(seed_value, size_id, 2 if size_id == "very_small" else 4)
		cells = rules.cells.duplicate(true)
	for cell in cells.values():
		cell["event"] = ""
		cell.erase("treasure")
	player_start = start_for_faction(0)
	undo_stack.clear()
	redo_stack.clear()
	saved_state = ""

func in_bounds(coord: Vector2i) -> bool:
	var at: Vector3 = Rules.Grid.to_world(coord)
	return Vector2(at.x, at.z).length() <= Sizes.generation_bounds(map_size).x

func clear_objects(cell: Dictionary) -> void:
	cell.erase("road")
	cell.erase("road_links")
	for field in ["lair","lair_wait","animal","animal_home","animal_target","treasure"]: cell.erase(field)
	cell.merge({"unit": 0, "capital": -1, "tree": false, "grave": false,
		"building": "", "mana_source": false, "event": ""}, true)

func paint(coord: Vector2i, tool: String, owner: int, value: int, event_id := "") -> bool:
	if not in_bounds(coord) or tool not in TOOLS: return false
	if tool == "Player start":
		if not cells.has(coord) or cells[coord]["owner"] < 0 or cells[coord]["mountain"] or cells[coord]["building"] == "bridge": return false
		var changed := player_start != coord
		player_start = coord
		return changed
	if tool == "Event" and (not Events.EVENTS.has(event_id)): return false
	if cells.size() >= MAX_CELLS and not cells.has(coord) and tool in ["Land", "Bridge"]: return false
	var before: Dictionary = cells.get(coord, {}).duplicate(true)
	if tool == "Water":
		cells.erase(coord)
		if player_start == coord: player_start = Rules.NONE
	elif tool == "Bridge":
		if (cells.has(coord) and cells[coord]["building"] != "bridge"): return false
		var bridge: Dictionary = Rules.new().make_cell()
		bridge["building"] = "bridge"
		bridge["value"] = 0
		cells[coord] = bridge
	elif tool == "Land":
		var adding: bool = not cells.has(coord) or cells[coord]["mountain"] or cells[coord]["building"] == "bridge"
		if not cells.has(coord): cells[coord] = Rules.new().make_cell(owner)
		if cells[coord]["building"] == "bridge": clear_objects(cells[coord])
		cells[coord]["mountain"] = false
		if adding: cells[coord]["value"] = value
	elif cells.has(coord):
		var cell: Dictionary = cells[coord]
		if tool == "Owner":
			if cell["mountain"] or cell["building"] == "bridge": return false
			if cell.get("lair", "") != "": clear_objects(cell)
			cell["owner"] = owner
			if owner >= 0: cell.erase("treasure")
			if cell["capital"] >= 0: cell["capital"] = owner
			if owner < 0:
				cell["unit"] = 0
				cell["building"] = ""
		elif tool == "Value":
			if not cell["mountain"] and cell["building"] != "bridge": cell["value"] = value
		elif tool == "Mountain":
			clear_objects(cell)
			cell.merge({"mountain": true, "owner": -1, "value": 0}, true)
		elif tool in LAIR_TOOLS:
			if cell.owner >= 0 or cell.mountain or cell.building == "bridge": return false
			clear_objects(cell)
			cell["lair"] = LAIR_TOOLS[tool]
			cell["lair_wait"] = 0
		elif tool == "Clear objects":
			if cell["building"] == "bridge": return false
			clear_objects(cell)
		elif not cell["mountain"] and cell["building"] != "bridge":
			if tool in ["Capital", "Scout", "Soldier", "Knight", "City", "Tower"] and cell["owner"] < 0: return false
			if tool == "Road":
				if cell.owner < 0: return false
				cell["road"] = true
			elif tool == "Mana source":
				if cell.get("lair", "") != "": clear_objects(cell)
				cell["mana_source"] = true
			else:
				# Mana is a terrain attribute and can coexist with structures.
				var mana: bool = cell["mana_source"]
				var capital: int = cell["capital"] if tool in ["Scout", "Soldier", "Knight"] else -1
				var building: String = cell["building"] if tool in ["Scout", "Soldier", "Knight"] and cell["building"] == "city" else ""
				var road: bool = cell.get("road", false)
				clear_objects(cell)
				cell["mana_source"] = mana
				cell["capital"] = capital
				cell["building"] = building
				if road: cell["road"] = true
				match tool:
					"Capital": cell["capital"] = cell["owner"]
					"Scout", "Soldier", "Knight": cell["unit"] = ["Scout", "Soldier", "Knight"].find(tool) + 1
					"City", "Tower": cell["building"] = tool.to_lower()
					"Tree": cell["tree"] = true
					"Grave": cell["grave"] = true
					"Event": cell["event"] = event_id
	return before != cells.get(coord, {})

func restore(data: Dictionary) -> void:
	title = data["title"]
	map_size = data["size"]
	rule_mode = data["rules"]
	seed_value = int(data["seed"])
	starting_gold = int(data["gold"])
	factions = data.get("factions", default_factions()).duplicate(true)
	cells.clear()
	for row in data["cells"]:
		var cell: Dictionary = Rules.new().make_cell(int(row["owner"]))
		for field in FIELDS:
			cell[field] = row.get(field, false) if field == "road" else row[field]
		if row.get("settlement_name", "") != "": cell["settlement_name"] = row.settlement_name
		if row.has("road_links"):
			cell["road_links"] = []
			for link in row.road_links: cell.road_links.append(Vector2i(int(link[0]), int(link[1])))
		if row.get("lair", "") != "":
			cell["lair"] = row.lair
			cell["lair_wait"] = 0
		if row.get("treasure", 0) > 0: cell["treasure"] = int(row.treasure)
		for field in ["owner", "unit", "capital", "value"]: cell[field] = int(cell[field])
		cells[Vector2i(int(row["q"]), int(row["r"]))] = cell
	if data.has("player_start"):
		var marker = data["player_start"]
		player_start = Rules.NONE if marker == null else Vector2i(int(marker[0]), int(marker[1]))
	else:
		player_start = start_for_faction(int(data.get("player_faction", 0)))

func erase(coord: Vector2i, tool: String, _hit_kind := "terrain") -> bool:
	if tool == "Player start":
		if player_start != coord: return false
		player_start = Rules.NONE
		return true
	if not in_bounds(coord) or not cells.has(coord): return false
	if tool in TILE_TOOLS:
		if player_start == coord: player_start = Rules.NONE
		cells.erase(coord)
		return true
	var cell: Dictionary = cells[coord]
	var before := cell.duplicate(true)
	# Painting removes decorations, never the terrain, owner or value.
	var bridge: bool = cell["building"] == "bridge"
	clear_objects(cell)
	if bridge: cell["building"] = "bridge"
	return before != cell

func read_data(data: Variant) -> String:
	# Reject invalid files atomically; never replace a draft on a failed load.
	if not data is Dictionary or data.get("format") != "slay-level" or data.get("version") != 1: return Loc.text("This is not a supported Slay level.")
	if not Sizes.SPECS.has(data.get("size")) or data.get("rules") not in ["modern", "classic"]: return Loc.text("Invalid map size or rules.")
	if not data.get("title") is String or data["title"].length() > 80: return Loc.text("Invalid level name.")
	for field in ["seed", "gold"]:
		if not is_number(data.get(field)) or data[field] < 0 or data[field] > 2147483647: return Loc.text("Invalid starting resources.")
	# Keep a bounded file budget even with the larger circular editing area.
	# Painting uses the same cap, so an authored draft can always be reloaded.
	if data["gold"] > 9999 or not data.get("cells") is Array or data["cells"].size() > MAX_CELLS: return Loc.text("Invalid level contents.")
	var saved_factions = data.get("factions", default_factions())
	if not saved_factions is Array or saved_factions.size() < 2 or saved_factions.size() > 64: return Loc.text("Invalid map kingdoms.")
	for faction in saved_factions:
		if not faction is Dictionary or not faction.get("name") is String or faction["name"].is_empty() or faction["name"].length() > 80: return Loc.text("Invalid map kingdoms.")
		for field in ["color", "terrain"]:
			if not faction.get(field) is String or not Color.html_is_valid(faction[field]): return Loc.text("Invalid map kingdoms.")
	if not data.has("player_start") and (not is_number(data.get("player_faction", 0)) or data.get("player_faction", 0) < 0 or data.get("player_faction", 0) >= saved_factions.size()): return Loc.text("Invalid player kingdom.")
	var marker = data.get("player_start")
	if marker != null:
		if not marker is Array or marker.size() != 2 or not is_number(marker[0]) or not is_number(marker[1]) or absf(marker[0]) > 100 or absf(marker[1]) > 100: return Loc.text("Invalid player start.")
	data = data.duplicate(true)
	# Older authored layouts are preserved under the current rules.
	data["rules"] = "modern"
	var seen := {}
	var bounds: Vector2 = Sizes.generation_bounds(data["size"])
	for row in data["cells"]:
		if not row is Dictionary: return "Invalid province."
		for field in ["q", "r", "owner", "unit", "capital", "value"]:
			if not is_number(row.get(field)): return Loc.text("Invalid province numbers.")
		if absf(row["q"]) > 100 or absf(row["r"]) > 100: return Loc.text("Province is outside the map.")
		var coord := Vector2i(int(row["q"]), int(row["r"]))
		var at: Vector3 = Rules.Grid.to_world(coord)
		if seen.has(coord) or Vector2(at.x, at.z).length() > bounds.x: return Loc.text("Duplicate province or province outside the map.")
		seen[coord] = true
		if row["owner"] < -1 or row["owner"] >= saved_factions.size() or row["unit"] < 0 or row["unit"] > 3 or row["capital"] < -1 or row["capital"] >= saved_factions.size() or row["value"] < 0 or row["value"] > 6: return Loc.text("Invalid province values.")
		for field in ["tree", "grave", "mana_source", "mountain"]:
			if not row.get(field) is bool: return Loc.text("Invalid terrain attributes.")
		if row.get("event") is String: row["event"] = Events.canonical_id(row["event"])
		if row.get("building") == "house": row["building"] = "city"
		if not row.get("road", false) is bool: return Loc.text("Invalid road attribute.")
		if not row.get("settlement_name", "") is String or row.get("settlement_name", "").length() > 40: return Loc.text("Invalid settlement name.")
		if row.has("road_links"):
			if not row.road_links is Array or row.road_links.size() > 6: return Loc.text("Invalid road connections.")
			for link in row.road_links:
				if not link is Array or link.size() != 2 or not is_number(link[0]) or not is_number(link[1]): return Loc.text("Invalid road connections.")
				if link[0] != floorf(link[0]) or link[1] != floorf(link[1]) or Rules.Grid.distance(coord, Vector2i(int(link[0]), int(link[1]))) != 1: return Loc.text("Invalid road connections.")
		if row.get("road", false) and (row.owner < 0 or row.mountain or row.building == "bridge"): return Loc.text("Roads need owned land.")
		if row.get("building") not in ["", "city", "tower", "bridge"] or (row.get("event") != "" and not Events.EVENTS.has(row.get("event"))): return "Unsupported object."
		if row.get("lair", "") not in ["","bear","wolf","boar"]: return "Unsupported object."
		if row.get("lair", "") != "" and (row.owner != -1 or row.unit != 0 or row.capital >= 0 or row.tree or row.grave or row.mana_source or row.mountain or row.building != "" or row.event != ""): return Loc.text("Lairs need empty neutral land.")
		if row["capital"] >= 0 and row["capital"] != row["owner"]: return Loc.text("Capital must belong to its province.")
		if (row["unit"] > 0 or row["building"] in ["city", "tower"]) and row["owner"] < 0: return Loc.text("Units and buildings need an owner.")
		var objects := int(row["tree"]) + int(row["grave"]) + int(row["building"] != "") + int(row["unit"] > 0) + int(row["capital"] >= 0) + int(row["event"] != "")
		if row.has("treasure"):
			if not is_number(row.treasure) or row.treasure < 1 or row.treasure > 10000 or row.owner != -1 or objects > 0 or row.mountain or row.get("lair", "") != "": return Loc.text("Treasure needs empty neutral land and a positive gold reward.")
		# Generated capitals can share their tile with a soldier.
		if objects > 1 and not (objects == 2 and row["unit"] > 0 and (row["capital"] >= 0 or row["building"] == "city")): return Loc.text("Objects overlap on a province.")
		if row["mountain"] and (row["owner"] != -1 or objects > 0 or row["mana_source"] or row["value"] != 0): return Loc.text("Mountain provinces must be empty and neutral.")
		if row["building"] == "bridge" and (row["owner"] != -1 or objects != 1 or row["mana_source"] or row["value"] != 0): return Loc.text("Bridges must be empty, neutral and zero-value.")
		if not row["mountain"] and row["building"] != "bridge" and row["value"] < 1: return Loc.text("Land needs a value from 1 to 6.")
	if marker != null and not seen.has(Vector2i(int(marker[0]), int(marker[1]))): return Loc.text("Player start must be on the map.")
	restore(data)
	undo_stack.clear()
	redo_stack.clear()
	mark_saved()
	return ""

func is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))

func playable_error() -> String:
	if cells.is_empty(): return Loc.text("Paint some land first.")
	if player_start == Rules.NONE or player_faction < 0: return Loc.text("Place the Player start marker on an owned province.")
	var rules = build_rules()
	if rules.kingdom_at(player_start).is_empty(): return Loc.text("Player start needs at least two connected provinces.")
	var player := false
	var enemy := false
	for kingdom in rules.kingdoms.values():
		player = player or kingdom["owner"] == player_faction
		enemy = enemy or kingdom["owner"] != player_faction
	if not player: return Loc.text("%s needs at least two connected provinces.") % factions[player_faction]["name"]
	if not enemy: return Loc.text("Add an opponent with at least two connected provinces.")
	return ""

func build_rules():
	var rules = Rules.new()
	rules.rule_mode = rule_mode
	rules.map_size = map_size
	rules.level_seed = seed_value
	rules.rng.seed = seed_value
	rules.cells = cells.duplicate(true)
	rules.faction_count = 2
	for cell in rules.cells.values(): rules.faction_count = maxi(rules.faction_count, cell["owner"] + 1)
	rules.faction_names = faction_names()
	rules.initial_kingdom_count = rules.faction_count
	rules.rebuild_kingdoms()
	for kingdom in rules.kingdoms.values(): kingdom["gold"] = starting_gold
	for faction in range(rules.faction_count): rules.set_mana(faction, 1)
	return rules

static func default_factions() -> Array:
	var result: Array = []
	for index in range(Catalog.FACTIONS.size()):
		result.append({"name": Catalog.FACTIONS[index], "color": Catalog.UI_COLORS[index].to_html(), "terrain": Catalog.TERRAIN_COLORS[index].to_html()})
	return result

func faction_names() -> Array:
	return factions.map(func(faction): return faction["name"])

func faction_colors(field: String) -> Array:
	return factions.map(func(faction): return Color.html(faction[field]))

func start_for_faction(faction: int) -> Vector2i:
	var coords := cells.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	for coord in coords:
		if cells[coord]["capital"] == faction: return coord
	for coord in coords:
		if cells[coord]["owner"] == faction: return coord
	return Rules.NONE
