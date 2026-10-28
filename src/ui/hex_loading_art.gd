extends Control
## Lightweight canvas geometry: loading never needs another 3D world or texture.
const Grid = preload("res://src/game/hex_grid.gd")
const GOLD := Color("ead29e")
const TOPS := [Color("829578"), Color("a5ae87"), Color("bcbd91"), Color("809992")]
var progress := 0.0
var elapsed := 0.0
var animated := true
var cells: Array[Dictionary] = []
var outline := PackedVector2Array()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(360, 208)
	for index in range(6):
		var angle := -PI / 2.0 + index * TAU / 6.0
		outline.append(Vector2(cos(angle), sin(angle)))
	for q in range(-2, 3):
		for r in range(-2, 3):
			var coord := Vector2i(q, r)
			if Grid.distance(coord, Vector2i.ZERO) > 2: continue
			cells.append({"coord":coord, "order":0})
	cells.sort_custom(func(a, b):
		var da := Grid.distance(a.coord, Vector2i.ZERO)
		var db := Grid.distance(b.coord, Vector2i.ZERO)
		return da < db if da != db else Vector2(a.coord).angle() < Vector2(b.coord).angle())
	for index in range(cells.size()): cells[index].order = index
	# Paint back to front, independently of the center-out assembly order.
	cells.sort_custom(func(a, b): return a.coord.y < b.coord.y if a.coord.y != b.coord.y else a.coord.x < b.coord.x)
	resized.connect(queue_redraw)

func polygon(at: Vector2, radius: float, flatten := 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in outline: points.append(at + point * Vector2(radius, radius * flatten))
	return points

func stroke(points: PackedVector2Array, color: Color, width := 1.0) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width, true)

func _draw() -> void:
	if outline.is_empty(): return
	var center := size * Vector2(0.5, 0.47)
	for cell in cells:
		var coord: Vector2i = cell.coord
		var world := Grid.to_world(coord)
		var home := center + Vector2(world.x * 33.0, world.z * 33.0 * 0.55)
		var fill := clampf(progress * cells.size() - int(cell.order), 0.0, 1.0)
		stroke(polygon(home, 31.5, 0.55), Color(0.58, 0.72, 0.68, 0.16))
		if fill <= 0.0:
			if int(cell.order) == mini(floori(progress * cells.size()), cells.size() - 1):
				var pulse := 0.45 + 0.15 * sin(elapsed * 2.5) if animated else 0.45
				stroke(polygon(home, 31.5, 0.55), Color(GOLD, pulse), 1.5)
			continue
		var lift := (1.0 - fill) * 18.0
		if animated: lift += sin(elapsed * 1.7 + int(cell.order) * 0.35) * 1.2
		var top := polygon(home - Vector2(0, lift), 31.5, 0.55)
		var color: Color = GOLD if cell.order == 0 else TOPS[posmod(coord.x * 7 + coord.y * 3, TOPS.size())]
		color.a = fill
		for edge in [2, 3]:
			var side := PackedVector2Array([top[edge], top[edge + 1], top[edge + 1] + Vector2(0, 10), top[edge] + Vector2(0, 10)])
			draw_colored_polygon(side, color.darkened(0.34 if edge == 2 else 0.48))
		draw_colored_polygon(top, color)
		stroke(top, Color(0.86, 0.88, 0.70, fill * 0.22))
		# A quiet traveling glint keeps held progress alive without inventing work.
		if animated:
			var glint := maxf(0.0, sin(elapsed * 1.5 - Grid.distance(coord, Vector2i.ZERO) * 0.8) - 0.84) * 1.8
			if glint > 0: stroke(top, Color(GOLD, glint * fill), 1.5)
