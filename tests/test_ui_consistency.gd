extends SceneTree
const Ui = preload("res://src/ui/ui_theme.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func geometry(box: StyleBox) -> Array:
	var result: Array = [box.get_minimum_size()]
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: result.append(box.get_content_margin(side))
	if box is StyleBoxFlat:
		for corner in [CORNER_TOP_LEFT,CORNER_TOP_RIGHT,CORNER_BOTTOM_LEFT,CORNER_BOTTOM_RIGHT]: result.append(box.get_corner_radius(corner))
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
			result.append(box.get_border_width(side))
			result.append(box.get_expand_margin(side))
	return result

func check_buttons(parent: Node) -> void:
	for node in parent.find_children("*","Button",true,false):
		if node is CheckButton: continue
		var normal: StyleBox = node.get_theme_stylebox("normal")
		for state in ["hover","pressed","hover_pressed","disabled"]:
			expect(geometry(node.get_theme_stylebox(state)) == geometry(normal),"Button shape and padding stay fixed for %s: %s" % [state,node.text])
		for state in ["font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
			expect(node.get_theme_color(state) == node.get_theme_color("font_color"),"Button text retains its intended contrast: " + node.text)

func pointer(point: Vector2, held := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event,true)
	await process_frame
	await process_frame

func capture(name_value: String) -> void:
	if "--preview" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/consistent_%s.png" % name_value)

func interact(button: Button, label: String) -> void:
	await pointer(Vector2(5,5))
	var rect := button.get_global_rect()
	var minimum := button.get_combined_minimum_size()
	await capture(label+"_normal")
	await pointer(rect.get_center())
	expect(button.get_draw_mode() == BaseButton.DRAW_HOVER,"Real pointer input reaches hover state: " + label)
	expect(button.get_global_rect() == rect and button.get_combined_minimum_size() == minimum,"Hover preserves layout: " + label)
	await capture(label+"_hover")
	var down := InputEventMouseButton.new()
	down.position = rect.get_center()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	root.push_input(down,true)
	await process_frame
	expect(button.get_global_rect() == rect,"Press preserves layout: " + label)
	await capture(label+"_pressed")
	await pointer(Vector2(5,5),true)
	down.position = Vector2(5,5)
	down.button_mask = 0
	down.pressed = false
	root.push_input(down,true)
	await process_frame
	button.disabled = true
	await process_frame
	expect(button.get_global_rect() == rect,"Disabled state preserves layout: " + label)
	button.disabled = false
	if button.focus_mode != Control.FOCUS_NONE:
		button.grab_focus()
		await process_frame
		expect(button.get_global_rect() == rect,"Keyboard focus preserves layout: " + label)
		button.release_focus()

func run() -> void:
	root.size = Vector2i(960,620)
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check_buttons(app.menus.backdrop)
	var quick: Button
	for button in app.menus.main_panel.find_children("*","Button",true,false):
		if button.text == "Quick Play": quick = button
	await interact(quick,"main")
	var panel = app.menus.multiplayer_panel
	panel.load_config({"count":6})
	app.menus.show_screen(app.menus.Screen.MULTIPLAYER)
	panel.show_page("players")
	await process_frame
	await interact(panel.start_button,"multiplayer")
	panel.show_page("map")
	await interact(panel.advanced_button,"advanced")
	panel.show_page("players")
	panel.player_tools.popup_centered(Vector2i(352,208))
	await process_frame
	check_buttons(panel.player_tools)
	await capture("player_options")
	panel.player_tools.hide()
	app.menus.open_options(app.menus.Screen.MAIN)
	app.menus.options_view.get_child(0).current_tab = 1
	await process_frame
	await capture("video")
	var theme: Theme = app.menus.backdrop.theme
	for state in ["grabber_highlight","grabber_disabled"]:
		expect(theme.get_icon(state,"HSlider").get_size() == theme.get_icon("grabber","HSlider").get_size(),"Slider thumb dimensions stay fixed")
	for kind in ["OptionButton","TabBar"]:
		var states := ["normal","hover","pressed","hover_pressed","disabled"] if kind == "OptionButton" else ["tab_unselected","tab_selected","tab_hovered","tab_disabled"]
		for state in states:
			expect(geometry(theme.get_stylebox(state,kind)) == geometry(theme.get_stylebox(states[0],kind)),"Dropdowns and tabs keep their geometry")
	await app.start_new_game(42,"very_small","normal",2)
	check_buttons(app.game.ui_root)
	app.game.open_shop("recruit")
	check_buttons(app.game.shop_panel)
	app.game.cancel_action()
	app.game.rules.kingdoms[app.game.active_capital()]["gold"] = 100
	app.game.inspect_province(app.game.active_capital())
	app.game.province_view.reveal = 1
	await interact(app.game.province_view.develop_button,"develop")
	await app.return_to_main_menu()
	app.open_editor()
	await process_frame
	check_buttons(app.editor.ui_root)
	expect(app.editor.file_dialog.theme != null and app.editor.confirm.theme != null,"Editor dialogs use the shared interface theme")
	await capture("editor")
	app.close_editor()
	app.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("UI consistency checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
