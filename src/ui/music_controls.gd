extends CanvasLayer
const Ui = preload("res://src/ui/ui_theme.gd")
const Loc = preload("res://src/localization/text.gd")
const INK := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">%s</svg>'
var music
var toggle: Button
var panel: Panel
var title: Label
var pause_button: Button
var next_button: Button
var play_icon: Texture2D
var pause_icon: Texture2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 85
	music = preload("res://src/audio/music_player.gd").new()
	add_child(music)
	var controls := Control.new()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.theme = Ui.create_theme()
	add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toggle = make_button(controls, Vector2(-74, 24), Loc.text("Music player"))
	toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	toggle.icon = Ui.svg_texture(INK % '<g fill="none" stroke="#ede7d4" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18V5l11-2v13 M9 9l11-2"/><ellipse cx="6" cy="18" rx="3" ry="2.5"/><ellipse cx="17" cy="16" rx="3" ry="2.5"/></g>')
	toggle.toggle_mode = true
	toggle.toggled.connect(set_open)
	panel = Panel.new()
	controls.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -324
	panel.offset_right = -24
	panel.offset_top = 72
	panel.offset_bottom = 196
	panel.add_theme_stylebox_override("panel", Ui.style(Color("17252a"), 12, true))
	panel.hide()
	var caption := Ui.label_at(panel, Loc.text("Now playing"), Vector2(16, 12), 12, Ui.MUTED)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = Ui.label_at(panel, "", Vector2(16, 34), 16)
	title.size = Vector2(268, 26)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pause_button = make_button(panel, Vector2(16, 74), "")
	next_button = make_button(panel, Vector2(74, 74), Loc.text("Next track"))
	play_icon = Ui.svg_texture(INK % '<path d="m8 4 13 8-13 8z" fill="#ede7d4"/>')
	pause_icon = Ui.svg_texture(INK % '<path d="M6 4h4v16H6zM14 4h4v16h-4z" fill="#ede7d4"/>')
	next_button.icon = Ui.svg_texture(INK % '<path d="m4 4 12 8L4 20zM17 4h3v16h-3z" fill="#ede7d4"/>')
	pause_button.pressed.connect(music.toggle_pause)
	next_button.pressed.connect(music.next_track)
	music.changed.connect(refresh)
	refresh()
	add_to_group("music_controls")
	refresh_loading()

func refresh_loading() -> void:
	var loading := not get_tree().get_nodes_in_group("loading_screens").is_empty()
	visible = not loading
	if loading: set_open(false)

func make_button(parent: Control, at: Vector2, tip: String) -> Button:
	var button := preload("res://src/ui/tooltip_button.gd").new()
	button.position = at
	button.size = Vector2(50, 40)
	button.tooltip_text = tip
	button.accessibility_name = tip
	parent.add_child(button)
	Sound.bind_button(button)
	return button

func refresh() -> void:
	title.text = music.track_title()
	title.tooltip_text = title.text
	pause_button.icon = play_icon if music.paused else pause_icon
	pause_button.tooltip_text = Loc.text("Resume music") if music.paused else Loc.text("Pause music")
	pause_button.accessibility_name = pause_button.tooltip_text

func set_open(open: bool) -> void:
	panel.visible = open
	toggle.set_pressed_no_signal(open)
	if not open:
		for button in [toggle, pause_button, next_button]:
			button.release_focus()

func _input(event: InputEvent) -> void:
	if not visible or not panel.visible: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_open(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if not panel.get_global_rect().has_point(event.position) and not toggle.get_global_rect().has_point(event.position):
			set_open(false)
