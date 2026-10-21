extends Control
const Loc = preload("res://src/localization/text.gd")
## Shared options screen for the main and pause menus.
const Hud = preload("res://src/ui/game_hud.gd")
const Tips = preload("res://src/ui/tooltip_widgets.gd")
signal rules_requested(mode: String)
var gameplay_page: Control
var rules_choice: OptionButton
var authored_rules := ""
var indicators_toggle: CheckButton
var sound_sliders: Dictionary = {}
var sound_mute: CheckButton
var window_mode: OptionButton
var resolution_choice: OptionButton
var antialiasing_choice: OptionButton
var background_choice: OptionButton
var stylized_water_toggle: CheckButton
var vsync_toggle: CheckButton
var shadow_toggle: CheckButton
var lighting_toggle: CheckButton
var camera_follow_toggle: CheckButton
var level_transition_toggle: CheckButton
var internal_borders_slider: HSlider
var internal_borders_value: Label
var audio_page: Control
var video_page: Control
var status_label: Label
var controls_page
var language_choice: OptionButton
var language_note: Label

func _ready() -> void:
	var tabs := preload("res://src/ui/options_tabs.gd").new()
	tabs.size = Vector2(432, 36)
	tabs.add_tab("Audio")
	tabs.add_tab("Video")
	tabs.add_tab("Gameplay")
	tabs.add_tab("Controls")
	tabs.tab_changed.connect(func(index: int):
		Sound.play(&"ui_click")
		audio_page.visible = index == 0
		video_page.visible = index == 1
		gameplay_page.visible = index == 2
		controls_page.visible = index == 3)
	add_child(tabs)
	audio_page = Control.new()
	audio_page.position.y = 49
	add_child(audio_page)
	video_page = Control.new()
	video_page.position.y = 49
	add_child(video_page)
	video_page.hide()
	gameplay_page = Control.new()
	gameplay_page.position.y = 49
	add_child(gameplay_page)
	gameplay_page.hide()
	controls_page = preload("res://src/ui/controls_view.gd").new()
	controls_page.position.y = 49
	add_child(controls_page)
	controls_page.hide()
	Hud.label_at(gameplay_page, "Rules", Vector2(0, 10), 15)
	rules_choice = Tips.Choice.new()
	rules_choice.position = Vector2(160, 0)
	rules_choice.size = Vector2(272, 38)
	rules_choice.add_item("Modern")
	rules_choice.add_item("Classic")
	Sound.bind_button(rules_choice)
	gameplay_page.add_child(rules_choice)
	rules_choice.item_selected.connect(func(index: int):
		rules_requested.emit("modern" if index == 0 else "classic"))
	var rules_note := Hud.label_at(gameplay_page, Loc.text("Modern adds province development, mana, spells,\nbridges and castle surrender.\n\nClassic keeps the original prototype rules.\n\nChanging rules resets your game and generates\na new island."), Vector2(0, 62), 15, Color("c5cdbb"))
	rules_note.size = Vector2(432, 185)
	rules_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	indicators_toggle = check(gameplay_page, Loc.text("Clear movement indicators"), Vector2(0, 260))
	indicators_toggle.size.x = 432
	indicators_toggle.tooltip_text = Loc.text("On: area border + curved arrow\nOff: tile outlines + dotted path")
	indicators_toggle.toggled.connect(func(value: bool): Gameplay.set_clear_indicators(value))
	Hud.label_at(gameplay_page, "Language", Vector2(0, 320), 15)
	language_choice = Tips.Choice.new()
	language_choice.position = Vector2(160, 310)
	language_choice.size = Vector2(272, 38)
	language_choice.fit_to_longest_item = false
	language_choice.clip_text = true
	language_choice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for language in Languages.languages:
		language_choice.add_item(language["name"])
		language_choice.set_item_metadata(language_choice.item_count - 1, language["locale"])
	Sound.bind_button(language_choice)
	gameplay_page.add_child(language_choice)
	language_note = Hud.label_at(gameplay_page, "", Vector2(0, 360), 13, Color("c5cdbb"))
	language_note.size = Vector2(432, 52)
	language_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	language_choice.item_selected.connect(func(index: int):
		Languages.set_language(language_choice.get_item_metadata(index))
		refresh_language())
	Languages.changed.connect(refresh_language)
	var buses := [&"Master", &"UI", &"SFX", &"Ambience"]
	var names := ["Overall volume", "Interface", "Game effects", "Ambience"]
	for index in range(buses.size()):
		var bus: StringName = buses[index]
		Hud.label_at(audio_page, names[index], Vector2(0, 18 + index * 56), 15)
		var slider := Tips.RangeSlider.new()
		slider.position = Vector2(160, 18 + index * 56)
		slider.size = Vector2(272, 24)
		slider.max_value = 100
		slider.step = 1
		slider.tooltip_text = Loc.text("Volume changes are saved automatically.")
		slider.value_changed.connect(func(value: float): Sound.set_volume(bus, value / 100.0))
		audio_page.add_child(slider)
		sound_sliders[bus] = slider
	sound_mute = check(audio_page, Loc.text("Mute all sounds"), Vector2(0, 246))
	sound_mute.size.x = 432
	sound_mute.toggled.connect(func(value: bool): Sound.set_muted(value))
	Hud.label_at(video_page, "Display mode", Vector2(0, 10), 15)
	window_mode = choice(["Windowed", "Fullscreen"], 0)
	window_mode.item_selected.connect(func(index: int):
		Video.set_preference(&"fullscreen", index == 1)
		refresh())
	Hud.label_at(video_page, "Window size", Vector2(0, 58), 15)
	var sizes: Array[String] = []
	for value in Video.RESOLUTIONS:
		sizes.append(Loc.text("%d × %d") % [value.x, value.y])
	resolution_choice = choice(sizes, 48)
	resolution_choice.tooltip_text = Loc.text("Windowed mode only\nFullscreen uses the display's native size")
	resolution_choice.item_selected.connect(func(index: int): Video.set_preference(&"resolution", Video.RESOLUTIONS[index]))
	Hud.label_at(video_page, "Anti-aliasing", Vector2(0, 106), 15)
	antialiasing_choice = choice(["Off", "2× MSAA", "4× MSAA", "8× MSAA"], 96)
	antialiasing_choice.tooltip_text = Loc.text("Smoother edges\nHigher settings use more GPU power")
	antialiasing_choice.item_selected.connect(func(index: int): Video.set_preference(&"antialiasing", index))
	Hud.label_at(video_page, "Background", Vector2(0, 154), 15)
	background_choice = choice(["Water", "Sky"], 144)
	background_choice.tooltip_text = Loc.text("Island backdrop\nAnimated water / softly lit sky")
	background_choice.item_selected.connect(func(index: int): Video.set_preference(&"background", "water" if index == 0 else "sky"))
	vsync_toggle = check(video_page, "VSync", Vector2(0, 230))
	vsync_toggle.tooltip_text = Loc.text("Synchronize frames with the display to reduce tearing.")
	vsync_toggle.toggled.connect(func(value: bool): Video.set_preference(&"vsync", value))
	shadow_toggle = check(video_page, "Shadows", Vector2(216, 230))
	shadow_toggle.tooltip_text = Loc.text("Turn 3D shadows off to reduce graphics load.")
	shadow_toggle.toggled.connect(func(value: bool): Video.set_preference(&"shadows", value))
	camera_follow_toggle = check(video_page, Loc.text("Follow active kingdom"), Vector2(0, 268))
	camera_follow_toggle.size.x = 432
	camera_follow_toggle.tooltip_text = Loc.text("Follow the active faction\nManual camera movement stops following this turn")
	camera_follow_toggle.toggled.connect(func(value: bool): Video.set_preference(&"follow_turn_camera", value))
	level_transition_toggle = check(video_page, Loc.text("Animate level transitions"), Vector2(0, 306))
	level_transition_toggle.size.x = 432
	level_transition_toggle.tooltip_text = Loc.text("Tile arrival / departure animations\nTurning off finishes the current transition")
	level_transition_toggle.toggled.connect(func(value: bool): Video.set_preference(&"level_transitions", value))
	Hud.label_at(video_page, "Internal borders", Vector2(0, 358), 15)
	internal_borders_slider = Tips.RangeSlider.new()
	internal_borders_slider.position = Vector2(160, 356)
	internal_borders_slider.size = Vector2(224, 24)
	internal_borders_slider.max_value = 100
	internal_borders_slider.step = 1
	internal_borders_slider.tooltip_text = Loc.text("Borders inside kingdoms\n0%: joined land · 100%: full borders")
	video_page.add_child(internal_borders_slider)
	internal_borders_value = Hud.label_at(video_page, "50%", Vector2(390, 359), 14, Color("c5cdbb"))
	internal_borders_value.size = Vector2(42, 24)
	internal_borders_slider.value_changed.connect(func(value: float):
		Video.set_preference(&"internal_borders", value / 100.0)
		internal_borders_value.text = Loc.text("%d%%") % roundi(value))
	stylized_water_toggle = check(video_page, Loc.text("Stylized water"), Vector2(0, 192))
	stylized_water_toggle.size.x = 210
	stylized_water_toggle.clip_text = true
	stylized_water_toggle.tooltip_text = Loc.text("On: flowing waves and foam\nOff: original calm water")
	stylized_water_toggle.toggled.connect(func(value: bool): Video.set_preference(&"stylized_water", value))
	lighting_toggle = check(video_page, Loc.text("Atmospheric lighting"), Vector2(216,192))
	lighting_toggle.size.x = 216
	lighting_toggle.clip_text = true
	lighting_toggle.tooltip_text = Loc.text("On: warm sunlight, cool shadows and nearby light accents\nOff: original simple lighting\nChanges apply immediately and are saved automatically.")
	lighting_toggle.toggled.connect(func(value: bool): Video.set_preference(&"atmospheric_lighting",value))
	status_label = Hud.label_at(self, "", Vector2(0, 420), 13, Color("dfa08b"))
	status_label.size.x = 432
	Sound.settings_save_failed.connect(func(_error: Error): status_label.text = Loc.text("Audio settings could not be saved."))
	Video.save_failed.connect(func(_error: Error): status_label.text = Loc.text("Video settings could not be saved."))
	Gameplay.save_failed.connect(func(_error: Error): status_label.text = Loc.text("Gameplay settings could not be saved."))
	Keys.save_failed.connect(func(_error: Error): status_label.text = Loc.text("Controls could not be saved."))
	Languages.save_failed.connect(func(_error: Error): status_label.text = Loc.text("Language settings could not be saved."))
	refresh()

func check(parent: Control, text_value: String, position_value: Vector2) -> CheckButton:
	var button := Tips.Toggle.new()
	button.text = text_value
	button.position = position_value
	button.size = Vector2(210, 38)
	Sound.bind_button(button)
	parent.add_child(button)
	return button

func choice(items: Array, y: float) -> OptionButton:
	var button := Tips.Choice.new()
	button.position = Vector2(160, y)
	button.size = Vector2(272, 38)
	for item in items:
		button.add_item(item)
	Sound.bind_button(button)
	video_page.add_child(button)
	return button

func refresh() -> void:
	refresh_language()
	indicators_toggle.set_pressed_no_signal(Gameplay.clear_indicators)
	rules_choice.select(0 if (Gameplay.rule_mode if authored_rules == "" else authored_rules) == "modern" else 1)
	for bus in sound_sliders:
		sound_sliders[bus].set_value_no_signal(Sound.get_volume(bus) * 100)
	sound_mute.set_pressed_no_signal(Sound.is_muted())
	window_mode.select(1 if Video.fullscreen else 0)
	resolution_choice.select(Video.RESOLUTIONS.find(Video.resolution))
	resolution_choice.disabled = Video.fullscreen
	antialiasing_choice.select(Video.antialiasing)
	background_choice.select(0 if Video.background == "water" else 1)
	stylized_water_toggle.set_pressed_no_signal(Video.stylized_water)
	vsync_toggle.set_pressed_no_signal(Video.vsync)
	shadow_toggle.set_pressed_no_signal(Video.shadows)
	lighting_toggle.set_pressed_no_signal(Video.atmospheric_lighting)
	camera_follow_toggle.set_pressed_no_signal(Video.follow_turn_camera)
	level_transition_toggle.set_pressed_no_signal(Video.level_transitions)
	internal_borders_slider.set_value_no_signal(Video.internal_borders * 100.0)
	internal_borders_value.text = Loc.text("%d%%") % roundi(Video.internal_borders * 100.0)

func refresh_language() -> void:
	if language_choice == null: return
	for index in range(language_choice.item_count):
		if language_choice.get_item_metadata(index) == Languages.selected_locale: language_choice.select(index)
	language_note.text = Loc.text("Restart the game to apply the selected language.") if Languages.restart_required() else Loc.text("Language changes apply the next time you launch the game.")
