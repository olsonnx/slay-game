extends RefCounted
## Faction objectives, reserved assignments and bounded local tactics.
## Worker-owned read-only position. No whole-board branch simulation.
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
var state
var faction: int
var spending: bool
var queries
var context: Dictionary
var units: Array = []
var options_by_region: Dictionary = {}
var reserved: Dictionary = {}
var danger: Dictionary = {}
var replies: Dictionary = {}
var enemy_capitals: Array = []
var enemy_armies: Dictionary = {}
var expiring_enemy_barriers := false
var objective_values: Dictionary = {}
var best: Dictionary = {}
var best_sequence: Array = []
var best_score := 0.0
var evaluated := 0
var done := false
var initialized := false
var unit_head := 0
var max_step_usec := 0
var started_usec := Time.get_ticks_usec()
var planning_usec := 0

func _init(model, owner: int, preparation := false, owns_snapshot := false, memory: Dictionary = {}, preparation_cache: Dictionary = {}) -> void:
	state = model if owns_snapshot else Analysis.snapshot(model)
	faction = owner
	spending = preparation
	queries = Analysis.Queries.new(state, preparation_cache)
	context = memory.duplicate(true)

func signature() -> Array:
	var result: Array = [faction]
	for coord in state.cells:
		var cell: Dictionary = state.cells[coord]
		if cell["capital"] >= 0 or state.is_bridge(coord) or state.is_barrier(coord):
			result.append([coord, cell["owner"], cell["capital"], cell["building"], cell.get("unit_owner", -1) if state.is_bridge(coord) else -1, cell.get("barrier_by", -1)])
	return result

func objective(coord: Vector2i) -> Dictionary:
	if not objective_values.has(coord): objective_values[coord] = build_objective(coord)
	return objective_values[coord]

func build_objective(coord: Vector2i) -> Dictionary:
	var cell: Dictionary = state.cells[coord]
	if state.has_wildlife(coord):
		return {"priority":40.0 if cell.get("lair", "") != "" else 27.0,"reason":"clear a wildlife lair" if cell.get("lair", "") != "" else "hunt a dangerous animal","kind":"capture"}
	if cell["owner"] != faction and not state.is_bridge(coord):
		var score: float = 8.0 + cell["value"] * 1.5
		var distance_to_goal := 100000
		for capital in enemy_capitals: distance_to_goal = mini(distance_to_goal, state.distance(coord, capital))
		score += maxf(0.0, 14.0 - distance_to_goal * 1.2)
		if cell["building"] == "city": score += 14.0
		var reason := "take a recruitment city" if cell["building"] == "city" else "expand territory"
		if cell.get("treasure", 0) > 0:
			score += cell["treasure"] * 0.6
			reason = "collect treasure"
		if cell["capital"] >= 0:
			score += 28.0
			reason = "take enemy capital"
		if cell.get("mana_source", false):
			score += 7.0
			reason = "secure mana source" if cell["capital"] < 0 else reason
		return {"priority": score, "reason": reason, "kind": "capture"}
	if cell["unit"] > 0 and state.unit_faction(coord) != faction:
		return {"priority": 12.0 + Analysis.UNIT_VALUE[cell["unit"]] * 0.4, "reason": "clear hostile crossing", "kind": "capture"}
	if cell["tree"] or cell["grave"]:
		var bank: Dictionary = queries.support(coord)
		var urgent := false
		if not bank.is_empty():
			var summary: Dictionary = queries.bank_summary(bank)
			urgent = summary["income"] - summary["upkeep"] < 0
		return {"priority": (8.0 + cell["value"] * 2.0) if urgent else (3.0 + cell["value"] * 0.8), "reason": "restore income", "kind": "restore"}
	var value := 0.0
	for next in [coord] + queries.neighbors(coord):
		if state.cells[next]["owner"] == faction and danger.has(next):
			value += 70.0 if state.cells[next]["capital"] >= 0 else state.cells[next]["value"] * 2.0
	return {"priority": value, "reason": "defend threatened territory", "kind": "defend"}

func initialize() -> void:
	if spending:
		# Preparation shares the cheap purchase pass; movement objectives and
		# per-unit reservations would be thrown away immediately afterwards.
		initialized = true
		return
	danger = queries.defense_needs(faction)
	var current := signature()
	if context.get("signature", []) != current:
		context = {"signature": current, "objectives": {}, "builds": int(context.get("builds", 0)) + 1}
	for coord in state.cells:
		if state.cells[coord].get("barrier_by", -1) >= 0 and state.cells[coord].barrier_by != faction: expiring_enemy_barriers = true
		if state.cells[coord]["capital"] >= 0 and state.cells[coord]["owner"] != faction: enemy_capitals.append(coord)
		if state.cells[coord]["unit"] > 0 and state.unit_faction(coord) == faction and not state.cells[coord]["moved"]:
			units.append(coord)
	units.sort_custom(func(a, b):
		if state.cells[a]["unit"] != state.cells[b]["unit"]: return state.cells[a]["unit"] > state.cells[b]["unit"]
		return a.x < b.x if a.x != b.x else a.y < b.y)
	initialized = true

func region_options(source: Vector2i, limit := 0) -> Array:
	var region: Dictionary = queries.region(source)
	var key := Vector3i(source.x, source.y, limit)
	if options_by_region.has(key): return options_by_region[key]
	var result: Array = []
	var before := distance_to_front(source, region)
	if not region.has("merge_strengths"):
		region["merge_strengths"] = {}
		for border in region["boundary"]: region["merge_strengths"][queries.defense(border)] = true
	for target in queries.candidate_targets(source):
		var cell: Dictionary = state.cells[target]
		var goal := objective(target)
		if cell["unit"] > 0 and state.unit_faction(target) == faction:
			if not region["merge_strengths"].has(cell["unit"]): continue
			goal = {"priority": 18.0, "reason": "combine units to breach frontier", "kind": "merge"}
		if goal["priority"] <= 0 and cell["owner"] == faction:
			var after := distance_to_front(target, region)
			if after < before: goal = {"priority":4.0 + (before - after) * 2.0, "reason":"advance toward the front", "kind":"advance"}
		if goal["priority"] <= 0: continue
		# Refresh local defence needs without discarding faction objectives. New
		# frontier sites extend the plan; captured goals retire naturally.
		if goal["kind"] == "capture" and context["objectives"].has(target):
			goal = context["objectives"][target]
		else:
			context["objectives"][target] = goal
		# Supply depends on current banks and army positions, so refresh it even
		# when the long-term capital objective is reused.
		goal = goal.duplicate()
		if cell["owner"] >= 0 and cell["owner"] != faction:
			var disruption: float = queries.cut_value(target)
			goal["priority"] += disruption + queries.campaign_value(target,faction)
			if disruption >= 12.0 and cell["capital"] < 0: goal["reason"] = "cut enemy supply"
		var option := [target, goal]
		if limit <= 0:
			result.append(option)
		else:
			var index := result.bsearch_custom(option, option_before)
			if index < limit:
				result.insert(index, option)
				if result.size() > limit: result.pop_back()
	if limit <= 0: result.sort_custom(option_before)
	options_by_region[key] = result
	return result

func option_before(a: Array, b: Array) -> bool:
	if a[1]["priority"] != b[1]["priority"]: return a[1]["priority"] > b[1]["priority"]
	return a[0].x < b[0].x if a[0].x != b[0].x else a[0].y < b[0].y

func distance_to_front(coord: Vector2i, region: Dictionary) -> int:
	if not region.has("front_distances"): region["front_distances"] = {}
	var distances: Dictionary = region["front_distances"]
	if not distances.has(coord):
		var nearest := 10000
		for border in region["boundary"]:
			if state.is_bridge(border) and state.cells[border]["unit"] == 0: continue
			nearest = mini(nearest, state.distance(coord, border))
		distances[coord] = nearest
	return distances[coord]

func defence_without(source: Vector2i, protected: Vector2i) -> int:
	var value := 0
	for next in [protected] + queries.neighbors(protected):
		var cell: Dictionary = state.cells[next]
		if cell["owner"] != faction: continue
		var local: int = 0 if next == source else cell["unit"]
		if cell["capital"] >= 0: local = maxi(local, 1)
		if cell["building"] == "tower": local = maxi(local, 2)
		if next != protected: local = mini(local, 2)
		value = maxi(value, local)
	var defended: Dictionary = state.cells[protected]
	if defended["owner"] != faction: return value
	if defended.get("site_defense_aura", false) and defended.get("building", "") == "monument": return value + 1
	if source != protected: return preload("res://src/game/event_sites.gd").defense_bonus(state, protected, value)
	return value

func exposure(source: Vector2i, target: Vector2i) -> float:
	var blocked: bool = state.fortification_blocks_attack(source, target)
	var landing: Vector2i = state.Movement.blocked_landing(state, source, target) if blocked else target
	if blocked and landing == source: return 0.0
	var loss := 0.0
	var rank: int = state.cells[source]["unit"]
	for protected in [source] + queries.neighbors(source):
		if state.cells[protected]["owner"] != faction or not danger.has(protected): continue
		var after := defence_without(source, protected)
		if state.distance(protected, landing) <= 1 and (blocked or not state.knight_duel(source, target)): after = maxi(after, rank if protected == landing else mini(rank, 2))
		if danger[protected]["strength"] > after and queries.defense(protected) >= danger[protected]["strength"]:
			var cell: Dictionary = state.cells[protected]
			var remaining_unit: int = 0 if protected == source else cell["unit"]
			loss += 110.0 if cell["capital"] >= 0 else 1.5 + (0.0 if cell["tree"] or cell["grave"] else cell["value"] * 0.8) + Analysis.UNIT_VALUE[remaining_unit] * 0.8
			loss += queries.supply_risk(protected)
	return loss * Analysis.profile(state)["risk"]

func tactical_score(source: Vector2i, target: Vector2i, goal: Dictionary) -> float:
	var score: float = goal["priority"] - state.distance(source, target) * 0.25
	var rank: int = state.cells[source]["unit"]
	var cell: Dictionary = state.cells[target]
	if goal["kind"] == "defend":
		var improved := false
		for next in [target] + queries.neighbors(target):
			var protection: int = rank if next == target else mini(rank, 2)
			if danger.has(next) and state.cells[next]["owner"] == faction and danger[next]["strength"] <= protection and queries.defense(next) < danger[next]["strength"]: improved = true
		if not improved: return -1000.0
		for next in [target] + queries.neighbors(target):
			if danger.has(next) and state.cells[next]["owner"] == faction and danger[next]["strength"] <= (rank if next == target else mini(rank,2)):
				score += queries.supply_risk(next) * 0.8
	if state.fortification_blocks_attack(source, target):
		score -= 9.0
	elif state.knight_duel(source, target):
		# A trade gains no land immediately. Permit it only when a ready follower
		# can use the opening and it is worth sacrificing the Knight.
		var follower := false
		var remaining_defence := 1 if cell["capital"] >= 0 else 2 if cell["building"] == "tower" else 0
		for next in queries.neighbors(target):
			if state.cells[next]["owner"] == cell["owner"]: remaining_defence = maxi(remaining_defence, state.local_defense(next))
		for other in units:
			if other != source and not reserved.has(other) and state.cells[other]["unit"] > remaining_defence and queries.region(other)["id"] == queries.region(source)["id"] and exposure(other, target) < goal["priority"]: follower = true
		score = goal["priority"] * 0.7 - 8.0 if follower and state.ai_difficulty != "easy" else -1000.0
	elif cell["unit"] > 0 and state.unit_faction(target) != faction:
		score += Analysis.UNIT_VALUE[cell["unit"]] * 0.4
	if (cell["owner"] != faction or state.is_bridge(target)) and state.ai_difficulty != "easy":
		if not replies.has(target):
			var strength := 0
			var removed: Array = state.castle_neighbors(source, target) if cell["capital"] >= 0 else []
			var seen: Dictionary = {}
			for next in [target] + queries.neighbors(target):
				var owner: int = state.unit_faction(next) if state.cells[next]["unit"] > 0 else state.cells[next]["owner"]
				if owner < 0 or owner == faction or state.is_mountain(next) or state.is_barrier(next): continue
				var region: Dictionary = queries.region(next)
				if seen.has(region["id"]): continue
				seen[region["id"]] = true
				if not enemy_armies.has(region["id"]):
					var army: Array = []
					for coord in region["members"]:
						if state.cells[coord]["unit"] > 0: army.append(coord)
					enemy_armies[region["id"]] = army
				for coord in enemy_armies[region["id"]]:
					# Settlement precedes movement: troops in a newly bankrupt
					# detached bank cannot make the imagined counterattack.
					if coord != target and coord not in removed and queries.attack_reach(coord, target) and not queries.cut_starves(target,coord): strength = maxi(strength, state.cells[coord]["unit"])
			# Legacy barriers can split today's regions, then reconnect an enemy
			# army at settlement. The normal local-region shortcut misses it.
			if expiring_enemy_barriers: strength = maxi(strength,queries.reply_strength(target,faction))
			replies[target] = strength
		var reply: int = replies[target]
		var after_defence := rank
		for next in queries.neighbors(target):
			if next != source and state.cells[next]["owner"] == faction: after_defence = maxi(after_defence, state.local_defense(next))
		if reply > after_defence: score -= Analysis.UNIT_VALUE[rank] * (1.3 if state.ai_difficulty == "hard" else 1.0) + goal["priority"] * 0.7
	return score - exposure(source, target) + Analysis.variation(state, source, target)

func assign_unit(source: Vector2i) -> void:
	var chosen: Dictionary = {}
	var value := 0.5
	var limit: int = 16 if state.ai_difficulty == "easy" else 40 if state.ai_difficulty == "normal" else 64
	var checked := 0
	# At most reserved.size() targets and the departure square can be skipped.
	# This retains exactly the same first `limit` eligible tactical candidates
	# without storing/sorting the remainder. Objective memory is still refreshed.
	for option in region_options(source, limit + reserved.size() + 1):
		var target: Vector2i = option[0]
		if target == source or reserved.has(target) or reserved.has(source): continue
		var score := tactical_score(source, target, option[1])
		evaluated += 1
		checked += 1
		if score > value:
			value = score
			chosen = {"kind": "move", "source": source, "coord": target, "priority": score, "reason": option[1]["reason"], "expected_tier": state.cells[source]["unit"], "target_owner": state.cells[target]["owner"]}
		if checked >= limit: break
	if not chosen.is_empty():
		reserved[chosen["coord"]] = true
		reserved[source] = true
		best_sequence.append(chosen)
		if best.is_empty(): best = chosen
		best_score += value

func step() -> bool:
	var started := Time.get_ticks_usec()
	if not done:
		if not initialized:
			initialize()
		elif spending:
			var options: Array = Candidates.preparation(state, faction, queries)
			evaluated = options.size()
			if not options.is_empty() and options[0]["priority"] > 0:
				best = options[0]
				best_sequence = [best]
				best_score = best["priority"]
			done = true
		elif unit_head < units.size():
			assign_unit(units[unit_head])
			unit_head += 1
		else:
			done = true
	max_step_usec = maxi(max_step_usec, Time.get_ticks_usec() - started)
	planning_usec += Time.get_ticks_usec() - started
	return done

func run() -> Dictionary:
	while not step(): pass
	return best
