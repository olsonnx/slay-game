extends CanvasLayer
## Opaque cover lets the board render and upload resources during preparation.
signal progress_changed(value: float)
const Loc = preload("res://src/localization/text.gd")
var cover: ColorRect
var caption: Label
var progress_bar: ProgressBar
var percentage: Label
var progress := 0.0
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
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 280
	content.add_theme_constant_override("separation", 16)
	center.add_child(content)
	caption = Label.new()
	caption.text = Loc.text("Creating map...")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color("ead29e"))
	content.add_child(caption)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 14
	progress_bar.max_value = 1.0
	progress_bar.step = 0.0
	progress_bar.show_percentage = false
	for style_name in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("172e38") if style_name == "background" else Color("ead29e")
		style.set_corner_radius_all(5)
		progress_bar.add_theme_stylebox_override(style_name, style)
	content.add_child(progress_bar)
	percentage = Label.new()
	percentage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	percentage.add_theme_color_override("font_color", Color("ead29e"))
	content.add_child(percentage)
	set_progress(progress)

func set_progress(value: float) -> void:
	progress = clampf(value, progress, 1.0)
	if is_instance_valid(progress_bar):
		progress_bar.value = progress
		percentage.text = "%d%%" % int(progress * 100.0)
	progress_changed.emit(progress)

func _process(delta: float) -> void:
	elapsed += delta
	caption.modulate.a = 0.8 + sin(elapsed * 3.0) * 0.2

func reveal() -> void:
	set_progress(1.0)
	var tween := create_tween()
	tween.tween_property(cover, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
