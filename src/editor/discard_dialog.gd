extends ColorRect
## A blocking in-game confirmation, sharing the editor's theme and buttons.
const Loc = preload("res://src/localization/text.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
signal confirmed
signal cancelled
var panel: PanelContainer
var keep_button: Button
var discard_button: Button
var previous_focus: WeakRef

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.04,0.08,0.10,0.65)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 480
	panel.add_theme_stylebox_override("panel",UiTheme.control_style(Color("17252a"),Vector2(24,24),13))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",20)
	panel.add_child(content)
	var title := Label.new()
	title.text = Loc.text("Unsaved level")
	title.add_theme_font_size_override("font_size",25)
	content.add_child(title)
	var description := Label.new()
	description.text = Loc.text("Discard changes to this level?")
	description.add_theme_font_size_override("font_size",16)
	description.add_theme_color_override("font_color",Color("c5cdbb"))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation",12)
	content.add_child(buttons)
	keep_button = make_button(buttons,Loc.text("Keep editing"),true)
	keep_button.pressed.connect(cancel)
	discard_button = make_button(buttons,Loc.text("Discard changes"),false)
	discard_button.pressed.connect(func(): hide(); confirmed.emit())
	# Tab and directional focus stay inside the blocking confirmation.
	for button in [keep_button,discard_button]:
		var other: Button = discard_button if button == keep_button else keep_button
		button.focus_next = button.get_path_to(other)
		button.focus_previous = button.get_path_to(other)
		button.focus_neighbor_left = button.get_path_to(other)
		button.focus_neighbor_right = button.get_path_to(other)
		button.focus_neighbor_top = button.get_path_to(other)
		button.focus_neighbor_bottom = button.get_path_to(other)
	hide()

func make_button(parent: Container, text_value: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0,48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(button,primary)
	Sound.bind_button(button)
	parent.add_child(button)
	return button

func popup_centered(_size := Vector2i.ZERO) -> void:
	previous_focus = weakref(get_viewport().gui_get_focus_owner())
	show()
	move_to_front()
	keep_button.grab_focus()

func cancel() -> void:
	hide()
	if previous_focus != null:
		var focus = previous_focus.get_ref()
		if is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()
	cancelled.emit()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
