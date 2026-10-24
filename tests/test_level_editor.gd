extends SceneTree
const Document = preload("res://src/editor/level_document.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if condition: passed += 1
	else:
		failed += 1
		push_error(message)

func press_key(code: int, ctrl := false, shift := false) -> void:
	var modifier := InputEventKey.new()
	if ctrl:
		modifier.keycode = KEY_CTRL
		modifier.physical_keycode = KEY_CTRL
		modifier.pressed = true
		Input.parse_input_event(modifier)
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = code if code >= KEY_A and code <= KEY_Z else 0
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	if ctrl:
		modifier.pressed = false
		Input.parse_input_event(modifier)
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func check_player_and_events() -> void:
	var doc = Document.new()
	doc.generate("small", "modern", true)
	for coord in [Vector2i.ZERO, Vector2i(1, 0)]: doc.paint(coord, "Land", 4, 2)
	for coord in [Vector2i(4, 0), Vector2i(5, 0)]: doc.paint(coord, "Land", 2, 2)
	doc.player_faction = 4
	expect(doc.playable_error() == "", "Selected non-Fern player works with sparse owners")
	var old := doc.state()
	old.erase("player_start")
	old["player_faction"] = 4
	var copy = Document.new()
	expect(copy.read_data(old) == "" and copy.player_faction == 4 and copy.player_start == doc.player_start, "Old faction picker maps migrate to a marker")
	for id in Document.Events.EVENTS:
		doc.paint(Vector2i(2, 0), "Land", -1, 1)
		doc.checkpoint()
		expect(doc.paint(Vector2i(2, 0), "Event", -1, 1, id), "Catalog event can be painted: " + id)
		expect(copy.read_data(JSON.parse_string(JSON.stringify(doc.state()))) == "" and copy.player_faction == 4 and copy.cells[Vector2i(2, 0)]["event"] == id, "Event and player survive save/load")
		doc.undo()
		expect(doc.cells[Vector2i(2, 0)]["event"] == "", "Undo removes event")
		doc.redo()
		expect(doc.build_rules().cells[Vector2i(2, 0)]["event"] == id, "Redo and playtest retain event")
		var rules = doc.build_rules()
		rules.human_factions = [4]
		rules.cells[Vector2i(1, 0)]["unit"] = 1
		var action: Dictionary = rules.perform_move(Vector2i(1, 0), Vector2i(2, 0))
		expect(not action.is_empty() and rules.pending_events.size() == 1 and rules.cells[Vector2i(2, 0)]["event"] == "", "Every authored encounter fires on the first visit: " + id)
		expect(rules.resolve_event(rules.pending_events[0], 0) != "", "Authored encounter or alternate resolves: " + id)
		doc.erase(Vector2i(2, 0), "Event")
	var legacy_forest := doc.state()
	for row in legacy_forest["cells"]:
		if row["q"] == 2 and row["r"] == 0: row["event"] = "lumberjack_overgrown"
	expect(copy.read_data(legacy_forest) == "" and copy.cells[Vector2i(2, 0)]["event"] == "lumberjack", "Older forest-event markers migrate to the one lumberjack event")
	expect(Document.Events.EVENTS.keys().filter(func(id): return String(id).begins_with("lumberjack")).size() == 1, "Editor catalog offers one lumberjack event")
	var marker_state := doc.state()
	doc.paint(Vector2i.ZERO, "Owner", 11, 2)
	expect(doc.player_faction == 11 and doc.player_start == Vector2i.ZERO, "Start marker follows changed ownership across all twelve kingdoms")
	expect(copy.read_data(doc.state()) == "" and copy.player_faction == 11, "Twelfth kingdom roundtrips")
	doc.paint(Vector2i(1, 0), "Owner", 11, 2)
	expect(doc.playable_error() == "", "Twelfth kingdom can be the player")
	doc.factions[11]["name"] = "Retired kingdom"
	doc.factions[11]["terrain"] = "123456ff"
	expect(copy.read_data(doc.state()) == "" and copy.factions[11]["name"] == "Retired kingdom" and copy.faction_colors("terrain")[11] == Color("123456"), "Removed or renamed catalog entries retain saved identity and colors")
	doc.factions.append({"name": "Future kingdom", "color": "abcdef", "terrain": "fedcba"})
	doc.paint(Vector2i.ZERO, "Owner", 12, 2)
	doc.paint(Vector2i(1, 0), "Owner", 12, 2)
	expect(copy.read_data(doc.state()) == "" and copy.player_faction == 12 and copy.playable_error() == "", "Map-local kingdoms survive catalog size changes")
	doc.restore(marker_state)
	var snapshot := doc.state()
	expect(not doc.paint(Vector2i(2, 0), "Player start", 0, 1), "Neutral land cannot hold a player start")
	expect(not doc.erase(Vector2i(1, 0), "Player start") and doc.state() == snapshot, "Right-click away from marker leaves map intact")
	doc.checkpoint()
	expect(doc.erase(Vector2i.ZERO, "Player start") and doc.player_start == Document.Rules.NONE and doc.state()["cells"] == snapshot["cells"], "Marker can be removed independently")
	expect(doc.playable_error() != "", "Missing marker prevents playtesting")
	doc.undo()
	expect(doc.player_start == Vector2i.ZERO, "Undo restores removed marker")
	doc.checkpoint()
	doc.erase(Vector2i.ZERO, "Land")
	expect(doc.player_start == Document.Rules.NONE, "Deleting marked terrain clears start")
	doc.undo()
	doc.paint(Vector2i.ZERO, "Owner", -1, 1)
	expect(doc.playable_error() != "", "Neutralizing marked land requires fixing the start")
	doc.restore(marker_state)
	var invalid := doc.state()
	invalid["player_start"] = [999, 0]
	expect(copy.read_data(invalid) != "", "Invalid start marker rejected")
	invalid = doc.state()
	invalid["cells"][0]["event"] = "unknown_event"
	expect(copy.read_data(invalid) != "", "Unknown event rejected")
	doc.paint(Vector2i(2, 0), "Mountain", -1, 1)
	expect(not doc.paint(Vector2i(2, 0), "Event", -1, 1, "gold"), "Events cannot be painted on mountains")

func check_tool_context(editor) -> void:
	var saved: Dictionary = editor.document.state()
	for tool in Document.TOOLS:
		editor.select_tool(tool)
		await process_frame
		await process_frame
		expect(editor.ui.context_panel.visible and editor.ui.context_tool == tool and editor.ui.brush_label.text == tool, "Every tool opens its own context: " + tool)
		expect(editor.ui.owner_row.visible == (tool in ["Land", "Owner"]), "Owner field is contextual: " + tool)
		expect(editor.ui.value_row.visible == (tool in ["Land", "Value"]), "Value field is contextual: " + tool)
		expect(editor.ui.random_toggle.visible == (tool in ["Land", "Value"]), "Random values are contextual: " + tool)
		expect(editor.ui.event_browser.visible == (tool == "Event"), "Event browser is contextual: " + tool)
		if tool != "Event":
			var content_bottom: float = editor.ui.context_form.position.y + editor.ui.context_form.get_combined_minimum_size().y
			expect(content_bottom <= editor.ui.context_panel.panel_height - 10, "Tool content fits its panel: " + tool)
		expect(editor.pointer_over_ui(editor.ui.context_panel.get_global_rect().get_center()), "Context panel blocks painting beneath itself")
	var blocked_press := InputEventMouseButton.new()
	blocked_press.button_index = MOUSE_BUTTON_LEFT
	blocked_press.pressed = true
	blocked_press.position = editor.ui.context_panel.get_global_rect().get_center()
	editor._unhandled_input(blocked_press)
	expect(editor.document.state() == saved and not editor.painting, "Clicks inside the context cannot paint the map beneath it")
	expect(editor.document.state() == saved, "Switching tools never edits the map")
	editor.select_tool("Land")
	editor.ui.owner_choice.item_selected.emit(editor.ui.owner_choice.selected)
	expect(editor.active_tool() == "Land", "Editing brush settings keeps the selected tool")
	editor.open_tools("Units")
	expect(editor.ui.tool_panel.visible and not editor.ui.context_panel.visible, "Category cards replace the context panel")
	editor.ui.tool_buttons[2].pressed.emit()
	expect(editor.active_tool() == "Soldier" and editor.ui.context_panel.visible and not editor.ui.tool_panel.visible, "Tool cards open their context immediately")
	editor.close_context()
	expect(not editor.ui.context_panel.visible and editor.active_tool() == "Soldier", "Closing the context preserves the active brush")
	editor.select_tool("Event")
	editor.ui.event_search.grab_focus()
	editor.ui.event_search.text = "wizard"
	editor.ui.filter_events()
	expect(root.gui_get_focus_owner() == editor.ui.event_search and editor.event_id == "wizard", "Searching immediately selects a matching event without losing text focus")
	expect(editor.ui.event_details.bbcode_enabled and not editor.ui.event_details.text.contains("[b]") and editor.ui.event_details.text.contains("0 mana[/color]"), "Editor previews use regular unit text and retain mana colours")
	editor.release_text_focus()
	editor.ui.event_search.text = ""
	editor.ui.filter_events()
	editor.select_event("gold")
	for coord in editor.document.cells:
		var cell: Dictionary = editor.document.cells[coord]
		if cell["mountain"] or cell["capital"] >= 0 or cell["unit"] > 0: continue
		var position: Vector2 = editor.view.camera.unproject_position(Document.Rules.Grid.to_world(coord))
		if editor.pointer_over_ui(position) or editor.view.hex_at_screen(position) != coord: continue
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = position
		editor._unhandled_input(press)
		press.pressed = false
		editor._input(press)
		expect(editor.document.cells[coord]["event"] == "gold" and editor.ui.context_panel.visible, "Events paint directly while the context stays open")
		editor.undo()
		break
	expect(editor.document.state() == saved, "Context event painting is undoable")
	editor.select_tool("Land")

func check_treasure() -> void:
	var doc := Document.new()
	doc.generate("small","modern",true)
	doc.paint(Vector2i.ZERO,"Land",-1,1)
	doc.cells[Vector2i.ZERO]["treasure"] = 15
	var saved := doc.state()
	var copy := Document.new()
	expect(copy.read_data(JSON.parse_string(JSON.stringify(saved))) == "" and copy.build_rules().cells[Vector2i.ZERO].treasure == 15,"Authored tutorial treasure survives JSON and playtest construction")
	for reward in [-1,0,10001,"15"]:
		var invalid: Dictionary = saved.duplicate(true)
		invalid.cells[0].treasure = reward
		expect(copy.read_data(invalid) != "" and copy.state() == saved,"Invalid treasure cannot corrupt the current draft")
	doc.checkpoint()
	doc.paint(Vector2i.ZERO,"Tree",-1,1)
	expect(not doc.cells[Vector2i.ZERO].has("treasure") and doc.cells[Vector2i.ZERO].tree,"Painting another object replaces an imported chest")
	doc.undo()
	expect(doc.cells[Vector2i.ZERO].treasure == 15,"Undo restores the original chest reward")
	doc.paint(Vector2i.ZERO,"Owner",0,1)
	expect(not doc.cells[Vector2i.ZERO].has("treasure") and copy.read_data(doc.state()) == "","Assigning an imported chest to an owner removes the neutral reward")

func run() -> void:
	check_treasure()
	check_player_and_events()
	var doc = Document.new()
	for mode in ["modern"]:
		for size_id in Document.Sizes.SPECS:
			doc.generate(size_id, mode)
			var copy = Document.new()
			expect(copy.read_data(JSON.parse_string(JSON.stringify(doc.state()))) == "", "Generated level roundtrips: " + mode + size_id)
			expect(copy.state() == doc.state(), "Roundtrip preserves every authored field")
			expect(copy.playable_error() == "", "Generated level is playable")
			expect(not copy.dirty(), "Loaded level starts clean")
	var huge = Document.new()
	huge.generate("huge", "modern", true)
	for q in range(-55, 56):
		for r in range(-23, 24):
			if huge.cells.size() < 1001:
				huge.paint(Vector2i(q, r), "Land", -1, 1)
	var huge_copy = Document.new()
	expect(huge.cells.size() == 1001 and huge_copy.read_data(JSON.parse_string(JSON.stringify(huge.state()))) == "" and huge_copy.cells.size() == 1001, "Huge authored islands roundtrip beyond the old 1,000-tile limit")
	doc.generate("small", "modern", true)
	expect(doc.playable_error() != "", "Blank level cannot play")
	doc.checkpoint()
	for coord in [Vector2i(0, 0), Vector2i(1, 0)]: doc.paint(coord, "Land", 0, 3)
	for coord in [Vector2i(4, 0), Vector2i(5, 0)]: doc.paint(coord, "Land", 1, 2)
	doc.paint(Vector2i.ZERO, "Player start", 0, 1)
	expect(doc.playable_error() == "", "Two connected kingdoms can play")
	var rules = doc.build_rules()
	expect(rules.kingdoms.size() == 2 and rules.cells.size() == 4, "Play builds capitals without adding terrain")
	expect(doc.cells[Vector2i.ZERO]["capital"] == -1, "Play normalization never mutates draft")
	for kingdom in rules.kingdoms.values(): expect(kingdom["gold"] == 10, "Starting gold applied")
	doc.undo()
	expect(doc.cells.is_empty(), "Undo restores full stroke")
	doc.redo()
	expect(doc.cells.size() == 4, "Redo restores full stroke")
	doc.mark_saved()
	var atomic_path := "res://artifacts/editor_atomic_save.json"
	expect(doc.save_file(atomic_path) == OK, "A draft saves through a temporary replacement file")
	var saved_contents := FileAccess.get_file_as_string(atomic_path)
	doc.title = "Replacement draft"
	# An open handle without delete sharing prevents Windows replacing this file.
	var locked_file := FileAccess.open(atomic_path, FileAccess.READ)
	var failed_save: Error = doc.save_file(atomic_path)
	if OS.get_name() == "Windows":
		expect(failed_save != OK and doc.dirty(), "A failed replacement keeps the draft unsaved")
		expect(FileAccess.get_file_as_string(atomic_path) == saved_contents, "A failed replacement preserves the previous saved draft")
	locked_file.close()
	expect(doc.save_file(atomic_path) == OK and not doc.dirty(), "Saving can retry after a replacement failure")
	expect(JSON.parse_string(FileAccess.get_file_as_string(atomic_path))["title"] == doc.title, "Successful replacement contains the entire new draft")
	DirAccess.remove_absolute(atomic_path)
	var before := doc.state()
	var invalid := before.duplicate(true)
	invalid["cells"][0]["owner"] = 20
	expect(doc.read_data(invalid) != "" and doc.state() == before, "Invalid load preserves existing draft")
	invalid = before.duplicate(true)
	invalid["cells"].append(invalid["cells"][0].duplicate())
	expect(doc.read_data(invalid) != "", "Duplicate province rejected")
	expect(not doc.paint(Vector2i(90, 90), "Land", 0, 1), "Brush respects bounds")
	doc.checkpoint()
	doc.paint(Vector2i.ZERO, "Mountain", -1, 1)
	expect(doc.cells[Vector2i.ZERO]["mountain"] and doc.cells[Vector2i.ZERO]["value"] == 0, "Mountain is neutral zero-value terrain")
	doc.paint(Vector2i.ZERO, "Land", 0, 4)
	doc.paint(Vector2i.ZERO, "Owner", 0, 4)
	doc.paint(Vector2i.ZERO, "Tree", 0, 4)
	doc.paint(Vector2i.ZERO, "Knight", 0, 4)
	expect(doc.cells[Vector2i.ZERO]["unit"] == 3 and not doc.cells[Vector2i.ZERO]["tree"], "Object brushes clear incompatible props")
	doc.paint(Vector2i.ZERO, "Water", -1, 1)
	expect(not doc.cells.has(Vector2i.ZERO), "Water removes province")
	doc.paint(Vector2i.ZERO, "Bridge", -1, 1)
	expect(doc.cells[Vector2i.ZERO]["building"] == "bridge" and doc.cells[Vector2i.ZERO]["value"] == 0, "Bridge spans water as neutral zero-value terrain")
	var bridge_copy = Document.new()
	expect(bridge_copy.read_data(JSON.parse_string(JSON.stringify(doc.state()))) == "", "Bridge level roundtrips")
	doc.paint(Vector2i.ZERO, "Land", 0, 3)
	doc.paint(Vector2i.ZERO, "Owner", 0, 3)
	doc.paint(Vector2i.ZERO, "Capital", 0, 3)
	doc.paint(Vector2i.ZERO, "Scout", 0, 3)
	expect(doc.cells[Vector2i.ZERO]["capital"] == 0 and doc.cells[Vector2i.ZERO]["unit"] == 1, "Soldier can share a capital")
	doc.erase(Vector2i.ZERO, "Land", "unit")
	expect(not doc.cells.has(Vector2i.ZERO), "Tile editing removes entire decorated tile even when clicking a soldier")
	doc.paint(Vector2i.ZERO, "Land", 0, 3)
	doc.paint(Vector2i.ZERO, "Capital", 0, 3)
	doc.paint(Vector2i.ZERO, "Scout", 0, 3)
	doc.paint(Vector2i.ZERO, "Mana source", 0, 3)
	doc.erase(Vector2i.ZERO, "Value", "terrain")
	expect(doc.cells[Vector2i.ZERO]["unit"] == 0 and doc.cells[Vector2i.ZERO]["capital"] == -1 and not doc.cells[Vector2i.ZERO]["mana_source"] and doc.cells[Vector2i.ZERO]["owner"] == 0 and doc.cells[Vector2i.ZERO]["value"] == 3, "Painting removes all decorations while preserving owner and value")
	doc.paint(Vector2i.ZERO, "Tree", 0, 3)
	doc.erase(Vector2i.ZERO, "Knight", "structure")
	expect(not doc.cells[Vector2i.ZERO]["tree"] and doc.cells.has(Vector2i.ZERO), "Right-click a tree removes the tree, retaining land")
	doc.paint(Vector2i.ZERO, "Mountain", -1, 1)
	doc.erase(Vector2i.ZERO, "Mountain", "structure")
	expect(not doc.cells.has(Vector2i.ZERO), "Tile editing removes mountains to water")
	doc.paint(Vector2i(2, 0), "Bridge", -1, 1)
	doc.erase(Vector2i(2, 0), "Bridge")
	expect(not doc.cells.has(Vector2i(2, 0)), "Remove bridge restores water")
	var video = root.get_node("Video")
	var background: String = video.background
	var borders: float = video.internal_borders
	if "--sky" in OS.get_cmdline_user_args(): video.set_preference(&"background", "sky", false)
	var animate: bool = video.level_transitions
	video.set_preference(&"level_transitions", false, false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	app.menus.editor_requested.emit()
	await process_frame
	expect(is_instance_valid(app.editor) and app.menus.screen == app.menus.Screen.HIDDEN, "Main menu opens editor")
	var editor = app.editor
	editor.document.generate("very_small", "modern")
	for cell in editor.document.cells.values():
		if cell["owner"] == 1: cell["owner"] = 11
		if cell["capital"] == 1: cell["capital"] = 11
	editor.document.factions[11]["name"] = "Saved Iris"
	editor.refresh(true)
	await check_tool_context(editor)
	expect(editor.ui.context_panel.visible and not editor.modal_open(), "Tool context leaves the map interactive")
	expect(editor.ui.owner_choice.item_count == Document.Catalog.FACTIONS.size() + 1, "Ownership offers every kingdom")
	editor.ui.category_buttons["Start"].pressed.emit()
	expect(editor.active_tool() == "Player start" and not editor.modal_open(), "Start button activates map marker placement")
	var start_coord: Vector2i = editor.document.start_for_faction(11)
	var old_start: Vector2i = editor.document.player_start
	var marker_cells: Dictionary = editor.document.cells.duplicate(true)
	editor.stroke.begin(editor.document)
	editor.stroke.paint(editor.document, start_coord, "Player start", -1, 1, false, editor.brush_rng)
	editor.end_stroke()
	editor.refresh()
	expect(editor.document.player_faction == 11 and editor.player_marker.visible, "Map marker selects the owned starting kingdom")
	expect(editor.document.cells == marker_cells, "Start marker coexists with all tile contents")
	editor.undo()
	expect(editor.document.player_start == old_start, "Undo restores start marker")
	editor.redo()
	expect(editor.document.player_start == start_coord, "Redo restores moved marker")
	editor.ui.category_buttons["Events"].pressed.emit()
	for query in ["goose", "rightful ruler", "honk", "nothing happens"]:
		editor.ui.event_search.text = query
		editor.ui.filter_events()
		expect(editor.ui.event_list.item_count > 0, "Search matches ID, title, description or outcome: " + query)
	editor.ui.event_search.text = "no-such-event"
	editor.ui.filter_events()
	expect(editor.ui.event_list.item_count == 0 and editor.event_id == "", "No results disables painting")
	editor.ui.event_search.text = "gold"
	editor.ui.filter_events()
	editor.select_event("gold")
	expect(editor.active_tool() == "Event" and not editor.modal_open(), "Selecting an event keeps its context open and activates brush")
	editor.select_tool("Land")
	var draft: Dictionary = editor.document.state()
	if "--preview" in OS.get_cmdline_user_args():
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/level_editor_initial.png")
	# Real save/load path, including malformed-file isolation.
	var path := OS.get_user_data_dir().path_join("levels/editor_test_fixture.json")
	DirAccess.make_dir_recursive_absolute("user://levels")
	# Drive the real FileDialog's Save/Open actions, rather than its signal handler.
	DirAccess.remove_absolute(path)
	editor.open_save()
	await process_frame
	expect(editor.file_dialog.visible and editor.file_dialog.access == FileDialog.ACCESS_FILESYSTEM, "Save opens a real filesystem explorer")
	if "--preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		editor.file_dialog.get_texture().get_image().save_png("res://artifacts/level_editor_save_dialog.png")
	editor.file_dialog.get_line_edit().text = path.get_file()
	editor.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	while editor.loading_map: await process_frame
	expect(FileAccess.file_exists(path) and not editor.document.dirty(), "Editor saves persistent file")
	editor.document.paint(Vector2i.ZERO, "Water", -1, 1)
	editor.open_load()
	await process_frame
	expect(editor.file_dialog.visible, "Load opens the file explorer")
	editor.file_dialog.get_line_edit().text = path.get_file()
	editor.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	while editor.loading_map: await process_frame
	expect(editor.document.state() == draft, "Editor loads saved file")
	# The same dialog can save/load an ordinary folder outside app data.
	var external_path := ProjectSettings.globalize_path("res://artifacts/editor_dialog_fixture.json")
	DirAccess.remove_absolute(external_path)
	editor.open_save()
	editor.file_dialog.current_dir = external_path.get_base_dir()
	editor.file_dialog.get_line_edit().text = external_path.get_file()
	editor.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	while editor.loading_map: await process_frame
	expect(FileAccess.file_exists(external_path) and editor.file_path == external_path, "Explorer saves to ordinary filesystem folders")
	editor.document.title = "Changed after saving"
	editor.open_load()
	editor.file_dialog.get_line_edit().text = external_path.get_file()
	editor.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	while editor.loading_map: await process_frame
	expect(editor.document.state() == draft, "Explorer reloads from ordinary filesystem folder")
	var corrupt_path := external_path.get_base_dir().path_join("editor_dialog_corrupt.json")
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt_file.store_string("not a level")
	corrupt_file.close()
	editor.open_load()
	editor.file_dialog.get_line_edit().text = corrupt_path.get_file()
	editor.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	while editor.loading_map: await process_frame
	expect(editor.document.state() == draft and editor.status.text == "This is not a supported Slay level.", "Malformed file selected through explorer preserves draft and reports an error")
	DirAccess.remove_absolute(corrupt_path)
	editor.request_action(func(): editor.status.text = "clean action")
	expect(not editor.confirm.visible and editor.status.text == "clean action", "Clean drafts navigate without confirmation")
	editor.document.title = "Unsaved name"
	editor.request_action(func(): editor.status.text = "discard action")
	expect(editor.confirm.visible, "Dirty drafts require discard choice")
	editor.confirm.hide()
	editor.document.title = draft["title"]
	# Exercise actual editor input and a stroke as one undo step.
	var painted_coord := Document.Rules.NONE
	for coord in editor.document.cells:
		var cell: Dictionary = editor.document.cells[coord]
		var candidate: Vector2 = editor.view.camera.unproject_position(Document.Rules.Grid.to_world(coord))
		if not cell["mountain"] and cell["unit"] == 0 and cell["capital"] < 0 and not cell["tree"] and not cell["grave"] and not editor.pointer_over_ui(candidate) and editor.view.hex_at_screen(candidate) == coord:
			painted_coord = coord
			break
	var position: Vector2 = editor.view.camera.unproject_position(Document.Rules.Grid.to_world(painted_coord))
	editor.tool_choice.select(Document.TOOLS.find("Value"))
	editor.value_choice.value = 6
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	editor._unhandled_input(press)
	press.pressed = false
	editor._input(press)
	expect(editor.document.cells[painted_coord]["value"] == 6 and editor.document.undo_stack.size() == 1, "Screen painting records one undoable stroke")
	editor.document.undo()
	editor.refresh()
	expect(editor.document.state() == draft, "Stroke undo restores saved draft")
	# Right-click removes; it never starts a camera orbit without Alt.
	editor.tool_choice.select(Document.TOOLS.find("Land"))
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	editor._unhandled_input(press)
	press.pressed = false
	editor._input(press)
	expect(not editor.document.cells.has(painted_coord) and not editor.rotating, "Right-click removes terrain instead of rotating")
	editor.document.undo()
	editor.refresh()
	expect(editor.document.state() == draft, "Right-click removal can be undone")
	press.alt_pressed = true
	press.pressed = true
	editor._unhandled_input(press)
	expect(editor.rotating and not editor.painting, "Alt + right-click reserves orbit without painting")
	press.pressed = false
	editor._input(press)
	press.alt_pressed = false
	editor.select_tool("Land")
	await process_frame
	# Regression: text controls must not trap Tab, wheel, middle-drag or WASD.
	var map_position := Vector2(650, 260)
	editor.name_edit.grab_focus()
	editor.pointer_position = editor.name_edit.get_global_rect().get_center()
	var overhead: bool = editor.view.top_down
	await press_key(KEY_TAB)
	expect(editor.view.top_down != overhead and root.gui_get_focus_owner() == null, "Tab switches views after title editing instead of cycling UI focus")
	editor.value_choice.get_line_edit().grab_focus()
	await press_key(KEY_TAB)
	expect(editor.view.top_down == overhead and root.gui_get_focus_owner() == null, "Tab also escapes the numeric field")
	editor.value_choice.get_line_edit().grab_focus()
	await process_frame
	editor.value_choice.get_line_edit().text = "4"
	editor.pointer_position = editor.value_choice.get_global_rect().get_center()
	await press_key(KEY_ENTER)
	expect(int(editor.value_choice.value) == 4 and root.gui_get_focus_owner() == null, "Enter commits a typed numeric value and returns control to the map")
	editor.name_edit.grab_focus()
	editor.pointer_position = editor.name_edit.get_global_rect().get_center()
	var title_before: String = editor.name_edit.text
	await press_key(KEY_W)
	expect(root.gui_get_focus_owner() == editor.name_edit and editor.name_edit.text != title_before, "W remains normal text input while actively editing the title")
	editor.name_edit.text = title_before
	var motion := InputEventMouseMotion.new()
	motion.position = map_position
	motion.relative = Vector2(1, 0)
	editor._input(motion)
	expect(root.gui_get_focus_owner() == null and editor.view.controls_enabled, "Returning the pointer to the map releases stale textbox focus")
	var focus_before: Vector3 = editor.view.focus
	await press_key(root.get_node("Keys").bindings["pan_up"])
	expect(editor.view.focus.distance_to(focus_before) > 0.0001, "WASD pans after leaving a textbox")
	editor.name_edit.grab_focus()
	press.position = map_position
	press.button_index = MOUSE_BUTTON_WHEEL_UP
	press.pressed = true
	var zoom_before: float = editor.view.zoom
	editor._input(press)
	editor._unhandled_input(press)
	editor.view.navigation._process(0.1)
	expect(editor.view.zoom < zoom_before and root.gui_get_focus_owner() == null, "Wheel zoom works after text editing")
	editor.value_choice.get_line_edit().grab_focus()
	press.button_index = MOUSE_BUTTON_MIDDLE
	editor._input(press)
	editor._unhandled_input(press)
	focus_before = editor.view.focus
	motion.relative = Vector2(15, 0)
	editor._input(motion)
	press.pressed = false
	editor._input(press)
	expect(editor.view.focus != focus_before and root.gui_get_focus_owner() == null, "Middle dragging pans after numeric-field editing")
	# Fast strokes interpolate all crossed hexes; random values roundtrip through history.
	editor.document.generate("small", "modern", true)
	editor.refresh(true)
	editor.select_tool("Land")
	editor.set_random_values(true)
	editor.brush_rng.seed = 12345
	var first := Vector2i(-4, -2)
	var last := Vector2i(4, -2)
	var first_screen: Vector2 = editor.view.camera.unproject_position(Document.Rules.Grid.to_world(first))
	var last_screen: Vector2 = editor.view.camera.unproject_position(Document.Rules.Grid.to_world(last))
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = first_screen
	press.pressed = true
	editor._input(press)
	editor._unhandled_input(press)
	motion.position = last_screen
	motion.relative = last_screen - first_screen
	editor._input(motion)
	editor._unhandled_input(motion)
	press.pressed = false
	press.position = last_screen
	editor._input(press)
	expect(editor.document.cells.size() == 9, "Fast left drag fills every intervening tile")
	var distinct := {}
	for cell in editor.document.cells.values():
		expect(cell["value"] >= 1 and cell["value"] <= 3, "Random tile values stay within 1–3")
		distinct[cell["value"]] = true
	expect(distinct.size() > 1 and not editor.value_choice.editable, "Random toggle produces varied values and disables the fixed input")
	var random_state: Dictionary = editor.document.state()
	editor.undo()
	expect(editor.document.cells.is_empty(), "Whole interpolated stroke undoes in one step")
	editor.redo()
	expect(editor.document.state() == random_state, "Redo restores the exact random values without rerolling")
	editor.document.paint(first, "Land", -1, 6)
	expect(editor.document.state() == random_state, "Drawing existing land does not overwrite its values")
	# Holding right while dragging removes decorated tiles as one stroke.
	editor.document.paint(first, "Tree", -1, 1)
	editor.refresh()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = first_screen
	editor._input(press)
	editor._unhandled_input(press)
	motion.position = last_screen
	motion.relative = last_screen - first_screen
	editor._input(motion)
	editor._unhandled_input(motion)
	press.position = last_screen
	press.pressed = false
	editor._input(press)
	expect(editor.document.cells.is_empty(), "Held right drag in Tiles removes every crossed tile, including decorations")
	editor.undo()
	expect(editor.document.cells.size() == 9 and editor.document.cells[first]["tree"], "Undo restores whole tiles and their decorations")
	editor.document.erase(first, "Owner")
	editor.refresh()
	press.button_index = MOUSE_BUTTON_LEFT
	editor.release_text_focus()
	await press_key(root.get_node("Keys").bindings["heatmap"])
	expect(editor.view.value_heatmap.active and editor.heatmap_legend.visible, "Heatmap shortcut enables the shared 3D filter and legend")
	editor.set_random_values(false)
	editor.select_tool("Value")
	editor.value_choice.value = 6
	press.pressed = true
	press.position = first_screen
	editor._input(press)
	editor._unhandled_input(press)
	press.pressed = false
	editor._input(press)
	expect(editor.view.value_heatmap.active and editor.view.value_heatmap.maximum == 6, "Value painting updates the active heatmap immediately")
	editor.undo()
	expect(editor.view.value_heatmap.active and editor.view.value_heatmap.maximum <= 3, "Undo updates the active heatmap without turning it off")
	editor.document.paint(first, "Tree", -1, 1)
	editor.refresh()
	var value_before: int = editor.document.cells[first]["value"]
	editor.sample_at(first_screen)
	expect(editor.active_tool() == "Tree" and int(editor.value_choice.value) == value_before and not editor.random_values, "Eyedropper copies decoration, owner and exact value")
	editor.select_tool("Owner")
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	editor._input(press)
	editor._unhandled_input(press)
	press.pressed = false
	editor._input(press)
	expect(editor.document.cells.has(first) and not editor.document.cells[first]["tree"] and editor.document.cells[first]["value"] == value_before, "Paint-mode right-click clears decorations while retaining tile value")
	for coord in editor.document.cells:
		editor.document.paint(coord, "Tree", -1, 1)
	editor.refresh()
	var values_before := {}
	for coord in editor.document.cells: values_before[coord] = editor.document.cells[coord]["value"]
	press.pressed = true
	press.position = first_screen
	editor._input(press)
	editor._unhandled_input(press)
	motion.position = last_screen
	motion.relative = last_screen - first_screen
	editor._input(motion)
	editor._unhandled_input(motion)
	press.position = last_screen
	press.pressed = false
	editor._input(press)
	expect(editor.document.cells.size() == 9, "Held right drag in Paint preserves every tile")
	for coord in editor.document.cells:
		expect(not editor.document.cells[coord]["tree"] and editor.document.cells[coord]["value"] == values_before[coord], "Decoration-clearing drag preserves each province value")
	editor.toggle_heatmap()
	editor.release_text_focus()
	await press_key(root.get_node("Keys").bindings["recruit"])
	await press_key(KEY_3)
	expect(editor.active_tool() == "Soldier", "Category and number shortcuts choose a tool card")
	await press_key(KEY_V)
	expect(editor.random_values, "V toggles random values")
	editor.view.focus += Vector3(2, 0, 1)
	await press_key(KEY_HOME)
	expect(editor.view.focus == editor.view.map_center, "Home centers the editor camera on the authored land")
	editor.select_tool("Land")
	editor.open_tools("Paint")
	expect(editor.active_tool() == "Owner", "Opening Paint immediately switches to decoration-safe painting mode")
	editor.open_tools("Tiles")
	expect(editor.active_tool() == "Land", "Opening Tiles immediately switches to whole-tile editing mode")
	editor.tool_panel.close()
	editor.document.read_data(draft)
	editor.set_random_values(false)
	editor.refresh(true)
	editor.document.title = "Quick save fixture"
	await press_key(KEY_S, true)
	expect(not editor.file_dialog.visible and not editor.document.dirty(), "Ctrl+S saves to the chosen path without reopening the explorer")
	var quick_saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(editor.file_path))
	expect(quick_saved["title"] == "Quick save fixture", "Quick save writes the updated level to disk")
	editor.document.title = draft["title"]
	editor.save_level()
	editor.refresh()
	editor.toggle_heatmap()
	await app.play_editor_level(draft)
	expect(editor.suspended and is_instance_valid(app.game), "Playtest isolates editor")
	expect(app.game.player_faction == 11 and app.game.rules.human_factions == [11], "Playtest gives selected faction human control")
	expect(not app.game.view.value_heatmap.active, "Editor heatmap does not leak into the playtest view")
	expect(app.game.rules.rule_mode == "modern" and app.game.rules.level_seed == int(draft["seed"]), "Playtest uses authored rules and seed")
	expect(app.game.NAMES[11] == "Saved Iris" and app.game.view.COLORS[11] == Document.Catalog.TERRAIN_COLORS[11], "Playtest uses map-local kingdom identity")
	var starting_cells: Dictionary = app.game.cells.duplicate(true)
	app.game.cells.values()[0]["value"] = 6
	app.pause_game()
	video.set_preference(&"internal_borders", 0.25, false)
	video.set_preference(&"background", "sky" if video.background == "water" else "water", false)
	await app.restart_current_level()
	expect(app.game.cells == starting_cells, "Restart restores authored starting position")
	expect(app.game.player_faction == 11, "Restart preserves selected player")
	app.pause_game()
	await app.return_to_main_menu()
	await process_frame
	expect(app.editor == editor and not editor.suspended and editor.document.state() == draft, "Returning from playtest preserves draft")
	expect(editor.view.sky_backdrop.visible == (video.background == "sky"), "Restored backdrop respects Water/Sky preference")
	expect(editor.view.camera.current and editor.view.board_root.is_visible_in_tree(), "Restored board and camera remain visible")
	expect(editor.view.water.visible == (video.background == "water"), "Editor catches up to appearance changes made during playtest")
	expect(editor.view.value_heatmap.active and editor.heatmap_legend.visible, "Returning from playtest restores the editor's heatmap")
	editor.toggle_heatmap()
	var visible_unit := false
	for unit in editor.view.units: visible_unit = visible_unit or unit.is_visible_in_tree()
	expect(visible_unit, "Turning off the restored heatmap reveals original soldiers")
	video.set_preference(&"internal_borders", borders, false)
	video.set_preference(&"background", "sky" if "--sky" in OS.get_cmdline_user_args() else background, false)
	video.set_preference(&"level_transitions", true, false)
	await app.play_editor_level(draft)
	while app.game.view.level_transitioning: await process_frame
	app.pause_game()
	await app.return_to_main_menu()
	expect(not editor.suspended and editor.document.state() == draft, "Animated playtest entry/departure preserves draft")
	if "--preview" in OS.get_cmdline_user_args():
		editor.owner_choice.select(1)
		editor.open_tools("Units")
		editor.select_tool("Knight")
		for small in [false, true]:
			root.size = Vector2i(960, 620) if small else Vector2i(1280, 820)
			for frame in range(8): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/level_editor%s.png" % ("_small" if small else ""))
			editor.toggle_heatmap()
			editor.open_tools("Paint")
			editor.select_tool("Value")
			editor.set_random_values(true)
			await create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/level_editor_heatmap%s.png" % ("_small" if small else ""))
			editor.toggle_heatmap()
			editor.open_tools("Units")
			editor.select_tool("Knight")
			editor.set_random_values(false)
		editor.tool_panel.close()
		editor.help_panel.show()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/level_editor_help_small.png")
		editor.help_panel.hide()
		editor.toggle_settings()
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/level_editor_settings_small.png")
		editor.toggle_settings()
		for tool in ["Land", "Owner", "Value", "Player start", "Event"]:
			editor.select_tool(tool)
			if tool == "Event":
				editor.ui.event_search.text = ""
				editor.ui.filter_events()
			await create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/level_editor_%s_context_small.png" % tool.to_lower().replace(" ", "_"))
		editor.close_context()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/level_editor_player_start_small.png")
	var preference: String = root.get_node("Gameplay").rule_mode
	editor.document.generate("very_small", "modern")
	editor.refresh(true)
	editor.name_edit.grab_focus()
	editor.pointer_position = editor.name_edit.get_global_rect().get_center()
	await press_key(KEY_F5)
	while app.transitioning: await process_frame
	expect(is_instance_valid(app.game) and editor.suspended, "F5 starts playtesting even from a focused text field")
	expect(app.game.rules.rule_mode == "modern", "Authored level uses the current mechanics")
	expect(root.get_node("Gameplay").rule_mode == preference, "Playtest does not rewrite the global rules preference")
	app.pause_game()
	await app.return_to_main_menu()
	app.close_editor()
	await process_frame
	expect(app.menus.screen == app.menus.Screen.MAIN and not is_instance_valid(app.editor), "Editor returns to main menu")
	app.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(external_path)
	video.set_preference(&"level_transitions", animate, false)
	video.set_preference(&"background", background, false)
	print("Level editor checks: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
