extends RefCounted
## One undoable drag. Owns interpolation and deduplication; no controls or camera.
const Grid = preload("res://src/game/hex_grid.gd")
var active := false
var removing := false
var visited: Dictionary = {}
var last_coord := Grid.NONE
var before: Dictionary = {}

func begin(document, erase := false) -> void:
	assert(not active, "Finish the previous brush stroke before starting another")
	active = true
	removing = erase
	before = document.state()
	visited.clear()
	break_path()

func break_path() -> void:
	last_coord = Grid.NONE

func paint(document, coord: Vector2i, tool: String, owner: int, value: int, random_values: bool, rng: RandomNumberGenerator, event_id := "") -> bool:
	if not active or coord == Grid.NONE: return false
	var path: Array[Vector2i] = []
	if last_coord != Grid.NONE:
		var steps := Grid.distance(last_coord, coord)
		for index in range(1, steps):
			path.append(Grid.from_world(Grid.to_world(last_coord).lerp(Grid.to_world(coord), float(index) / steps)))
	path.append(coord)
	last_coord = coord
	var changed := false
	for next in path:
		if visited.has(next): continue
		visited[next] = true
		var chosen_value := rng.randi_range(1, 3) if random_values and tool in ["Land", "Value"] else value
		var edited: bool = document.erase(next, tool) if removing else document.paint(next, tool, owner, chosen_value, event_id)
		changed = changed or edited
	return changed

func finish(document) -> void:
	if active and before != document.state():
		document.commit_stroke(before)
	active = false
	removing = false
	visited.clear()
	before = {}
	break_path()
