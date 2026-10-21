extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func run() -> void:
	root.size = Vector2i(1200, 800)
	var original_limit := Engine.max_fps
	Engine.max_fps = 0
	var editor = load("res://src/editor/level_editor.gd").new()
	root.add_child(editor)
	expect(Engine.max_fps == 120, "Editor bounds rendering when the application was uncapped")
	await editor.new_island(true)
	editor.close_context()
	var preview: MeshInstance3D = editor.brush_preview
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var rebuilds: int = editor.view.static_batches.rebuild_count
	for index in range(2000):
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(600 + (index % 50) * 3, 200 + (index % 30) * 3)
		motion.relative = Vector2(1, 0)
		editor._input(motion)
		editor._unhandled_input(motion)
	expect(editor.brush_preview == preview and editor.view.overlay_root.get_child_count() == 1, "Water hover reuses one outline across thousands of cursor updates")
	expect(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) <= node_count, "Hover does not allocate and queue scene nodes for deletion")
	expect(preview.visible and preview.material_override == editor.brush_preview_water, "Blank water shows the blue tile-placement outline")
	expect(editor.document.cells.is_empty() and editor.view.static_batches.rebuild_count == rebuilds, "Water hover neither paints nor rebuilds terrain")
	var point: Vector2 = editor.view.camera.unproject_position(Vector3.ZERO)
	var click := InputEventMouseButton.new()
	click.position = point
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	editor._input(click)
	editor._unhandled_input(click)
	click.pressed = false
	editor._input(click)
	expect(editor.document.cells.has(Vector2i.ZERO) and preview.material_override == editor.brush_preview_land, "Placing the first tile updates the retained cursor to a land outline")
	editor.undo()
	expect(editor.document.cells.is_empty(), "First-tile placement stays undoable")
	var ui_motion := InputEventMouseMotion.new()
	ui_motion.position = editor.ui.view_button.get_global_rect().get_center()
	editor._input(ui_motion)
	expect(not preview.visible, "Moving over UI hides the placement cursor")
	editor.queue_free()
	await process_frame
	expect(Engine.max_fps == 0, "Closing the editor restores the application's original FPS limit")
	Engine.max_fps = 55
	var second = load("res://src/editor/level_editor.gd").new()
	root.add_child(second)
	expect(Engine.max_fps == 55, "Editor respects an existing lower frame limit")
	root.remove_child(second)
	expect(Engine.max_fps == 55, "Detaching for playtest restores the preceding limit")
	root.add_child(second)
	expect(Engine.max_fps == 55, "Returning from playtest reapplies the lower limit")
	second.queue_free()
	await process_frame
	Engine.max_fps = original_limit
	print("Editor water-hover checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
