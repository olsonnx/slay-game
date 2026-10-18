extends CanvasLayer
const Loc = preload("res://src/localization/text.gd")
## Always visible across menu/gameplay; F3 toggles without touching display settings.
var menu_background
var readout: Label
var elapsed := 0.0
var previous_menu_frames := 0
var menu_fps := 0
var app_frames := 0
var previous_app_frames := 0
var app_fps := 0
var shown := true
var binding_capture_active: Callable

func _init(background) -> void:
	menu_background = background

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	readout = Label.new()
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_font_size_override("font_size", 12)
	readout.add_theme_color_override("font_color", Color("c8d4c8"))
	readout.add_theme_constant_override("outline_size", 3)
	readout.add_theme_color_override("font_outline_color", Color("102129"))
	add_child(readout)
	readout.anchor_left = 1
	readout.anchor_right = 1
	readout.offset_left = -250
	readout.offset_right = -24
	readout.offset_top = 3
	readout.offset_bottom = 38
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	refresh()

func _on_frame_drawn() -> void:
	app_frames += 1

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.25:
		return
	menu_fps = roundi((menu_background.rendered_frames - previous_menu_frames) / elapsed)
	app_fps = roundi((app_frames - previous_app_frames) / elapsed)
	previous_app_frames = app_frames
	previous_menu_frames = menu_background.rendered_frames
	elapsed = 0.0
	refresh()

func refresh() -> void:
	var fps := app_fps
	readout.text = Loc.text("%d FPS · %.1f ms") % [fps, 1000.0 / fps] if fps > 0 else Loc.text("FPS · measuring…")
	if menu_background.active:
		readout.text += Loc.text("\nMenu: %d FPS") % menu_fps
	readout.visible = shown

func _input(event: InputEvent) -> void:
	# Let the controls page explain reserved keys instead of swallowing capture.
	if binding_capture_active.is_valid() and binding_capture_active.call(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		shown = not shown
		readout.visible = shown
		get_viewport().set_input_as_handled()
