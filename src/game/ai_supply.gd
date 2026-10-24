extends RefCounted
## One iterative articulation pass per queried bank; no branch copies or RNG.
## Estimates disruption, not guaranteed deaths: the opponent can still escape.
const Catalog = preload("res://src/game/game_catalog.gd")
const VALUES := [0.0, 10.0, 21.0, 38.0]

static func resources(model, coord: Vector2i, owner: int) -> Array:
	var cell: Dictionary = model.cells[coord]
	var land := int(cell["owner"] == owner)
	var income := 0
	if land:
		income = cell["value"] if not cell["tree"] and not cell["grave"] else 0
		if cell["building"] == "house": income += model.HOUSE_INCOME
	var rank: int = cell["unit"] if model.unit_faction(coord) == owner else 0
	var capital_recovery: int = cell["value"] if land and (cell["tree"] or cell["grave"]) else 0
	return [land, income, model.unit_upkeep(rank, owner), VALUES[rank], capital_recovery]

static func add_into(a: Array, b: Array) -> void:
	for i in range(4): a[i] += b[i]
	a[4] = maxi(a[4],b[4])

static func bank_cuts(model, bank: Dictionary, queries) -> Dictionary:
	var root: Vector2i = bank["capital"]
	var owner: int = bank["owner"]
	var nodes := {}
	var stack := [root]
	nodes[root] = {"index": 0, "low": 0, "parent": model.NONE, "head": 0, "sum": resources(model,root,owner), "detached": [0,0,0,0.0,0], "score": 0.0, "ranges": [], "doomed": []}
	while not stack.is_empty():
		var coord: Vector2i = stack.back()
		var node: Dictionary = nodes[coord]
		var adjacent: Array = queries.neighbors(coord)
		if node["head"] < adjacent.size():
			var next: Vector2i = adjacent[node["head"]]
			node["head"] += 1
			if model.is_mountain(next) or not (model.cells[next]["kingdom"] == root or model.is_bridge(next)): continue
			if next == node["parent"]: continue
			if nodes.has(next):
				node["low"] = mini(node["low"], nodes[next]["index"])
			else:
				nodes[next] = {"index": nodes.size(), "low": nodes.size(), "parent": coord, "head": 0, "sum": resources(model,next,owner), "detached": [0,0,0,0.0,0], "score": 0.0, "ranges": [], "doomed": []}
				stack.append(next)
			continue
		stack.pop_back()
		if coord == root: continue
		var parent: Dictionary = nodes[node["parent"]]
		parent["low"] = mini(parent["low"], node["low"])
		add_into(parent["sum"],node["sum"])
		if node["low"] >= parent["index"]:
			var branch: Array = node["sum"]
			add_into(parent["detached"],branch)
			var interval := Vector2i(node["index"],nodes.size()-1)
			parent["ranges"].append(interval)
			if branch[0] > 0:
				parent["score"] += minf(8.0,branch[0]*0.6)
				if branch[2] > branch[1] + branch[4] or branch[0] < 2:
					parent["score"] += branch[3]*0.65 + maxf(0.0,branch[2]-branch[1])*0.6
					parent["doomed"].append(interval)
	var result := {}
	var total: Array = nodes[root]["sum"]
	for coord in nodes:
		if coord == root or nodes[coord]["detached"][0] == 0: continue
		var node: Dictionary = nodes[coord]
		var own := resources(model,coord,owner)
		var detached: Array = node["detached"]
		var retained_net: float = total[1]-detached[1]-own[1] - (total[2]-detached[2]-own[2])
		var score: float = node["score"]
		if bank["gold"] + retained_net < 0:
			score += maxf(0.0,total[3]-detached[3]-own[3])*0.5
		result[coord] = {"score":minf(60.0,score),"doomed":node["doomed"],"detached":node["ranges"],"retained_starves":bank["gold"]+retained_net < 0}
	var indices := {}
	for coord in nodes: indices[coord] = nodes[coord]["index"]
	result["indices"] = indices
	return result
