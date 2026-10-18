extends CanvasLayer
## Opaque cover lets the board render and upload resources during preparation.
var cover: ColorRect
var caption: Label
var elapsed := 0.0

func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	cover = ColorRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.color = Color("253d47")
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(cover)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(center)
	caption = Label.new()
	caption.text = "Preparing island…"
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color("ead29e"))
	center.add_child(caption)

func _process(delta: float) -> void:
	elapsed += delta
	caption.modulate.a = 0.8 + sin(elapsed * 3.0) * 0.2

func reveal() -> void:
	var tween := create_tween()
	tween.tween_property(cover, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
