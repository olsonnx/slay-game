extends SceneTree
## Native display verification and reproducible music-player screenshots.
var app
var saved_resolution: Vector2i
var saved_fullscreen: bool

func _initialize() -> void: call_deferred("run")

func capture(label: String) -> void:
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + label + ".png")
	print("Captured ", label, " / window ", root.size, " / 3D scale ", root.scaling_3d_scale)

func run() -> void:
	var video = root.get_node("Video")
	saved_resolution = video.resolution
	saved_fullscreen = video.fullscreen
	video.set_preference(&"fullscreen", false, false)
	video.set_preference(&"resolution", Vector2i(1280,720), false)
	app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await capture("music-loading-hidden")
	if not app.startup_complete: await app.startup_finished
	app.music_controls.set_open(true)
	await capture("music-menu-720p")
	await app.start_new_game(42, "tiny", "easy", 2)
	while app.game.view.level_transitioning: await process_frame
	await capture("music-game-720p")
	video.set_preference(&"fullscreen", true, false)
	await capture("music-fullscreen-render-720p")
	video.set_preference(&"resolution", Vector2i(1920,1080), false)
	await capture("music-fullscreen-render-1080p")
	app.pause_game()
	app.menus.open_options(app.menus.Screen.PAUSE)
	await capture("music-options-audio")
	app.menus.options_view.get_child(0).current_tab = 1
	await capture("music-options-video")
	app.continue_game()
	await app.return_to_main_menu()
	app.queue_free()
	await process_frame
	video.set_preference(&"fullscreen", saved_fullscreen, false)
	video.set_preference(&"resolution", saved_resolution, false)
	await create_timer(1.2).timeout
	quit()
