extends Control
## Clockwise hold progress along the button's rounded border.
var progress := 0.0:
	set(amount):
		progress = clampf(amount, 0.0, 1.0)
		visible = progress > 0.0
		queue_redraw()
var border := PackedVector2Array()
var perimeter := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(rebuild_border)
	rebuild_border()
	hide()

func rebuild_border() -> void:
	border.clear()
	perimeter = 0.0
	var inset := 2.0
	var radius := 7.0
	border.append(Vector2(size.x / 2, inset))
	var corners := [Vector2(size.x - inset - radius, inset + radius), Vector2(size.x - inset - radius, size.y - inset - radius), Vector2(inset + radius, size.y - inset - radius), Vector2(inset + radius, inset + radius)]
	for corner in range(4):
		for step in range(9):
			var angle := -PI / 2 + corner * PI / 2 + step * PI / 16
			border.append(corners[corner] + Vector2.from_angle(angle) * radius)
	border.append(border[0])
	for index in range(1, border.size()):
		perimeter += border[index - 1].distance_to(border[index])
	queue_redraw()

func _draw() -> void:
	if border.size() < 2 or progress <= 0:
		return
	draw_polyline(border, Color(0.78, 0.83, 0.63, 0.18), 2.0, true)
	var filled := PackedVector2Array([border[0]])
	var remaining := perimeter * progress
	for index in range(1, border.size()):
		var length := border[index - 1].distance_to(border[index])
		if remaining < length:
			filled.append(border[index - 1].lerp(border[index], remaining / length))
			break
		filled.append(border[index])
		remaining -= length
	draw_polyline(filled, Color("c8d3a1"), 2.0, true)
