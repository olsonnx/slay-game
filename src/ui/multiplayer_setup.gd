extends Panel
const Loc = preload("res://src/localization/text.gd")
signal start_requested(config: Dictionary)
signal back_requested
signal online_requested
const Hud = preload("res://src/ui/game_hud.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
const Setup = preload("res://src/game/match_setup.gd")
var size_choice: OptionButton
var size_warning: Label
var count_choice: OptionButton
var order_choice: OptionButton
var preset_choice: OptionButton
var seed_input: LineEdit
var rows: Array = []
var summary: Label
var start_button: Button
var source_choice: OptionButton
var map_dialog: FileDialog
var selected_level: Dictionary = {}
var map_path := ""
var map_error := ""
var players_group: Control
var map_group: Control
var advanced_group: Control
var players_tab: Button
var map_tab: Button
var advanced_button: Button
var difficulty_heading: Label
var player_tools: PopupPanel
var roster_scroll: ScrollContainer
var roster_content: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -410
	offset_right = 410
	offset_top = -295
	offset_bottom = 295
	add_theme_stylebox_override("panel", Hud.style(Color("17252a"), 13, true))
	Hud.label_at(self, "Local multiplayer", Vector2(24, 20), 28)
	action("Steam online…", Rect2(610, 20, 186, 36), func(): online_requested.emit())
	players_tab = action("Players",Rect2(24,70,130,36),func(): show_page("players"))
	map_tab = action(Loc.text("Map"),Rect2(164,70,154,36),func(): show_page("map"))
	for tab in [players_tab,map_tab]:
		tab.toggle_mode = true
		Hud.UiTheme.style_button(tab,false,true)
	players_group = group(self,Vector2(24,126),Vector2(772,340))
	map_group = group(self,Vector2(24,126),Vector2(772,340))
	Hud.label_at(players_group,"Kingdoms",Vector2(0,8),14)
	count_choice = choice(Vector2(88,0),144,[],players_group)
	action("Player options…",Rect2(596,0,176,34),func(): player_tools.popup_centered(Vector2i(352,208)),players_group)
	for field in [["Name",0],["Control",260],["Colour",428]]:
		Hud.label_at(players_group,field[0],Vector2(field[1],56),13,Color("adbdaf"))
	difficulty_heading = Hud.label_at(players_group,"AI difficulty",Vector2(608,56),13,Color("adbdaf"))
	roster_scroll = ScrollContainer.new()
	roster_scroll.position = Vector2(0,82)
	roster_scroll.size = Vector2(772,252)
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_scroll.follow_focus = true
	players_group.add_child(roster_scroll)
	roster_content = Control.new()
	roster_content.custom_minimum_size = Vector2(752,0)
	roster_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(roster_content)
	for index in range(Sizes.MAX_NATIONS):
		var y := index * 42
		var name_input := LineEdit.new()
		name_input.position = Vector2(0,y)
		name_input.size = Vector2(244,36)
		name_input.max_length = 18
		name_input.placeholder_text = Loc.text("Player %d") % (index+1)
		roster_content.add_child(name_input)
		var controller = choice(Vector2(260,y),152,["Player","Computer"],roster_content)
		var color_choice = choice(Vector2(428,y),164,[],roster_content)
		color_choice.tooltip_text = Loc.text("Starting colour · choosing an occupied colour swaps the two seats.")
		for color in range(Catalog.FACTIONS.size()):
			var swatch := Image.create(14,14,false,Image.FORMAT_RGBA8)
			swatch.fill(Catalog.UI_COLORS[color])
			color_choice.add_icon_item(ImageTexture.create_from_image(swatch), Catalog.FACTIONS[color])
		color_choice.get_popup().max_size.y = 360
		var difficulty = choice(Vector2(608,y),144,["Easy","Normal","Hard"],roster_content)
		difficulty.tooltip_text = Loc.text("Difficulty for this computer opponent.")
		rows.append({"name":name_input,"controller":controller,"color":color_choice,"difficulty":difficulty})
		controller.item_selected.connect(func(_value): refresh_summary())
		difficulty.item_selected.connect(func(_value): refresh_summary())
		color_choice.item_selected.connect(func(selected): select_color(index,selected))
	Hud.label_at(map_group,"Map",Vector2(0,0),14)
	source_choice = choice(Vector2(0,28),556,["Generated island"],map_group)
	source_choice.item_selected.connect(func(_index):
		if source_choice.selected == 1 and selected_level.is_empty():
			show_map_error(Loc.text("Load an editor map to continue."))
			return
		map_error = ""
		if using_editor_map(): apply_level_settings()
		else: refresh_counts()
		refresh_map_controls())
	action(Loc.text("Load editor map…"),Rect2(572,28,200,34),open_map_picker,map_group)
	Hud.label_at(map_group,"Size",Vector2(0,94),14)
	size_choice = choice(Vector2(0,120),772,Sizes.IDS.map(func(id): return Sizes.choice_label(id)),map_group)
	for index in range(Sizes.IDS.size()): size_choice.get_popup().set_item_tooltip(index,Sizes.tile_tooltip(Sizes.IDS[index]))
	size_warning = Hud.label_at(map_group,"",Vector2(0,162),13,Color("efc885"))
	size_warning.size = Vector2(772,20)
	advanced_button = action("Advanced  ▸",Rect2(0,184,772,34),toggle_advanced,map_group)
	advanced_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	advanced_group = group(map_group,Vector2(0,238),Vector2(772,70))
	Hud.label_at(advanced_group,"Island seed",Vector2.ZERO,14)
	Hud.label_at(advanced_group,"Turn order",Vector2(400,0),14)
	seed_input = LineEdit.new()
	seed_input.position = Vector2(0,26)
	seed_input.size = Vector2(372,36)
	seed_input.placeholder_text = "Random"
	seed_input.max_length = 10
	advanced_group.add_child(seed_input)
	order_choice = choice(Vector2(400,26),372,["Seat order",Loc.text("Shuffle at start")],advanced_group)
	advanced_group.hide()
	player_tools = PopupPanel.new()
	player_tools.title = "Player options"
	var popup_theme := Hud.UiTheme.create_theme()
	popup_theme.set_stylebox("panel","PopupPanel",Hud.style(Color("17252a"),12,true))
	player_tools.theme = popup_theme
	add_child(player_tools)
	var tools_group = group(player_tools,Vector2.ZERO,Vector2(320,184))
	Hud.label_at(tools_group,"Player options",Vector2(18,14),18)
	var close_tools = action("×",Rect2(274,10,30,30),func(): player_tools.hide(),tools_group)
	Hud.UiTheme.style_button(close_tools,false,false,true)
	Hud.label_at(tools_group,"AI preset",Vector2(18,54),14)
	preset_choice = choice(Vector2(118,46),184,["Custom","Easy","Normal","Hard"],tools_group)
	preset_choice.select(2)
	preset_choice.tooltip_text = Loc.text("Set computer difficulty for every seat.")
	preset_choice.item_selected.connect(func(index):
		if index > 0:
			for row in rows: row["difficulty"].select(index-1))
	action("Shuffle colours",Rect2(18,108,284,40),shuffle_colors,tools_group)
	summary = Hud.label_at(self,"",Vector2(24,478),14,Color("e6a18b"))
	summary.hide()
	action("Back",Rect2(24,524,156,42),func(): back_requested.emit())
	start_button = action("Start game",Rect2(532,524,264,42),start_match)
	Hud.UiTheme.style_button(start_button,true)
	size_choice.item_selected.connect(func(_index): refresh_counts())
	count_choice.item_selected.connect(func(_index): refresh_rows())
	seed_input.text_changed.connect(func(_text): refresh_summary())
	map_dialog = FileDialog.new()
	map_dialog.theme = Hud.UiTheme.create_theme()
	map_dialog.access = FileDialog.ACCESS_FILESYSTEM
	map_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	map_dialog.title = Loc.text("Choose an editor map")
	map_dialog.filters = PackedStringArray([Loc.text("*.json ; Slay levels")])
	map_dialog.file_selected.connect(load_editor_map)
	add_child(map_dialog)
	show_page("players")
	load_config(Gameplay.multiplayer_setup if not Gameplay.multiplayer_setup.is_empty() else {"rules":Gameplay.rule_mode})

func group(parent: Node, at: Vector2, dimensions: Vector2) -> Control:
	var node := Control.new()
	node.position = at
	node.size = dimensions
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func show_page(page: String) -> void:
	players_group.visible = page == "players"
	map_group.visible = page == "map"
	players_tab.set_pressed_no_signal(page == "players")
	map_tab.set_pressed_no_signal(page == "map")

func toggle_advanced() -> void:
	advanced_group.visible = not advanced_group.visible
	advanced_button.text = "Advanced  ▾" if advanced_group.visible else "Advanced  ▸"

func choice(at: Vector2, width: float, items: Array, parent: Node = null) -> OptionButton:
	var node = preload("res://src/ui/tooltip_widgets.gd").Choice.new()
	node.position = at
	node.size = Vector2(width,36)
	for item in items: node.add_item(item)
	(parent if parent != null else self).add_child(node)
	Sound.bind_button(node)
	return node

func action(text_value: String, rect: Rect2, callback: Callable, parent: Node = null) -> Button:
	var node := Button.new()
	node.text = text_value
	node.position = rect.position
	node.size = rect.size
	Hud.UiTheme.style_button(node)
	node.pressed.connect(callback)
	(parent if parent != null else self).add_child(node)
	Sound.bind_button(node)
	return node

func load_config(saved: Dictionary) -> void:
	var config := Setup.normalize(saved)
	source_choice.select(0)
	source_choice.clear()
	source_choice.add_item("Generated island")
	selected_level.clear()
	map_path = ""
	map_error = ""
	size_choice.select(maxi(0, Sizes.IDS.find(config["size"])))
	order_choice.select(1 if config["order"] == "random" else 0)
	seed_input.text = str(config["seed"]) if config["seed"] >= 0 else ""
	refresh_counts()
	count_choice.select(clampi(config["count"]-2,0,count_choice.item_count-1))
	var colors: Array = []
	for index in range(rows.size()):
		var seat: Dictionary = config["slots"][index] if index < config["count"] else {}
		var color: int = seat.get("color",-1)
		if color < 0:
			color = 0
			while color in colors: color += 1
		colors.append(color)
		rows[index]["name"].text = seat.get("name", Loc.text("Player %d") % (index+1))
		rows[index]["controller"].select(0 if seat.get("controller","ai") == "human" else 1)
		rows[index]["color"].select(color)
		rows[index]["color"].set_meta("previous",color)
		rows[index]["difficulty"].select(["easy","normal","hard"].find(seat.get("difficulty","normal")))
	refresh_rows()
	if config.has("map_path"): load_editor_map(config["map_path"],true)
	refresh_map_controls()

func refresh_counts() -> void:
	if using_editor_map():
		apply_level_settings()
		return
	var count: int = selected_level["factions"].size() if count_choice.item_count == 1 and not selected_level.is_empty() else count_choice.selected+2 if count_choice.item_count else 4
	var size_id: String = Sizes.IDS[size_choice.selected]
	count_choice.clear()
	for value in range(2,Sizes.MAX_KINGDOMS[size_id]+1): count_choice.add_item(str(value))
	count_choice.select(Sizes.clamp_kingdom_count(size_id,count)-2)
	size_choice.tooltip_text = Sizes.tile_tooltip(size_id)
	size_warning.text = Sizes.size_warning(size_id)
	refresh_rows()

func refresh_rows() -> void:
	roster_content.custom_minimum_size.y = seat_count() * 42 - 6
	for index in range(rows.size()):
		for control in rows[index].values(): control.visible = index < seat_count()
	refresh_summary()

func select_color(seat: int, color: int) -> void:
	# Swapping prevents duplicates without rejecting a player's choice.
	var old: int = rows[seat]["color"].get_meta("previous",seat)
	for index in range(rows.size()):
		if index != seat and rows[index]["color"].selected == color:
			rows[index]["color"].select(old)
	for row in rows: row["color"].set_meta("previous",row["color"].selected)

func shuffle_colors() -> void:
	var colors: Array = range(Catalog.FACTIONS.size())
	colors.shuffle()
	for index in range(rows.size()):
		rows[index]["color"].select(colors[index])
		rows[index]["color"].set_meta("previous",colors[index])

func config() -> Dictionary:
	var slots: Array = []
	for index in range(seat_count()):
		var row: Dictionary = rows[index]
		slots.append({"name":row["name"].text,"controller":"human" if row["controller"].selected == 0 else "ai","color":row["color"].selected,"difficulty":["easy","normal","hard"][row["difficulty"].selected]})
	var settings := {"size":Sizes.IDS[size_choice.selected],"count":slots.size(),"rules":"modern","order":["fixed","random"][order_choice.selected],"seed":int(seed_input.text) if seed_input.text != "" else -1,"slots":slots}
	if using_editor_map():
		settings["map_path"] = map_path
		settings["size"] = selected_level["data"]["size"]
	return Setup.normalize(settings)

func refresh_summary() -> void:
	if summary == null: return
	var preset: int = rows[0]["difficulty"].selected+1
	for index in range(seat_count()):
		if rows[index]["difficulty"].selected+1 != preset: preset = 0
	preset_choice.select(preset)
	var humans := Setup.human_count(config())
	var valid_seed := seed_input.text == "" or (seed_input.text.is_valid_int() and int(seed_input.text) >= 0 and int(seed_input.text) <= 2147483647)
	start_button.disabled = map_error != "" or humans < 2 or not valid_seed
	summary.text = map_error if map_error != "" else Loc.text("Choose at least two local players.") if humans < 2 else Loc.text("Seed must be a number between 0 and 2147483647.") if not valid_seed else ""
	summary.visible = summary.text != ""
	Hud.UiTheme.fit_text(summary,summary.text,772)
	var has_computer := false
	for index in range(rows.size()):
		var computer: bool = index < seat_count() and rows[index]["controller"].selected == 1
		rows[index]["difficulty"].visible = computer
		has_computer = has_computer or computer
	difficulty_heading.visible = has_computer

func start_match() -> void:
	refresh_summary()
	if start_button.disabled: return
	var settings := config()
	Gameplay.set_multiplayer_setup(settings)
	start_requested.emit(settings)

func using_editor_map() -> bool:
	return source_choice.selected == 1 and not selected_level.is_empty()

func seat_count() -> int:
	return selected_level["factions"].size() if using_editor_map() else count_choice.selected+2

func open_map_picker() -> void:
	DirAccess.make_dir_recursive_absolute("user://levels")
	map_dialog.current_dir = map_path.get_base_dir() if map_path != "" else OS.get_user_data_dir().path_join("levels")
	map_dialog.popup_centered_ratio(0.75)

func load_editor_map(path: String, preserve_roster := false) -> void:
	var loaded := Setup.read_level(path)
	if loaded["error"] != "":
		show_map_error(loaded["error"])
		return
	selected_level = loaded
	map_path = path
	map_error = ""
	if source_choice.item_count == 1: source_choice.add_item("")
	source_choice.set_item_text(1,Loc.text("Editor · %s") % loaded["data"]["title"])
	source_choice.set_item_tooltip(1,path)
	source_choice.select(1)
	if not preserve_roster:
		var colors: Array = loaded["factions"].duplicate()
		for color in range(Catalog.FACTIONS.size()):
			if color not in colors: colors.append(color)
		for index in range(rows.size()):
			rows[index]["color"].select(colors[index])
			rows[index]["color"].set_meta("previous",colors[index])
			if rows[index]["name"].text in Catalog.FACTIONS: rows[index]["name"].text = Catalog.FACTIONS[colors[index]]
	apply_level_settings()
	refresh_map_controls()

func apply_level_settings() -> void:
	var data: Dictionary = selected_level["data"]
	size_choice.select(maxi(0, Sizes.IDS.find(data["size"])))
	count_choice.clear()
	count_choice.add_item(str(selected_level["factions"].size()))
	count_choice.select(0)
	seed_input.text = str(data["seed"])
	refresh_rows()

func refresh_map_controls() -> void:
	var size_id: String = Sizes.IDS[size_choice.selected]
	if size_warning != null:
		size_warning.text = Sizes.size_warning(size_id)
	var authored := source_choice.selected == 1
	for control in [size_choice,count_choice]:
		control.disabled = authored
		control.tooltip_text = Loc.text("Defined by the selected editor map.") if authored else ""
	if not authored: size_choice.tooltip_text = Sizes.tile_tooltip(size_id)
	seed_input.editable = not authored
	seed_input.tooltip_text = Loc.text("Defined by the selected editor map.") if authored else Loc.text("Leave blank for a new island, or enter 0–2147483647 to repeat one.")
	refresh_summary()

func show_map_error(error: String) -> void:
	if source_choice.selected == 0:
		selected_level.clear()
		if source_choice.item_count == 1: source_choice.add_item("")
		source_choice.set_item_text(1,Loc.text("Editor map unavailable"))
		source_choice.select(1)
	map_error = error
	show_page("map")
	refresh_map_controls()
