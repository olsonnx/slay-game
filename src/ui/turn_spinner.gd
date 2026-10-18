extends Control
## Lightweight, pausable busy indicator; never intercepts button input.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(8, 8)
	set_active(false)

func set_active(active: bool) -> void:
	visible = active
	set_process(active)
	if not active:
		rotation = 0

func _process(delta: float) -> void:
	rotation = fmod(rotation + delta * TAU, TAU)

func _draw() -> void:
	for index in range(8):
		var angle := index * TAU / 8
		var color := Color("182b25")
		color.a = (index + 1) / 8.0
		draw_arc(Vector2(8, 8), 6, angle, angle + 0.48, 5, color, 2, true)
