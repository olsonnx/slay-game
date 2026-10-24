extends RefCounted
## Read-only memoization for one immutable search position or candidate pass.
## Never attach this to live rules: discard it before any model mutation.
var model
const Catalog = preload("res://src/game/game_catalog.gd")
var routes: Dictionary = {}
var regions: Dictionary = {}
var targets: Dictionary = {}
var frontiers: Dictionary = {}
var danger: Dictionary = {}
var defenses: Dictionary = {}
var banks: Dictionary = {}
var banks_ready := false
var supports: Dictionary = {}
var adjacent: Dictionary = {}
var candidate_sets: Dictionary = {}
var movement_values: Dictionary = {}
const Supply = preload("res://src/game/ai_supply.gd")
var supply_cuts: Dictionary = {}
var recruitment_values: Dictionary = {}
var unfilled_jobs: Dictionary = {}
var needs: Dictionary = {}
var bridge_shores: Dictionary = {}
var army_strengths: Dictionary = {}
var frontier_replies: Dictionary = {}
var supply_risks: Dictionary = {}
var bank_pressure: Dictionary = {}
var campaign_values: Dictionary = {}
var bridge_plans: Dictionary = {}
var bridge_losses: Dictionary = {}
var removed_routes: Dictionary = {}

func reply_strength(target: Vector2i, faction: int) -> int:
	var key := Vector3i(target.x,target.y,faction)
	if frontier_replies.has(key): return frontier_replies[key]
	var strength := 0
	for next in [target] + neighbors(target):
		var owner: int = model.unit_faction(next) if model.cells[next]["unit"] > 0 else model.cells[next]["owner"]
		if owner < 0 or owner == faction or model.is_mountain(next) or model.is_barrier(next): continue
		var component := region(next)
		if not army_strengths.has(component["id"]):
			var rank := 0
			for member in component["members"]:
				if model.unit_faction(member) != owner or model.cells[member]["unit"] == 0: continue
				var home := support(member)
				if home.is_empty(): continue
				var summary := bank_summary(home)
				if home["gold"] + summary["income"] - summary["upkeep"] < 0: continue
				rank = maxi(rank,model.cells[member]["unit"])
			army_strengths[component["id"]] = rank
		strength = maxi(strength,army_strengths[component["id"]])
	frontier_replies[key] = strength
	return strength

func supply_risk(coord: Vector2i) -> float:
	if supply_risks.has(coord): return supply_risks[coord]
	var bank: Dictionary = model.kingdom_at(coord)
	if bank.is_empty() or bank["capital"] == coord: return 0.0
	var ring := {}
	for next in neighbors(coord):
		if not model.is_mountain(next) and (model.cells[next]["kingdom"] == bank["capital"] or model.is_bridge(next)): ring[next] = true
	# A connected surviving neighbour ring proves this is not a supply neck.
	# Avoid a bank-wide graph pass for ordinary exposed border land.
	var risk := 0.0
	if ring.size() >= 2 and ring.size() <= 4:
		var pending := [ring.keys()[0]]
		var seen := {pending[0]:true}
		while not pending.is_empty():
			var current: Vector2i = pending.pop_back()
			for next in ring:
				if not seen.has(next) and model.distance(current,next) == 1:
					seen[next] = true
					pending.append(next)
		if seen.size() != ring.size(): risk = cut_value(coord)
	supply_risks[coord] = risk
	return risk

func campaign_value(coord: Vector2i, faction: int) -> float:
	var key := Vector3i(coord.x,coord.y,faction)
	if campaign_values.has(key): return campaign_values[key]
	var bank: Dictionary = model.kingdom_at(coord)
	var value := 0.0
	if not bank.is_empty() and bank["owner"] != faction:
		var capital: Vector2i = bank["capital"]
		if not bank_pressure.has(capital):
			var summary := bank_summary(bank)
			var net: int = summary["income"]-summary["upkeep"]
			var pressure := minf(12.0,summary["income"]*0.075 + bank["gold"]*0.025)
			# Already doomed armies are less urgent than the core funding a recovery.
			if bank["gold"] + net < 0: pressure *= 0.25
			bank_pressure[capital] = pressure
		value = bank_pressure[capital] * (2.0 if coord == capital else 1.0)
		value += maxf(0.0,5.0-model.distance(coord,capital))*0.5
	campaign_values[key] = value
	return value

func cut_value(coord: Vector2i) -> float:
	var bank: Dictionary = model.kingdom_at(coord)
	if bank.is_empty() or coord == bank["capital"]: return 0.0
	var capital: Vector2i = bank["capital"]
	if not supply_cuts.has(capital): supply_cuts[capital] = Supply.bank_cuts(model,bank,self)
	return supply_cuts[capital].get(coord,{}).get("score",0.0)

func cut_starves(cut: Vector2i, source: Vector2i) -> bool:
	var bank: Dictionary = model.kingdom_at(cut)
	if bank.is_empty() or model.is_bridge(source) or model.cells[source]["kingdom"] != bank["capital"]: return false
	cut_value(cut)
	if not supply_cuts.has(bank["capital"]): return false
	var analysis: Dictionary = supply_cuts[bank["capital"]]
	if not analysis.has(cut) or not analysis["indices"].has(source): return false
	var index: int = analysis["indices"][source]
	var detail: Dictionary = analysis[cut]
	for interval in detail["doomed"]:
		if index >= interval.x and index <= interval.y: return true
	if detail["retained_starves"]:
		for interval in detail["detached"]:
			if index >= interval.x and index <= interval.y: return false
		return source != cut
	return false

func capture_value(coord: Vector2i, faction: int) -> float:
	var cell: Dictionary = model.cells[coord]
	var value: float = 6.0 + cell["value"] * 1.2
	if cell.get("lair", "") != "": value += 24.0
	if cell.get("animal", "") != "": value += 12.0
	if cell["owner"] >= 0 and cell["owner"] != faction: value += 5.0 + cut_value(coord)
	if cell["capital"] >= 0: value += 30.0
	if cell["mana_source"]: value += 5.0
	if cell["building"] == "monument":
		value += float(cell.get("site_income",0))*4.0+float(cell.get("site_mana",0))*8.0
		if cell.get("site_steel",false): value += 12.0
	if cell["unit"] > 0: value += [0.0,4.0,8.0,14.0][cell["unit"]]
	if model.is_bridge(coord) and cell["unit"] > 0 and model.unit_faction(coord) != faction: value += 8.0
	value += campaign_value(coord,faction)
	return value

func recruitment_value(coord: Vector2i, tier: int) -> float:
	var component := region(coord)
	var previous: int = model.cells[coord]["unit"]
	var key := Vector3i(component["id"],tier,previous)
	if recruitment_values.has(key): return recruitment_values[key]
	var faction: int = model.cells[coord]["owner"]
	var unmet := recruitment_jobs(coord)
	component["ready_strength"] = component["free_strength"]
	var best := 0.0
	var count := 0
	for target in component["boundary"]:
		if model.cells[target]["owner"] == faction and not model.has_wildlife(target): continue
		if model.is_bridge(target) and (model.cells[target]["unit"] == 0 or model.unit_faction(target) == faction): continue
		var protection := defense(target)
		# Pay for the cheapest rank that opens this target. An upgrade must add
		# a capability the current unit lacks, not just another wage obligation.
		if tier <= protection: continue
		var reply := reply_strength(target,faction) if tier >= 2 and tier > component["ready_strength"] else 0
		var reserve_role: bool = reply >= 2 and tier == reply and previous < reply and component["ready_strength"] < reply
		if not unmet.has(target) and not reserve_role: continue
		if previous > protection and not reserve_role: continue
		var value := capture_value(target,faction)
		# An upgrade that makes an unsafe capture supportable deserves the same
		# landing value as recruiting a new reserve, with its lower real cost.
		# One combat reserve can hold expansion against the visible army beyond
		# the neutral buffer; stop paying this premium once that role is filled.
		if reserve_role: value += 12.0 + reply * 6.0
		# Price the first unit that can break this defence more highly than
		# another of a rank the ready army already supplies. This gives a
		# Knight a role even when the defended border tile itself is poor.
		if protection >= 1 and tier == protection + 1 and component["ready_strength"] <= protection:
			value += protection * 4.0
		if tier > protection + 1 and not reserve_role: value *= 0.25
		best = maxf(best,value)
		count += 1
	# A breach enables continued campaigning, not only the first captured hex.
	# Keep that bounded premium below capital defence and retain real wages.
	var result := best * 1.7 + minf(4.0,count) * 1.5 if count > 0 else 0.0
	recruitment_values[key] = result
	return result

func recruitment_jobs(coord: Vector2i) -> Dictionary:
	var component := region(coord)
	if unfilled_jobs.has(component["id"]): return unfilled_jobs[component["id"]]
	var faction: int = model.cells[coord]["owner"]
	var available: Array = []
	var jobs: Array = []
	for member in component["members"]:
		if model.cells[member]["unit"] > 0 and not model.cells[member]["moved"] and model.unit_faction(member) == faction: available.append(member)
	# Keep a necessary capital defender available for its defensive job.
	var threats_here := defense_needs(faction)
	for member in component["members"]:
		if model.cells[member]["capital"] < 0 or not threats_here.has(member): continue
		var needed: int = threats_here[member]["strength"]
		if needed <= 1: continue
		var permanent := 1
		for next in neighbors(member):
			if model.cells[next]["owner"] == faction and model.cells[next]["building"] == "tower": permanent = 2
		if permanent >= needed: continue
		for source in available:
			var protection: int = model.cells[source]["unit"] if source == member else mini(2, model.cells[source]["unit"]) if model.distance(source,member) == 1 and model.cells[source]["owner"] == faction else 0
			if protection >= needed:
				available.erase(source)
				break
	available.sort_custom(func(a,b): return model.cells[a]["unit"] < model.cells[b]["unit"])
	component["free_units"] = available.duplicate()
	component["free_strength"] = 0
	for source in available: component["free_strength"] = maxi(component["free_strength"],model.cells[source]["unit"])
	for target in component["boundary"]:
		if model.cells[target]["owner"] == faction and not model.has_wildlife(target) or model.is_bridge(target) and (model.cells[target]["unit"] == 0 or model.unit_faction(target) == faction): continue
		if defense(target) < 3: jobs.append(target)
	jobs.sort_custom(func(a,b):
		if defense(a) != defense(b): return defense(a) > defense(b)
		if model.cells[a]["capital"] != model.cells[b]["capital"]: return model.cells[a]["capital"] > model.cells[b]["capital"]
		return a.x < b.x if a.x != b.x else a.y < b.y)
	var unmet := {}
	for target in jobs:
		var assigned := false
		for source in available:
			if model.cells[source]["unit"] > defense(target):
				available.erase(source)
				assigned = true
				break
		if not assigned: unmet[target] = true
	unfilled_jobs[component["id"]] = unmet
	return unmet

func defense_needs(faction: int) -> Dictionary:
	if needs.has(faction): return needs[faction]
	var direct := threats(faction)
	# Existing threat records are immutable; only replace projected entries.
	var result: Dictionary = direct.duplicate()
	# Two ready-on-their-turn attackers can breach the approach then take the
	# capital. Count only followers strong enough to beat its current defence.
	for bank in model.kingdoms.values():
		if bank["owner"] != faction: continue
		var capital: Vector2i = bank["capital"]
		for approach in neighbors(capital):
			if model.cells[approach]["owner"] != faction or not direct.has(approach): continue
			var sources: Array = direct[approach]["sources"]
			var attackers := {}
			var strength := 0
			for source in sources:
				var rank: int = model.cells[source]["unit"]
				if rank > defense(approach) and rank > defense(capital):
					var owner: int = model.unit_faction(source)
					if not attackers.has(owner): attackers[owner] = [0,0]
					attackers[owner][0] += 1
					attackers[owner][1] = maxi(attackers[owner][1],rank)
					if attackers[owner][0] >= 2: strength = maxi(strength,attackers[owner][1])
			if strength > 0 and (not result.has(capital) or result[capital]["strength"] < strength):
				result[capital] = {"strength":strength,"sources":sources,"projected":true}
	needs[faction] = result
	return result

func bridge_value(site: Vector2i, capital: Vector2i) -> float:
	var key := [site,capital]
	if bridge_plans.has(key): return bridge_plans[key]["value"]
	var faction: int = model.cells[capital]["owner"]
	var current: Dictionary = frontier(capital)
	var banks_seen := {}
	var new_targets := {}
	for next in neighbors(site):
		if model.is_mountain(next) or model.is_barrier(next): continue
		if model.is_bridge(next):
			# A bridge chain can reach a new shore without placing another land tile.
			if model.cells[next]["unit"] > 0 and model.unit_faction(next) != faction: continue
			var other := region_for_bridge(next,faction)
			if not other.is_empty():
				for target in other:
					if model.cells[target]["owner"] == faction:
						var bank: Vector2i = model.cells[target]["kingdom"]
						if bank != capital and model.kingdoms.has(bank): banks_seen[bank] = true
					elif not current.has(target): new_targets[target] = true
		elif model.cells[next]["owner"] == faction:
			var bank: Vector2i = model.cells[next]["kingdom"]
			if bank != capital and model.kingdoms.has(bank): banks_seen[bank] = true
		elif not current.has(next): new_targets[next] = true
	# Filling an internal hole adds neither new frontier nor another bank.
	var value := banks_seen.size() * 14.0
	for target in new_targets:
		if model.cells[target]["owner"] != faction and not model.is_bridge(target):
			value += 3.0 if model.cells[target]["owner"] < 0 else 5.0
	value = minf(value,35.0)
	bridge_plans[key] = {"value":value,"targets":new_targets}
	return value

func bridge_campaign(site: Vector2i, capital: Vector2i) -> float:
	# Price a crossing with a usable landing force, not merely exposed shore.
	# No simulated boards: inspect at most the new frontier and current bank.
	bridge_value(site,capital)
	var plan: Dictionary = bridge_plans[[site,capital]]
	if plan.has("campaign"): return plan["campaign"]
	plan["campaign"] = 0.0
	if plan["targets"].is_empty(): return 0.0
	var bank: Dictionary = model.kingdoms[capital]
	var faction: int = bank["owner"]
	if not recruitment_jobs(capital).is_empty(): return 0.0
	var component := region(capital)
	var finances := bank_summary(bank)
	var best := 0.0
	var viable := 0
	for target in plan["targets"]:
		if model.is_bridge(target) or defense(target) >= 3: continue
		var rank := maxi(defense(target)+1,reply_strength(target,faction))
		var affordable := false
		for source in component["members"]:
			var cell: Dictionary = model.cells[source]
			if model.unit_faction(source) != faction: continue
			if cell["unit"] >= rank and component["free_units"].has(source):
				affordable = true
				break
			# Upgrading a necessary guard does not free it for the landing.
			if cell["unit"] > 0 and not component["free_units"].has(source): continue
			var price: int = model.recruitment_cost(source,faction,rank,capital)
			var wages: int = model.unit_upkeep(rank,faction) - model.unit_upkeep(cell["unit"],faction)
			if price >= 0 and bank["gold"] >= model.BRIDGE_COST + price + 10 and finances["income"] - finances["upkeep"] - wages >= 0:
				affordable = true
				break
		if not affordable: continue
		viable += 1
		best = maxf(best,capture_value(target,faction)*0.5)
	if viable > 0: plan["campaign"] = minf(24.0,6.0+best+mini(4,viable)*2.0)
	return plan["campaign"]

func bridge_access_loss(site: Vector2i, faction: int) -> float:
	var key := Vector3i(site.x,site.y,faction)
	if bridge_losses.has(key): return bridge_losses[key]
	var loss := 0.0
	for bank in model.kingdoms.values():
		if bank["owner"] != faction: continue
		var capital: Vector2i = bank["capital"]
		var before := friendly_routes(capital)
		if not before.has(site): continue
		var after := routes_without(capital,site)
		var remaining_front := {}
		var strength := 0
		for coord in before:
			if model.unit_faction(coord) == faction: strength = maxi(strength,model.cells[coord]["unit"])
			if model.cells[coord]["owner"] == faction and not after.has(coord): loss += 3.0
		for coord in after:
			for target in neighbors(coord): remaining_front[target] = true
		for target in frontier(capital):
			if target == site or remaining_front.has(target) or model.is_bridge(target): continue
			if strength > defense(target): loss += 4.0 if model.cells[target]["owner"] < 0 else 6.0
	loss = minf(36.0,loss)
	bridge_losses[key] = loss
	return loss

func routes_without(source: Vector2i, removed: Vector2i) -> Dictionary:
	if source == removed: return {}
	var faction: int = model.unit_faction(source)
	var key := [removed,source,faction]
	if removed_routes.has(key): return removed_routes[key]
	var result := {source:true}
	var pending := [source]
	while not pending.is_empty():
		var current: Vector2i = pending.pop_back()
		for next in neighbors(current):
			if next == removed or result.has(next) or model.is_mountain(next) or model.is_barrier(next): continue
			var cell: Dictionary = model.cells[next]
			if cell["owner"] == faction or model.is_bridge(next) and (cell["unit"] == 0 or model.unit_faction(next) == faction):
				result[next] = true
				pending.append(next)
	for member in result: removed_routes[[removed,member,faction]] = result
	return result

func bridge_threat_relief(site: Vector2i, faction: int) -> float:
	var relief := 0.0
	var danger_here := defense_needs(faction)
	for protected in neighbors(site):
		if model.cells[protected]["owner"] != faction or not danger_here.has(protected): continue
		var threat: int = danger_here[protected]["strength"]
		if threat < defense(protected) or threat == defense(protected) and not (threat == 3 and model.cells[protected]["unit"] == 3): continue
		var remaining := 0
		var seen := {}
		for source in danger_here[protected]["sources"]:
			if source == site or seen.has(source): continue
			var component := routes_without(source,site)
			var touches := false
			for next in neighbors(protected):
				if component.has(next): touches = true
			for member in component:
				seen[member] = true
				if touches and model.cells[member]["unit"] > 0 and model.unit_faction(member) == model.unit_faction(source): remaining = maxi(remaining,model.cells[member]["unit"])
		if remaining >= threat: continue
		var saved: float = 80.0 if model.cells[protected]["capital"] >= 0 else 10.0 + supply_risk(protected)*0.6
		if remaining > defense(protected): saved = (threat-remaining)*2.0
		relief = maxf(relief,saved)
	return relief

func region_for_bridge(site: Vector2i, faction: int) -> Dictionary:
	var key := Vector3i(site.x,site.y,faction)
	if bridge_shores.has(key): return bridge_shores[key]
	# Empty neutral bridges have no faction of their own. Cache the shores of
	# their bridge-only component, including any friendly banks it reconnects.
	var result := {}
	var pending := [site]
	var seen := {site:true}
	while not pending.is_empty():
		var coord: Vector2i = pending.pop_back()
		for next in neighbors(coord):
			if model.is_mountain(next) or model.is_barrier(next): continue
			if not model.is_bridge(next):
				result[next] = true
			elif not seen.has(next) and (model.cells[next]["unit"] == 0 or model.unit_faction(next) == faction):
				seen[next] = true
				pending.append(next)
	for coord in seen: bridge_shores[Vector3i(coord.x,coord.y,faction)] = result
	return result

func neighbors(coord: Vector2i) -> Array:
	if not adjacent.has(coord):
		adjacent[coord] = model.neighbors(coord)
	return adjacent[coord]

func candidate_targets(source: Vector2i) -> Array:
	# Search enumeration needs destination membership, not source-rooted paths.
	# Regions are immutable here; authoritative commands still build/validate paths.
	if model.cells[source]["moved"] or model.is_mountain(source) or model.is_barrier(source):
		return []
	var component := region(source)
	var strength: int = model.cells[source]["unit"]
	var key := Vector2i(component["id"], strength)
	if not candidate_sets.has(key):
		var result: Array = []
		var faction: int = model.unit_faction(source)
		for coord in component["members"]:
			var cell: Dictionary = model.cells[coord]
			if (cell["building"] in ["", "monument"] or model.is_bridge(coord)) and (cell["unit"] == 0 or cell["unit"] == strength and strength < 3):
				result.append(coord)
		for coord in component["boundary"]:
			var protection: int = model.attack_defense(coord,faction) if model.has_wildlife(coord) else defense(coord)
			if (model.cells[coord]["owner"] != faction or model.is_bridge(coord) or model.has_wildlife(coord)) and (strength > protection or strength == 3 and model.cells[coord]["unit"] == 3 and model.unit_faction(coord) != faction):
				result.append(coord)
		candidate_sets[key] = result
	return candidate_sets[key]

func _init(state) -> void:
	model = state

func friendly_routes(source: Vector2i) -> Dictionary:
	if not routes.has(source):
		routes[source] = model.friendly_routes(source)
	return routes[source]

func reachable_targets(source: Vector2i) -> Dictionary:
	if not targets.has(source):
		targets[source] = model.reachable_targets(source)
	return targets[source]

func defense(coord: Vector2i) -> int:
	if not defenses.has(coord):
		defenses[coord] = model.defense(coord)
	return defenses[coord]

func support(coord: Vector2i) -> Dictionary:
	if not supports.has(coord):
		supports[coord] = model.unit_kingdom(coord)
	return supports[coord]

func bank_summary(kingdom: Dictionary) -> Dictionary:
	var capital: Vector2i = kingdom["capital"]
	if not banks_ready:
		# The public upkeep query scans off-land units for each kingdom. A search
		# position is immutable, so account for every unit once across all banks.
		for bank in model.kingdoms.values():
			banks[bank["capital"]] = {"income": model.income(bank), "upkeep": 0}
		for coord in model.cells:
			var cell: Dictionary = model.cells[coord]
			if cell["unit"] == 0:
				continue
			var home: Dictionary = model.kingdom_at(coord)
			if home.is_empty():
				home = support(coord)
			if not home.is_empty():
				banks[home["capital"]]["upkeep"] += model.unit_upkeep(cell["unit"], home["owner"])
		banks_ready = true
	return banks[capital]

func frontier(capital: Vector2i) -> Dictionary:
	if not frontiers.has(capital):
		var result: Dictionary = {}
		for coord in friendly_routes(capital):
			for next in model.neighbors(coord):
				if (model.cells[next]["owner"] != model.cells[capital]["owner"] or model.has_wildlife(next)) and not model.is_mountain(next) and not model.is_barrier(next):
					result[next] = true
		frontiers[capital] = result
	return frontiers[capital]

func region(source: Vector2i) -> Dictionary:
	var faction: int = model.unit_faction(source)
	var key := Vector3i(source.x, source.y, faction)
	if not regions.has(key):
		var parents := friendly_routes(source)
		var boundary: Dictionary = {}
		for coord in parents:
			for target in neighbors(coord):
				if not parents.has(target) and not model.is_mountain(target) and not model.is_barrier(target):
					boundary[target] = true
		var result := {"boundary": boundary, "members": parents.keys(), "id": regions.size()}
		regions[key] = result
		for coord in parents:
			regions[Vector3i(coord.x, coord.y, faction)] = result
	return regions[key]

func threats(faction: int) -> Dictionary:
	if not danger.has(faction):
		var result: Dictionary = {}
		var groups: Dictionary = {}
		var order: Dictionary = {}
		for source in model.cells:
			order[source] = order.size()
			var unit: Dictionary = model.cells[source]
			if unit["unit"] == 0 or model.unit_faction(source) == faction:
				continue
			var component := region(source)
			var key: int = component["id"]
			if not groups.has(key):
				groups[key] = {"component": component, "strength": 0, "sources": []}
			groups[key]["strength"] = maxi(groups[key]["strength"], unit["unit"])
			groups[key]["sources"].append(source)
		# Every unit in one accessible region threatens the same boundary. Aggregate
		# once instead of appending its source to every border tile repeatedly.
		for group in groups.values():
			for target in group["component"]["boundary"]:
				if model.cells[target]["owner"] != faction and model.unit_faction(target) != faction:
					continue
				if not result.has(target):
					result[target] = {"strength": group["strength"], "sources": group["sources"]}
				else:
					result[target]["strength"] = maxi(result[target]["strength"], group["strength"])
					var combined: Array = result[target]["sources"] + group["sources"]
					combined.sort_custom(func(a, b): return order[a] < order[b])
					result[target]["sources"] = combined
		# Animals take one adjacent step per World turn, rather than using a
		# kingdom's unlimited friendly movement. They do not coordinate armies.
		for source in model.cells:
			var kind: String = model.cells[source].get("animal", "")
			if kind == "": continue
			for target in neighbors(source):
				if model.cells[target].owner != faction or not model.Wildlife.can_attack(model,target,kind): continue
				var strength: int = model.Wildlife.DEFINITIONS[kind].attack
				if not result.has(target): result[target] = {"strength":strength,"sources":[source]}
				else:
					result[target] = {"strength":maxi(result[target].strength,strength),"sources":result[target].sources+[source]}
		danger[faction] = result
	return danger[faction]
