extends RefCounted
## Layout built from the same panels, type and controls as the session menus.
const Ui = preload("res://src/ui/ui_theme.gd")
const Loc = preload("res://src/localization/text.gd")

static func panel_style(padding := Vector2(24, 20)) -> StyleBoxFlat:
	var box := Ui.style(Color("17252a"), 13, true)
	box.content_margin_left = padding.x
	box.content_margin_right = padding.x
	box.content_margin_top = padding.y
	box.content_margin_bottom = padding.y
	return box

static func label(parent: Node, text: String, size := 14, color := Ui.TEXT) -> Label:
	var node := Label.new()
	node.text = Loc.text(text)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

static func build(v) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	v.add_child(layer)
	var ui := Control.new()
	v.interface = ui
	ui.theme = Ui.create_theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.background = ColorRect.new()
	v.background.color = Color("172c33")
	ui.add_child(v.background)
	v.background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if v.library_backdrop != null:
		var image := TextureRect.new()
		image.texture = v.library_backdrop
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.background.add_child(image)
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var shade := ColorRect.new()
		shade.color = Color(0.05, 0.09, 0.10, 0.50)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.background.add_child(shade)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_header(v, ui)
	build_library(v, ui)
	build_transport(v, ui)

static func icon_button(v, parent: Node, kind: String, hint: String, callback: Callable, primary := false) -> Button:
	var button: Button = v.make_button(parent, hint, callback, primary)
	button.text = ""
	button.name = kind.capitalize()
	button.icon = preload("res://src/ui/replay_icons.gd").get_icon(kind, primary)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(40, 40)
	Ui.style_button(button, primary, false, true)
	return button

static func build_header(v, ui: Control) -> void:
	v.header_panel = PanelContainer.new()
	ui.add_child(v.header_panel)
	v.header_panel.position = Vector2(20, 20)
	v.header_panel.add_theme_stylebox_override("panel", panel_style(Vector2(14, 12)))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	v.header_panel.add_child(content)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	v.back_button = icon_button(v, row, "back", "Back to main menu", v.request_close)
	v.title = label(row, "Replays", 18)
	v.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.legend = HFlowContainer.new()
	v.legend.add_theme_constant_override("h_separation", 16)
	v.legend.add_theme_constant_override("v_separation", 4)
	content.add_child(v.legend)

static func build_library(v, ui: Control) -> void:
	v.library = PanelContainer.new()
	ui.add_child(v.library)
	v.library.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.library.offset_left = -410
	v.library.offset_right = 410
	v.library.offset_top = -260
	v.library.offset_bottom = 260
	v.library.add_theme_stylebox_override("panel", panel_style())
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	v.library.add_child(content)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 6)
	content.add_child(heading)
	label(heading, "Replays", 28)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	content.add_child(body)
	var recordings := VBoxContainer.new()
	recordings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recordings.add_theme_constant_override("separation", 10)
	body.add_child(recordings)
	label(recordings, "Saved replays", 16)
	v.list = ItemList.new()
	v.list.custom_minimum_size = Vector2(420, 260)
	v.list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.list.add_theme_font_size_override("font_size", 16)
	v.list.add_theme_constant_override("v_separation", 14)
	recordings.add_child(v.list)
	v.list.item_selected.connect(v.select_recording)
	v.list.item_activated.connect(func(index): v.load_recording(v.paths[index]))
	var info := PanelContainer.new()
	info.custom_minimum_size.x = 300
	info.add_theme_stylebox_override("panel", Ui.control_style(Color("1c2d32"), Vector2(16, 16)))
	body.add_child(info)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info.add_child(scroll)
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_constant_override("separation", 10)
	scroll.add_child(summary)
	v.preview_title = label(summary, "Choose a recording", 18)
	v.preview_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.preview_result = label(summary, "", 16, Ui.ACCENT)
	v.preview_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.preview_details = label(summary, "", 14, Ui.MUTED)
	v.preview_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.message = label(summary, "", 13, Ui.MUTED)
	v.message.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	content.add_child(footer)
	v.watch_button = v.make_button(footer, "Watch replay", v.watch_selected, true)
	v.watch_button.custom_minimum_size.x = 164
	v.load_buttons = [v.watch_button, v.make_button(footer, "Open replay file", v.open_file_dialog), v.make_button(footer, "Refresh", v.refresh_library)]
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	v.make_button(footer, "Back", v.request_close).custom_minimum_size.x = 88

static func build_transport(v, ui: Control) -> void:
	v.transport = PanelContainer.new()
	ui.add_child(v.transport)
	v.transport.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	v.transport.offset_left = -410
	v.transport.offset_right = 410
	v.transport.offset_top = -140
	v.transport.offset_bottom = -20
	v.transport.add_theme_stylebox_override("panel", panel_style(Vector2(16, 12)))
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	v.transport.add_child(controls)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 16)
	controls.add_child(status)
	v.details = label(status, "Starting position", 16)
	v.details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.progress = label(status, "", 14, Ui.MUTED)
	v.slider = preload("res://src/ui/tooltip_widgets.gd").RangeSlider.new()
	v.slider.step = 1
	v.slider.custom_minimum_size.y = 22
	v.slider.tooltip_text = Loc.text("Timeline\nDrag to seek. Left / Right: previous / next action.")
	controls.add_child(v.slider)
	v.slider.value_changed.connect(func(value): v.requested_step = int(value))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	controls.add_child(row)
	v.start_button = icon_button(v, row, "start", "Go to start", func(): v.seek_to(0))
	v.previous_button = icon_button(v, row, "previous", "Previous action · Left arrow", func(): v.seek_to(v.timeline.cursor - 1))
	v.play_button = icon_button(v, row, "play", "Play · Space", v.toggle_play, true)
	v.next_button = icon_button(v, row, "next", "Next action · Right arrow", func(): v.seek_to(v.timeline.cursor + 1))
	v.end_button = icon_button(v, row, "end", "Go to end · End", func(): v.seek_to(v.timeline.steps.size() - 1))
	v.speed_choice = preload("res://src/ui/tooltip_widgets.gd").Choice.new()
	for value in v.PLAYBACK_SPEEDS: v.speed_choice.add_item("%s×" % (str(int(value)) if value >= 1 else "0.5"))
	v.speed_choice.select(1)
	v.speed_choice.custom_minimum_size = Vector2(72, 40)
	v.speed_choice.tooltip_text = Loc.text("Playback speed\n0.5× to 16×. Applies to movement animations too.")
	row.add_child(v.speed_choice)
	v.get_node("/root/Sound").bind_button(v.speed_choice)
	v.speed_choice.item_selected.connect(v.select_speed)
	v.movement_checkbox = preload("res://src/ui/tooltip_widgets.gd").Checkbox.new()
	v.movement_checkbox.text = Loc.text("Movement only")
	v.movement_checkbox.tooltip_text = Loc.text("Movement only\nSkip non-movement steps while keeping all recorded state changes. The final position remains available.")
	v.movement_checkbox.add_theme_font_size_override("font_size", 14)
	v.movement_checkbox.add_theme_stylebox_override("focus", Ui.focus_style(Vector2(4, 4)))
	for checked in [true, false]:
		var tick := '<path d="m5 10 3 3 7-7" fill="none" stroke="#20332d" stroke-width="2"/>' if checked else ""
		var texture := Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect x="2" y="2" width="16" height="16" rx="3" fill="%s" stroke="#9eb2a7"/>%s</svg>' % ["#c8d3a1" if checked else "#1c2d32", tick])
		v.movement_checkbox.add_theme_icon_override("checked" if checked else "unchecked", texture)
	row.add_child(v.movement_checkbox)
	v.movement_checkbox.toggled.connect(v.set_movement_only)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	v.browse_button = icon_button(v, row, "recording", "Choose recording · Escape", v.show_library)
	v.camera_button = icon_button(v, row, "camera", "Camera", v.camera_activated)
	v.camera_hold_indicator = preload("res://src/ui/hold_indicator.gd").new()
	v.camera_button.add_child(v.camera_hold_indicator)
	v.camera_hold_indicator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.camera_button.button_down.connect(v.begin_camera_press)
	v.camera_button.button_up.connect(v.end_camera_press)
	v.camera_button.mouse_exited.connect(v.cancel_camera_press)
	v.hide_ui_button = icon_button(v, row, "hide", "Hide UI · F10\nPress F10 or Escape to show the controls again.", v.toggle_ui)
	v.restore_ui_button = icon_button(v, ui, "show", "Show UI · F10", v.toggle_ui)
	v.restore_ui_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	v.restore_ui_button.offset_left = -60
	v.restore_ui_button.offset_top = -60
	v.restore_ui_button.offset_right = -20
	v.restore_ui_button.offset_bottom = -20
	v.restore_ui_button.hide()
