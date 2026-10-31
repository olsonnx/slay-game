extends ColorRect
## Shared in-game confirmation. No native window chrome or independent scaling.
const Loc = preload("res://src/localization/text.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
signal confirmed
signal cancelled
var title := "Confirm action"
var dialog_text := ""
var cancel_text := "Back"
var confirm_text := "Continue"
var primary_confirm := true
var panel: PanelContainer
var title_label: Label
var description: Label
var keep_button: Button
var discard_button: Button
var previous_focus: WeakRef

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.create_theme()
	color = Color(0.04,0.08,0.10,0.72)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	var surface := UiTheme.panel_style()
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: surface.set_content_margin(side,24)
	panel.add_theme_stylebox_override("panel",surface)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",20)
	panel.add_child(content)
	title_label = Label.new()
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size",25)
	content.add_child(title_label)
	description = Label.new()
	description.add_theme_font_size_override("font_size",15)
	description.add_theme_color_override("font_color",UiTheme.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation",12)
	content.add_child(buttons)
	keep_button = make_button(buttons,not primary_confirm)
	keep_button.pressed.connect(cancel)
	discard_button = make_button(buttons,primary_confirm)
	discard_button.pressed.connect(func(): dismiss(); confirmed.emit())
	for button in [keep_button,discard_button]:
		var other: Button = discard_button if button == keep_button else keep_button
		button.focus_next = button.get_path_to(other)
		button.focus_previous = button.get_path_to(other)
		for direction in ["left","right","top","bottom"]: button.set("focus_neighbor_"+direction,button.get_path_to(other))
	resized.connect(update_width)
	update_width()
	hide()

func make_button(parent: Container, primary: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0,44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(button,primary)
	Sound.bind_button(button)
	parent.add_child(button)
	return button

func update_width() -> void:
	if panel != null: panel.custom_minimum_size.x = minf(480,maxf(280,size.x-48))

func popup_centered(_size := Vector2i.ZERO) -> void:
	title_label.text = Loc.text(title)
	description.text = Loc.text(dialog_text)
	keep_button.text = Loc.text(cancel_text)
	discard_button.text = Loc.text(confirm_text)
	previous_focus = weakref(get_viewport().gui_get_focus_owner())
	show()
	move_to_front()
	keep_button.grab_focus()

func dismiss() -> void:
	hide()
	if previous_focus != null:
		var focus = previous_focus.get_ref()
		if is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()

func cancel() -> void:
	dismiss()
	cancelled.emit()

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
