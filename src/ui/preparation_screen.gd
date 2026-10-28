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
var hex_art

func _enter_tree() -> void:
	add_to_group("loading_screens")
	get_tree().call_group("music_controls", "refresh_loading")

func _exit_tree() -> void:
	remove_from_group("loading_screens")
	get_tree().call_group("music_controls", "refresh_loading")

func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	cover = ColorRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.color = Color("172f39")
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.theme = preload("res://src/ui/ui_theme.gd").create_theme()
	add_child(cover)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 360
	content.add_theme_constant_override("separation", 12)
	center.add_child(content)
	hex_art = preload("res://src/ui/hex_loading_art.gd").new()
	content.add_child(hex_art)
	caption = Label.new()
	caption.text = Loc.text("Creating map...")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color("ead29e"))
	content.add_child(caption)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 6
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
	percentage.add_theme_font_size_override("font_size", 14)
	percentage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	percentage.add_theme_color_override("font_color", Color("ead29e"))
	content.add_child(percentage)
	set_progress(progress)

func set_progress(value: float) -> void:
	progress = clampf(value, progress, 1.0)
	if is_instance_valid(progress_bar):
		progress_bar.value = progress
		percentage.text = "%d%%" % int(progress * 100.0)
		hex_art.progress = progress
		hex_art.queue_redraw()
	progress_changed.emit(progress)

func _process(delta: float) -> void:
	elapsed += delta
	hex_art.animated = Video.level_transitions and not Video.reduced_motion
	if hex_art.animated:
		hex_art.elapsed = elapsed
		hex_art.queue_redraw()

func reveal() -> void:
	set_progress(1.0)
	# Give the destination a real frame beneath the opaque cover before blending.
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	var tween := create_tween()
	tween.tween_property(cover, "modulate:a", 0.0, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	queue_free()
