extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## Session configuration uses seat IDs independently of their chosen palette.
const Catalog = preload("res://src/game/game_catalog.gd")
const Sizes = preload("res://src/game/map_sizes.gd")

static func normalize(value: Dictionary) -> Dictionary:
	var size_id = value.get("size", "small")
	var count = value.get("count", 4)
	var map_path = value.get("map_path", "")
	if not map_path is String: map_path = ""
	# Authored maps retain retired size metadata; generated lobbies use current choices.
	if size_id not in Sizes.IDS and not (map_path != "" and Sizes.SPECS.has(size_id)): size_id = "small"
	count = clampi(count if count is int else 4, 2, 6) if map_path != "" else Sizes.clamp_kingdom_count(size_id, count if count is int else 4)
	var result := {"size": size_id, "count": count, "rules": "classic" if value.get("rules") == "classic" else "modern", "seed": -1, "order": "random" if value.get("order") == "random" else "fixed", "slots": []}
	if map_path != "": result["map_path"] = map_path
	var seed_value = value.get("seed", -1)
	if seed_value is int: result["seed"] = clampi(seed_value, -1, 2147483647)
	var slots = value.get("slots", [])
	if not slots is Array: slots = []
	var used: Array = []
	for index in range(count):
		var seat: Dictionary = slots[index] if index < slots.size() and slots[index] is Dictionary else {}
		var color = seat.get("color", index)
		if not color is int or color < 0 or color >= Catalog.FACTIONS.size() or color in used:
			color = 0
			while color in used: color += 1
		used.append(color)
		var name_value = seat.get("name", "")
		name_value = name_value.strip_edges().left(18) if name_value is String else ""
		var controller: String = "human" if seat.get("controller", "human" if index < 2 else "ai") == "human" else "ai"
		var difficulty = seat.get("difficulty", "normal")
		if difficulty not in ["easy", "normal", "hard"]: difficulty = "normal"
		result["slots"].append({"name": name_value if name_value != "" else Loc.text("Player %d") % (index + 1) if controller == "human" else Catalog.FACTIONS[color], "color": color, "controller": controller, "difficulty": difficulty})
	return result

static func quick_play(size_id: String, count: int, difficulty: String, kingdom: int, seed_value: int, rule_mode: String) -> Dictionary:
	# Palette selection never consumes the map/gameplay RNG or changes seat IDs.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x5A17C01
	var palettes: Array = range(Catalog.FACTIONS.size())
	for index in range(palettes.size()-1,0,-1):
		var other := rng.randi_range(0,index)
		var previous: int = palettes[index]
		palettes[index] = palettes[other]
		palettes[other] = previous
	if kingdom >= 0 and kingdom < Catalog.FACTIONS.size():
		palettes.erase(kingdom)
		palettes.push_front(kingdom)
	var slots := []
	for index in range(Sizes.clamp_kingdom_count(size_id,count)):
		var color: int = palettes[index]
		slots.append({"name":Catalog.FACTIONS[color], "color":color, "controller":"human" if index == 0 else "ai", "difficulty":difficulty})
	return {"size":size_id,"count":slots.size(),"rules":rule_mode,"seed":seed_value,"order":"fixed","slots":slots}

static func human_count(config: Dictionary) -> int:
	var count := 0
	for seat in config["slots"]:
		count += int(seat["controller"] == "human")
	return count

static func read_level(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error":Loc.text("Could not open the editor map. Choose the file again.")}
	if file.get_length() > 2000000: return {"error":Loc.text("This map file is too large.")}
	var document = preload("res://src/editor/level_document.gd").new()
	var error: String = document.read_data(JSON.parse_string(file.get_as_text()))
	if error != "": return {"error":error}
	var rules = document.build_rules()
	var factions: Array = []
	var capitals: Array = []
	for cell in rules.cells.values():
		if cell["owner"] >= 0 and cell["owner"] not in factions: factions.append(cell["owner"])
	for kingdom in rules.kingdoms.values():
		if kingdom["owner"] not in capitals: capitals.append(kingdom["owner"])
	factions.sort()
	if factions.size() < 2: return {"error":Loc.text("A multiplayer map needs at least two starting factions.")}
	if factions.size() > 6: return {"error":Loc.text("Local multiplayer supports up to six active kingdoms per map.")}
	for faction in factions:
		if faction not in capitals:
			return {"error":Loc.text("%s needs at least two connected provinces for multiplayer.") % document.factions[faction]["name"]}
	# Compact sparse authored owners into seat IDs without changing their land.
	# Original faction IDs remain available to seed each seat's starting colour.
	var data: Dictionary = document.state()
	# Keep saved palettes aligned with the compacted multiplayer seat IDs.
	data["factions"] = factions.map(func(faction): return document.factions[faction].duplicate(true))
	for cell in data["cells"]:
		if cell["owner"] >= 0: cell["owner"] = factions.find(cell["owner"])
		if cell["capital"] >= 0: cell["capital"] = factions.find(cell["capital"])
	return {"error":"", "data":data, "factions":factions}
