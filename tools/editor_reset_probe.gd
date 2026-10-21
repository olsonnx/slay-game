extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var Doc = load("res://src/editor/level_document.gd")
	var doc = Doc.new()
	var start := Time.get_ticks_usec()
	doc.generate("huge", "modern", true)
	print("BLANK_HUGE_MS ", (Time.get_ticks_usec()-start)/1000.0)
	var editor = load("res://src/editor/level_editor.gd").new()
	start = Time.get_ticks_usec()
	root.add_child(editor)
	print("EDITOR_OPEN_MS ", (Time.get_ticks_usec()-start)/1000.0)
	await process_frame
	start = Time.get_ticks_usec()
	editor.document.generate("huge", "modern")
	print("GENERATE_HUGE_MS ", (Time.get_ticks_usec()-start)/1000.0)
	start = Time.get_ticks_usec()
	editor.refresh(true)
	print("REFRESH_HUGE_MS ", (Time.get_ticks_usec()-start)/1000.0, " tiles=",editor.document.cells.size())
	await process_frame
	start = Time.get_ticks_usec()
	editor.document.generate("huge", "modern", true)
	print("RESET_BLANK_GENERATE_MS ", (Time.get_ticks_usec()-start)/1000.0)
	start = Time.get_ticks_usec()
	editor.refresh(true)
	print("RESET_BLANK_REFRESH_MS ", (Time.get_ticks_usec()-start)/1000.0)
	editor.queue_free()
	await process_frame
	quit()
