extends SceneTree
const Sizes = preload("res://src/game/map_sizes.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	root.size = Vector2i(960,620)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var menus = app.menus
	var names: Array = []
	for size_id in Sizes.IDS: names.append(Sizes.spec(size_id)["name"])
	expect(names == ["Tiny", "Small", "Standard", "Large", "Huge"], "All selectors use the requested five names in order")
	expect(menus.size_choice.item_count == 5 and menus.size_choice.get_item_text(2) == Sizes.choice_label("large"), "Quick Play exposes Standard at the former Large budget")
	menus.show_screen(menus.Screen.SETUP)
	menus.size_choice.select(Sizes.IDS.find("huge"))
	menus.size_choice.item_selected.emit(Sizes.IDS.find("huge"))
	await process_frame
	expect(menus.setup_hint.text == Sizes.size_warning("huge") and menus.setup_hint.is_visible_in_tree(),"Huge warning is visible without hovering in Quick Play")
	expect(menus.setup_hint.position.y+menus.setup_hint.size.y <= menus.setup_start_button.position.y,"Warning fits above Start at the minimum viewport")
	expect(menus.setup_hint.get_line_count() <= 2,"English warning fits two lines")
	if "--preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/huge-warning-quickplay.png")
	menus.size_choice.select(Sizes.IDS.find("small"))
	menus.size_choice.item_selected.emit(Sizes.IDS.find("small"))
	expect(not menus.setup_hint.text.contains("Warning"),"Switching back to Small restores the ordinary setup hint")
	var panel = menus.multiplayer_panel
	panel.load_config({"size":"small","count":4,"rules":"modern"})
	menus.show_screen(menus.Screen.MULTIPLAYER)
	panel.show_page("map")
	panel.size_choice.select(Sizes.IDS.find("huge"))
	panel.size_choice.item_selected.emit(Sizes.IDS.find("huge"))
	await process_frame
	expect(panel.size_warning.text == Sizes.size_warning("huge") and panel.size_warning.is_visible_in_tree(),"Multiplayer shows the same warning on selecting Huge")
	expect(panel.size_warning.position.y+panel.size_warning.size.y <= panel.advanced_button.position.y,"Warning fits above Advanced")
	if "--preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/huge-warning-multiplayer.png")
	panel.size_choice.select(Sizes.IDS.find("small"))
	panel.size_choice.item_selected.emit(Sizes.IDS.find("small"))
	expect(panel.size_warning.text == "","Multiplayer clears the warning on Small")
	expect(Sizes.tile_tooltip("huge").contains(Sizes.size_warning("huge")),"Shared tooltips include the warning for editor and size popups")
	app.queue_free()
	await process_frame
	print("Huge warning checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
