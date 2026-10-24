extends CanvasLayer
## Editor controls and layout emit semantic intentions; no document or board owner.
const Loc = preload("res://src/localization/text.gd")
const Document = preload("res://src/editor/level_document.gd")
const Hud = preload("res://src/ui/game_hud.gd")
const EventText = preload("res://src/ui/event_text.gd")
const Events = preload("res://src/game/event_catalog.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const TOOL_GROUPS := {"Tiles": ["Land", "Mountain", "Bridge", "Water"], "Units": ["Capital", "Scout", "Soldier", "Knight"], "Build": ["House", "Tower", "Bear cave", "Wolf den", "Boar burrow"], "Paint": ["Owner", "Value", "Tree", "Grave", "Mana source", "Clear objects"]}
signal action_requested(action: StringName, arguments: Array)
signal focus_release_requested
signal title_changed(value: String)
signal gold_changed(value: int)
signal owner_changed
signal value_changed
signal random_values_changed(value: bool)
signal brush_changed
signal file_chosen(path: String)
signal discard_cancelled
signal discard_confirmed
signal shortcuts_requested
var context_panel
var context_tool := ""
var variant_choice: OptionButton
var variant_row: HBoxContainer
var owner_row: HBoxContainer
var value_row: HBoxContainer
var context_form: VBoxContainer
var context_description: Label
var context_hint: Label
var event_browser: Control
var event_search: LineEdit
var event_list: ItemList
var event_details: RichTextLabel
var event_count: Label
var selected_event := ""
var events_enabled := true
var ui_root: Control
var panel: Panel
var tool_panel
var tool_group := ""
var tool_buttons: Array[Button] = []
var settings_shade: ColorRect
var help_panel: Panel
var view_button: Button
var brush_label: Label
var heatmap_button: Button
var heatmap_legend: Panel
var heatmap_range_label: Label
var heatmap_gradient: Gradient
var random_toggle: CheckButton
var ui_blockers: Array[Control] = []
var category_buttons: Dictionary = {}
var help_text: Label
var status: Label
var name_edit: LineEdit
var tool_choice: OptionButton
var owner_choice: OptionButton
var value_choice: SpinBox
var size_choice: OptionButton
var gold_choice: SpinBox
var undo_button: Button
var redo_button: Button
var file_dialog: FileDialog
var confirm

func command(action: StringName, arguments: Array = []) -> Callable:
	return func(): action_requested.emit(action, arguments)

func add_label(parent: Node, text: String, font_size := 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("ede7d4"))
	parent.add_child(label)
	return label

func add_button(parent: Node, text: String, action: Callable) -> Button:
	var button := preload("res://src/ui/tooltip_button.gd").new()
	button.text = text
	button.custom_minimum_size.y = 36
	Hud.UiTheme.style_button(button)
	Sound.bind_button(button)
	button.pressed.connect(func(): focus_release_requested.emit(); action.call())
	parent.add_child(button)
	return button

func choice(parent: Node, items: Array) -> OptionButton:
	var select := preload("res://src/ui/tooltip_widgets.gd").Choice.new()
	select.custom_minimum_size.y = 34
	select.focus_mode = Control.FOCUS_NONE
	for item in items: select.add_item(str(item))
	parent.add_child(select)
	Sound.bind_button(select)
	return select

func number(parent: Node, low: int, high: int, initial: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.value = initial
	spin.custom_minimum_size.y = 34
	parent.add_child(spin)
	return spin

func build_ui() -> void:
	build_identity()
	var controls := build_toolbar()
	var dock := build_brush_dock()
	build_tool_panel()
	var files := build_file_actions()
	build_help()
	build_settings()
	build_tool_context()
	build_dialogs()
	ui_blockers = [name_edit, controls, dock, files, tool_panel, context_panel, help_panel]
	build_heatmap()
	shortcuts_requested.emit()

func build_identity() -> void:
	ui_root = Control.new()
	ui_root.theme = Hud.UiTheme.create_theme()
	add_child(ui_root)
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_edit = LineEdit.new()
	name_edit.position = Vector2(28, 20)
	name_edit.size = Vector2(320, 38)
	name_edit.max_length = 80
	name_edit.placeholder_text = "Level name"
	name_edit.add_theme_font_size_override("font_size", 27)
	name_edit.add_theme_color_override("font_color", Color("ede7d4"))
	name_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	name_edit.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	name_edit.add_theme_stylebox_override("focus", Hud.UiTheme.focus_style(Vector2.ZERO))
	ui_root.add_child(name_edit)
	name_edit.text_changed.connect(title_changed.emit)
	status = Hud.label_at(ui_root, "", Vector2(30, 62), 12, Color("b5c6bd"))
	status.size = Vector2(470, 40)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Keep the brush index as the single selection source for buttons/shortcuts.
	tool_choice = choice(ui_root, Document.TOOLS)
	tool_choice.hide()
	tool_choice.item_selected.connect(func(_index: int): brush_changed.emit())

func build_toolbar() -> Control:
	var controls := Control.new()
	ui_root.add_child(controls)
	controls.anchor_left = 1
	controls.anchor_right = 1
	controls.offset_left = -402
	controls.offset_right = -24
	controls.offset_top = 24
	controls.offset_bottom = 64
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_button = hud_button(controls, "", Rect2(0, 0, 50, 40), command(&"toggle_view"))
	view_button.tooltip_text = Loc.text("Overhead / 3D · Tab. Alt + right drag rotates.")
	heatmap_button = hud_button(controls, "", Rect2(60, 0, 50, 40), command(&"toggle_heatmap"))
	heatmap_button.icon = Hud.HEATMAP_ICON
	heatmap_button.toggle_mode = true
	undo_button = hud_button(controls, "Undo", Rect2(120, 0, 64, 40), command(&"undo"))
	redo_button = hud_button(controls, "Redo", Rect2(194, 0, 64, 40), command(&"redo"))
	hud_button(controls, "?", Rect2(268, 0, 44, 40), func(): help_panel.visible = not help_panel.visible)
	var settings_button := hud_button(controls, "", Rect2(322, 0, 50, 40), command(&"toggle_settings"))
	settings_button.icon = Hud.COG_ICON
	settings_button.tooltip_text = Loc.text("Island settings, new island and main menu.")
	return controls

func build_brush_dock() -> Control:
	var dock := Hud.panel(ui_root, Rect2(0, 0, 498, 74))
	pin_bottom(dock, 24, -98, 498, 74)
	var groups := ["Tiles", "Units", "Build", "Paint", "Events", "Start"]
	for index in range(groups.size()):
		var group: String = groups[index]
		var action := command(&"open_tools", [group])
		if group == "Events": action = command(&"select_tool", ["Event"])
		if group == "Start": action = command(&"select_tool", ["Player start"])
		var button := hud_button(dock, group, Rect2(15 + index * 79, 15, 73, 44), action)
		button.toggle_mode = true
		category_buttons[group] = button
	return dock

func build_tool_panel() -> void:
	tool_panel = preload("res://src/ui/context_panel.gd").new()
	tool_panel.add_theme_stylebox_override("panel", Hud.style(Color(0.09, 0.14, 0.16, 0.96), 13, true))
	ui_root.add_child(tool_panel)
	tool_panel.hide()

func build_file_actions() -> Control:
	var files := Control.new()
	ui_root.add_child(files)
	pin_bottom(files, -350, -90, 326, 66, true)
	files.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_button(files, "Save", Rect2(0, 8, 66, 50), command(&"save_level")).tooltip_text = Loc.text("Save level · Ctrl+S. Ctrl+Shift+S: save as.")
	hud_button(files, "Load", Rect2(76, 8, 66, 50), command(&"load")).tooltip_text = Loc.text("Load a level · Ctrl+O")
	hud_button(files, "Playtest →", Rect2(152, 8, 174, 50), command(&"playtest"), true).tooltip_text = Loc.text("Playtest the draft · F5")
	return files

func build_help() -> void:
	help_panel = Hud.panel(ui_root, Rect2(0, 0, 380, 362))
	help_panel.anchor_left = 1
	help_panel.anchor_right = 1
	help_panel.offset_left = -404
	help_panel.offset_right = -24
	help_panel.offset_top = 78
	help_panel.offset_bottom = 440
	Hud.label_at(help_panel, "Editor controls", Vector2(16, 15), 18)
	help_text = Hud.label_at(help_panel, "", Vector2(16, 48), 13)
	help_text.size = Vector2(348, 300)
	help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_panel.hide()

func build_settings() -> void:
	settings_shade = ColorRect.new()
	settings_shade.color = Color(0.04, 0.08, 0.10, 0.60)
	ui_root.add_child(settings_shade)
	settings_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_shade.hide()
	panel = Hud.panel(settings_shade, Rect2(0, 0, 418, 462))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -209
	panel.offset_right = 209
	panel.offset_top = -231
	panel.offset_bottom = 231
	Hud.label_at(panel, "Island settings", Vector2(24, 20), 25)
	Hud.UiTheme.place_close_button(hud_button(panel, "×", Rect2(), command(&"toggle_settings")))
	# Containers own the form flow so another settings row cannot overlap buttons.
	var form := VBoxContainer.new()
	form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	form.offset_left = 24
	form.offset_right = -24
	form.offset_top = 70
	form.offset_bottom = -20
	form.add_theme_constant_override("separation", 14)
	panel.add_child(form)
	gold_choice = number(panel, 0, 9999, 10)
	form_row(form, Loc.text("Starting gold per kingdom"), 216, gold_choice)
	gold_choice.value_changed.connect(func(value: float): gold_changed.emit(int(value)))
	var heading := add_label(form, "New island", 18)
	heading.custom_minimum_size.y = 36
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var size_labels: Array = []
	for size_id in Document.Sizes.IDS:
		size_labels.append(Document.Sizes.choice_label(size_id))
	size_choice = choice(panel, size_labels)
	for index in range(Document.Sizes.IDS.size()):
		size_choice.get_popup().set_item_tooltip(index, Document.Sizes.tile_tooltip(Document.Sizes.IDS[index]))
	form_row(form, Loc.text("Map size"), 114, size_choice)
	var generation := HBoxContainer.new()
	generation.add_theme_constant_override("separation", 10)
	form.add_child(generation)
	for option in [["Generate island", false], ["Blank island", true]]:
		var button := add_button(generation, option[0], command(&"new_island", [option[1]]))
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_button(form, "Center camera", command(&"center")).custom_minimum_size.y = 40
	add_button(form, "Main menu", command(&"back")).custom_minimum_size.y = 40

func build_tool_context() -> void:
	context_panel = preload("res://src/ui/context_panel.gd").new()
	context_panel.add_theme_stylebox_override("panel", Hud.style(Color("17252a"), 13, true))
	ui_root.add_child(context_panel)
	context_panel.hide()
	brush_label = Hud.label_at(context_panel, "Land", Vector2(16, 14), 23, Color("eed3a1"))
	Hud.UiTheme.place_close_button(hud_button(context_panel, "×", Rect2(), command(&"close_context")), 12)
	context_form = VBoxContainer.new()
	context_panel.add_child(context_form)
	context_form.position = Vector2(16, 58)
	context_form.size.x = 386
	context_form.add_theme_constant_override("separation", 12)
	context_form.minimum_size_changed.connect(fit_context)
	variant_choice = choice(context_form, [])
	variant_row = context_row(context_form, Loc.text("Brush"), variant_choice)
	variant_choice.item_selected.connect(func(index: int): action_requested.emit(&"select_tool", [variant_choice.get_item_metadata(index)]))
	owner_choice = choice(context_form, ["Neutral"] + Array(Catalog.FACTIONS))
	owner_row = context_row(context_form, Loc.text("Owner"), owner_choice)
	owner_choice.item_selected.connect(func(_index: int): owner_changed.emit())
	value_choice = number(context_form, 1, 6, 1)
	value_row = context_row(context_form, Loc.text("Land value"), value_choice)
	value_choice.value_changed.connect(func(_value: float): value_changed.emit())
	random_toggle = preload("res://src/ui/tooltip_widgets.gd").Toggle.new()
	random_toggle.text = Loc.text("Random values 1–3")
	random_toggle.focus_mode = Control.FOCUS_NONE
	random_toggle.tooltip_text = Loc.text("Random value 1–3 · V\nApplies to new land / Value painting")
	random_toggle.toggled.connect(random_values_changed.emit)
	context_form.add_child(random_toggle)
	context_description = add_label(context_form, "", 14)
	context_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_hint = add_label(context_form, "", 12)
	context_hint.add_theme_color_override("font_color", Color("9eb2a7"))
	context_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_event_browser()

func context_row(parent: Container, caption: String, field: Control) -> HBoxContainer:
	form_row(parent, caption, 120, field)
	return field.get_parent()

func build_event_browser() -> void:
	event_browser = Control.new()
	context_panel.add_child(event_browser)
	event_browser.position = Vector2(16, 58)
	event_browser.size = Vector2(488, 330)
	event_search = LineEdit.new()
	event_browser.add_child(event_search)
	event_search.size = Vector2(488, 36)
	event_search.placeholder_text = Loc.text("Search events, descriptions or outcomes…")
	event_search.text_changed.connect(func(_query: String): filter_events())
	event_count = Hud.label_at(event_browser, "", Vector2(0, 46), 12, Color("9eb2a7"))
	var author := Button.new()
	author.text = Loc.text("Create events…")
	author.position = Vector2(256,41)
	author.size = Vector2(136,28)
	author.pressed.connect(command(&"open_event_editor"))
	event_browser.add_child(author)
	var reload := Button.new()
	reload.text = Loc.text("Reload")
	reload.position = Vector2(400,41)
	reload.size = Vector2(88,28)
	reload.tooltip_text = Loc.text("Load events saved by the Event Editor")
	reload.pressed.connect(command(&"reload_events"))
	event_browser.add_child(reload)
	event_list = ItemList.new()
	event_browser.add_child(event_list)
	event_list.position = Vector2(0, 74)
	event_list.size = Vector2(204, 208)
	event_list.item_selected.connect(show_event)
	event_details = RichTextLabel.new()
	event_details.bbcode_enabled = true
	event_browser.add_child(event_details)
	event_details.position = Vector2(220, 74)
	event_details.size = Vector2(268, 208)
	var hint := Hud.label_at(event_browser, Loc.text("Select an event, then paint. Every encounter resolves on the first visit."), Vector2(0, 296), 12, Color("9eb2a7"))
	hint.size = Vector2(488, 32)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_browser.hide()
	filter_events(false)

func tool_group_for(tool: String) -> String:
	for group in TOOL_GROUPS:
		if tool in TOOL_GROUPS[group]: return group
	return "Events" if tool == "Event" else "Start"

func render_context(tool: String, restart := false) -> void:
	context_tool = tool
	brush_label.text = Loc.text(tool)
	var group := tool_group_for(tool)
	for category in category_buttons:
		category_buttons[category].set_pressed_no_signal(category == group)
	variant_choice.clear()
	var variants: Array = TOOL_GROUPS.get(group, [])
	for variant in variants:
		var index := variant_choice.item_count
		variant_choice.add_item(Loc.text(variant))
		variant_choice.set_item_metadata(index, variant)
		variant_choice.set_item_disabled(index, not events_enabled and variant in Document.MODERN_TOOLS)
		if variant == tool: variant_choice.select(index)
	variant_row.visible = variants.size() > 1
	owner_row.visible = tool in ["Land", "Owner"]
	value_row.visible = tool in ["Land", "Value"]
	random_toggle.visible = tool in ["Land", "Value"]
	context_form.visible = tool != "Event"
	event_browser.visible = tool == "Event"
	var descriptions := {
		"Land": "New land uses this owner and value. Redrawing existing land keeps its owner and value.",
		"Water": "Remove provinces and everything on them.",
		"Mountain": "Turn existing land into neutral, impassable mountains with value 0. Clears all objects.",
		"Bridge": "Place neutral, zero-value bridges over water. Units can cross them during play.",
		"Owner": "Change province ownership. Capitals follow the new owner; neutral land cannot keep units or buildings.",
		"Value": "Set the value of existing land, from 1 to 6. Keeps ownership and objects.",
		"Capital": "Place a capital on owned land. Uses that province's owner and keeps mana sources.",
		"Scout": "Place a Scout on owned land. Keeps capitals and mana sources; replaces other objects.",
		"Soldier": "Place a Soldier on owned land. Keeps capitals and mana sources; replaces other objects.",
		"Knight": "Place a Knight on owned land. Keeps capitals and mana sources; replaces other objects.",
		"House": "Place a house on owned land. Uses that province's owner and keeps mana sources.",
		"Tower": "Place a tower on owned land. Uses that province's owner and keeps mana sources.",
		"Bear cave": "Place a bear cave on neutral land. Replaces other objects. Its bear emerges on the first World turn.",
		"Wolf den": "Place a wolf den on neutral land. Replaces other objects. Its wolf emerges on the first World turn.",
		"Boar burrow": "Place a boar burrow on neutral land. Replaces other objects. Its boar emerges on the first World turn.",
		"Tree": "Place trees on land. Replaces other objects and keeps mana sources.",
		"Grave": "Place graves on land. Replaces other objects and keeps mana sources.",
		"Mana source": "Add mana sources to land without replacing its units, buildings or decorations.",
		"Clear objects": "Clear units, buildings, capitals, events and decorations. Keeps terrain, owner and value.",
		"Player start": "Mark an owned province as the player's starting kingdom. The marker follows its current owner and keeps all objects."
	}
	context_description.text = Loc.text(descriptions.get(tool, ""))
	context_hint.text = Loc.text("Left drag: place · Right drag: delete provinces") if tool in Document.TILE_TOOLS else Loc.text("Left drag: paint · Right drag: clear decorations")
	if tool == "Water": context_hint.text = Loc.text("Left or right drag: delete provinces")
	if tool == "Player start": context_hint.text = Loc.text("Left click: place or move start · Right click the marker: remove start")
	# Use the same animated panel as province details, keeping the map interactive.
	context_form.size = Vector2(386, 0)
	context_panel.panel_height = 404 if tool == "Event" else maxf(180, 74 + context_form.get_combined_minimum_size().y)
	context_panel.rest_top = -110 - context_panel.panel_height
	pin_bottom(context_panel, 24, context_panel.rest_top, 520 if tool == "Event" else 418, context_panel.panel_height)
	context_panel.reveal = context_panel.reveal
	context_panel.open(restart)

func fit_context() -> void:
	if context_tool == "" or context_tool == "Event": return
	context_panel.panel_height = maxf(180, 74 + context_form.get_combined_minimum_size().y)
	context_panel.rest_top = -110 - context_panel.panel_height
	context_panel.reveal = context_panel.reveal

func filter_events(notify_selection := true) -> void:
	event_list.clear()
	var query := event_search.text.strip_edges().to_lower()
	for id in Events.EVENTS:
		var entry: Dictionary = Events.EVENTS[id]
		var searchable := str(id) + " " + Loc.text(entry["title"]) + " " + Loc.text(entry["text"]) + " " + Loc.text(entry.get("requirements", ""))
		for outcome in entry["choices"]:
			searchable += " " + Loc.text(outcome[0]) + " " + Loc.text(outcome[1])
		var matches := true
		for word in query.split(" ", false):
			if not searchable.to_lower().contains(word): matches = false
		if not matches: continue
		var index := event_list.add_item(Loc.text(entry["title"]))
		event_list.set_item_metadata(index, id)
		event_list.set_item_tooltip(index, str(id) + " · " + Loc.text(entry["title"]))
	event_count.text = Loc.text("%d / %d events") % [event_list.item_count, Events.EVENTS.size()]
	var selected := -1
	for index in range(event_list.item_count):
		if event_list.get_item_metadata(index) == selected_event: selected = index
	if selected < 0 and event_list.item_count > 0: selected = 0
	if selected >= 0:
		event_list.select(selected)
		show_event(selected, notify_selection)
	else:
		event_details.text = Loc.text("No matching events. Try another search.")
		if notify_selection: action_requested.emit(&"event_selected", [""])

func show_event(index: int, notify_selection := true) -> void:
	selected_event = event_list.get_item_metadata(index)
	var entry: Dictionary = Events.EVENTS[selected_event]
	var plain := Loc.text(entry["title"]) + "\n" + selected_event + "\n\n" + Loc.text(entry["text"])
	plain += "\n\n" + Loc.text("Main outcome requirements: %s") % Loc.text(entry.get("requirements", "Any army entering this province.")) + "\n" + Loc.text("Unmet requirements draw a weighted event that can affect the arriving army. The lumberjack adapts to the current forest coverage.")
	for outcome in entry["choices"]:
		plain += "\n\n" + Loc.text(outcome[0]) + "\n" + Loc.text(outcome[1])
	event_details.text = EventText.rich_text(plain)
	event_details.scroll_to_line(0)
	if notify_selection: action_requested.emit(&"event_selected", [selected_event])

func build_dialogs() -> void:
	file_dialog = FileDialog.new()
	file_dialog.theme = ui_root.theme
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray([Loc.text("*.json ; Slay levels")])
	file_dialog.file_selected.connect(file_chosen.emit)
	add_child(file_dialog)
	confirm = preload("res://src/editor/discard_dialog.gd").new()
	confirm.theme = ui_root.theme
	ui_root.add_child(confirm)
	confirm.confirmed.connect(discard_confirmed.emit)
	confirm.cancelled.connect(discard_cancelled.emit)

func build_heatmap() -> void:
	heatmap_legend = Hud.panel(ui_root, Rect2(24, 104, 254, 78), false)
	Hud.label_at(heatmap_legend, "Province value", Vector2(12, 8), 14)
	var zero := ColorRect.new()
	zero.color = Color.BLACK
	zero.position = Vector2(12, 34)
	zero.size = Vector2(20, 15)
	zero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heatmap_legend.add_child(zero)
	heatmap_gradient = Gradient.new()
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = heatmap_gradient
	var bar := TextureRect.new()
	bar.texture = gradient_texture
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.position = Vector2(44, 34)
	bar.size = Vector2(198, 15)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heatmap_legend.add_child(bar)
	heatmap_range_label = Hud.label_at(heatmap_legend, "", Vector2(12, 52), 12)
	heatmap_legend.hide()

func hud_button(parent: Node, text: String, rect: Rect2, action: Callable, primary := false) -> Button:
	var button := add_button(parent, text, action)
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	Hud.UiTheme.style_button(button,primary)
	return button

func pin_bottom(control: Control, left: float, top: float, width: float, height: float, right := false) -> void:
	control.anchor_top = 1
	control.anchor_bottom = 1
	control.anchor_left = 1 if right else 0
	control.anchor_right = control.anchor_left
	control.offset_left = left
	control.offset_right = left + width
	control.offset_top = top
	control.offset_bottom = top + height

func render_tools(group: String, rule_mode: String, active_tool: String, texture: Callable) -> void:
	tool_group = group
	for child in tool_panel.get_children():
		tool_panel.remove_child(child)
		child.queue_free()
	tool_buttons.clear()
	var tools: Array = TOOL_GROUPS[group]
	var height := 62 + ceili(tools.size() / 3.0) * 108 + 15
	tool_panel.panel_height = height
	tool_panel.rest_top = -110 - height
	pin_bottom(tool_panel, 24, tool_panel.rest_top, 418, height)
	Hud.label_at(tool_panel, group, Vector2(15, 20), 16)
	Hud.UiTheme.place_close_button(hud_button(tool_panel, "×", Rect2(), func(): tool_panel.close()))
	for index in range(tools.size()):
		var tool: String = tools[index]
		var button := hud_button(tool_panel, "", Rect2(15 + (index % 3) * 132, 62 + (index / 3) * 108, 124, 100), command(&"select_tool", [tool]))
		button.toggle_mode = true
		button.set_meta("tool", tool)
		button.set_pressed_no_signal(active_tool == tool)
		button.tooltip_text = Loc.text("%s · %d\nLeft: place · right: %s") % [Loc.text(tool), index + 1, Loc.text("delete tile" if tool in Document.TILE_TOOLS else "clear decorations")]
		var label := Hud.label_at(button, tool, Vector2(0, 74), 14)
		label.size = Vector2(124, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Hud.label_at(button, str(index + 1), Vector2(8, 5), 11, Color("9eb2a7"))
		if tool in ["Scout", "Soldier", "Knight"] or tool in Document.LAIR_TOOLS:
			var image := TextureRect.new()
			if tool in Document.LAIR_TOOLS:
				var atlas := AtlasTexture.new()
				atlas.atlas = preload("res://src/rendering/wildlife_presentation.gd").SHEETS[Document.LAIR_TOOLS[tool]]
				atlas.region = Rect2(0,12,32,20)
				image.texture = atlas
			else:
				image.texture = texture.call(["Scout", "Soldier", "Knight"].find(tool) + 1, maxi(0, owner_choice.selected - 1))
			image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.position = Vector2(30, 8)
			image.size = Vector2(64, 62)
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(image)
		else:
			var symbols := {"Land": "⬡", "Mountain": "▲", "Tree": "♣", "Grave": "†", "Mana source": "◆", "Capital": "♜", "House": "⌂", "Tower": "♜", "Bridge": "═", "Owner": "⚑", "Value": "123", "Water": "≈", "Clear objects": "×"}
			var icon := Hud.label_at(button, symbols[tool], Vector2(0, 10), 38, Color("c8d3a1"))
			icon.size = Vector2(124, 58)
			icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tool_buttons.append(button)
	tool_panel.open(true)

func form_row(parent: Container, caption: String, label_width: float, field: Control) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 36
	row.add_theme_constant_override("separation", 0)
	parent.add_child(row)
	var label := add_label(row, caption)
	label.custom_minimum_size.x = label_width
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	field.reparent(row)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
