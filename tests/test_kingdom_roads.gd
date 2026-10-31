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
		if coord in sites: cells[coord].building = "city"
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
func fixture(coords: Array, sites: Array):
	var model = Rules.new()
	model.cells = cells_at(coords,sites)
	model.cells[coords[0]].capital = 0
	model.cells[coords[0]].building = ""
	model.rebuild_kingdoms()
	for bank in model.kingdoms.values(): bank.gold = 10000
	return model
func run() -> void:
	var start := Vector2i.ZERO
	var finish := Vector2i(2,-1)
	var diamond = fixture([start,Vector2i(1,0),Vector2i(1,-1),finish],[start,finish])
	expect(Roads.network(diamond.cells).is_empty(),"Structures do not create free automatic roads")
	var quoted: Array = diamond.road_targets(start,0)[finish].path
	expect(diamond.build_road(start,finish,0),"Player can purchase a shortest connection across equal-length alternatives")
	var edges := Roads.network(diamond.cells)
	expect(edges.size() == 2 and reachable(adjacency(edges),start).has(finish),"Purchased diamond connection follows one route without an extra branch")
	for index in range(quoted.size()-1):
		expect(reachable(adjacency(edges),quoted[index]).has(quoted[index+1]),"Rendered connection retains the quoted route")
	var reversed := {}
	var keys: Array = diamond.cells.keys()
	keys.reverse()
	for coord in keys: reversed[coord] = diamond.cells[coord]
	expect(Roads.network(reversed) == edges,"Rendering is independent of cell insertion order")
	var triangle = fixture([start,Vector2i(1,0),Vector2i(0,1)],[start,Vector2i(1,0),Vector2i(0,1)])
	expect(triangle.build_road(start,Vector2i(1,0),0) and triangle.build_road(start,Vector2i(0,1),0),"Two adjoining connections can be purchased independently")
	expect(Roads.network(triangle.cells).size() == 2,"Adjacent paved endpoints do not invent an unpurchased third edge")
	var line: Array = []
	for x in range(9): line.append(Vector2i(x,0))
	var model = fixture(line,[start,Vector2i(1,0),Vector2i(7,0),Vector2i(8,0)])
	model.build_road(start,Vector2i(1,0),0)
	model.build_road(Vector2i(7,0),Vector2i(8,0),0)
	edges = Roads.network(model.cells)
	expect(edges.size() == 2 and not reachable(adjacency(edges),start).has(Vector2i(8,0)),"Separate purchased segments remain separate until connected")
	expect(model.build_road(start,Vector2i(8,0),0),"Player can connect the two existing paved sections")
	edges = Roads.network(model.cells)
	expect(edges.size() == 8 and reachable(adjacency(edges),start).has(Vector2i(8,0)),"The combined network renders the purchased shared route")
	model.cells[Vector2i(4,0)].owner = 1
	edges = Roads.network(model.cells)
	expect(not reachable(adjacency(edges),start).has(Vector2i(8,0)),"Captured road land interrupts the friendly network")
	var disjoint = fixture([start,Vector2i(1,0),Vector2i(5,0),Vector2i(6,0)],[start,Vector2i(1,0),Vector2i(5,0),Vector2i(6,0)])
	expect(disjoint.build_road(start,Vector2i(1,0),0) and disjoint.build_road(Vector2i(5,0),Vector2i(6,0),0),"Each disconnected kingdom can buy its own local connection")
	expect(not disjoint.build_road(start,Vector2i(6,0),0) and Roads.network(disjoint.cells).size() == 2,"Road construction does not cross missing water tiles")
	model = fixture([start,Vector2i(1,0),Vector2i(1,-1),finish],[start,finish])
	model.cells[Vector2i(1,0)].mountain = true
	expect(model.build_road(start,finish,0) and Roads.network(model.cells).size() == 2,"Paid connections detour around a blocked alternative")
	model = fixture([start,Vector2i(1,0),Vector2i(1,-1),finish],[start,finish])
	model.cells[Vector2i(1,0)].mountain = true
	model.cells[Vector2i(1,-1)].mountain = true
	expect(not model.build_road(start,finish,0) and Roads.network(model.cells).is_empty(),"Blocked structures cannot purchase a road through mountains")
	# Early authored road tiles lack edge records and retain their adjacency rule.
	var legacy := cells_at([start,Vector2i(1,0)],[])
	for cell in legacy.values(): cell.road = true
	expect(Roads.network(legacy).size() == 1,"Legacy paved tiles remain readable without explicit edge records")
	print("Kingdom road checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
