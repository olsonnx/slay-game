extends Control
const Loc = preload("res://src/localization/text.gd")
const Hud = preload("res://src/ui/game_hud.gd")
const Tips = preload("res://src/ui/tooltip_widgets.gd")
var gameplay_page: Control
var interface_page: Control
var audio_page: Control
var video_page: Control
var controls_page
var indicators_toggle: CheckButton
var sound_sliders: Dictionary = {}
var sound_mute: CheckButton
var window_mode: OptionButton
var resolution_choice: OptionButton
var antialiasing_choice: OptionButton
var background_choice: OptionButton
var vsync_toggle: CheckButton
var shadow_toggle: CheckButton
var camera_follow_toggle: CheckButton
var level_transition_toggle: CheckButton
var internal_borders_slider: HSlider
var internal_borders_value: Label
var language_choice: OptionButton
var language_note: Label
var status_label: Label
var tabs
var reset_button: Button
var reset_dialog
var pending_reset := 0
var rows: Dictionary = {}
var heights: Dictionary = {}
var preferences: Dictionary = {}
var output_choice: OptionButton
var background_mute: CheckButton
var scale_note: Label

func _ready() -> void:
	tabs = preload("res://src/ui/options_tabs.gd").new()
	tabs.size = Vector2(432,36)
	for title in ["Audio", "Video", "Game", "Controls", "Interface"]: tabs.add_tab(title)
	for button in tabs.get_children(): button.add_theme_font_size_override("font_size",12)
	add_child(tabs)
	audio_page = make_page()
	video_page = make_page()
	gameplay_page = make_page()
	controls_page = preload("res://src/ui/controls_view.gd").new()
	controls_page.position.y = 49
	add_child(controls_page)
	interface_page = make_page()
	tabs.tab_changed.connect(func(index): show_tab(index); Sound.play(&"ui_click"))
	build_audio()
	build_video()
	build_gameplay()
	build_interface()
	status_label = Hud.label_at(self,"",Vector2(0,380),12,Color("dfa08b"))
	status_label.size = Vector2(432,24)
	reset_button = Button.new()
	Hud.UiTheme.style_button(reset_button)
	reset_button.text = Loc.text("Restore this tab's defaults")
	reset_button.position = Vector2(0,408)
	reset_button.size = Vector2(432,32)
	add_child(reset_button)
	Sound.bind_button(reset_button)
	var reset_layer := CanvasLayer.new()
	reset_layer.layer = 100
	add_child(reset_layer)
	reset_dialog = preload("res://src/ui/confirmation_panel.gd").new()
	reset_dialog.title = Loc.text("Restore defaults")
	reset_dialog.dialog_text = Loc.text("Restore settings in this tab? Your profile, progress and other tabs will be kept.")
	reset_dialog.cancel_text = "Keep settings"
	reset_dialog.confirm_text = "Restore defaults"
	reset_dialog.confirmed.connect(func(): restore_tab(pending_reset))
	reset_layer.add_child(reset_dialog)
	reset_button.pressed.connect(func():
		controls_page.cancel_capture()
		pending_reset = tabs.current_tab
		reset_dialog.title = Loc.text("Restore %s defaults?") % tabs.get_tab_title(pending_reset)
		reset_dialog.popup_centered())
	visibility_changed.connect(func():
		if not is_visible_in_tree(): reset_dialog.hide())
	Sound.settings_save_failed.connect(func(_error): status_label.text = Loc.text("Audio settings could not be saved."))
	Video.save_failed.connect(func(_error): status_label.text = Loc.text("Video settings could not be saved."))
	Gameplay.save_failed.connect(func(_error): status_label.text = Loc.text("Gameplay settings could not be saved."))
	Keys.save_failed.connect(func(_error): status_label.text = Loc.text("Controls could not be saved."))
	Languages.save_failed.connect(func(_error): status_label.text = Loc.text("Language settings could not be saved."))
	Video.changed.connect(refresh)
	Gameplay.changed.connect(refresh)
	Sound.settings_changed.connect(refresh)
	Languages.changed.connect(refresh_language)
	get_viewport().size_changed.connect(refresh)
	show_tab(0)
	refresh()

func make_page() -> Control:
	var page := Control.new()
	page.position.y = 49
	page.size = Vector2(432,324)
	add_child(page)
	var scroll := ScrollContainer.new()
	scroll.size = page.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size.x = 416
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	rows[page] = content
	heights[page] = 0.0
	return page

func row(page: Control, height := 52.0) -> Control:
	var content: Control = rows[page]
	var result := Control.new()
	result.position.y = heights[page]
	result.size = Vector2(416,height)
	content.add_child(result)
	heights[page] += height
	content.custom_minimum_size.y = heights[page]
	return result

func heading(page: Control, text_value: String) -> void:
	Hud.label_at(row(page,32),text_value,Vector2(0,6),14,Hud.UiTheme.ACCENT)

func label(parent: Control, text_value: String) -> void:
	var caption := Hud.label_at(parent,text_value,Vector2(0,10),14)
	caption.size = Vector2(154,30)
	caption.clip_text = true

func choose(page: Control, title: String, items: Array, tip := "") -> OptionButton:
	var container := row(page)
	label(container,title)
	var button := Tips.Choice.new()
	button.position = Vector2(160,0)
	button.size = Vector2(248,38)
	button.fit_to_longest_item = false
	button.clip_text = true
	button.tooltip_text = Loc.text(tip)
	for item in items: button.add_item(Loc.text(str(item)))
	container.add_child(button)
	Sound.bind_button(button)
	return button

func check(page: Control, text_value: String, tip := "") -> CheckButton:
	var button := Tips.Toggle.new()
	button.text = Loc.text(text_value)
	button.tooltip_text = Loc.text(tip)
	button.size = Vector2(408,38)
	row(page,44).add_child(button)
	Sound.bind_button(button)
	return button

func slider(page: Control, title: String, minimum: float, maximum: float, step_value: float, tip := "") -> Dictionary:
	var container := row(page)
	label(container,title)
	var control := Tips.RangeSlider.new()
	control.position = Vector2(160,9)
	control.size = Vector2(180,24)
	control.min_value = minimum
	control.max_value = maximum
	control.step = step_value
	control.tooltip_text = Loc.text(tip)
	container.add_child(control)
	var value := Hud.label_at(container,"",Vector2(346,10),12,Hud.UiTheme.MUTED)
	value.size = Vector2(62,24)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return {"control":control,"value":value}

func preference_toggle(page: Control, title: String, owner: Node, key: String, tip := "") -> CheckButton:
	var button := check(page,title,tip)
	button.toggled.connect(func(value): owner.set_preference(key,value))
	preferences[key] = {"control":button,"owner":owner}
	return button

func preference_slider(page: Control, title: String, owner: Node, key: String, minimum: float, maximum: float, step_value: float, tip := "") -> Dictionary:
	var entry := slider(page,title,minimum,maximum,step_value,tip)
	entry["owner"] = owner
	entry.control.value_changed.connect(func(value): owner.set_preference(key,value))
	preferences[key] = entry
	return entry

func build_audio() -> void:
	for entry in [[&"Master","Overall volume"],[&"UI","Interface"],[&"SFX","Game effects"],[&"Ambience","Ambience"],[&"Music","Music"]]:
		var bus: StringName = entry[0]
		var pair := slider(audio_page,entry[1],0,100,1,"Volume changes are saved automatically.")
		pair.control.value_changed.connect(func(value):
			pair.value.text = "%d%%" % roundi(value)
			Sound.set_volume(bus,value/100.0))
		sound_sliders[bus] = pair.control
		pair.control.set_meta("value_label",pair.value)
	sound_mute = check(audio_page,"Mute all sounds")
	sound_mute.toggled.connect(func(value): Sound.set_muted(value))
	background_mute = check(audio_page,"Mute when unfocused","Silence audio while another application is active.")
	background_mute.toggled.connect(func(value): Sound.set_mute_unfocused(value))
	output_choice = choose(audio_page,"Output device",["Default"],"Choose your speakers or headphones. Missing devices fall back to the system default.")
	output_choice.item_selected.connect(func(index): Sound.set_output_device(output_choice.get_item_metadata(index)))

func build_video() -> void:
	heading(video_page,"Display")
	window_mode = choose(video_page,"Display mode",["Windowed","Fullscreen"])
	window_mode.item_selected.connect(func(index): Video.set_preference(&"fullscreen",index == 1))
	var resolutions: Array = []
	for value in Video.RESOLUTIONS: resolutions.append("%d × %d" % [value.x,value.y])
	resolution_choice = choose(video_page,"Resolution",resolutions,"Windowed: window size. Fullscreen: scene rendering resolution; interface stays sharp.")
	resolution_choice.item_selected.connect(func(index): Video.set_preference(&"resolution",Video.RESOLUTIONS[index]))
	vsync_toggle = preference_toggle(video_page,"VSync",Video,"vsync","Synchronize frames with the display to reduce tearing.")
	for key in ["frame_limit","background_frame_limit"]:
		var names: Array = []
		for limit in Video.FRAME_LIMITS: names.append("Unlimited" if limit == 0 else "%d FPS" % limit)
		var control := choose(video_page,"Frame limit" if key == "frame_limit" else "Unfocused limit",names,"VSync may cap FPS below this limit. Losing focus never increases the active frame limit.")
		control.item_selected.connect(func(index): Video.set_preference(key,Video.FRAME_LIMITS[index]))
		preferences[key] = {"control":control,"owner":Video,"choices":Video.FRAME_LIMITS}
	heading(video_page,"Graphics")
	antialiasing_choice = choose(video_page,"Anti-aliasing",["Off","2× MSAA","4× MSAA","8× MSAA"],"Smoother edges. Higher settings use more GPU power.")
	antialiasing_choice.item_selected.connect(func(index): Video.set_preference(&"antialiasing",index))
	shadow_toggle = preference_toggle(video_page,"Shadows",Video,"shadows")
	preference_toggle(video_page,"Contact shadows",Video,"ambient_occlusion","Adds shading where objects meet. Disabling this can improve GPU performance.")
	preference_toggle(video_page,"Depth of field",Video,"depth_of_field","Diorama blur when viewing the board up close. Turn off for a consistently sharp board.")
	preference_toggle(video_page,"Clouds",Video,"clouds","Show distant clouds when zoomed out, keeping the island clear.")
	preference_slider(video_page,"Brightness",Video,"brightness",0.7,1.3,0.05)
	background_choice = choose(video_page,"Background",["Water","Sky"])
	background_choice.item_selected.connect(func(index): Video.set_preference(&"background","water" if index == 0 else "sky"))
	preference_toggle(video_page,"Animated menu",Video,"menu_animation","Turn off decorative menu movement to reduce distraction and CPU work.")

func build_gameplay() -> void:
	camera_follow_toggle = preference_toggle(gameplay_page,"Follow active kingdom",Video,"follow_turn_camera","Manual camera movement stops following for the current turn.")
	level_transition_toggle = preference_toggle(gameplay_page,"Animate island transitions",Video,"level_transitions")
	preference_slider(gameplay_page,"Playback speed",Gameplay,"playback_speed",0.5,3.0,0.5,"Changes movement playback, not game rules or AI decisions. Hold the speed key for 6× playback.")
	preference_toggle(gameplay_page,"Pause when unfocused",Gameplay,"pause_on_focus_loss","Pause solo and local games when switching applications. Online matches keep running.")
	heading(gameplay_page,"Camera")
	preference_slider(gameplay_page,"Pan sensitivity",Gameplay,"camera_speed",0.25,2.0,0.05)
	preference_slider(gameplay_page,"Rotate sensitivity",Gameplay,"rotation_speed",0.25,2.0,0.05)
	preference_slider(gameplay_page,"Zoom sensitivity",Gameplay,"zoom_speed",0.25,2.0,0.05)
	preference_toggle(gameplay_page,"Invert scroll zoom",Gameplay,"invert_zoom")
	preference_toggle(gameplay_page,"Invert vertical rotation",Gameplay,"invert_vertical")

func build_interface() -> void:
	preference_slider(interface_page,"UI scale",Video,"ui_scale",0.75,1.5,0.05,"Scales menus, text and the HUD together. Enlargement is limited to keep every control inside the current window.")
	scale_note = Hud.label_at(row(interface_page,40),"",Vector2.ZERO,12,Hud.UiTheme.MUTED)
	scale_note.size = Vector2(408,38)
	scale_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preference_slider(interface_page,"Tooltip delay",Video,"tooltip_delay",0,1.5,0.05,"Seconds before hover help appears.")
	preference_toggle(interface_page,"Show FPS",Video,"show_fps","F3 also toggles the performance display.")
	preference_toggle(interface_page,"Reduced motion",Video,"reduced_motion","Stops decorative menu movement, animated loading tiles, island transitions and automatic camera pans.")
	indicators_toggle = check(interface_page,"Clear movement indicators","Show area borders and curved arrows instead of tile outlines and dotted paths.")
	indicators_toggle.toggled.connect(func(value): Gameplay.set_clear_indicators(value))
	var borders := preference_slider(interface_page,"Internal borders",Video,"internal_borders",0,1,0.01,"Visibility of borders within a kingdom.")
	internal_borders_slider = borders.control
	internal_borders_value = borders.value
	language_choice = choose(interface_page,"Language",[])
	language_choice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for language in Languages.languages:
		language_choice.add_item(language.name)
		language_choice.set_item_metadata(language_choice.item_count-1,language.locale)
	language_choice.item_selected.connect(func(index): Languages.set_language(language_choice.get_item_metadata(index)))
	language_note = Hud.label_at(row(interface_page,48),"",Vector2.ZERO,12,Hud.UiTheme.MUTED)
	language_note.size = Vector2(408,46)
	language_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func show_tab(index: int) -> void:
	var pages := [audio_page,video_page,gameplay_page,controls_page,interface_page]
	for i in range(pages.size()): pages[i].visible = i == index

func refresh() -> void:
	if language_choice == null: return
	refresh_language()
	indicators_toggle.set_pressed_no_signal(Gameplay.clear_indicators)
	for bus in sound_sliders:
		var control: HSlider = sound_sliders[bus]
		control.set_value_no_signal(Sound.get_volume(bus)*100)
		control.get_meta("value_label").text = "%d%%" % roundi(control.value)
	sound_mute.set_pressed_no_signal(Sound.previous_mute if Sound.focus_muted else Sound.is_muted())
	background_mute.set_pressed_no_signal(Sound.mute_unfocused)
	output_choice.clear()
	var devices := AudioServer.get_output_device_list()
	if "Default" not in devices: devices.insert(0,"Default")
	for device in devices:
		output_choice.add_item(device)
		output_choice.set_item_metadata(output_choice.item_count-1,device)
		if device == Sound.output_device: output_choice.select(output_choice.item_count-1)
	window_mode.select(1 if Video.fullscreen else 0)
	resolution_choice.select(Video.RESOLUTIONS.find(Video.resolution))
	antialiasing_choice.select(Video.antialiasing)
	background_choice.select(0 if Video.background == "water" else 1)
	for key in preferences:
		var entry: Dictionary = preferences[key]
		var value = entry.owner.get(key)
		if entry.control is CheckButton: entry.control.set_pressed_no_signal(value)
		elif entry.control is OptionButton: entry.control.select(entry.choices.find(value))
		else:
			entry.control.set_value_no_signal(value)
			entry.value.text = ("%.2f s" % value) if key == "tooltip_delay" else ("%.1f×" % value) if key == "playback_speed" else "%d%%" % roundi(value*100)
	scale_note.text = Loc.text("Applied UI scale: %d%%. Fits the current window.") % roundi(Video.effective_ui_scale()*100)
	preferences.ambient_occlusion.control.disabled = not Video.shadows

func refresh_language() -> void:
	if language_choice == null: return
	for index in range(language_choice.item_count):
		if language_choice.get_item_metadata(index) == Languages.selected_locale: language_choice.select(index)
	language_note.text = Loc.text("Restart the game to apply the selected language.") if Languages.restart_required() else Loc.text("Language changes apply the next time you launch the game.")

func restore_tab(index: int) -> void:
	match index:
		0:
			for pair in [[&"Master",0.0],[&"UI",-8.0],[&"SFX",-6.0],[&"Ambience",-6.0],[&"Music",0.0]]: Sound.set_volume(pair[0],db_to_linear(pair[1]))
			Sound.set_muted(false)
			Sound.set_mute_unfocused(false)
			Sound.set_output_device("Default")
		1:
			for key in ["frame_limit","background_frame_limit","menu_animation","depth_of_field","ambient_occlusion","brightness","clouds"]: Video.set_preference(key,Video.EXTRA_DEFAULTS[key])
			for pair in [["fullscreen",false],["resolution",Video.BASE_SIZE],["vsync",true],["antialiasing",2],["shadows",true],["background","water"],["plastic_tiles",true],["atmospheric_lighting",true],["stylized_water",false]]: Video.set_preference(pair[0],pair[1])
		2:
			for key in Gameplay.PRESENTATION_DEFAULTS: Gameplay.set_preference(key,Gameplay.PRESENTATION_DEFAULTS[key])
			Video.set_preference(&"follow_turn_camera",true)
			Video.set_preference(&"level_transitions",true)
		3:
			controls_page.cancel_capture()
			Keys.reset_defaults()
		4:
			for key in ["ui_scale","tooltip_delay","show_fps","reduced_motion"]: Video.set_preference(key,Video.EXTRA_DEFAULTS[key])
			Video.set_preference(&"internal_borders",0.5)
			Gameplay.set_clear_indicators(true)
			Languages.set_language("en")
	refresh()
