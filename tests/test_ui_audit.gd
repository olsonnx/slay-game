extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func frames(count := 3) -> void:
	for frame in range(count): await process_frame
func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event,true)
	await frames()
func click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)
	await frames()

func run() -> void:
	var video = root.get_node("Video")
	var gameplay = root.get_node("Gameplay")
	var keys = root.get_node("Keys")
	video.set_preference(&"level_transitions",false,false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	app.menus.open_options(app.menus.Screen.MAIN)
	var options = app.menus.options_view
	video.set_preference(&"brightness",1.2,false)
	gameplay.set_preference("camera_speed",1.8,false)
	options.tabs.current_tab = 1
	options.reset_button.pressed.emit()
	await frames()
	var dialog = options.reset_dialog
	expect(dialog is ColorRect and dialog.is_visible_in_tree(),"Settings reset uses an embedded game panel")
	expect(dialog.title_label.text.contains("Video") and video.brightness == 1.2,"Opening reset identifies the tab without changing any preferences")
	expect(root.gui_get_focus_owner() == dialog.keep_button,"Reset starts with the safe Keep settings choice focused")
	await key(KEY_TAB)
	expect(root.gui_get_focus_owner() == dialog.discard_button,"Tab reaches the confirmation action")
	await key(KEY_TAB)
	expect(root.gui_get_focus_owner() == dialog.keep_button,"Tab stays inside the confirmation")
	await click(options.tabs.get_child(2).get_global_rect().get_center())
	expect(options.tabs.current_tab == 1,"The modal shade blocks settings behind the confirmation")
	await key(KEY_ESCAPE)
	expect(not dialog.visible and app.menus.screen == app.menus.Screen.OPTIONS and video.brightness == 1.2,"Escape dismisses only the reset without leaving Options or changing settings")
	options.reset_button.pressed.emit()
	dialog.discard_button.pressed.emit()
	expect(video.brightness == 1.0 and gameplay.camera_speed == 1.8,"Confirm resets only the requested category")
	keys.set_binding("recruit",KEY_J,false)
	options.tabs.current_tab = 3
	expect(options.reset_button.visible,"Controls shares the same footer reset action as every other tab")
	options.reset_button.pressed.emit()
	expect(keys.bindings.recruit == KEY_J,"Controls reset waits for confirmation")
	dialog.discard_button.pressed.emit()
	expect(keys.bindings == keys.DEFAULTS and gameplay.camera_speed == 1.8,"Controls confirmation restores bindings without resetting another category")
	options.reset_button.pressed.emit()
	app.menus.show_screen(app.menus.Screen.MAIN)
	expect(not dialog.visible,"Leaving Options cannot leave a detached modal covering another screen")
	var album = root.get_node("PaintingAlbum")
	album.seen.clear()
	app.menus.show_screen(app.menus.Screen.COLLECTION)
	var collection = app.menus.collection_panel
	collection.collection_tabs.current_tab = 1
	await frames()
	expect(collection.cards.is_empty() and collection.empty_label.visible and collection.thumbnails.is_empty(),"Collected filter has an explicit empty state without loading locked art")
	var entries = album.entries()
	album.seen[entries[0].path] = true
	album.changed.emit()
	await frames()
	expect(collection.cards.size() == 1 and collection.cards.has(entries[0].path) and collection.progress_bar.value == 1,"Discovery refreshes filtered cards and collection progress")
	collection.collection_tabs.current_tab = 0
	await frames()
	for dimensions in [Vector2i(1280,720),Vector2i(960,620)]:
		root.size = dimensions
		video.set_preference(&"ui_scale",1.5,false)
		await frames(6)
		var viewport_rect := Rect2(Vector2.ZERO,root.get_visible_rect().size)
		expect(viewport_rect.encloses(collection.get_global_rect()),"Collection panel remains inside the viewport with enlarged UI")
		var card: Button = collection.cards[entries[0].path]
		for label in card.find_children("*","Label",true,false):
			expect(card.get_global_rect().encloses(label.get_global_rect()),"Card titles and artist credits remain inside their card")
		collection.open_painting(entries[0].path)
		await frames(6)
		expect(viewport_rect.encloses(collection.viewer_toolbar.get_global_rect()),"Viewer controls remain accessible at minimum window size")
		expect(root.gui_get_focus_owner() == collection.viewer_back_button,"Opening a painting moves keyboard focus into its viewer")
		collection.close_viewer()
		expect(root.gui_get_focus_owner() == card,"Closing the viewer restores focus to its painting card")
	app.queue_free()
	await frames()
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("UI audit checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
