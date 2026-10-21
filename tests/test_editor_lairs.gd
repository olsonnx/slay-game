extends SceneTree
const Document = preload("res://src/editor/level_document.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture():
	var doc = Document.new()
	doc.generate("small","modern",true)
	for coord in [Vector2i.ZERO,Vector2i(1,0),Vector2i(-1,0)]: doc.paint(coord,"Land",-1,3)
	doc.paint(Vector2i(3,0),"Land",0,2)
	doc.paint(Vector2i(0,2),"Land",-1,1)
	doc.paint(Vector2i(0,2),"Mountain",-1,1)
	doc.paint(Vector2i(0,3),"Bridge",-1,1)
	return doc
func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
func run() -> void:
	root.size = Vector2i(1200,800)
	root.get_node("Sound").set_muted(true,false)
	for tool in Document.LAIR_TOOLS:
		var doc = fixture()
		doc.cells[Vector2i.ZERO].tree = true
		doc.cells[Vector2i.ZERO].mana_source = true
		var before: Dictionary = doc.state()
		doc.checkpoint()
		expect(doc.paint(Vector2i.ZERO,tool,5,1),"Each lair can be painted on neutral land")
		var cell: Dictionary = doc.cells[Vector2i.ZERO]
		expect(cell.lair == Document.LAIR_TOOLS[tool] and cell.lair_wait == 0 and cell.value == 3 and not cell.tree and not cell.mana_source,"Lair painting keeps land value and clears incompatible objects")
		expect(not doc.paint(Vector2i.ZERO,tool,-1,1),"Repainting the same lair is a no-op")
		var after: Dictionary = doc.state()
		doc.undo()
		expect(doc.state() == before,"Undo restores replaced objects")
		doc.redo()
		expect(doc.state() == after,"Redo restores the authored lair")
		var path := "res://artifacts/editor-lair-test.json"
		expect(doc.save_file(path) == OK and not doc.dirty(),"Authored lairs save cleanly")
		var copy = Document.new()
		expect(copy.read_data(JSON.parse_string(FileAccess.get_file_as_string(path))) == "" and copy.state() == after,"Authored lairs round-trip through a level file")
		DirAccess.remove_absolute(path)
		var rules = doc.build_rules()
		var actions: Array = rules.world_turn()
		expect(actions.size() == 1 and actions[0].kind == "spawn" and actions[0].animal == Document.LAIR_TOOLS[tool] and rules.distance(actions[0].target,Vector2i.ZERO) == 1,"Playtesting an authored lair emerges beside it on the first World turn")
		expect(doc.state() == after,"Playtest spawning never changes the editor draft")
		for coord in [Vector2i(3,0),Vector2i(0,2),Vector2i(0,3),Vector2i(0,4)]:
			expect(not doc.paint(coord,tool,-1,1),"Lairs reject owned land, mountains, bridges and water")
		expect(doc.erase(Vector2i.ZERO,tool) and doc.cells[Vector2i.ZERO].value == 3 and not doc.cells[Vector2i.ZERO].has("lair"),"Right erasing removes lairs without deleting land")
		doc.rule_mode = "classic"
		expect(not doc.paint(Vector2i.ZERO,tool,-1,1),"Classic rejects lair painting")
	var editor = load("res://src/editor/level_editor.gd").new()
	root.add_child(editor)
	await process_frame
	editor.document = fixture()
	editor.refresh(true)
	for frame in range(3): await process_frame
	editor.open_tools("Build")
	expect(editor.ui.tool_buttons.size() == 5,"Build palette contains the two buildings and three lairs")
	for tool in Document.LAIR_TOOLS:
		var index: int = editor.TOOL_GROUPS.Build.find(tool)
		if not editor.ui.tool_panel.visible: editor.open_tools("Build")
		editor.ui.tool_buttons[index].pressed.emit()
		expect(editor.active_tool() == tool and editor.ui.context_description.text.contains("neutral land"),"Each lair card selects the correct brush and explains valid terrain")
		editor.stroke.begin(editor.document)
		editor.stroke.paint(editor.document,Vector2i.ZERO,tool,-1,1,false,editor.brush_rng)
		editor.end_stroke()
		editor.refresh()
		editor.select_tool("Land")
		editor.sample_at(editor.view.camera.unproject_position(editor.view.coord_position(Vector2i.ZERO)))
		expect(editor.active_tool() == tool,"Eyedropper selects the lair species")
	editor.document.rule_mode = "classic"
	editor.refresh()
	editor.ui.tool_panel.close()
	editor.open_tools("Build")
	for button in editor.ui.tool_buttons:
		expect(button.disabled == (button.get_meta("tool") in Document.LAIR_TOOLS),"Classic disables only the lair cards in Build")
	editor.document.rule_mode = "modern"
	editor.refresh()
	editor.document.mark_saved()
	var calls := {"first":0,"other":0}
	editor.request_action(func(): calls.first += 1)
	expect(calls.first == 1 and not editor.confirm.visible,"Saved drafts navigate without prompting")
	editor.document.title = "Unsaved lairs"
	var saved_draft: Dictionary = editor.document.state()
	editor.request_action(func(): calls.first += 1)
	editor.request_action(func(): calls.other += 1)
	expect(editor.confirm.visible and editor.modal_open() and not editor.view.controls_enabled and editor.confirm is ColorRect,"Unsaved changes use a blocking panel in the editor's UI")
	expect(root.gui_get_focus_owner() == editor.confirm.keep_button,"Keep editing is the safe initial keyboard choice")
	await press(KEY_TAB)
	expect(root.gui_get_focus_owner() == editor.confirm.discard_button,"Keyboard focus reaches the discard choice")
	await press(KEY_TAB)
	expect(root.gui_get_focus_owner() == editor.confirm.keep_button,"Keyboard focus stays inside the popup")
	if "--preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/editor-unsaved-after.png")
	await press(KEY_ENTER)
	expect(not editor.confirm.visible and not editor.pending_action.is_valid() and calls.first == 1 and calls.other == 0 and editor.document.state() == saved_draft,"Keep editing cancels navigation and preserves all changes")
	editor.ui.settings_shade.show()
	editor.request_action(func(): calls.first += 1)
	await press(KEY_ESCAPE)
	expect(not editor.confirm.visible and editor.ui.settings_shade.visible and calls.first == 1,"Escape cancels just the popup and preserves its underlying settings")
	editor.ui.settings_shade.hide()
	editor.request_action(func(): calls.first += 1)
	editor.request_action(func(): calls.other += 1)
	editor.confirm.discard_button.pressed.emit()
	expect(not editor.confirm.visible and calls.first == 2 and calls.other == 0 and not editor.pending_action.is_valid(),"Discard runs only the original pending action once")
	editor.discard_changes()
	expect(calls.first == 2,"A stale confirmation cannot run the action again")
	editor.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Editor lair/dialog checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
