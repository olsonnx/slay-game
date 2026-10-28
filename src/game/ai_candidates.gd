extends RefCounted
## Strategic candidate generation; no hidden event IDs or random rolls are read.
const Analysis = preload("res://src/game/ai_analysis.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const Infrastructure = preload("res://src/game/ai_logistics.gd")

static func add(result: Array, kind: String, coord: Vector2i, score: float, extra := {}) -> void:
	var action := {"kind": kind, "coord": coord, "priority": score}
	action.merge(extra)
	result.append(action)

static func preparation(model, faction: int, queries = null) -> Array:
	queries = Analysis.Queries.new(model) if queries == null else queries
	var result: Array = []
	var city_reserves := {}
	var danger: Dictionary = queries.defense_needs(faction)
	var tower_price: int = model.tower_cost(faction)
	var trail_useful := false
	for source in model.cells:
		if model.unit_faction(source) != faction or model.cells[source]["unit"] == 0 or model.cells[source]["moved"]:
			continue
		var capture_options := 0
		var has_neutral := false
		for target in queries.candidate_targets(source):
			if target == source:
				continue
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
		var city_sites := Infrastructure.city_sites(model, kingdom, border, danger)
		if not city_sites.is_empty(): city_reserves[capital] = true
		var needed := 1
		for target in border:
			needed = maxi(needed, mini(3, queries.defense(target) + 1))
		var deployment := 0
		var open_deployment := 0
		for site in kingdom["hexes"]:
			if model.cells[site]["building"] == "" and not model.is_mountain(site):
				deployment += 1
				if model.cells[site]["unit"] == 0 and not model.is_barrier(site): open_deployment += 1
		var reserve := mini(6, maxi(2, ceili(kingdom["hexes"].size() * 0.25)))
		var finances: Dictionary = queries.bank_summary(kingdom)
		var tower_affordable: bool = kingdom["gold"] >= tower_price and Analysis.safe_spending(kingdom, tower_price, -model.Catalog.TOWER_UPKEEP, queries)
		var reinforcement_budget: int = queries.unit_upkeep(needed, faction) + 2 * queries.unit_upkeep(1, faction)
		var needs_income: bool = finances["income"] - finances["upkeep"] < reinforcement_budget
		for coord in kingdom["hexes"]:
			var cell: Dictionary = model.cells[coord]
			var urgent := Analysis.endangered(model, coord, danger)
			var importance := 70.0 if cell["capital"] >= 0 else 15.0
			if urgent: importance += queries.supply_risk(coord)
			if urgent and model.can_entrench(coord, faction):
				add(result, "entrench", coord, importance, {"capital":capital})
			for tier in range(cell["unit"] + 1, 4):
				if border.is_empty() and not urgent:
					continue
				var cost: int = model.recruitment_cost(coord, faction, tier, capital)
				var wages: int = queries.unit_upkeep(tier, faction) - queries.unit_upkeep(cell["unit"], faction)
				if cost < 0 or not Analysis.sustainable(model, kingdom, wages, cost, queries):
					continue
				var utility: float = queries.recruitment_value(coord,tier) - wages * 0.85 - cost * 0.16
				if urgent and tier >= danger[coord]["strength"]:
					utility += importance * (0.65 if danger[coord].get("projected",false) else 1.0)
				# Adjacent defenders lend at most Soldier protection. A Knight is
				# justified by an actual breach or a threat on its own square.
				for next in queries.neighbors(coord):
					if model.cells[next]["owner"] == faction and danger.has(next) and danger[next]["strength"] <= mini(tier,2) and Analysis.endangered(model,next,danger):
						utility += 55.0 if model.cells[next]["capital"] >= 0 else 3.0
						utility += queries.supply_risk(next) * 0.8
				if utility > 0:
					add(result, "recruit", coord, utility, {"tier": tier, "capital": capital})
			# Most tiles cannot contribute useful tower cover. Avoid scanning every
			# tower on the board for their escalating price at every such tile.
			if tower_affordable and cell["unit"] == 0 and cell["capital"] < 0 and cell["building"] == "" and not cell["tree"] and not cell["grave"]:
				var cover := 0.0
				for next in [coord] + model.neighbors(coord):
					if model.cells[next]["owner"] == faction and Analysis.endangered(model, next, danger) and danger[next]["strength"] <= 2:
						cover += 65.0 if model.cells[next]["capital"] >= 0 else 12.0
						cover += queries.supply_risk(next) * 0.8
				if cover > 0 and model.can_build(coord, faction, "tower", capital):
					add(result, "tower", coord, cover, {"capital": capital})
			if city_sites.has(coord) and model.can_build(coord, faction, "city", capital) and Analysis.safe_spending(kingdom, model.CITY_COST, 0, queries):
				add(result, "city", coord, city_sites[coord], {"capital":capital})
			if model.can_develop(coord, faction) and not cell["tree"] and not cell["grave"] and not urgent and Analysis.safe_spending(kingdom,model.development_cost(coord),1,queries):
				add(result, "develop", coord, 2.0 / maxf(1.0, model.development_cost(coord)), {"capital": capital})
		result.append_array(Infrastructure.roads(model, kingdom, border, queries))
		if kingdom["gold"] >= model.BRIDGE_COST + 10 and Analysis.safe_spending(kingdom,model.BRIDGE_COST,-model.Catalog.BRIDGE_UPKEEP,queries):
			for site in model.bridge_targets(faction, capital):
				var benefit: float = queries.bridge_value(site,capital) + queries.bridge_campaign(site,capital) - model.BRIDGE_COST * 0.16
				if benefit > 0:
					add(result, "bridge", site, benefit, {"capital": capital})
	# Mana opportunities compete faction-wide, rather than kingdom iteration order.
	for spell in model.Spells.SPELLS:
		for coord in model.spell_targets(spell, faction):
			var cell: Dictionary = model.cells[coord]
			var utility := 0.0
			match spell:
				"summon":
					var kingdom: Dictionary = model.kingdom_at(coord)
					if Analysis.sustainable(model, kingdom, queries.unit_upkeep(1, faction), 0, queries):
						utility = 4.0 if queries.recruitment_value(coord,1) > 0 else 0.0
						if Analysis.endangered(model, coord, danger) and danger[coord]["strength"] == 1:
							utility += 15.0
				"shatter":
					if model.is_bridge(coord) and cell["unit"] > 0 and model.unit_faction(coord) != faction:
						utility = Analysis.UNIT_VALUE[cell["unit"]] * 0.65
					elif model.is_bridge(coord):
						utility = queries.bridge_threat_relief(coord,faction)
					if model.is_bridge(coord):
						utility -= queries.bridge_access_loss(coord,faction)
						if cell["unit"] > 0 and model.unit_faction(coord) == faction: utility -= Analysis.UNIT_VALUE[cell["unit"]]
				"trailblaze":
					utility = 7.0 if trail_useful else 0.0
			if utility > 0:
				add(result, "spell", coord, utility, {"spell": spell})
	# Save toward a needed forward city rather than spending every spare coin.
	# Urgent defence still takes precedence over infrastructure.
	result = result.filter(func(action):
		return not city_reserves.has(action.get("capital")) or action.kind == "city" or action.priority >= 55.0 or Analysis.endangered(model, action.coord, danger))
	result.sort_custom(func(a, b): return a["priority"] > b["priority"])
	return diverse(result, int(Analysis.profile(model)["candidates"]), false)

static func movements(model, faction: int, queries = null) -> Array:
	queries = Analysis.Queries.new(model) if queries == null else queries
	var result: Array = []
	var danger: Dictionary = queries.defense_needs(faction)
	var frontiers: Dictionary = {}
	for kingdom in model.kingdoms.values():
		if kingdom["owner"] == faction:
			frontiers[kingdom["capital"]] = queries.frontier(kingdom["capital"])
	for source in model.cells:
		if model.unit_faction(source) != faction or model.cells[source]["unit"] == 0 or model.cells[source]["moved"]:
			continue
		var shortlist: Array = []
		var support_capital: Vector2i = queries.support(source).get("capital", source)
		for target in queries.candidate_targets(source):
			if target == source:
				continue
			var cell: Dictionary = model.cells[target]
			var key := [Vector4i(target.x, target.y, faction, model.cells[source]["unit"]), support_capital]
			var value: Array
			if queries.movement_values.has(key):
				value = queries.movement_values[key]
			else:
				value = movement_value(model, source, target, faction, danger, frontiers, support_capital, queries)
				queries.movement_values[key] = value
			var score: float = value[0] + Analysis.variation(model, source, target)
			# The policy retains at most two options per unit. Avoid constructing
			# thousands of dictionaries that would immediately be discarded.
			var option := [score, target, value[1]]
			if shortlist.size() < 2:
				shortlist.append(option)
				shortlist.sort_custom(func(a, b): return a[0] > b[0])
			elif score > shortlist[1][0]:
				shortlist[1] = option
				if score > shortlist[0][0]:
					shortlist.reverse()
		for option in shortlist:
			add(result, "move", option[1], option[0], {"source": source, "reason": option[2]})
	result.sort_custom(func(a, b): return a["priority"] > b["priority"])
	return diverse(result, int(Analysis.profile(model)["candidates"]), true, model)

static func movement_value(model, source: Vector2i, target: Vector2i, faction: int, danger: Dictionary, frontiers: Dictionary, support_capital: Vector2i, queries) -> Array:
	var cell: Dictionary = model.cells[target]
	var score := -2.0
	var reason := "reposition"
	if model.has_wildlife(target):
		return [40.0 if cell.get("lair", "") != "" else 27.0,"clear a wildlife lair" if cell.get("lair", "") != "" else "hunt a dangerous animal"]
	if cell["owner"] != faction and not model.is_bridge(target):
		score = 8.0 + cell["value"] * 1.5
		reason = "capture land"
		if cell["capital"] >= 0:
			score += 22.0 + model.castle_neighbors(source, target).size() * 4.0
			reason = "capture capital"
		if cell["mana_source"]:
			score += 5.0
			reason = "capture source"
		if cell.get("treasure", 0) > 0:
			score += cell["treasure"] * 0.6
			reason = "collect treasure"
		if cell["owner"] >= 0:
			score += queries.campaign_value(target,faction)
			var disruption: float = queries.cut_value(target)
			score += disruption
			if disruption >= 12.0 and cell["capital"] < 0: reason = "cut enemy supply"
	if cell["unit"] > 0:
		if model.unit_faction(target) == faction:
			score = 6.0
			# Favor a merge that unlocks a reachable defended target.
			for next in frontiers.get(support_capital, {}):
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
		var before := 10000
		var after := 10000
		for border in frontiers.get(support_capital, {}):
			before = mini(before, model.distance(source, border))
			after = mini(after, model.distance(target, border))
		if after < before:
			score += (before - after) * 2.0
			reason = "advance toward the front"
		for next in [target] + queries.neighbors(target):
			if model.cells[next]["owner"] == faction and Analysis.endangered(model, next, danger):
				score += 35.0 if model.cells[next]["capital"] >= 0 else 4.0
				score += queries.supply_risk(next) * 0.8
				reason = "protect kingdom"
	if model.fortification_blocks_attack(source, target):
		score -= 8.0
		reason = "remove ward"
	if model.knight_duel(source, target):
		score -= 18.0
		reason = "trade knights"
	return [score, reason]

static func diverse(sorted: Array, limit: int, movement: bool, model = null) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	if movement:
		# Different destinations and ranks get a chance before interchangeable
		# Scouts consume every slot by proposing the same capture.
		var destinations := {}
		for candidate in sorted:
			var target: Vector2i = candidate["coord"]
			var tier: int = model.cells[candidate["source"]]["unit"] if model != null else 0
			var destination := Vector3i(target.x,target.y,tier)
			var source_key := str(candidate["source"])
			if destinations.has(destination) or seen.get(source_key,0) >= 2: continue
			destinations[destination] = true
			seen[source_key] = seen.get(source_key,0) + 1
			result.append(candidate)
			if result.size() >= limit: break
		# Where the budget permits, preserve a second departure square for the
		# same job: leaving one defender may be unsafe while another can move.
		for candidate in sorted:
			if result.size() >= limit: break
			if candidate in result: continue
			var target: Vector2i = candidate["coord"]
			var tier: int = model.cells[candidate["source"]]["unit"] if model != null else 0
			var destination := Vector3i(target.x,target.y,tier)
			var source_key := str(candidate["source"])
			if int(destinations.get(destination,0)) >= 2 or seen.get(source_key,0) >= 2: continue
			destinations[destination] = 2
			seen[source_key] = seen.get(source_key,0)+1
			result.append(candidate)
		result.sort_custom(func(a,b): return a["priority"] > b["priority"])
		return result
	if not movement:
		# Reserve a representative of every useful rank before filling the dock.
		# Total candidate and search budgets remain unchanged.
		for tier in [1,2,3]:
			for candidate in sorted:
				if candidate["kind"] == "recruit" and candidate["tier"] == tier:
					result.append(candidate)
					seen["recruit%d" % tier] = 1
					break
	# Retain alternatives across action kinds/units rather than one crowded dock.
	for candidate in sorted:
		var key: String = str(candidate["source"]) if movement else candidate.get("spell", candidate["kind"])
		if not movement and candidate["kind"] == "recruit": key = "recruit%d" % candidate["tier"]
		if not movement and candidate in result: continue
		if seen.get(key, 0) >= 2:
			continue
		seen[key] = seen.get(key, 0) + 1
		result.append(candidate)
		if result.size() >= limit:
			break
	if not movement: result.sort_custom(func(a,b): return a["priority"] > b["priority"])
	return result

static func apply(model, action: Dictionary, faction: int) -> bool:
	match action["kind"]:
		"entrench": return model.entrench(action["coord"], faction)
		"move": return model.move_unit(action["source"], action["coord"])
		"road": return model.build_road(action["source"], action["coord"], faction)
		"recruit": return model.recruit(action["coord"], faction, action["tier"], action["capital"])
		"spell": return model.cast_spell(action["spell"], action["coord"], faction)
		"develop": return model.develop(action["coord"], faction)
		_: return model.build_structure(action["coord"], faction, action["kind"], action["capital"])
