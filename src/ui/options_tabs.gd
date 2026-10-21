extends HBoxContainer
## Equal-width options tabs aligned to the settings content below them.
signal tab_changed(index: int)
const Ui = preload("res://src/ui/ui_theme.gd")
const Loc = preload("res://src/localization/text.gd")
var group := ButtonGroup.new()
var current_tab := 0:
	set(value):
		if value < 0 or value >= get_child_count() or value == current_tab: return
		current_tab = value
		for index in range(get_child_count()): get_child(index).set_pressed_no_signal(index == value)
		tab_changed.emit(value)
var tab_count: int:
	get: return get_child_count()

func _init() -> void:
	add_theme_constant_override("separation", 8)

func add_tab(title: String) -> void:
	var index := get_child_count()
	var button := preload("res://src/ui/tooltip_button.gd").new()
	button.text = Loc.text(title)
	button.tooltip_text = Loc.text(title)
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 36
	button.clip_text = true
	Ui.style_button(button, false, true)
	add_child(button)
	button.set_pressed_no_signal(index == current_tab)
	Sound.bind_button(button, func(): return &"")
	button.pressed.connect(func(): current_tab = index)
	button.gui_input.connect(navigate_tab.bind(index))

func navigate_tab(event: InputEvent, index: int) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode not in [KEY_LEFT, KEY_RIGHT]: return
	current_tab = clampi(index + (-1 if event.keycode == KEY_LEFT else 1), 0, tab_count - 1)
	get_child(current_tab).grab_focus()
	accept_event()

func get_tab_rect(index: int) -> Rect2:
	return get_child(index).get_rect()

func get_tab_title(index: int) -> String:
	return get_child(index).text
