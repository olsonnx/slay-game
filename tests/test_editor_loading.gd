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

func wait_for_load(editor) -> int:
	var frames := 0
	while editor.loading_map:
		frames += 1
		await process_frame
	return frames

func run() -> void:
	var editor = load("res://src/editor/level_editor.gd").new()
	root.add_child(editor)
	await process_frame
	var first_palette: Texture2D = editor.view.birds.textures[0]
	editor.ui.size_choice.select(editor.Document.Sizes.IDS.find("huge"))
	editor.new_island(false)
	expect(editor.loading_map and editor.view.camera.cull_mask == 0 and not editor.view.birds.visible and not editor.view.controls_enabled, "Map replacement immediately covers and locks the editor and birds")
	var frames: int = await wait_for_load(editor)
	expect(frames > 5, "Huge map generation and construction yield responsive frames")
	expect(editor.document.cells.size() >= 700 and editor.view.tile_nodes.size() == editor.document.cells.size(), "Huge generated island finishes with every authored tile")
	expect(editor.view.static_batches.instance_count > 0 and not editor.view.bulk_rebuilding and editor.view.camera.cull_mask != 0, "Completed replacement publishes terrain batches")
	expect(editor.view.birds.visible and editor.view.birds.flocks.size() == 3, "Only the finished island reveals its three birds")
	var saved: Dictionary = editor.document.state()
	var path := "user://editor-loading-fixture.json"
	expect(editor.document.save_file(path) == OK, "Generated draft saves for reload verification")
	editor.new_island(true)
	await wait_for_load(editor)
	expect(editor.document.cells.is_empty() and editor.view.cells.is_empty() and editor.view.tile_nodes.is_empty(), "Blank reset retires all old terrain")
	expect(editor.view.birds.flocks.is_empty() and editor.view.static_batches.instance_count == 0, "Blank reset leaves no old birds or render instances")
	editor.ui.file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	editor.file_selected(path)
	expect(editor.loading_map, "Loading a saved map uses the covered replacement path")
	frames = await wait_for_load(editor)
	expect(frames > 3 and editor.document.state() == saved, "Saved map loads across frames without changing its authored state")
	expect(editor.view.tile_nodes.size() == editor.document.cells.size() and editor.view.birds.textures[0] == first_palette, "Reload reuses bird textures and finishes complete geometry")
	var other = load("res://src/rendering/board_view.gd").new()
	root.add_child(other)
	expect(other.birds.textures[0] == first_palette, "Another board shares the prepared bird palette without rebuilding it")
	other.queue_free()
	editor.queue_free()
	await process_frame
	# Ogg playback is retired by the audio mixing thread after board cleanup.
	await create_timer(1.2).timeout
	DirAccess.remove_absolute(path)
	print("Editor loading checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
