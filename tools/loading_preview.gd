extends SceneTree
## Native snapshots of the shared loading cover at real progress values.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var small := "--small" in OS.get_cmdline_user_args()
	root.size = Vector2i(960, 620) if small else Vector2i(1400, 960)
	root.get_node("Sound").set_muted(true, false)
	var screen = load("res://src/ui/preparation_screen.gd").new()
	root.add_child(screen)
	for value in [0.0, 0.42, 0.85, 1.0]:
		screen.set_progress(value)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/loading-hex-%d%s.png" % [int(value * 100), "-small" if small else ""])
	await screen.reveal()
	await process_frame
	root.get_node("Sound").stop_all()
	quit()
