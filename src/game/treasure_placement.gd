extends RefCounted
## Visible, safe rewards favor side branches over the shortest rival corridor.
const GOLD := 15
const TILES_PER_CHEST := 100.0

static func site_score(state, coord: Vector2i, capitals: Array) -> float:
	var nearest := 100000
	var detour := 100000
	for capital in capitals:
		nearest = mini(nearest, state.distance(coord, capital))
		for other in capitals:
			if other == capital: continue
			detour = mini(detour, state.distance(coord, capital) + state.distance(coord, other) - state.distance(capital, other))
	if nearest < 4: return -1.0
	if detour == 100000: detour = nearest
	var coast: int = 6 - state.neighbors(coord).size()
	return nearest + detour * 2.0 + coast * 0.7

static func generate(state) -> void:
	if state.map_size not in ["medium", "large", "very_large", "huge"]: return
	var capitals: Array = state.kingdoms.keys()
	var sites: Array = []
	var neutral := 0
	for coord in state.cells:
		var cell: Dictionary = state.cells[coord]
		if cell["owner"] != -1 or state.is_mountain(coord) or state.is_bridge(coord): continue
		neutral += 1
		if cell["mana_source"] or cell["event"] != "" or cell["tree"] or cell["grave"] or cell.get("treasure", 0) > 0: continue
		var near_event := false
		for next in state.neighbors(coord):
			if state.cells[next]["event"] != "": near_event = true
		if near_event: continue
		var score := site_score(state, coord, capitals)
		if score >= 0: sites.append({"coord":coord, "score":score})
	# Seeded tie-breaking keeps placement varied without changing the land itself.
	sites = state.shuffled(sites)
	sites.sort_custom(func(a, b): return a["score"] > b["score"])
	var target := maxi(1, roundi(neutral / TILES_PER_CHEST))
	var placed: Array = []
	for site in sites:
		var coord: Vector2i = site["coord"]
		var near_chest := false
		for other in placed:
			if state.distance(coord, other) < 6: near_chest = true
		if near_chest: continue
		state.cells[coord]["treasure"] = GOLD
		placed.append(coord)
		if placed.size() >= target: break
