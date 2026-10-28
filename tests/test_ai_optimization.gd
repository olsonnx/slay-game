extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Logistics = preload("res://src/game/logistics.gd")
const Queries = preload("res://src/game/ai_queries.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
var checks := 0
var failures := 0
class FullSortStrategy extends "res://src/game/ai_strategist.gd":
	func region_options(source: Vector2i, _limit := 0) -> Array:
		return super.region_options(source, 0)
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

# Independent reference for exact distances, discovery order and parent ties.
func reference_routes(model, source: Vector2i) -> Dictionary:
	var parents := {source: Rules.NONE}
	var costs := {source:0}
	var faction: int = model.unit_faction(source)
	var budget: int = Rules.Catalog.MOVEMENT[model.cells[source].unit] * 2
	var pending := [source]
	while not pending.is_empty():
		var best := 0
		for index in range(1,pending.size()):
			if costs[pending[index]] < costs[pending[best]]: best = index
		var current: Vector2i = pending.pop_at(best)
		for next in model.neighbors(current):
			var cell: Dictionary = model.cells[next]
			if not (cell.owner == faction or cell.building == "bridge" and (cell.unit == 0 or cell.get("unit_owner",-1) == faction)): continue
			if model.is_mountain(next) or model.is_barrier(next) or model.has_wildlife(next): continue
			var cost: int = costs[current] + Logistics.step_cost(model,current,next,faction)
			if cost > budget or cost >= costs.get(next,2147483647): continue
			costs[next] = cost
			parents[next] = current
			if next not in pending: pending.append(next)
	return {"parents":parents,"costs":costs,"budget":budget}

func reference_threats(model, faction: int) -> Dictionary:
	var result := {}
	for source in model.cells:
		var unit: Dictionary = model.cells[source]
		if unit.unit == 0 or model.unit_faction(source) == faction: continue
		var travel := reference_routes(model,source)
		var touched := {}
		for approach in travel.parents:
			if travel.costs[approach] + 2 > travel.budget: continue
			for target in model.neighbors(approach):
				if model.cells[target].owner != faction and model.unit_faction(target) != faction: continue
				if touched.has(target) or model.is_mountain(target) or model.is_barrier(target): continue
				touched[target] = true
				if not result.has(target): result[target] = {"strength":unit.unit,"sources":[source]}
				else:
					result[target].strength = maxi(result[target].strength,unit.unit)
					result[target].sources.append(source)
	for source in model.cells:
		var kind: String = model.cells[source].get("animal","")
		if kind == "": continue
		for target in model.neighbors(source):
			if model.cells[target].owner != faction or not model.Wildlife.can_attack(model,target,kind): continue
			var strength: int = model.Wildlife.DEFINITIONS[kind].attack
			if not result.has(target): result[target] = {"strength":strength,"sources":[source]}
			else: result[target] = {"strength":maxi(result[target].strength,strength),"sources":result[target].sources+[source]}
	return result

func route_checks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for seed_value in range(4):
		var model = Rules.new()
		for q in range(-7,8):
			for r in range(-6,7):
				var coord := Vector2i(q,r)
				var cell: Dictionary = model.make_cell(0 if q < 0 else 1)
				cell.road = rng.randf() < 0.65
				cell.mountain = rng.randf() < 0.08
				if rng.randf() < 0.05: cell.barrier_by = 1
				if rng.randf() < 0.08:
					cell.building = "bridge"
					cell.owner = -1
				if rng.randf() < 0.12:
					cell.unit = rng.randi_range(1,3)
					cell.unit_owner = rng.randi_range(0,1)
				if rng.randf() < 0.02: cell.animal = "wolf"
				model.cells[coord] = cell
		for source in model.cells:
			if model.cells[source].unit == 0: continue
			var actual := Logistics.routes(model,source)
			var expected := reference_routes(model,source)
			expect(actual == expected, "Bucket routes preserve distances and equal-cost parents")
			expect(actual.parents.keys() == expected.parents.keys(), "Route discovery order stays deterministic")
		for faction in range(2):
			expect(Queries.new(model).threats(faction) == reference_threats(model,faction), "Distant-army rejection preserves all threat strengths and source ordering")
	# Deliberately exercise decrease-key when an earlier-discovered node is
	# improved into a cost bucket that already contains a later-discovered node.
	var queue = preload("res://src/game/integer_frontier.gd").new()
	queue.push(Vector2i.ZERO,0)
	queue.push(Vector2i(1,0),4)
	queue.push(Vector2i(2,0),3)
	queue.push(Vector2i(1,0),3)
	expect(not queue.is_empty() and queue.pop() == Vector2i.ZERO, "Frontier starts at minimum cost")
	expect(not queue.is_empty() and queue.pop() == Vector2i(1,0), "Decrease-key retains first discovery priority")
	expect(not queue.is_empty() and queue.pop() == Vector2i(2,0), "Equal-cost successor remains ordered")

func preparation_checks() -> void:
	for difficulty in ["easy","normal","hard"]:
		for seed_value in range(3):
			var model = Rules.new()
			model.generate(seed_value,"medium",4)
			model.ai_difficulty = difficulty
			model.begin_turn(1)
			for bank in model.kingdoms.values(): bank.gold = 150
			var ai = model.KingdomAI.new(model)
			var cache := {}
			for purchase in range(int(Analysis.profile(model).spending)):
				var view = Analysis.snapshot(model)
				var cached = Queries.new(view,cache)
				var options := Candidates.preparation(view,1,cached)
				expect(options == Candidates.preparation(view,1), "Cached purchases exactly match fresh options after every mutation")
				if options.is_empty(): break
				var action: Dictionary = options[0]
				expect(Candidates.apply(model,action,1), "Chosen cached purchase is legal")
				ai.invalidate_preparation(cache,action,1)
	# Animal attacks must disappear when newly recruited defenders stop them,
	# even though army reach and adjacency are reused.
	var model = Rules.new()
	for q in range(6): model.cells[Vector2i(q,0)] = model.make_cell(0)
	model.cells[Vector2i(1,1)] = model.make_cell(-1)
	model.cells[Vector2i(1,1)].animal = "wolf"
	model.cells[Vector2i.ZERO].capital = 0
	model.rebuild_kingdoms()
	var cache := {}
	var before := Queries.new(model,cache).threats(0)
	model.cells[Vector2i(1,0)].unit = 3
	var ai = model.KingdomAI.new(model)
	ai.invalidate_preparation(cache,{"kind":"recruit","coord":Vector2i(1,0)},0)
	var after := Queries.new(model,cache).threats(0)
	expect(before.has(Vector2i(1,0)) and not after.has(Vector2i(1,0)), "Wildlife is reevaluated after recruitment")
	for kind in ["road","bridge","spell","future_kind"]:
		cache["army_danger"] = {0:{}}
		ai.invalidate_preparation(cache,{"kind":kind,"coord":Vector2i.ZERO},0)
		expect(cache.is_empty(), "Uncertain/topology-changing actions invalidate preparation facts")
	model.cells[Vector2i(2,0)].building = "bridge"
	model.cells[Vector2i(2,0)].owner = -1
	cache["army_danger"] = {0:{}}
	ai.invalidate_preparation(cache,{"kind":"recruit","coord":Vector2i(2,0)},0)
	expect(cache.is_empty(), "Bridge occupancy cannot reuse enemy routes")
	model = Rules.new()
	for q in range(6): model.cells[Vector2i(q,0)] = model.make_cell(0 if q < 2 else 1)
	model.cells[Vector2i.ZERO].capital = 0
	model.cells[Vector2i(5,0)].capital = 1
	model.cells[Vector2i(3,0)].unit = 2
	model.cells[Vector2i(4,0)].unit = 2
	model.rebuild_kingdoms()
	cache = {}
	var projected := Queries.new(model,cache).defense_needs(0)
	expect(projected.has(Vector2i.ZERO) and projected[Vector2i.ZERO].get("projected",false), "Two attackers project a capital breach before recruitment")
	model.cells[Vector2i.ZERO].unit = 2
	model.KingdomAI.new(model).invalidate_preparation(cache,{"kind":"recruit","coord":Vector2i.ZERO},0)
	expect(not Queries.new(model,cache).defense_needs(0).has(Vector2i.ZERO), "Capital projections refresh against newly recruited defenders")

func shortlist_checks() -> void:
	var strategy = load("res://src/game/ai_strategist.gd")
	for difficulty in ["easy","normal","hard"]:
		for seed_value in [11,42,71]:
			var model = Rules.new()
			model.generate(seed_value,"large",6)
			model.ai_difficulty = difficulty
			var index := 0
			for coord in model.cells:
				var cell: Dictionary = model.cells[coord]
				index += 1
				if cell.owner < 0 or model.is_mountain(coord) or model.has_wildlife(coord) or model.is_barrier(coord): continue
				if index % 3 == 0:
					cell.unit = 1 + (index / 3) % 3
					cell.moved = false
				if index % 7 == 0: cell.road = true
			var bounded = strategy.new(model,1)
			var full = FullSortStrategy.new(model,1)
			bounded.run()
			full.run()
			expect(bounded.best_sequence == full.best_sequence and bounded.best_score == full.best_score, "Bounded shortlist preserves full-sort assignments and tactical scores")

func run() -> void:
	route_checks()
	preparation_checks()
	shortlist_checks()
	print("AI optimization checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
