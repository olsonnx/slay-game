extends SceneTree
func _initialize() -> void:
	root.title = "Slay & Reign - Tutorial Editor"
	root.min_size = Vector2i(1160,720)
	root.size = Vector2i(1360,900)
	auto_accept_quit = false
	call_deferred("start")
func start() -> void:
	if DisplayServer.get_name() != "headless": root.mode = Window.MODE_WINDOWED
	root.min_size = Vector2i(1160,720)
	root.size = Vector2i(1360,900)
	var editor = load("res://src/tutorial_editor/tutorial_editor.gd").new()
	root.add_child(editor)
	root.close_requested.connect(editor.request_close)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tutorial="):
			editor.dialog_action = "open"
			editor.file_chosen(argument.trim_prefix("--tutorial="))
