extends Panel
signal saved
signal cancelled
signal deleted
const Ui = preload("res://src/ui/ui_theme.gd")
const Loc = preload("res://src/localization/text.gd")
const Flag = preload("res://src/ui/kingdom_flag.gd")
const Profile = preload("res://src/settings/player_profile.gd")
const Clock = preload("res://src/game/match_clock.gd")
var title: Label
var stats_view: Control
var edit_view: Control
var country_view: Control
var flag_view: Control
var edit_tabs: TabBar
var edit_button: Button
var delete_button: Button
var delete_confirmation: Panel
var confirm_delete_button: Button
var name_input: LineEdit
var motto_input: LineEdit
var country_color
var field_color
var accent_color
var symbol_color
var pattern: OptionButton
var symbol: OptionButton
var placement: OptionButton
var symbol_scale: HSlider
var preview
var game_preview
var save_button: Button
var cancel_button: Button
var status: Label
var statistics: Dictionary = {}
var kingdom_title: Label
var motto_label: Label
var xp_progress
var required := false
var editing := false
var loading := false

func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -400
	offset_right = 400
	offset_top = -320
	offset_bottom = 320
	add_theme_stylebox_override("panel", Ui.style(Color("17252a"), 13, true))
	title = Ui.label_at(self, "", Vector2(24, 18), 28)
	title.size = Vector2(680, 36)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	edit_button = action(self, "", Vector2(728, 24), Vector2(48, 40))
	edit_button.icon = preload("res://src/ui/menu_icons.gd").brush()
	edit_button.tooltip_text = Loc.text("Customize your kingdom")
	edit_button.pressed.connect(func(): set_editing(true))
	stats_view = Control.new()
	stats_view.position.y = 84
	add_child(stats_view)
	edit_view = Control.new()
	edit_view.position.y = 90
	add_child(edit_view)
	build_stats()
	build_editor()
	preview = Flag.new()
	add_child(preview)
	game_preview = preload("res://src/ui/profile_country_preview.gd").new()
	add_child(game_preview)
	status = Ui.label_at(self, "", Vector2(24, 548), 13, Color("dfa08b"))
	status.size = Vector2(752, 24)
	save_button = action(self, "Save changes", Vector2(24, 576), Vector2(364, 40), true)
	save_button.pressed.connect(commit)
	cancel_button = action(self, "Back", Vector2(412, 576), Vector2(364, 40))
	cancel_button.pressed.connect(back)
	delete_button = action(self, "Delete profile", Vector2(24, 576), Vector2(180, 40))
	Ui.button_foreground(delete_button, Color("dfa08b"))
	delete_button.pressed.connect(func(): delete_confirmation.show())
	build_delete_confirmation()
	PlayerProfile.changed.connect(refresh_statistics)
	SteamOnline.changed.connect(refresh_player_name)

func build_stats() -> void:
	kingdom_title = Ui.label_at(stats_view, "", Vector2(140, 16), 22)
	kingdom_title.size = Vector2(396, 54)
	kingdom_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kingdom_title.max_lines_visible = 2
	kingdom_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	motto_label = Ui.label_at(stats_view, "", Vector2(140, 72), 14, Ui.MUTED)
	motto_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	motto_label.size = Vector2(396, 40)
	xp_progress = preload("res://src/ui/account_xp_bar.gd").new()
	xp_progress.position = Vector2(24, 112)
	xp_progress.size = Vector2(512, 64)
	stats_view.add_child(xp_progress)
	Ui.label_at(stats_view, "Match record", Vector2(24, 192), 20)
	var labels := ["Matches played", "Victories", "Defeats", "Win rate", "Average match", "Total play time", "Best win streak", "Longest match"]
	for index in range(labels.size()):
		var at := Vector2(24 + index % 2 * 256, 230 + index / 2 * 50)
		Ui.label_at(stats_view, labels[index], at, 13, Ui.MUTED)
		statistics[labels[index]] = Ui.label_at(stats_view, "0", at + Vector2(0, 18), 22)

func build_editor() -> void:
	edit_tabs = TabBar.new()
	edit_tabs.position = Vector2(24, 0)
	edit_tabs.size = Vector2(752, 40)
	edit_tabs.add_tab(Loc.text("Country"))
	edit_tabs.add_tab(Loc.text("Flag"))
	edit_view.add_child(edit_tabs)
	country_view = Control.new()
	country_view.position.y = 58
	edit_view.add_child(country_view)
	flag_view = Control.new()
	flag_view.position.y = 58
	edit_view.add_child(flag_view)
	edit_tabs.tab_changed.connect(func(_tab): update_editor_tab())
	Ui.label_at(country_view, "Kingdom name", Vector2(24, 8), 14, Ui.MUTED)
	name_input = text_input(country_view, Vector2(24, 36), 32)
	name_input.placeholder_text = Loc.text("Name your kingdom")
	name_input.text_changed.connect(func(_text): refresh_preview())
	Ui.label_at(country_view, "Motto (optional)", Vector2(24, 104), 14, Ui.MUTED)
	motto_input = text_input(country_view, Vector2(24, 132), 64)
	Ui.label_at(country_view, "Country color", Vector2(24, 200), 14, Ui.MUTED)
	country_color = color_input(country_view, Vector2(24, 228), Vector2(320, 40))
	Ui.label_at(country_view, "Your country in game", Vector2(400, 8), 14, Ui.MUTED)
	Ui.label_at(flag_view, "Pattern", Vector2(24, 8), 14, Ui.MUTED)
	pattern = choice(["Solid", "Horizontal halves", "Vertical halves", "Diagonal", "Cross", "Saltire", "Border"], Vector2(152, 0))
	Ui.label_at(flag_view, "Field", Vector2(24, 60), 14, Ui.MUTED)
	field_color = color_input(flag_view, Vector2(152, 52), Vector2(192, 36))
	Ui.label_at(flag_view, "Accent", Vector2(24, 112), 14, Ui.MUTED)
	accent_color = color_input(flag_view, Vector2(152, 104), Vector2(192, 36))
	Ui.label_at(flag_view, "Emblem", Vector2(24, 180), 14, Ui.MUTED)
	symbol = choice(["Crown", "Star", "Sun", "Tower", "Tree", "Sword", "Diamond", "None"], Vector2(152, 172))
	Ui.label_at(flag_view, "Color", Vector2(24, 232), 14, Ui.MUTED)
	symbol_color = color_input(flag_view, Vector2(152, 224), Vector2(192, 36))
	Ui.label_at(flag_view, "Size", Vector2(24, 284), 14, Ui.MUTED)
	symbol_scale = HSlider.new()
	symbol_scale.position = Vector2(152, 282)
	symbol_scale.size = Vector2(192, 24)
	symbol_scale.min_value = 0.2
	symbol_scale.max_value = 0.65
	symbol_scale.step = 0.01
	flag_view.add_child(symbol_scale)
	symbol_scale.value_changed.connect(func(_value): refresh_preview())
	Ui.label_at(flag_view, "Position", Vector2(24, 336), 14, Ui.MUTED)
	placement = choice(["Center", "Upper left", "Upper right", "Lower left", "Lower right", "Left", "Right"], Vector2(152, 328))
	Ui.label_at(flag_view, "Flag preview", Vector2(400, 8), 14, Ui.MUTED)

func update_editor_tab() -> void:
	if country_view == null or preview == null: return
	country_view.visible = edit_tabs.current_tab == 0
	flag_view.visible = edit_tabs.current_tab == 1
	preview.visible = not editing or edit_tabs.current_tab == 1
	game_preview.visible = editing and edit_tabs.current_tab == 0
	game_preview.refresh()

func build_delete_confirmation() -> void:
	delete_confirmation = Panel.new()
	delete_confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	delete_confirmation.add_theme_stylebox_override("panel", Ui.style(Color(0.025, 0.04, 0.05, 0.88), 13))
	add_child(delete_confirmation)
	var box := Panel.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -232
	box.offset_right = 232
	box.offset_top = -146
	box.offset_bottom = 146
	box.add_theme_stylebox_override("panel", Ui.style(Color("17252a"), 13, true))
	delete_confirmation.add_child(box)
	Ui.label_at(box, "Delete this profile?", Vector2(24, 22), 24)
	var message := Ui.label_at(box, "", Vector2(24, 72), 16)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.text = Loc.text("This permanently deletes your kingdom, flag, match record and tutorial progress. You will start again with a new profile.")
	message.size = Vector2(416, 108)
	confirm_delete_button = action(box, "Delete profile", Vector2(24, 220), Vector2(200, 44))
	confirm_delete_button.pressed.connect(delete_profile)
	action(box, "Keep profile", Vector2(240, 220), Vector2(200, 44), true).pressed.connect(func(): delete_confirmation.hide())
	delete_confirmation.hide()

func text_input(parent: Control, at: Vector2, limit: int) -> LineEdit:
	var node := LineEdit.new()
	node.position = at
	node.size = Vector2(320, 40)
	node.max_length = limit
	parent.add_child(node)
	return node

func color_input(parent: Control, at: Vector2, dimensions: Vector2):
	var node = preload("res://src/ui/simple_color_picker.gd").new()
	node.position = at
	node.size = dimensions
	parent.add_child(node)
	node.color_changed.connect(func(_color): refresh_preview())
	return node

func choice(labels: Array, at: Vector2) -> OptionButton:
	var node := preload("res://src/ui/tooltip_widgets.gd").Choice.new()
	node.position = at
	node.size = Vector2(192, 36)
	for text in labels: node.add_item(Loc.text(text))
	flag_view.add_child(node)
	node.item_selected.connect(func(_index): refresh_preview())
	Sound.bind_button(node)
	return node

func action(parent: Control, text: String, at: Vector2, dimensions: Vector2, primary := false) -> Button:
	var node := Button.new()
	node.text = Loc.text(text)
	node.position = at
	node.size = dimensions
	Ui.style_button(node, primary)
	Sound.bind_button(node)
	parent.add_child(node)
	return node

func refresh_player_name() -> void:
	title.text = SteamOnline.player_display_name()

func open(mandatory := false) -> void:
	required = mandatory
	loading = true
	var value: Dictionary = PlayerProfile.data if PlayerProfile.exists() else Profile.default_identity()
	name_input.text = value.name
	motto_input.text = value.motto
	country_color.color = Color(value.color)
	field_color.color = Color(value.flag.field)
	accent_color.color = Color(value.flag.accent)
	symbol_color.color = Color(value.flag.ink)
	pattern.select(Profile.PATTERNS.find(value.flag.pattern))
	symbol.select(Profile.SYMBOLS.find(value.flag.symbol))
	placement.select(Profile.PLACEMENTS.find(value.flag.placement))
	symbol_scale.value = value.flag.scale
	status.text = ""
	delete_confirmation.hide()
	loading = false
	refresh_player_name()
	edit_tabs.current_tab = 0
	set_editing(not PlayerProfile.exists())
	refresh_statistics()

func set_editing(value: bool) -> void:
	editing = value
	var height := 640.0 if editing else 624.0
	var width := 800.0 if editing else 560.0
	offset_left = -width * 0.5
	offset_right = width * 0.5
	title.size.x = width - 120
	edit_button.position.x = width - 72
	status.size.x = width - 48
	cancel_button.position.x = 412 if editing else 292
	cancel_button.size.x = 364 if editing else 244
	offset_top = -height * 0.5
	offset_bottom = height * 0.5
	for button in [save_button, cancel_button, delete_button]: button.position.y = height - 64
	status.position.y = height - 92
	stats_view.visible = not editing
	edit_view.visible = editing
	edit_button.visible = not editing and PlayerProfile.exists()
	delete_button.visible = not editing and PlayerProfile.exists()
	save_button.visible = editing
	save_button.text = Loc.text("Save changes") if PlayerProfile.exists() else Loc.text("Create kingdom")
	cancel_button.text = Loc.text("Quit game") if required else Loc.text("Cancel") if editing else Loc.text("Back")
	preview.position = Vector2(400, 220) if editing else Vector2(24, 100)
	preview.size = Vector2(376, 250.6667) if editing else Vector2(96, 64)
	game_preview.position = Vector2(400, 188)
	game_preview.size = Vector2(376, 332)
	update_editor_tab()
	refresh_preview()
	game_preview.refresh()

func draft() -> Dictionary:
	return {"name":name_input.text, "motto":motto_input.text, "color":country_color.color.to_html(false), "flag":{
		"pattern":Profile.PATTERNS[pattern.selected], "symbol":Profile.SYMBOLS[symbol.selected],
		"placement":Profile.PLACEMENTS[placement.selected], "scale":symbol_scale.value,
		"field":field_color.color.to_html(false), "accent":accent_color.color.to_html(false), "ink":symbol_color.color.to_html(false)}}

func refresh_preview() -> void:
	if loading or preview == null: return
	preview.set_design(draft().flag)
	game_preview.set_color(country_color.color)
	save_button.disabled = name_input.text.strip_edges().is_empty()

func refresh_statistics() -> void:
	var stats: Dictionary = PlayerProfile.statistics
	xp_progress.show_profile(stats.xp)
	var values := [str(stats.matches), str(stats.wins), str(stats.losses), "%d%%" % roundi(100.0 * stats.wins / maxi(1, stats.matches)),
		Clock.display(PlayerProfile.average_seconds()), Clock.display(stats.seconds), str(stats.best_streak), Clock.display(stats.longest)]
	var index := 0
	for key in statistics:
		statistics[key].text = values[index]
		index += 1
	kingdom_title.text = PlayerProfile.data.get("name", "")
	motto_label.text = PlayerProfile.data.get("motto", "")

func commit() -> void:
	if name_input.text.strip_edges().is_empty():
		status.text = Loc.text("Please give your kingdom a name.")
		return
	for picker in [country_color, field_color, accent_color, symbol_color]:
		if not picker.valid():
			status.text = Loc.text("Enter a six-digit hex color, such as #86B998.")
			return
	var error: Error = PlayerProfile.save_identity(draft())
	if error != OK:
		status.text = Loc.text("Your profile could not be saved. Please try again.")
		return
	if required: saved.emit()
	else: open(false)

func back() -> void:
	if delete_confirmation.visible:
		delete_confirmation.hide()
	elif editing and PlayerProfile.exists(): open(false)
	else: cancelled.emit()

func delete_profile() -> void:
	var error: Error = PlayerProfile.delete_profile()
	if error != OK:
		delete_confirmation.hide()
		status.text = Loc.text("Your profile could not be deleted. Please try again.")
		return
	deleted.emit()
