extends SceneTree
const Roads = preload("res://src/rendering/kingdom_roads.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const Grid = preload("res://src/game/hex_grid.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func cells_at(coords: Array, sites: Array) -> Dictionary:
	var rules := Rules.new()
	var cells := {}
	for coord in coords:
		cells[coord] = rules.make_cell(0)
		cells[coord].kingdom = Vector2i.ZERO
		if coord in sites: cells[coord].building = "house"
	return cells
func adjacency(edges: Dictionary) -> Dictionary:
	var graph := {}
	for pair in edges:
		for index in range(2):
			if not graph.has(pair[index]): graph[pair[index]] = []
			graph[pair[index]].append(pair[1 - index])
	return graph
func reachable(graph: Dictionary, start: Vector2i) -> Dictionary:
	var visited := {start:true}
	var pending := [start]
	var cursor := 0
	while cursor < pending.size():
		var coord: Vector2i = pending[cursor]
		cursor += 1
		for next in graph.get(coord, []):
			if not visited.has(next):
				visited[next] = true
				pending.append(next)
	return visited
func run() -> void:
	var start := Vector2i.ZERO
	var finish := Vector2i(2, -1)
	var diamond := cells_at([start,Vector2i(1,0),Vector2i(1,-1),finish], [start,finish])
	var edges := Roads.network(diamond)
	expect(edges.size() == 2 and reachable(adjacency(edges), start).has(finish), "Equal-length alternatives produce one shortest route instead of a loop")
	var reversed := {}
	var keys: Array = diamond.keys()
	keys.reverse()
	for coord in keys: reversed[coord] = diamond[coord]
	expect(Roads.network(reversed) == edges, "Route selection is independent of dictionary insertion order")
	var sites := [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1)]
	expect(Roads.network(cells_at(sites,sites)).size() == 2, "Three adjacent structures connect without a triangular road loop")
	var line: Array = []
	for x in range(9): line.append(Vector2i(x,0))
	sites = [Vector2i.ZERO,Vector2i(1,0),Vector2i(7,0),Vector2i(8,0)]
	edges = Roads.network(cells_at(line,sites))
	expect(edges.size() == 8 and reachable(adjacency(edges), start).has(sites.back()), "Separate pairs of nearby buildings join one shared network")
	# A dense set of structures exercises branch sharing and equal paths.
	var coords: Array = []
	sites = []
	for q in range(-4,5):
		for r in range(-4,5):
			if Grid.distance(Vector2i.ZERO,Vector2i(q,r)) > 4: continue
			coords.append(Vector2i(q,r))
			if posmod(q * 3 + r, 4) == 0: sites.append(Vector2i(q,r))
	var cells := cells_at(coords, sites)
	edges = Roads.network(cells)
	var graph := adjacency(edges)
	var connected := reachable(graph, sites[0])
	expect(edges.size() == graph.size() - 1, "The shared network is a tree, giving a unique route between every connected pair")
	for site in sites: expect(connected.has(site), "All reachable structures belong to the same road network")
	var shuffled := coords.duplicate()
	shuffled.reverse()
	expect(Roads.network(cells_at(shuffled,sites)) == edges, "Dense tied routes stay stable when land order changes")
	var disjoint := cells_at([start, Vector2i(1,0), Vector2i(5,0), Vector2i(6,0)], [start, Vector2i(1,0), Vector2i(5,0), Vector2i(6,0)])
	edges = Roads.network(disjoint)
	expect(edges.size() == 2, "Disconnected land keeps separate trees without crossing water")
	diamond[Vector2i(1,0)].mountain = true
	expect(Roads.network(diamond).size() == 2, "A blocked alternative leaves one valid detour")
	diamond[Vector2i(1,-1)].mountain = true
	expect(Roads.network(diamond).is_empty(), "Blocked structures have no road through mountains")
	print("Kingdom road checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
