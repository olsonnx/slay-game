extends Control
## Vector heraldry shared by the profile editor, menu badge and game HUD.
var design: Dictionary = {}
func set_design(value: Dictionary) -> void:
	design = value.duplicate(true)
	queue_redraw()
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)
func polygon(points: Array, color: Color, center := Vector2.ZERO, scale_value := Vector2.ONE) -> void:
	var vertices := PackedVector2Array()
	for point in points: vertices.append(center + point * scale_value)
	draw_colored_polygon(vertices, color)
func _draw() -> void:
	if design.is_empty(): return
	var field := Color(design.get("field", "283b3e"))
	var accent := Color(design.get("accent", "86b998"))
	var ink := Color(design.get("ink", "ede7d4"))
	draw_rect(Rect2(Vector2.ZERO, size), field)
	match design.get("pattern", "solid"):
		"horizontal": draw_rect(Rect2(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5)), accent)
		"vertical": draw_rect(Rect2(Vector2(size.x * 0.5, 0), Vector2(size.x * 0.5, size.y)), accent)
		"diagonal": polygon([Vector2.ZERO, Vector2(size.x, 0), size], accent)
		"cross":
			draw_rect(Rect2(Vector2(size.x * 0.42, 0), Vector2(size.x * 0.16, size.y)), accent)
			draw_rect(Rect2(Vector2(0, size.y * 0.38), Vector2(size.x, size.y * 0.24)), accent)
		"saltire":
			draw_line(Vector2.ZERO, size, accent, size.y * 0.19, true)
			draw_line(Vector2(0, size.y), Vector2(size.x, 0), accent, size.y * 0.19, true)
		"border": draw_rect(Rect2(Vector2.ONE * size.y * 0.06, size - Vector2.ONE * size.y * 0.12), accent, false, size.y * 0.12)
	var center := size * 0.5
	match design.get("placement", "center"):
		"left": center = size * Vector2(0.25, 0.5)
		"right": center = size * Vector2(0.75, 0.5)
		"upper_left": center = size * Vector2(0.25, 0.27)
		"upper_right": center = size * Vector2(0.75, 0.27)
		"lower_left": center = size * Vector2(0.25, 0.73)
		"lower_right": center = size * Vector2(0.75, 0.73)
	var radius := size.y * float(design.get("scale", 0.38)) * 0.5
	var stretch := Vector2.ONE * radius
	match design.get("symbol", "crown"):
		"crown": polygon([Vector2(-1,-0.7),Vector2(-0.45,-0.1),Vector2(0,-1),Vector2(0.45,-0.1),Vector2(1,-0.7),Vector2(0.75,0.8),Vector2(-0.75,0.8)], ink, center, stretch)
		"diamond": polygon([Vector2(0,-1),Vector2(0.8,0),Vector2(0,1),Vector2(-0.8,0)], ink, center, stretch)
		"star", "sun":
			var points: Array = []
			var count := 5 if design.symbol == "star" else 12
			for index in range(count * 2):
				var angle := -PI / 2 + index * PI / count
				points.append(Vector2(cos(angle), sin(angle)) * (1.0 if index % 2 == 0 else 0.45 if count == 5 else 0.65))
			polygon(points, ink, center, stretch)
		"tower":
			polygon([Vector2(-0.8,-1),Vector2(-0.3,-1),Vector2(-0.3,-0.5),Vector2(0.3,-0.5),Vector2(0.3,-1),Vector2(0.8,-1),Vector2(0.8,1),Vector2(-0.8,1)], ink, center, stretch)
			draw_rect(Rect2(center + Vector2(-0.18,0.2) * radius, Vector2(0.36,0.8) * radius), field)
		"tree":
			draw_rect(Rect2(center + Vector2(-0.12,0.1) * radius, Vector2(0.24,0.9) * radius), ink)
			polygon([Vector2(0,-1),Vector2(0.85,0.4),Vector2(-0.85,0.4)], ink, center, stretch)
		"sword":
			polygon([Vector2(0,-1),Vector2(0.2,-0.6),Vector2(0.14,0.35),Vector2(0.65,0.35),Vector2(0.65,0.55),Vector2(0.12,0.55),Vector2(0.12,1),Vector2(-0.12,1),Vector2(-0.12,0.55),Vector2(-0.65,0.55),Vector2(-0.65,0.35),Vector2(-0.14,0.35),Vector2(-0.2,-0.6)], ink, center, stretch)
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color(1,1,1,0.15), false, 1.0)
