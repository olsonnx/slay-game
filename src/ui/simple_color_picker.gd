extends HBoxContainer
## A color wheel and a six-digit hex field, without advanced color controls.
signal color_changed(value: Color)
const Ui = preload("res://src/ui/ui_theme.gd")
const Loc = preload("res://src/localization/text.gd")
var color := Color("86b998"):
	set(value):
		color = Color(value.r, value.g, value.b, 1.0)
		if swatch != null:
			swatch.color = color
			hex_input.text = "#" + color.to_html(false).to_upper()
			hex_input.remove_theme_color_override("font_color")
			if wheel != null: wheel.color = color
			if wheel_hex != null:
				wheel_hex.text = hex_input.text
				wheel_hex.remove_theme_color_override("font_color")
var swatch: ColorRect
var hex_input: LineEdit
var popup: PopupPanel
var wheel: ColorPicker
var wheel_hex: LineEdit

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var button := Button.new()
	button.custom_minimum_size = Vector2(40, 34)
	button.tooltip_text = Loc.text("Choose a color")
	add_child(button)
	Sound.bind_button(button)
	swatch = ColorRect.new()
	button.add_child(swatch)
	swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	swatch.offset_left = 5
	swatch.offset_right = -5
	swatch.offset_top = 5
	swatch.offset_bottom = -5
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hex_input = LineEdit.new()
	hex_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hex_input.custom_minimum_size.x = 94
	hex_input.max_length = 7
	hex_input.tooltip_text = Loc.text("Hex color, for example #86B998")
	add_child(hex_input)
	hex_input.text_changed.connect(parse_hex)
	popup = PopupPanel.new()
	popup.theme = Ui.create_theme()
	add_child(popup)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	popup.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	wheel = ColorPicker.new()
	wheel.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	wheel.edit_alpha = false
	wheel.edit_intensity = false
	wheel.sampler_visible = false
	wheel.color_modes_visible = false
	wheel.sliders_visible = false
	wheel.hex_visible = false
	wheel.presets_visible = false
	wheel.can_add_swatches = false
	wheel.custom_minimum_size = Vector2(260, 260)
	column.add_child(wheel)
	wheel_hex = LineEdit.new()
	wheel_hex.max_length = 7
	wheel_hex.tooltip_text = hex_input.tooltip_text
	column.add_child(wheel_hex)
	wheel_hex.text_changed.connect(func(value): parse_hex(value, wheel_hex))
	wheel.color_changed.connect(func(value): color = value; color_changed.emit(color))
	button.pressed.connect(func(): wheel.color = color; popup.popup_centered())
	color = color

func valid() -> bool:
	return hex_input != null and hex_input.text.trim_prefix("#").length() == 6 and Color.html_is_valid(hex_input.text)

func parse_hex(value: String, editor: LineEdit = null) -> void:
	var source := editor if editor != null else hex_input
	if value.trim_prefix("#").length() != 6 or not Color.html_is_valid(value):
		source.add_theme_color_override("font_color", Color("dfa08b"))
		if source != hex_input: hex_input.text = value
		if source != wheel_hex: wheel_hex.text = value
		return
	var caret := source.caret_column
	color = Color(value)
	source.caret_column = mini(source.text.length(), caret + (0 if value.begins_with("#") else 1))
	color_changed.emit(color)
