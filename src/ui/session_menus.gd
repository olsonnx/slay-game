extends CanvasLayer
const Loc = preload("res://src/localization/text.gd")
## Always processes so menus and Escape remain usable while the game is paused.
signal new_game_requested(size_id: String, kingdom_count: int)
signal multiplayer_requested(config: Dictionary)
signal continue_requested
signal main_menu_requested
signal quit_requested
signal restart_requested
signal rules_requested(mode: String)
signal tutorial_requested(category: String)
signal save_replay_requested
signal show_map_requested
signal results_requested
signal editor_requested

const Hud = preload("res://src/ui/game_hud.gd")
const Options = preload("res://src/ui/options_view.gd")
const MapSizes = preload("res://src/game/map_sizes.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
enum Screen { HIDDEN, MAIN, PAUSE, OPTIONS, QUIT, CONFIRM, DEFEAT, SETUP, MULTIPLAYER, MAP, TUTORIAL }
var screen := Screen.HIDDEN
var options_origin := Screen.MAIN
var quit_destination := ""
var backdrop: ColorRect
var main_panel: Panel
var setup_panel: Panel
var size_choice: OptionButton
var kingdom_choice: OptionButton
var difficulty_choice: OptionButton
var player_kingdom_choice: OptionButton
var setup_hint: Label
var multiplayer_panel
var tutorial_panel
var defeat_title: Label
var defeat_description: Label
var setup_start_button: Button
var pause_panel: Panel
var options_panel: Panel
var quit_panel: Panel
var confirm_panel: Panel
var defeat_panel: Panel
var defeat_restart_button: Button
var defeat_menu_button: Button
var save_replay_button: Button
var replay_status: Label
var result_values: Dictionary = {}
var results_faction: OptionButton
var results_totals: Dictionary = {}
var show_map_button: Button
var return_results_button: Button
var results_dim_tween: Tween
var results_shade: ShaderMaterial
var confirm_label: Label
var confirm_description: Label
var confirm_action_button: Button
var confirm_origin := Screen.QUIT
var options_view
var restart_button: Button
var options_back: Button
var navigation_locked := false
var menu_background
var quit_menu_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	menu_background = preload("res://src/ui/menu_background.gd").new()
	add_child(menu_background)
	backdrop = ColorRect.new()
	backdrop.color = Color("172c33")
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Hud.UiTheme.create_theme()
	backdrop.theme = theme
	main_panel = centered_panel(502)
	side_panel(main_panel, 384)
	Hud.label_at(main_panel, Loc.text("Slay & Reign"), Vector2(24, 21), 48)
	button(main_panel, "Quick Play", 102, func(): show_screen(Screen.SETUP), true)
	button(main_panel, "Tutorial", 166, func(): show_screen(Screen.TUTORIAL))
	button(main_panel, "Multiplayer", 230, func(): show_screen(Screen.MULTIPLAYER))
	button(main_panel, "Level editor", 294, func(): editor_requested.emit())
	var main_options := button(main_panel, "Options", 358, func(): open_options(Screen.MAIN))
	main_options.tooltip_text = Loc.text("Options — Audio, Video, Gameplay, Controls and Replays")
	button(main_panel, "Quit game", 422, func(): quit_requested.emit())
	setup_panel = centered_panel(490)
	side_panel(setup_panel, 480)
	Hud.label_at(setup_panel, "Quick Play", Vector2(24, 22), 28)
	Hud.label_at(setup_panel, "Map size", Vector2(24, 79), 15, Color("c5cdbb"))
	size_choice = preload("res://src/ui/tooltip_widgets.gd").Choice.new()
	size_choice.position = Vector2(24, 106)
	size_choice.size = Vector2(432, 44)
	for size_id in MapSizes.IDS:
		size_choice.add_item(MapSizes.choice_label(size_id))
		size_choice.set_item_metadata(size_choice.item_count - 1, size_id)
		size_choice.get_popup().set_item_tooltip(size_choice.item_count - 1, MapSizes.tile_tooltip(size_id))
	size_choice.select(MapSizes.IDS.find("small"))
	Sound.bind_button(size_choice)
	setup_panel.add_child(size_choice)
	Hud.label_at(setup_panel, "Kingdoms", Vector2(24, 151), 15, Color("c5cdbb"))
	kingdom_choice = preload("res://src/ui/tooltip_widgets.gd").Choice.new()
	kingdom_choice.position = Vector2(24, 176)
	kingdom_choice.size = Vector2(208, 44)
	kingdom_choice.tooltip_text = Loc.text("Starting kingdoms · includes yours\nAll sizes: 2–6")
	Sound.bind_button(kingdom_choice)
	setup_panel.add_child(kingdom_choice)
	refresh_kingdom_choices()
	size_choice.item_selected.connect(func(_index: int): refresh_kingdom_choices())
	Hud.label_at(setup_panel, "Difficulty", Vector2(248, 151), 15, Color("c5cdbb"))
	difficulty_choice = preload("res://src/ui/tooltip_widgets.gd").Choice.new()
	difficulty_choice.position = Vector2(248, 176)
	difficulty_choice.size = Vector2(208, 44)
	for difficulty in ["easy", "normal", "hard"]:
		difficulty_choice.add_item(difficulty.capitalize())
		difficulty_choice.set_item_metadata(difficulty_choice.item_count - 1, difficulty)
	difficulty_choice.select(["easy", "normal", "hard"].find(Gameplay.difficulty))
	difficulty_choice.tooltip_text = Loc.text("Easy: forgiving · Normal: coordinated\nHard: plans ahead · equal resources")
	Sound.bind_button(difficulty_choice)
	setup_panel.add_child(difficulty_choice)
	Hud.label_at(setup_panel, "Your kingdom", Vector2(24, 226), 15, Color("c5cdbb"))
	player_kingdom_choice = preload("res://src/ui/tooltip_widgets.gd").Choice.new()
	player_kingdom_choice.position = Vector2(24, 251)
	player_kingdom_choice.size = Vector2(432, 44)
	player_kingdom_choice.add_item(Loc.text("Random"))
	player_kingdom_choice.set_item_metadata(0,-1)
	for color in range(Catalog.FACTIONS.size()):
		var swatch := Image.create(16,16,false,Image.FORMAT_RGBA8)
		swatch.fill(Catalog.UI_COLORS[color])
		player_kingdom_choice.add_icon_item(ImageTexture.create_from_image(swatch),Catalog.FACTIONS[color])
		player_kingdom_choice.set_item_metadata(color+1,color)
	player_kingdom_choice.select(Gameplay.quick_play_kingdom+1)
	player_kingdom_choice.get_popup().max_size.y = 360
	player_kingdom_choice.tooltip_text = Loc.text("Choose your kingdom, or let each new match pick one at random.")
	player_kingdom_choice.item_selected.connect(func(_index): Gameplay.set_quick_play_kingdom(player_kingdom_choice.get_selected_metadata()))
	Sound.bind_button(player_kingdom_choice)
	setup_panel.add_child(player_kingdom_choice)
	setup_hint = Hud.label_at(setup_panel, "", Vector2(24,319),14,Color("adbdaf"))
	setup_hint.size = Vector2(432,38)
	setup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refresh_kingdom_choices()
	setup_start_button = button(setup_panel, "Start game", 362, func():
		Gameplay.set_difficulty(difficulty_choice.get_selected_metadata())
		Gameplay.set_quick_play_kingdom(player_kingdom_choice.get_selected_metadata())
		new_game_requested.emit(size_choice.get_selected_metadata(), kingdom_choice.get_selected_metadata()), true)
	button(setup_panel, "Back", 426, func(): show_screen(Screen.MAIN))
	multiplayer_panel = preload("res://src/ui/multiplayer_setup.gd").new()
	backdrop.add_child(multiplayer_panel)
	multiplayer_panel.start_requested.connect(func(config: Dictionary): multiplayer_requested.emit(config))
	multiplayer_panel.back_requested.connect(func(): show_screen(Screen.MAIN))
	tutorial_panel = preload("res://src/ui/tutorial_selection.gd").new()
	backdrop.add_child(tutorial_panel)
	tutorial_panel.selected.connect(func(category: String):
		if not navigation_locked: tutorial_requested.emit(category))
	tutorial_panel.back_requested.connect(func(): show_screen(Screen.MAIN))
	pause_panel = centered_panel(410)
	Hud.label_at(pause_panel, "Paused", Vector2(24, 22), 30)
	button(pause_panel, "Continue", 94, resume, true)
	restart_button = button(pause_panel, "Restart", 158, confirm_restart)
	restart_button.tooltip_text = Loc.text("Restart level\nSame island and starting state")
	var pause_options := button(pause_panel, "Options", 222, func(): open_options(Screen.PAUSE))
	pause_options.tooltip_text = Loc.text("Options — Audio, Video, Gameplay, Controls and Replays")
	button(pause_panel, "Quit", 286, func(): show_screen(Screen.QUIT))
	options_panel = centered_panel(600)
	Hud.label_at(options_panel, "Options", Vector2(24, 18), 28)
	options_view = Options.new()
	options_view.position = Vector2(24, 76)
	options_view.size = Vector2(432, 444)
	options_panel.add_child(options_view)
	options_view.rules_requested.connect(func(mode: String): rules_requested.emit(mode))
	options_back = button(options_panel, "Back", 524, close_options)
	quit_panel = centered_panel(346)
	Hud.label_at(quit_panel, "Leave game", Vector2(24, 22), 28)
	quit_menu_button = button(quit_panel, "Main menu", 94, func(): confirm_quit("main"))
	button(quit_panel, "Quit game", 158, func(): confirm_quit("desktop"))
	button(quit_panel, "Back", 222, func(): show_screen(Screen.PAUSE))
	confirm_panel = centered_panel(320)
	confirm_label = Hud.label_at(confirm_panel, "", Vector2(24, 24), 25)
	confirm_description = Hud.label_at(confirm_panel, Loc.text("The current game will be discarded."), Vector2(24, 75), 15, Color("c5cdbb"))
	confirm_action_button = button(confirm_panel, "Leave game", 128, confirm_leave)
	button(confirm_panel, "Back", 192, close_confirmation)
	defeat_panel = preload("res://src/ui/context_panel.gd").new()
	backdrop.add_child(defeat_panel)
	defeat_panel.add_theme_stylebox_override("panel", Hud.UiTheme.style(Color(0.09, 0.14, 0.16, 0.96), 13, true))
	defeat_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	defeat_panel.offset_left = -240
	defeat_panel.offset_right = 240
	defeat_panel.panel_height = 548
	defeat_panel.rest_top = -274
	defeat_panel.reveal = 1.0
	results_shade = preload("res://src/ui/modal_shade.gd").create_material()
	defeat_title = Hud.label_at(defeat_panel, "Defeat", Vector2(24, 18), 30)
	defeat_description = Hud.label_at(defeat_panel, "", Vector2(24, 64), 15, Color("c5cdbb"))
	results_faction = preload("res://src/ui/tooltip_widgets.gd").Choice.new()
	results_faction.position = Vector2(24, 60)
	results_faction.size = Vector2(432, 36)
	defeat_panel.add_child(results_faction)
	Sound.bind_button(results_faction)
	results_faction.item_selected.connect(func(_index: int): refresh_results())
	var captions := ["Soldiers slain", "Soldiers lost", "Tiles conquered", "Capitals squashed", "Turns", "Time played"]
	var keys := ["slain", "lost", "tiles", "capitals", "turns", "time"]
	for index in range(keys.size()):
		var caption := Hud.label_at(defeat_panel, captions[index], Vector2(24, 111 + index * 32), 17, Color("c5cdbb"))
		caption.mouse_filter = Control.MOUSE_FILTER_PASS
		caption.tooltip_text = Loc.text("All unit tiers. Losses include starvation; merging units is not a loss.") if index < 2 else Loc.text("Cumulative captures, including recaptured land and surrendered provinces.") if index == 2 else Loc.text("Real playing time, including AI turns and excluding pauses.") if index == 5 else ""
		var value := Hud.label_at(defeat_panel, "0", Vector2(318, 111 + index * 32), 18)
		value.size = Vector2(138, 28)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		result_values[keys[index]] = value
	replay_status = Hud.label_at(defeat_panel, "", Vector2(24, 312), 13, Color("c5cdbb"))
	replay_status.size = Vector2(432, 28)
	save_replay_button = button(defeat_panel, "Save replay", 346, func(): save_replay_requested.emit())
	defeat_restart_button = button(defeat_panel, "Restart level", 346, func(): restart_requested.emit(), true)
	defeat_restart_button.position.x = 24
	defeat_restart_button.size.x = 210
	save_replay_button.position.x = 246
	save_replay_button.size.x = 210
	defeat_restart_button.text = ""
	defeat_restart_button.icon = preload("res://src/ui/result_icons.gd").restart()
	defeat_restart_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	defeat_restart_button.tooltip_text = Loc.text("Restart level")
	save_replay_button.text = ""
	save_replay_button.icon = preload("res://src/ui/result_icons.gd").save()
	save_replay_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_replay_button.tooltip_text = Loc.text("Save replay")
	show_map_button = button(defeat_panel, "Show map", 410, func(): show_map_requested.emit())
	defeat_menu_button = button(defeat_panel, "Main menu", 474, func(): main_menu_requested.emit())
	return_results_button = button(defeat_panel, "Back to results", 0, func(): results_requested.emit())
	defeat_panel.remove_child(return_results_button)
	add_child(return_results_button)
	return_results_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	return_results_button.offset_left = -216
	return_results_button.offset_right = -24
	return_results_button.offset_top = 24
	return_results_button.offset_bottom = 72
	show_screen(Screen.HIDDEN)

func show_results(game) -> void:
	defeat_title.text = Loc.text("Match finished") if game.is_hotseat() else Loc.text("Victory") if game.rules.territory(0) > 0 else Loc.text("Defeat")
	defeat_description.text = game.message
	defeat_description.visible = true
	# Hotseat needs a separate row for the outcome and the statistics selector.
	var extra_height := 32 if game.is_hotseat() else 0
	defeat_panel.panel_height = 548 + extra_height
	defeat_panel.rest_top = -defeat_panel.panel_height / 2.0
	for child in defeat_panel.get_children():
		if child is Control:
			if not child.has_meta("results_base_y"): child.set_meta("results_base_y", child.position.y)
			var base_y: float = child.get_meta("results_base_y")
			if base_y >= 100 or child == results_faction: child.position.y = base_y + extra_height
	results_faction.visible = game.is_hotseat()
	results_faction.clear()
	for faction in game.rules.human_factions:
		results_faction.add_item(game.NAMES[faction])
		results_faction.set_item_metadata(results_faction.item_count - 1, faction)
	results_totals = game.match_results
	result_values["turns"].text = str(game.round_number)
	result_values["time"].text = preload("res://src/game/match_clock.gd").display(game.match_clock.seconds())
	refresh_results()
	save_replay_button.disabled = game.rules.replay_log == null
	replay_status.text = Loc.text("Replay not saved. Save it before leaving this screen.")
	if game.rules.replay_log != null: replay_saved(game.rules.replay_log)

func refresh_results() -> void:
	var faction: int = results_faction.get_selected_metadata() if results_faction.item_count > 0 else 0
	var totals: Dictionary = results_totals.get(faction, {})
	for key in ["slain", "lost", "tiles", "capitals"]:
		result_values[key].text = str(totals.get(key, 0))

func replay_saved(replay) -> void:
	save_replay_button.disabled = replay.path != ""
	if replay.path != "": replay_status.text = Loc.text("Replay saved. Find it in Options → Replays.")
	elif replay.error != "": replay_status.text = Loc.text("Replay could not be saved. Try again.")

func refresh_kingdom_choices() -> void:
	size_choice.tooltip_text = MapSizes.tile_tooltip(size_choice.get_selected_metadata())
	if setup_hint != null:
		var warning := MapSizes.size_warning(size_choice.get_selected_metadata())
		setup_hint.text = Loc.text("Your kingdom against computer opponents.") if warning == "" else warning
		setup_hint.add_theme_color_override("font_color",Color("adbdaf") if warning == "" else Color("efc885"))
	var count: int = MapSizes.DEFAULT_KINGDOMS if kingdom_choice.item_count == 0 else kingdom_choice.get_selected_metadata()
	count = MapSizes.clamp_kingdom_count(size_choice.get_selected_metadata(), count)
	kingdom_choice.clear()
	for value in range(2, MapSizes.MAX_KINGDOMS[size_choice.get_selected_metadata()] + 1):
		kingdom_choice.add_item(Loc.text("%d kingdoms") % value)
		kingdom_choice.set_item_metadata(kingdom_choice.item_count - 1, value)
	kingdom_choice.select(count - 2)

func centered_panel(height: float) -> Panel:
	var node := Hud.panel(backdrop, Rect2(0, 0, 480, height))
	node.anchor_left = 0.5
	node.anchor_right = 0.5
	node.anchor_top = 0.5
	node.anchor_bottom = 0.5
	node.offset_left = -240
	node.offset_right = 240
	node.offset_top = -height / 2
	node.offset_bottom = height / 2
	return node

func button(parent: Panel, text_value: String, y: float, callback: Callable, primary := false) -> Button:
	var node := preload("res://src/ui/tooltip_button.gd").new()
	node.text = text_value
	node.position = Vector2(24, y)
	node.size = Vector2(parent.size.x - 48, 48)
	node.add_theme_font_size_override("font_size", 18)
	Hud.UiTheme.style_button(node,primary)
	Sound.bind_button(node, func(): return &"ui_close" if text_value in ["Back", "Continue"] else &"ui_click")
	node.pressed.connect(func():
		if not navigation_locked:
			callback.call())
	parent.add_child(node)
	return node

func show_screen(next: Screen) -> void:
	if next == Screen.DEFEAT and screen == Screen.DEFEAT: return
	var entering_results := next == Screen.DEFEAT and screen != Screen.DEFEAT
	if results_dim_tween != null and results_dim_tween.is_valid(): results_dim_tween.kill()
	if next != Screen.DEFEAT: defeat_panel.close()
	screen = next
	var decorative := next in [Screen.MAIN, Screen.SETUP, Screen.MULTIPLAYER, Screen.TUTORIAL] or (next == Screen.OPTIONS and options_origin == Screen.MAIN)
	menu_background.set_active(decorative)
	if next == Screen.OPTIONS:
		if decorative:
			side_panel(options_panel, 480)
		else:
			options_panel.anchor_left = 0.5
			options_panel.anchor_right = 0.5
			options_panel.offset_left = -240
			options_panel.offset_right = 240
	backdrop.visible = next not in [Screen.HIDDEN, Screen.MAP]
	backdrop.material = results_shade if next == Screen.DEFEAT else null
	backdrop.color = Color(0, 0, 0, 0) if decorative else Color(0.05, 0.10, 0.13, 0.88)
	main_panel.visible = next == Screen.MAIN
	setup_panel.visible = next == Screen.SETUP
	multiplayer_panel.visible = next == Screen.MULTIPLAYER
	tutorial_panel.visible = next == Screen.TUTORIAL
	pause_panel.visible = next == Screen.PAUSE
	options_panel.visible = next == Screen.OPTIONS
	quit_panel.visible = next == Screen.QUIT
	confirm_panel.visible = next == Screen.CONFIRM
	defeat_panel.visible = next == Screen.DEFEAT
	return_results_button.visible = next == Screen.MAP
	if entering_results:
		defeat_panel.open(true)
		backdrop.color = Color(0.03, 0.06, 0.08, 0.0)
		results_dim_tween = create_tween()
		results_dim_tween.tween_property(backdrop, "color:a", 0.78, defeat_panel.ENTRANCE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	get_viewport().gui_release_focus()

func side_panel(node: Panel, width: float) -> void:
	node.anchor_left = 0.045
	node.anchor_right = 0.045
	node.offset_left = 0
	node.offset_right = width

func open_options(origin: Screen) -> void:
	options_origin = origin
	options_view.refresh()
	show_screen(Screen.OPTIONS)

func close_options() -> void:
	show_screen(options_origin)

func resume() -> void:
	continue_requested.emit()

func confirm_quit(destination: String) -> void:
	quit_destination = destination
	confirm_origin = Screen.QUIT
	confirm_label.text = Loc.text("Return to editor?") if destination == "main" and quit_menu_button.text == Loc.text("Return to editor") else Loc.text("Return to main menu?") if destination == "main" else Loc.text("Quit the game?")
	confirm_description.text = Loc.text("The current game will be discarded.")
	confirm_action_button.text = "Leave game"
	show_screen(Screen.CONFIRM)

func confirm_restart() -> void:
	quit_destination = "restart"
	confirm_origin = Screen.PAUSE
	confirm_label.text = Loc.text("Restart this level?")
	confirm_description.text = Loc.text("Progress will reset. The same level will be used.")
	confirm_action_button.text = "Restart"
	show_screen(Screen.CONFIRM)

func close_confirmation() -> void:
	show_screen(confirm_origin)

func confirm_leave() -> void:
	if quit_destination == "restart":
		restart_requested.emit()
	elif quit_destination == "main":
		main_menu_requested.emit()
	else:
		quit_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if navigation_locked or screen == Screen.HIDDEN or not event is InputEventKey or not event.pressed or event.echo:
		return
	if screen == Screen.OPTIONS and options_view.controls_page.pending != "":
		return
	if event.keycode != KEY_ESCAPE:
		return
	if screen == Screen.MAIN:
		return
	if screen == Screen.DEFEAT:
		get_viewport().set_input_as_handled()
		return
	Sound.play(&"ui_close")
	match screen:
		Screen.MAP: results_requested.emit()
		Screen.SETUP, Screen.MULTIPLAYER, Screen.TUTORIAL: show_screen(Screen.MAIN)
		Screen.PAUSE: resume()
		Screen.OPTIONS: close_options()
		Screen.QUIT: show_screen(Screen.PAUSE)
		Screen.CONFIRM: close_confirmation()
	get_viewport().set_input_as_handled()

func lock_navigation(locked: bool) -> void:
	navigation_locked = locked
	for node in backdrop.find_children("*", "BaseButton", true, false):
		node.disabled = locked
	for row in multiplayer_panel.rows:
		row["name"].editable = not locked
	multiplayer_panel.seed_input.editable = not locked
	if not locked:
		multiplayer_panel.refresh_map_controls()
