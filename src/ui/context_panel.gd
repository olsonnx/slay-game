extends Panel
## Shared entrance for the contextual panels above the resource dock.
const ENTRANCE_OFFSET := 8.0
const ENTRANCE_SECONDS := 0.24
var rest_top := -331.0
var panel_height := 177.0
var slide: Tween
var reveal := 0.0:
	set(amount):
		reveal = amount
		offset_top = lerpf(rest_top + ENTRANCE_OFFSET, rest_top, amount)
		offset_bottom = offset_top + panel_height
		modulate.a = amount

func open(restart := false) -> void:
	if visible and not restart:
		return
	if slide != null and slide.is_valid():
		slide.kill()
	reveal = 0.0
	show()
	slide = create_tween()
	slide.tween_property(self, "reveal", 1.0, ENTRANCE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func close() -> void:
	if slide != null and slide.is_valid():
		slide.kill()
	hide()
	reveal = 0.0
