extends SceneTree
func _initialize() -> void:
	root.title = "Slay & Reign - Event Editor"
	root.min_size = Vector2i(1180,760)
	root.size = Vector2i(1480,920)
	auto_accept_quit = false
	call_deferred("start")
func start() -> void:
	if DisplayServer.get_name() != "headless": root.mode = Window.MODE_WINDOWED
	var editor = load("res://src/event_editor/event_editor.gd").new()
	root.add_child(editor)
	root.close_requested.connect(editor.request_close)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--event="):
			editor.file_action = "import"
			editor.file_selected(argument.trim_prefix("--event="))
		if argument == "--capture":
			await create_timer(0.6).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/event-editor-preview.png")
			root.get_node("Sound").stop_all()
			quit()
