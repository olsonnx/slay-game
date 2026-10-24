extends SceneTree

class TrackedDocument extends "res://src/editor/level_document.gd":
	var snapshot_reads := 0
	func state() -> Dictionary:
		snapshot_reads += 1
		return super.state()

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func hover(editor, screen: Vector2, count: int) -> void:
	for index in range(count):
		var motion := InputEventMouseMotion.new()
		motion.position = screen + Vector2(index % 4, 0)
		motion.relative = Vector2(1, 0)
		editor._input(motion)
		editor._unhandled_input(motion)

func run() -> void:
	root.size = Vector2i(1200, 800)
	var editor = load("res://src/editor/level_editor.gd").new()
	root.add_child(editor)
	await process_frame
	var doc := TrackedDocument.new()
	doc.generate("huge", "modern", true)
	for q in range(-18, 19):
		for r in range(-14, 15): doc.cells[Vector2i(q, r)] = doc.Rules.new().make_cell()
	editor.document = doc
	editor.refresh(true)
	editor.close_context()
	var water: Vector2 = editor.view.camera.unproject_position(doc.Rules.Grid.to_world(Vector2i(30, 0)))
	expect(not editor.pointer_over_ui(water) and not doc.cells.has(editor.view.hex_at_screen(water, true)), "Performance fixture hovers over empty map space")
	doc.snapshot_reads = 0
	hover(editor, water, 100)
	expect(doc.snapshot_reads == 0, "Rapid empty-space hover never serializes or sorts the whole map")
	expect(editor.ui.status.text == editor.document_status and editor.ui.status.text.contains("1073 TILES"), "Empty-space hover restores the cached editor summary")
	var land: Vector2 = editor.view.camera.unproject_position(Vector3.ZERO)
	hover(editor, land, 100)
	expect(doc.snapshot_reads == 0 and editor.ui.status.text.contains("Province"), "Land hover shows province details without document snapshots")
	doc.mark_saved()
	editor.update_status()
	expect(not editor.ui.status.text.contains(" *"), "Save clears the dirty marker")
	doc.snapshot_reads = 0
	hover(editor, water, 100)
	expect(doc.snapshot_reads == 0 and not editor.ui.status.text.contains(" *"), "Saved-state hover remains cheap and accurate")
	editor.ui.name_edit.text = "Changed title"
	editor.ui.name_edit.text_changed.emit("Changed title")
	expect(doc.title == "Changed title" and editor.document_status.contains(" *"), "A real metadata edit refreshes the dirty marker")
	doc.snapshot_reads = 0
	hover(editor, water, 100)
	expect(doc.snapshot_reads == 0 and editor.ui.status.text.contains(" *"), "Unsaved-state hover uses the refreshed summary")
	editor.select_tool("Value")
	editor.ui.value_choice.set_value_no_signal(3)
	editor.stroke.begin(doc)
	doc.snapshot_reads = 0
	hover(editor, land, 8)
	expect(doc.cells[Vector2i.ZERO]["value"] == 3 and doc.snapshot_reads == 0, "Painting updates tiles without snapshotting the full map on each brush sample")
	editor.end_stroke()
	expect(doc.undo_stack.size() == 1 and editor.document_status.contains(" *"), "Finishing the stroke preserves undo and dirty-state reporting")
	editor.queue_free()
	await process_frame
	# Let the audio mixing thread release the board's stopped ambience loops.
	await create_timer(1.2).timeout
	print("Editor interaction checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
