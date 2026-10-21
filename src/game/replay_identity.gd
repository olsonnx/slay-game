extends RefCounted
## Recorded seat identities are independent of palette indices and display names.
const Catalog = preload("res://src/game/game_catalog.gd")

static func capture(names: Array, colors: Array, terrain: Array) -> Array:
	var result: Array = []
	for index in range(mini(names.size(), mini(colors.size(), terrain.size()))):
		result.append({"name":names[index], "color":colors[index].to_html(), "terrain":terrain[index].to_html()})
	return result

static func resolve(header: Dictionary) -> Dictionary:
	var colors: Array = Catalog.UI_COLORS.duplicate()
	var terrain: Array = Catalog.TERRAIN_COLORS.duplicate()
	var metadata = header.get("metadata", {})
	if not metadata is Dictionary: return {"colors":colors, "terrain":terrain}
	# Older normal matches already saved their palette choices in the seat list.
	var match_data = metadata.get("match", {})
	var slots = match_data.get("slots", []) if match_data is Dictionary else []
	if slots is Array and not slots.is_empty():
		var used: Array[int] = []
		for index in range(mini(slots.size(), colors.size())):
			if not slots[index] is Dictionary: continue
			var palette = slots[index].get("color")
			if not (palette is int or palette is float) or not is_finite(float(palette)) or palette != floorf(float(palette)): continue
			var id := int(palette)
			if id < 0 or id >= colors.size(): continue
			colors[index] = Catalog.UI_COLORS[id]
			terrain[index] = Catalog.TERRAIN_COLORS[id]
			used.append(id)
		# Match the live game's unused seats, which later revolts may activate.
		var spare: int = slots.size()
		for id in range(Catalog.FACTIONS.size()):
			if id in used: continue
			if spare >= colors.size(): break
			colors[spare] = Catalog.UI_COLORS[id]
			terrain[spare] = Catalog.TERRAIN_COLORS[id]
			spare += 1
	# New recordings retain exact authored colours as well as the normal palette.
	var factions = metadata.get("factions", [])
	if factions is Array:
		for index in range(mini(factions.size(), colors.size())):
			if not factions[index] is Dictionary: continue
			for field in ["color", "terrain"]:
				var value = factions[index].get(field)
				if value is String and Color.html_is_valid(value):
					if field == "color": colors[index] = Color.html(value)
					else: terrain[index] = Color.html(value)
	return {"colors":colors, "terrain":terrain}
