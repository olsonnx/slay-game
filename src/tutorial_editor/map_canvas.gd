extends Control
## Orthographic schematic for tile picking; no running game or simulation ownership.
signal picked(coord: Vector2i)
var cells: Dictionary = {}
var target := Vector2i(999,999)
var source := Vector2i(999,999)
var points: Dictionary = {}
var hovered := Vector2i(999,999)
var scale_value := 26.0
var origin := Vector2.ZERO
var zoom := 1.0
var pan := Vector2.ZERO
const COLORS := [Color("86b998"),Color("d79879"),Color("91a6c7"),Color("c5b478"),Color("b29acd"),Color("73b7b7")]

func _ready() -> void:
	custom_minimum_size = Vector2(320,320)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): hovered = Vector2i(999,999); queue_redraw())

func set_map(value: Dictionary) -> void:
	cells = value
	zoom = 1.0
	pan = Vector2.ZERO
	queue_redraw()

func at(coord: Vector2i) -> Vector2:
	return Vector2(sqrt(3.0)*(coord.x+coord.y*0.5),1.5*coord.y)

func _draw() -> void:
	draw_style_box(preload("res://src/ui/ui_theme.gd").style(Color("152d36"),8),Rect2(Vector2.ZERO,size))
	if cells.is_empty(): return
	var minimum := Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	for coord in cells:
		minimum = minimum.min(at(coord)-Vector2.ONE)
		maximum = maximum.max(at(coord)+Vector2.ONE)
	scale_value = minf((size.x-52)/maxf(1,maximum.x-minimum.x),(size.y-52)/maxf(1,maximum.y-minimum.y))
	scale_value = minf(48,scale_value)*zoom
	origin = size*0.5-(minimum+maximum)*0.5*scale_value+pan
	points.clear()
	for coord in cells:
		var center := origin+at(coord)*scale_value
		points[coord] = center
		var polygon := PackedVector2Array()
		for corner in range(6): polygon.append(center+Vector2.from_angle((corner*60-30)*PI/180)*scale_value*0.95)
		var cell: Dictionary = cells[coord]
		var color: Color = COLORS[cell.owner] if cell.owner >= 0 else Color("b5b89a")
		if cell.mountain: color = Color("596b70")
		if cell.building == "bridge": color = Color("be9a65")
		draw_colored_polygon(polygon,color)
		polygon.append(polygon[0])
		draw_polyline(polygon,Color("243d43"),1.0,true)
		var mark := ""
		if cell.capital >= 0: mark = "CAP"
		elif cell.unit > 0: mark = ["","S1","S2","K3"][cell.unit]
		elif cell.building != "": mark = cell.building.to_upper().substr(0,3)
		elif cell.tree: mark = "TREE"
		elif cell.grave: mark = "GRAVE"
		elif cell.mountain: mark = "MTN"
		elif cell.mana_source: mark = "MANA"
		var font := ThemeDB.fallback_font
		var font_size := 12 if scale_value >= 25 else 9
		if scale_value < 14: mark = ""
		draw_string(font,center+Vector2(-scale_value*0.75,-1),mark,HORIZONTAL_ALIGNMENT_CENTER,scale_value*1.5,font_size,Color("162d34"))
		if scale_value >= 22: draw_string(font,center+Vector2(-scale_value,14),"%d,%d" % [coord.x,coord.y],HORIZONTAL_ALIGNMENT_CENTER,scale_value*2,10,Color("243d43"))
	for entry in [[source,Color("79e1f2")],[target,Color("ffd66e")],[hovered,Color.WHITE]]:
		var center := origin+at(entry[0])*scale_value
		if entry[0] != Vector2i(999,999): draw_arc(center,scale_value*0.88,0,TAU,36,entry[1],3,true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			pan += event.relative
			queue_redraw()
			return
		hovered = nearest(event.position)
		tooltip_text = "Tile %d, %d" % [hovered.x,hovered.y]
		var cell: Dictionary = cells.get(hovered,{})
		tooltip_text += " - water" if cell.is_empty() else " | Owner %d | Value %d | Unit %d | %s" % [cell.owner,cell.value,cell.unit,cell.building]
		queue_redraw()
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var old := zoom
		zoom = clampf(zoom*(1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.2),0.4,12.0)
		var ratio := zoom/old
		pan = (event.position-size*0.5)*(1-ratio)+pan*ratio
		queue_redraw()
		accept_event()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		picked.emit(nearest(event.position))
		accept_event()

func nearest(point: Vector2) -> Vector2i:
	var v := (point-origin)/scale_value
	var r := v.y/1.5
	var q := v.x/sqrt(3.0)-r*0.5
	var cube := Vector3(q,-q-r,r)
	var snapped := cube.round()
	var difference := (snapped-cube).abs()
	if difference.x > difference.y and difference.x > difference.z: snapped.x = -snapped.y-snapped.z
	elif difference.y > difference.z: snapped.y = -snapped.x-snapped.z
	else: snapped.z = -snapped.x-snapped.y
	return Vector2i(int(snapped.x),int(snapped.z))
