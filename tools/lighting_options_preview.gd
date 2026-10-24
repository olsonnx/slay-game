extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("Video").set_preference(&"resolution",Vector2i(960,620),false)
	root.get_node("Sound").set_muted(true,false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await create_timer(0.5).timeout
	app.menus.open_options(app.menus.Screen.MAIN)
	app.menus.options_view.get_child(0).get_child(1).pressed.emit()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/lighting-options-960.png")
	app.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit()
