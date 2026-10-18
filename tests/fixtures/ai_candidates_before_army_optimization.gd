extends RefCounted
## Strategic candidate generation; no hidden event IDs or random rolls are read.
const Analysis = preload("res://src/game/ai_analysis.gd")
const Catalog = preload("res://src/game/game_catalog.gd")

static func add(result: Array, kind: String, coord: Vector2i, score: float, extra := {}) -> void:
	var action := {"kind": kind, "coord": coord, "priority": score}
	action.merge(extra)
	result.append(action)

static func preparation(model, faction: int, queries = null) -> Array:
	queries = Analysis.Queries.new(model) if queries == null else queries
	var result: Array = []
	var danger: Dictionary = queries.threats(faction)
	var trail_useful := false
	for source in model.cells:
		if model.unit_faction(source) != faction or model.cells[source]["unit"] == 0 or model.cells[source]["moved"]:
			continue
		var capture_options := 0
		var has_neutral := false
		for target in queries.reachable_targets(source):
			if model.cells[target]["owner"] != faction and not model.is_bridge(target):
				capture_options += 1
				if model.cells[target]["owner"] == -1:
					has_neutral = true
					for next in model.neighbors(target):
						if next != source and model.cells[next]["owner"] != faction and not model.is_mountain(next) and not model.is_barrier(next) and model.cells[source]["unit"] > queries.defense(next):
							trail_useful = true
		if has_neutral and capture_options >= 2:
			trail_useful = true
	for kingdom in model.kingdoms.values():
		if kingdom["owner"] != faction:
			continue
		var capital: Vector2i = kingdom["capital"]
		var border: Dictionary = queries.frontier(capital)
		var needed := 1
		for target in border:
			needed = maxi(needed, mini(3, queries.defense(target) + 1))
		for coord in kingdom["hexes"]:
			var cell: Dictionary = model.cells[coord]
			var urgent := Analysis.endangered(model, coord, danger)
			var importance := 70.0 if cell["capital"] >= 0 else 15.0
			for tier in range(cell["unit"] + 1, 4):
				if border.is_empty() and not urgent:
					continue
				var cost: int = model.recruitment_cost(coord, faction, tier, capital)
				var wages: int = Catalog.unit_upkeep(tier, model.is_modern()) - Catalog.unit_upkeep(cell["unit"], model.is_modern())
				if cost < 0 or not Analysis.sustainable(model, kingdom, wages, cost, queries):
					continue
				var utility := 3.0 if not border.is_empty() else -5.0
				if tier == needed:
					utility += 4.0
				if urgent and tier >= danger[coord]["strength"]:
					utility += importance
				add(result, "recruit", coord, utility, {"tier": tier, "capital": capital})
			if model.can_build(coord, faction, "tower", capital):
				var cover := 0.0
				for next in [coord] + model.neighbors(coord):
					if model.cells[next]["owner"] == faction and Analysis.endangered(model, next, danger) and danger[next]["strength"] <= 2:
						cover += 65.0 if model.cells[next]["capital"] >= 0 else 12.0
				if cover > 0:
					add(result, "tower", coord, cover, {"capital": capital})
			if model.can_build(coord, faction, "house", capital) and not urgent:
				add(result, "house", coord, 2.0, {"capital": capital})
			if model.can_develop(coord, faction) and not cell["tree"] and not cell["grave"] and not urgent:
				add(result, "develop", coord, 2.0 / maxf(1.0, model.development_cost(coord)), {"capital": capital})
		if not model.is_modern():
			continue
		for site in model.bridge_targets(faction, capital):
			var benefit := 0.0
			for next in model.neighbors(site):
				if model.is_bridge(next) or model.cells[next]["kingdom"] == capital:
					continue
				benefit += 12.0 if model.cells[next]["owner"] == faction else 3.0
			if benefit > 0 and kingdom["gold"] >= model.BRIDGE_COST + 10:
				add(result, "bridge", site, benefit, {"capital": capital})
	# Mana opportunities compete faction-wide, rather than kingdom iteration order.
	if model.is_modern():
		for spell in model.Spells.SPELLS:
			for coord in model.spell_targets(spell, faction):
				var cell: Dictionary = model.cells[coord]
				var utility := 0.0
				match spell:
					"summon":
						var kingdom: Dictionary = model.kingdom_at(coord)
						if Analysis.sustainable(model, kingdom, Catalog.unit_upkeep(1, model.is_modern()), 0, queries):
							utility = 4.0 if not queries.frontier(kingdom["capital"]).is_empty() else 0.0
							if Analysis.endangered(model, coord, danger) and danger[coord]["strength"] == 1:
								utility += 15.0
					"fortify":
						if Analysis.endangered(model, coord, danger):
							utility = 60.0 if cell["capital"] >= 0 else 12.0
					"shatter":
						if model.is_bridge(coord) and cell["unit"] > 0 and model.unit_faction(coord) != faction:
							utility = Analysis.UNIT_VALUE[cell["unit"]] * 0.65
						elif model.is_bridge(coord):
							for next in model.neighbors(coord):
								if Analysis.endangered(model, next, danger):
									utility = 10.0
					"trailblaze":
						utility = 7.0 if trail_useful else 0.0
					"grove":
						if cell["owner"] >= 0 and cell["owner"] != faction:
							utility = cell["value"] * 1.2 - (2.0 if cell["mana_source"] else 0.0)
					"barrier":
						if danger.has(coord):
							if Analysis.endangered(model, coord, danger) and cell["value"] >= 3:
								utility = cell["value"] * 1.5
							for next in model.neighbors(coord):
								if model.cells[next]["owner"] == faction and model.cells[next]["capital"] >= 0:
									utility = 14.0
				if utility > 0:
					add(result, "spell", coord, utility, {"spell": spell})
	result.sort_custom(func(a, b): return a["priority"] > b["priority"])
	return diverse(result, int(Analysis.profile(model)["candidates"]), false)

static func movements(model, faction: int, queries = null) -> Array:
	queries = Analysis.Queries.new(model) if queries == null else queries
	var result: Array = []
	var danger: Dictionary = queries.threats(faction)
	var frontiers: Dictionary = {}
	for kingdom in model.kingdoms.values():
		if kingdom["owner"] == faction:
			frontiers[kingdom["capital"]] = queries.frontier(kingdom["capital"])
	for source in model.cells:
		if model.unit_faction(source) != faction or model.cells[source]["unit"] == 0 or model.cells[source]["moved"]:
			continue
		for target in queries.reachable_targets(source):
			var cell: Dictionary = model.cells[target]
			var score := -2.0
			var reason := "reposition"
			if cell["owner"] != faction and not model.is_bridge(target):
				score = 8.0 + cell["value"] * 1.5
				reason = "capture land"
				if cell["capital"] >= 0:
					score += 22.0 + model.castle_neighbors(source, target).size() * 4.0
					reason = "capture capital"
				if cell["mana_source"]:
					score += 5.0
					reason = "capture source"
			if cell["unit"] > 0:
				if model.unit_faction(target) == faction:
					score = 6.0
					# Favor a merge that unlocks a reachable defended target.
					for next in frontiers.get(queries.support(source).get("capital", source), {}):
						if queries.defense(next) == cell["unit"]:
							score += 4.0
							break
					reason = "merge for strength"
				else:
					score += Analysis.UNIT_VALUE[cell["unit"]] * 0.4
			if cell["owner"] == faction and (cell["tree"] or cell["grave"]):
				score += cell["value"] * 2.0 + 3.0
				reason = "restore income"
			if cell["owner"] == faction:
				for next in [target] + model.neighbors(target):
					if model.cells[next]["owner"] == faction and Analysis.endangered(model, next, danger):
						score += 35.0 if model.cells[next]["capital"] >= 0 else 4.0
						reason = "protect kingdom"
			if model.fortification_blocks_attack(source, target):
				score -= 8.0
				reason = "remove ward"
			if model.knight_duel(source, target):
				score -= 18.0
				reason = "trade knights"
			score += Analysis.variation(model, source, target)
			add(result, "move", target, score, {"source": source, "reason": reason})
	result.sort_custom(func(a, b): return a["priority"] > b["priority"])
	return diverse(result, int(Analysis.profile(model)["candidates"]), true)

static func diverse(sorted: Array, limit: int, movement: bool) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	# Retain alternatives across action kinds/units rather than one crowded dock.
	for candidate in sorted:
		var key: String = str(candidate["source"]) if movement else candidate.get("spell", candidate["kind"])
		if seen.get(key, 0) >= 2:
			continue
		seen[key] = seen.get(key, 0) + 1
		result.append(candidate)
		if result.size() >= limit:
			break
	return result

static func apply(model, action: Dictionary, faction: int) -> bool:
	match action["kind"]:
		"move": return model.move_unit(action["source"], action["coord"])
		"recruit": return model.recruit(action["coord"], faction, action["tier"], action["capital"])
		"spell": return model.cast_spell(action["spell"], action["coord"], faction)
		"develop": return model.develop(action["coord"], faction)
		_: return model.build_structure(action["coord"], faction, action["kind"], action["capital"])
