extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("Video").set_preference(&"depth_of_field",false,false)
	root.get_node("Sound").set_muted(true,false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await process_frame
	var album = root.get_node("PaintingAlbum")
	album.seen.clear()
	for entry in album.entries(): album.seen[entry.path] = true
	app.menus.collection_button.pressed.emit()
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/gallery-loading.png")
	while app.transitioning: await process_frame
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/gallery-loaded.png")
	app.menus.show_screen(app.menus.Screen.MAIN)
	var start := Time.get_ticks_usec()
	app.menus.collection_button.pressed.emit()
	print("Cached gallery entry: ",(Time.get_ticks_usec()-start)/1000.0," ms")
	app.queue_free()
	await process_frame
	quit()
