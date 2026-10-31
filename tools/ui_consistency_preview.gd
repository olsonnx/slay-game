extends SceneTree
var app
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	for frame in range(10): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/ui-audit-"+label+".png")
	print("UI preview: ",label)
func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"fullscreen",false,false)
	video.set_preference(&"resolution",Vector2i(1280,720),false)
	video.set_preference(&"ui_scale",1.0,false)
	video.set_preference(&"level_transitions",false,false)
	video.set_preference(&"menu_animation",false,false)
	video.set_preference(&"depth_of_field",false,false)
	root.get_node("Sound").set_muted(true,false)
	app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	app.menus.show_screen(app.menus.Screen.MAIN)
	await capture("main")
	var album = root.get_node("PaintingAlbum")
	album.seen.clear()
	app.menus.show_screen(app.menus.Screen.COLLECTION)
	var collection = app.menus.collection_panel
	await capture("locked")
	var entries = album.entries()
	for index in range(mini(2,entries.size())): album.seen[entries[index].path] = true
	collection.open_album()
	await capture("gallery")
	collection.collection_tabs.current_tab = 1
	await capture("collected")
	collection.open_painting(entries[0].path)
	await capture("viewer")
	app.menus.open_options(app.menus.Screen.MAIN)
	app.menus.options_view.reset_button.pressed.emit()
	await capture("reset")
	app.menus.options_view.reset_dialog.cancel()
	DisplayServer.window_set_size(Vector2i(960,620))
	video.set_preference(&"ui_scale",1.5,false)
	app.menus.show_screen(app.menus.Screen.COLLECTION)
	collection.collection_tabs.current_tab = 0
	await capture("gallery-small")
	collection.open_painting(entries[0].path)
	await capture("viewer-small")
	app.menus.open_options(app.menus.Screen.MAIN)
	app.menus.options_view.reset_button.pressed.emit()
	await capture("reset-small")
	app.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	quit()
