extends SceneTree
var app
var original: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/settings-"+label+".png")
	print("Settings preview: ",label)
func run() -> void:
	var video = root.get_node("Video")
	for key in ["fullscreen","resolution","ui_scale","show_fps"]: original[key] = video.get(key)
	video.set_preference(&"fullscreen",false,false)
	video.set_preference(&"resolution",Vector2i(1280,720),false)
	video.set_preference(&"ui_scale",1.0,false)
	video.set_preference(&"show_fps",false,false)
	app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	app.menus.open_options(app.menus.Screen.MAIN)
	var options = app.menus.options_view
	for index in range(5):
		options.tabs.current_tab = index
		await capture(["audio","video","gameplay","controls","interface"][index])
	for index in [0,2,4]:
		options.tabs.current_tab = index
		[options.audio_page,options.video_page,options.gameplay_page,options.controls_page,options.interface_page][index].get_child(0).scroll_vertical = 2000
		await capture(["audio-bottom","unused","game-bottom","unused","interface-bottom"][index])
	options.interface_page.get_child(0).scroll_vertical = 0
	options.video_page.get_child(0).scroll_vertical = 2000
	options.tabs.current_tab = 1
	await capture("video-scrolled")
	options.tabs.current_tab = 4
	video.set_preference(&"ui_scale",1.5,false)
	await capture("ui-large")
	DisplayServer.window_set_size(Vector2i(960,620))
	await capture("minimum-window-large-ui")
	app.queue_free()
	await process_frame
	for key in original: video.set_preference(key,original[key],false)
	await create_timer(1.2).timeout
	quit()
