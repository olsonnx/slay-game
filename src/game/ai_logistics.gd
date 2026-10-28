extends RefCounted
## Recruitment coverage and useful supply links, shared by both AI backends.
const Logistics = preload("res://src/game/logistics.gd")

static func city_sites(model, bank: Dictionary, border: Dictionary, danger: Dictionary) -> Dictionary:
	var hubs := []
	for coord in bank.hexes:
		if Logistics.recruitment_hub(model.cells[coord]): hubs.append(coord)
	var uncovered := []
	for target in border:
		var distance := 1000
		for hub in hubs: distance = mini(distance, model.distance(hub, target))
		if distance >= 4: uncovered.append(target)
	var result := {}
	for coord in bank.hexes:
		var cell: Dictionary = model.cells[coord]
		if cell.unit > 0 or cell.capital >= 0 or cell.building != "" or cell.tree or cell.grave or model.is_mountain(coord) or model.is_barrier(coord) or model.has_wildlife(coord): continue
		if danger.has(coord) and danger[coord].strength > model.defense(coord): continue
		var nearest := 1000
		for hub in hubs: nearest = mini(nearest, model.distance(coord, hub))
		if nearest < 3: continue
		var coverage := 0
		for target in uncovered:
			if model.distance(coord, target) <= 2: coverage += 1
		if coverage > 0: result[coord] = 36.0 + mini(coverage, 6) * 2.0 + mini(nearest, 6)
	return result

static func travel_costs(model, source: Vector2i, faction: int) -> Dictionary:
	var costs := {source:0}
	var pending = preload("res://src/game/integer_frontier.gd").new()
	pending.push(source, 0)
	while not pending.is_empty():
		var current: Vector2i = pending.pop()
		if costs[current] != pending.cost: continue
		for next in model.neighbors(current):
			var cell: Dictionary = model.cells[next]
			if cell.owner != faction and not (model.is_bridge(next) and (cell.unit == 0 or model.unit_faction(next) == faction)): continue
			if model.is_mountain(next) or model.is_barrier(next) or model.has_wildlife(next): continue
			var cost: int = costs[current] + Logistics.step_cost(model, current, next, faction)
			if cost >= costs.get(next, 2147483647): continue
			costs[next] = cost
			pending.push(next, cost)
	return costs

static func front_distance(model, coord: Vector2i, border: Dictionary) -> int:
	var distance := 1000
	for target in border: distance = mini(distance, model.distance(coord, target))
	return distance

static func roads(model, bank: Dictionary, border: Dictionary, queries) -> Array:
	var result := []
	if border.is_empty(): return result
	var faction: int = bank.owner
	var finances: Dictionary = queries.bank_summary(bank)
	var income: int = finances.income
	for source in bank.hexes:
		if not Logistics.recruitment_hub(model.cells[source]): continue
		var rear := front_distance(model, source, border)
		if rear < 3: continue
		var costs := travel_costs(model, source, faction)
		var plans: Dictionary = model.road_targets(source, faction)
		for target in plans:
			if not Logistics.recruitment_hub(model.cells[target]): continue
			var front := front_distance(model, target, border)
			if front > 3 or rear - front < 2: continue
			var plan: Dictionary = plans[target]
			# A road must save at least one full movement point on the current
			# best route, lead toward the front, and preserve a city reserve.
			var planned_cost := 0
			for index in range(plan.path.size() - 1):
				planned_cost += 2 if model.is_bridge(plan.path[index]) or model.is_bridge(plan.path[index + 1]) else 1
			var saving: int = costs.get(target, 0) - planned_cost
			if saving < 2 or plan.cost <= 0 or plan.cost > mini(20, maxi(3, income)) or bank.gold - plan.cost < model.CITY_COST: continue
			if bank.gold - plan.cost + income - finances.upkeep < 0: continue
			result.append({"source":source, "coord":target, "capital":bank.capital, "kind":"road", "priority":4.0 + saving * 0.5})
	return result
