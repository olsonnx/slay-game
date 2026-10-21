extends Control
const Loc = preload("res://src/localization/text.gd")
var series: Array = []
var maximum := 1.0
var last_round := 1
var hover_round := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): hover_round = -1; queue_redraw())
	resized.connect(queue_redraw)

func first_round() -> int:
	var first := last_round
	for line in series:
		if not line.points.is_empty(): first = mini(first,int(line.points[0].x))
	return first

func plot() -> Rect2:
	return Rect2(48, 34, maxf(1, size.x-64), maxf(1, size.y-62))

func point_position(point: Vector2) -> Vector2:
	var area := plot()
	var span := maxf(1, last_round-first_round())
	return Vector2(area.position.x+(point.x-first_round())/span*area.size.x, area.end.y-point.y/maxf(1,maximum)*area.size.y)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var fraction := clampf((event.position.x-plot().position.x)/plot().size.x,0,1)
		hover_round = roundi(lerpf(first_round(),last_round,fraction))
		queue_redraw()

func _get_tooltip(_at: Vector2) -> String:
	if hover_round < 0: return ""
	var rows := PackedStringArray([Loc.text("Round %d") % hover_round])
	for line in series:
		for point in line.points:
			if int(point.x) == hover_round:
				rows.append(Loc.text("%s · %d G") % [line.title,int(point.y)])
	return "\n".join(rows)

func _make_custom_tooltip(text: String) -> Object:
	return preload("res://src/ui/compact_tooltip.gd").create(text)

func _draw() -> void:
	var font := get_theme_default_font()
	var muted := Color("9eb2a7")
	var area := plot()
	draw_string(font, Vector2(0, 15), Loc.text("Income"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, muted)
	for fraction in [0.0, 0.5, 1.0]:
		var y: float = area.end.y-fraction*area.size.y
		draw_line(Vector2(area.position.x,y),Vector2(area.end.x,y), Color(0.65,0.75,0.7,0.14),1)
		draw_string(font,Vector2(0,y+4),str(roundi(maximum*fraction)),HORIZONTAL_ALIGNMENT_LEFT,-1,11,muted)
	if hover_round >= 0:
		var x := point_position(Vector2(hover_round,0)).x
		draw_line(Vector2(x,area.position.y),Vector2(x,area.end.y),Color(1,1,1,0.2),1)
	for line in series:
		var vertices := PackedVector2Array()
		for point in line.points: vertices.append(point_position(point))
		if vertices.size() > 1: draw_polyline(vertices, line.color, 2, true)
		if not vertices.is_empty(): draw_circle(vertices[-1],3,line.color)
		for point in line.points:
			if int(point.x) == hover_round: draw_circle(point_position(point),4,line.color)
	var ticks := [first_round()]
	if last_round > first_round(): ticks.append(last_round)
	for turn in ticks:
		var x := point_position(Vector2(turn,0)).x
		draw_string(font,Vector2(x-6,size.y-5),str(turn),HORIZONTAL_ALIGNMENT_LEFT,-1,11,muted)
	draw_string(font,Vector2(area.get_center().x-20,size.y-5),Loc.text("Round"),HORIZONTAL_ALIGNMENT_LEFT,-1,11,muted)
