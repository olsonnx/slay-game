extends Control
const Doc = preload("res://src/tutorial_editor/tutorial_document.gd")
const Lessons = preload("res://src/game/tutorial_lessons.gd")
const Level = preload("res://src/editor/level_document.gd")
const Simulator = preload("res://src/tutorial_editor/tutorial_simulator.gd")
const Ui = preload("res://src/ui/ui_theme.gd")
const AUTOSAVE := "user://tutorial-editor-autosave.json"
var document = Doc.new()
var step_index := 0
var steps_list: ItemList
var canvas
var inspector
var status: Label
var preview: Label
var file_label: Label
var template: OptionButton
var dialog: FileDialog
var confirmation: ConfirmationDialog
var dialog_action := ""
var pending: Callable
var pick_field: LineEdit
var save_timer: Timer
var history: Array = []
var history_index := -1
var app
var return_layer: CanvasLayer
var play_return: Button
var controls: Dictionary = {}
var map_state: Label
var pick_hint: Label
var prompt_scroll: ScrollContainer
var prompt_heading: Label
var mode_tabs: TabBar
var level_tools
var step_menu: PopupMenu
var file_menu: PopupMenu
var play_menu: PopupMenu
var template_menu: PopupMenu
var editing_level := false
var level_document = Level.new()
var topic_positions: Array = []
var stroke_changed := false
var picking_area := false
var finish_area_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Ui.create_theme()
	add_theme_font_size_override("font_size",14)
	var background := ColorRect.new()
	background.color = Color("101f26")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,14)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",10)
	margin.add_child(layout)
	var bar := HBoxContainer.new()
	layout.add_child(bar)
	var file_button := MenuButton.new()
	file_button.text = "File"
	bar.add_child(file_button)
	file_menu = file_button.get_popup()
	for entry in [["New tutorial",0],["Open...",1],["Save as...",2],["Import level...",3],["Recover autosave",4],["Use in game...",5]]: file_menu.add_item(entry[0],entry[1])
	template = OptionButton.new()
	for course in Lessons.categories(): template.add_item(course.title)
	# Keep the template selection as document state; the menu presents the choices.
	template.hide()
	bar.add_child(template)
	template_menu = PopupMenu.new()
	template_menu.name = "Templates"
	file_menu.add_child(template_menu)
	for course in Lessons.categories(): template_menu.add_item(course.title)
	file_menu.add_submenu_item("Start from template", "Templates")
	template_menu.id_pressed.connect(func(id): template.select(id); guard(load_template))
	file_menu.id_pressed.connect(file_action)
	button(bar,"Undo",undo)
	button(bar,"Redo",redo)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	mode_tabs = TabBar.new()
	mode_tabs.clip_tabs = false
	mode_tabs.custom_minimum_size.x = 240
	mode_tabs.add_tab("Write steps")
	mode_tabs.add_tab("Edit level")
	bar.add_child(mode_tabs)
	mode_tabs.tab_changed.connect(func(index): set_level_mode(index == 1))
	spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	button(bar,"Save",save)
	var play_button := MenuButton.new()
	play_button.text = "Play / Check"
	bar.add_child(play_button)
	play_menu = play_button.get_popup()
	for entry in [["Play from beginning",0],["Play selected step",1],["Preview selected step",2],["Check entire script",3]]: play_menu.add_item(entry[0],entry[1])
	play_menu.id_pressed.connect(play_action)
	file_label = Label.new()
	file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_label.clip_text = true
	layout.add_child(file_label)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 210
	layout.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 190
	left.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(left)
	label(left,"STEPS")
	steps_list = ItemList.new()
	steps_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	steps_list.item_selected.connect(select_step)
	left.add_child(steps_list)
	var row := HBoxContainer.new()
	left.add_child(row)
	button(row,"Add",add_step)
	var more := MenuButton.new()
	more.text = "Step actions"
	row.add_child(more)
	step_menu = more.get_popup()
	for entry in [["Duplicate step",0],["Move up",1],["Move down",2],["Delete step",3]]: step_menu.add_item(entry[0],entry[1])
	step_menu.id_pressed.connect(step_action)
	var workspace := HSplitContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.split_offset = 510
	body.add_child(workspace)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_child(center)
	var map_bar := HBoxContainer.new()
	center.add_child(map_bar)
	map_state = Label.new()
	map_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_bar.add_child(map_state)
	button(map_bar,"Done",cancel_pick)
	finish_area_button = controls.Done
	finish_area_button.hide()
	button(map_bar,"Reset view",func(): canvas.zoom = 1.0; canvas.pan = Vector2.ZERO; canvas.framing_dirty = true; canvas.queue_redraw())

	pick_hint = Label.new()
	pick_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pick_hint.text = "Use Pick beside a tile field to choose it on the map."
	center.add_child(pick_hint)
	canvas = preload("res://src/tutorial_editor/map_canvas.gd").new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.picked.connect(tile_picked)
	canvas.stroke_started.connect(begin_level_stroke)
	canvas.paint_requested.connect(paint_level)
	canvas.stroke_finished.connect(end_level_stroke)
	center.add_child(canvas)
	prompt_heading = Label.new()
	prompt_heading.text = "PLAYER PROMPT"
	center.add_child(prompt_heading)
	preview = Label.new()
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_scroll = ScrollContainer.new()
	prompt_scroll.custom_minimum_size.y = 150
	prompt_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(prompt_scroll)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_scroll.add_child(preview)
	inspector = preload("res://src/tutorial_editor/step_inspector.gd").new()
	inspector.custom_minimum_size.x = 390
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.size_flags_stretch_ratio = 0.8
	inspector.changed.connect(changed)
	inspector.preview_changed.connect(update_preview)
	inspector.pick_requested.connect(start_pick)
	inspector.area_pick_requested.connect(start_area_pick)
	inspector.tab_changed.connect(func(_index): cancel_pick())
	var details := VBoxContainer.new()
	details.custom_minimum_size.x = 390
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_child(details)
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(inspector)
	level_tools = preload("res://src/tutorial_editor/level_tools.gd").new()
	level_tools.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(level_tools)
	level_tools.hide()
	level_tools.brush_changed.connect(func(): cancel_pick(); update_level_hint())
	level_tools.gold_changed.connect(func(value):
		begin_level_stroke()
		level_document.starting_gold = value
		stroke_changed = true
		store_level()
		for position in topic_positions:
			position.document.starting_gold = value
			document.data.steps[position.index].setup = position.document.state()
		end_level_stroke())
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 42
	layout.add_child(status)
	dialog = FileDialog.new()
	dialog.theme = theme
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; JSON files"])
	dialog.size = Vector2i(900,600)
	dialog.current_dir = ProjectSettings.globalize_path("res://")
	dialog.file_selected.connect(file_chosen)
	add_child(dialog)
	confirmation = ConfirmationDialog.new()
	confirmation.theme = theme
	confirmation.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmation.get_label().custom_minimum_size = Vector2(500,100)
	confirmation.confirmed.connect(func(): if pending.is_valid(): pending.call())
	add_child(confirmation)
	save_timer = Timer.new()
	save_timer.wait_time = 0.65
	save_timer.one_shot = true
	save_timer.timeout.connect(commit)
	add_child(save_timer)
	new_document()
	get_viewport().size_changed.connect(update_density)
	call_deferred("update_density")

func update_density() -> void:
	# UI scaling reduces the logical workspace as well as the physical window.
	# Let the map flex before the prompt's minimum height pushes the form out.
	var compact := get_viewport_rect().size.y < 760
	canvas.custom_minimum_size.y = 240 if compact else 320
	prompt_scroll.custom_minimum_size.y = 80 if compact else 150

func button(parent: Node, text: String, callback: Callable) -> void:
	var node := Button.new()
	node.text = text
	node.pressed.connect(callback)
	parent.add_child(node)
	controls[text] = node
	node.tooltip_text = {
		"Undo":"Undo the last draft edit (Ctrl+Z)", "Redo":"Restore an undone edit (Ctrl+Y)",
		"Save":"Save your tutorial file (Ctrl+S)", "Save as":"Save a separate copy (Ctrl+Shift+S)",
		"Preview step":"Simulate earlier objectives and show the board before the selected step.",
		"Check script":"Check whether the authored actions and conditions can be completed in sequence.",
		"Playtest":"Play the tutorial from the beginning. Return here to keep editing.",
		"Play this step":"Play from the selected step using its simulated checkpoint.",
		"Use in game":"Install this draft for its course topic. You will review a replacement confirmation.",
		"Import map":"Replace the map for every exercise, keeping step text and targets. Undo restores prepared positions.",
		"Duplicate":"Copy the selected step with a fresh ID.",
		"Reset view":"Fit the map in the available space and reset zoom and pan."
	}.get(text,"")

func label(parent: Node, text: String) -> void:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size",13)
	parent.add_child(node)

func message(text: String) -> void:
	status.text = text

func reset_history() -> void:
	history = [document.data.duplicate(true)]
	history_index = 0

func load_template() -> void:
	var category: String = Lessons.IDS[template.selected]
	document = Doc.new()
	document.data = {"format":"slay-tutorial","version":1,"title":Lessons.category_title(category),"description":Lessons.categories()[template.selected].description,"category":category,"opponent_mode":"ai" if category == "practice" else "scripted","require_victory":category == "practice","map":Lessons.Scenarios.map_data(category),"steps":Lessons.authored_steps(category)}
	document.data.map.erase("tutorial")
	document.data.map.erase("tutorial_category")
	step_index = 0
	reset_history()
	refresh(true)
	message("Template loaded. Edit a step, import your map, or playtest. Save a copy when ready.")

func new_document() -> void:
	load_template()
	document.data.title = "My tutorial"
	document.data.steps = [Doc.new_step()]
	document.data.require_victory = false
	document.saved = JSON.stringify(document.data)
	reset_history()
	refresh(true)
	message("New tutorial. Use Edit level to build your board, then Write steps to guide the player.")

func refresh(reset_map := false) -> void:
	cancel_pick()
	step_index = clampi(step_index,0,document.data.steps.size()-1)
	refresh_list()
	inspector.bind(document.data,document.data.steps[step_index])
	if reset_map or editing_level:
		if editing_level:
			load_editable_level()
		else:
			var level := Level.new()
			var setup := prepared_index()
			level.read_data(document.data.steps[setup].setup if setup >= 0 else document.data.map)
			canvas.set_map(level.cells)
			map_state.text = "Exercise starting position" if setup >= 0 else "Course starting level"
	update_preview()

func refresh_list() -> void:
	steps_list.clear()
	for index in range(document.data.steps.size()):
		var step: Dictionary = document.data.steps[index]
		steps_list.add_item("%02d  %s" % [index+1,step.title])
		steps_list.set_item_tooltip(index,"%s\n%s" % [step.get("exercise","Independent objective"),step.task])
	steps_list.select(step_index)
	steps_list.ensure_current_is_visible()
	update_controls()

func update_preview() -> void:
	var step: Dictionary = document.data.steps[step_index]
	canvas.area_targets = [] if editing_level else Doc.target_hexes(step) if step.has("targets") else []
	canvas.target = Doc.NONE if editing_level else Doc.coord(step.get("highlight",step.get("target")))
	canvas.source = Doc.NONE if editing_level else Doc.coord(step.get("details",{}).get("source"))
	canvas.queue_redraw()
	var reading: Dictionary = inspector.substeps_editor.preview_page()
	preview.text = step.title + "\n\n" + step.text + "\n\n" + step.task if reading.is_empty() else (reading.get("title","") if reading.get("title","") != "" else step.title) + "\n\n" + reading.text
	file_label.tooltip_text = document.path
	update_controls()
	file_label.text = ("* " if document.dirty() else "") + (document.path if document.path != "" else "Unsaved tutorial") + " | " + document.data.title + " | Map: " + document.data.map.title

func select_step(index: int) -> void:
	commit()
	step_index = index
	pick_field = null
	refresh(true)
	message("Edit this starting position in Edit level, or use Play / Check to preview the simulated step.")

func changed() -> void:
	if picking_area and not document.data.steps[step_index].has("targets"): cancel_pick()
	refresh_list()
	update_preview()
	save_timer.start()

func commit() -> void:
	save_timer.stop()
	if history_index >= 0 and document.data == history[history_index]: return
	history.resize(history_index+1)
	history.append(document.data.duplicate(true))
	if history.size() > 80: history.pop_front()
	history_index = history.size()-1
	Doc.write_atomic(AUTOSAVE,document.data)
	update_controls()

func undo() -> void:
	commit()
	if history_index <= 0: return
	history_index -= 1
	document.data = history[history_index].duplicate(true)
	refresh(true)
	Doc.write_atomic(AUTOSAVE,document.data)

func redo() -> void:
	if history_index >= history.size()-1: return
	history_index += 1
	document.data = history[history_index].duplicate(true)
	refresh(true)
	Doc.write_atomic(AUTOSAVE,document.data)

func unique_id() -> String:
	var value := "step_%d" % Time.get_ticks_usec()
	return value

func add_step() -> void:
	commit()
	var value := Doc.new_step()
	value.id = unique_id()
	document.data.steps.insert(step_index+1,value)
	step_index += 1
	changed()
	refresh()

func duplicate_step() -> void:
	commit()
	var value: Dictionary = document.data.steps[step_index].duplicate(true)
	value.id = unique_id()
	value.title += " (copy)"
	document.data.steps.insert(step_index+1,value)
	step_index += 1
	changed()
	refresh()

func delete_step() -> void:
	if document.data.steps.size() <= 1: message("Keep at least one step."); return
	commit()
	document.data.steps.remove_at(step_index)
	step_index = mini(step_index,document.data.steps.size()-1)
	changed()
	refresh()

func move_step(direction: int) -> void:
	var next := step_index+direction
	if next < 0 or next >= document.data.steps.size(): return
	commit()
	var value = document.data.steps.pop_at(step_index)
	document.data.steps.insert(next,value)
	step_index = next
	changed()
	refresh()

func update_controls() -> void:
	controls.Undo.disabled = history_index <= 0 and (history_index < 0 or document.data == history[history_index])
	controls.Redo.disabled = history_index >= history.size()-1 or (history_index >= 0 and document.data != history[history_index])
	step_menu.set_item_disabled(1,step_index == 0)
	step_menu.set_item_disabled(2,step_index >= document.data.steps.size()-1)
	step_menu.set_item_disabled(3,document.data.steps.size() <= 1)
	file_menu.set_item_disabled(4,not FileAccess.file_exists(AUTOSAVE))

func start_pick(field: LineEdit) -> void:
	cancel_pick()
	if editing_level: set_level_mode(false)
	pick_field = field
	pick_hint.text = "Picking: %s | Click a map tile | Esc to cancel" % field.get_parent().get_parent().name
	canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS

func cancel_pick() -> void:
	if picking_area:
		canvas.finish_stroke()
		end_level_stroke()
	picking_area = false
	if finish_area_button != null: finish_area_button.hide()
	if canvas != null: canvas.edit_enabled = editing_level
	pick_field = null
	if pick_hint != null: pick_hint.text = "Use Pick beside a tile field to choose it on the map."
	if canvas != null: canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS if editing_level else Control.CURSOR_POINTING_HAND
	if editing_level and level_tools != null: update_level_hint()

func tile_picked(coord: Vector2i) -> void:
	if pick_field == null: message("Tile %d, %d. Use a Pick button to assign it to a rule." % [coord.x,coord.y]); return
	pick_field.text = "%d, %d" % [coord.x,coord.y]
	pick_field.text_changed.emit(pick_field.text)
	cancel_pick()
	message("Tile assigned. Condition and opponent forms need Add or Update to commit their row.")

func guard(action: Callable) -> void:
	commit()
	if not document.dirty(): action.call(); return
	pending = action
	confirmation.title = "Unsaved tutorial"
	confirmation.dialog_text = "Discard the current unsaved changes? Cancel to save them first."
	confirmation.ok_button_text = "Discard changes"
	confirmation.popup_centered(Vector2i(560,200))

func choose_file(action: String) -> void:
	dialog_action = action
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if action == "save" else FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = {"save":"Save tutorial","open":"Open tutorial","map":"Import map exported by the level editor"}[action]
	if action == "save": dialog.current_file = document.data.category + ".tutorial.json"
	dialog.popup_centered()

func file_chosen(filename: String) -> void:
	match dialog_action:
		"save":
			var error := document.save_file(filename)
			message("Saved " + filename if error == "" else error)
		"open":
			var loaded := Doc.new()
			var error := loaded.load_file(filename)
			if error != "": message(error); return
			document = loaded
			step_index = 0
			reset_history()
			refresh(true)
			message("Loaded " + filename)
		"map": import_map(filename)
	update_preview()

func import_map(filename: String) -> void:
	if not FileAccess.file_exists(filename): message("Map does not exist."); return
	var file := FileAccess.open(filename,FileAccess.READ)
	if file == null or file.get_length() > Doc.MAX_BYTES: message("Cannot open map or file is too large."); return
	var value = JSON.parse_string(file.get_as_text())
	var level := Level.new()
	var error := level.read_data(value)
	if error != "": message(error); return
	commit()
	document.data.map = value.duplicate(true)
	for step in document.data.steps: step.erase("setup")
	changed()
	refresh(true)
	message("Map imported for all exercises. Separate practice positions were removed; check existing targets before playtesting.")

func save() -> void:
	commit()
	if document.path == "": choose_file("save"); return
	var error := document.save_file(document.path)
	message("Saved " + document.path if error == "" else error)
	update_preview()

func recover() -> void:
	if not FileAccess.file_exists(AUTOSAVE): message("No autosave exists yet."); return
	var value = JSON.parse_string(FileAccess.get_file_as_string(AUTOSAVE))
	if not value is Dictionary or value.get("format") != "slay-tutorial" or not value.get("steps") is Array or value.steps.is_empty(): message("Autosave is unreadable."); return
	document = Doc.new()
	document.data = value
	step_index = 0
	reset_history()
	refresh(true)
	message("Recovered autosave. Save it to a tutorial file.")

func validate_script() -> void:
	commit()
	var result: Dictionary = Simulator.run(document)
	message("Script checked: every specified action and condition is valid, including the ending." if result.error == "" else result.error)

func preview_step() -> void:
	cancel_pick()
	commit()
	var result: Dictionary = Simulator.run(document,step_index)
	if result.rules != null:
		canvas.set_map(result.rules.cells)
		map_state.text = "Before step %d | Round %d" % [step_index+1,result.round]
	message("Board before step %d, turn %d. This preview does not change your draft." % [step_index+1,result.round] if result.error == "" else result.error)

func install() -> void:
	commit()
	var error := Doc.validate(document.data)
	if error != "": message(error); return
	pending = func():
		var folder := "res://tutorials"
		DirAccess.make_dir_recursive_absolute(folder)
		var filename: String = folder + "/" + document.data.category + ".json"
		if FileAccess.file_exists(filename):
			var backup := DirAccess.copy_absolute(filename,filename+".bak")
			if backup != OK: message("Could not back up the installed tutorial: " + error_string(backup)); return
		var result := Doc.write_atomic(filename,document.data)
		message("Installed. Open Tutorial > " + document.data.category.capitalize() + " in the game." if result == "" else result)
	confirmation.title = "Use tutorial in game"
	confirmation.dialog_text = "Replace the %s tutorial with this draft? Your map is embedded in the file. The previous installed file is kept as .bak. Save a separate copy to keep editing." % document.data.category.capitalize()
	confirmation.ok_button_text = "Use in game"
	confirmation.popup_centered(Vector2i(560,200))

func playtest(from_step: bool) -> void:
	cancel_pick()
	if app != null: return
	commit()
	var error := Doc.validate(document.data)
	if error != "": message(error); return
	var result: Dictionary = Simulator.run(document,step_index) if from_step else {}
	if from_step and result.error != "": message(result.error); return
	get_node("/root/Video").set_preference(&"level_transitions",false,false)
	app = preload("res://src/app/app.gd").new()
	get_viewport().add_child(app)
	app.menus.quit_requested.disconnect(app.quit_game)
	app.menus.quit_requested.connect(stop_playtest)
	hide()
	var play_data: Dictionary = document.level_data()
	play_data["tutorial_playtest"] = true
	await app.start_new_game(document.data.map.seed,document.data.map.size,"easy",2,play_data)
	if from_step:
		# Retry must return to this exercise, even when playtesting a later goal.
		var tutor = app.game.tutorial
		var group: String = str(document.data.steps[step_index].get("exercise","step_"+str(step_index)))
		for number in range(step_index+1):
			if str(document.data.steps[number].get("exercise","step_"+str(number))) == group:
				tutor.index = number
				tutor.enter_step()
				break
		app.game.rules = result.rules
		app.game.round_number = result.round
		app.game.tutorial.index = step_index
		app.game.tutorial.enter_step()
	app.game.tutorial_exit_requested.disconnect(app.return_to_tutorials)
	app.game.tutorial_exit_requested.connect(stop_playtest)
	return_layer = CanvasLayer.new()
	return_layer.layer = 100
	return_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().add_child(return_layer)
	play_return = Button.new()
	play_return.text = "Return to tutorial editor"
	play_return.position = Vector2(20,86)
	play_return.pressed.connect(stop_playtest)
	return_layer.add_child(play_return)

func stop_playtest() -> void:
	if app == null or app.transitioning: return
	if return_layer != null: return_layer.queue_free(); return_layer = null
	await app.return_to_main_menu()
	app.queue_free()
	app = null
	get_tree().paused = false
	await get_tree().process_frame
	show()
	message("Playtest ended. Draft unchanged.")

func request_close() -> void:
	if app != null:
		await stop_playtest()
	guard(func(): get_tree().quit())

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and (pick_field != null or picking_area):
		cancel_pick()
		get_viewport().set_input_as_handled()
		return
	if app != null or not event is InputEventKey or not event.pressed or event.echo or not event.ctrl_pressed: return
	match event.keycode:
		KEY_S:
			if event.shift_pressed: choose_file("save")
			else: save()
		KEY_Z: undo()
		KEY_Y: redo()
		_: return
	get_viewport().set_input_as_handled()

func file_action(id: int) -> void:
	match id:
		0: guard(new_document)
		1: guard(func(): choose_file("open"))
		2: choose_file("save")
		3: choose_file("map")
		4: guard(recover)
		5: install()

func prepared_index() -> int:
	for index in range(step_index,-1,-1):
		if document.data.steps[index].has("setup"): return index
	return -1

func set_level_mode(enabled: bool) -> void:
	canvas.finish_stroke()
	end_level_stroke()
	mode_tabs.set_block_signals(true)
	mode_tabs.current_tab = 1 if enabled else 0
	mode_tabs.set_block_signals(false)
	editing_level = enabled
	canvas.edit_enabled = enabled
	inspector.visible = not enabled
	level_tools.visible = enabled
	prompt_scroll.visible = not enabled
	prompt_heading.visible = not enabled
	cancel_pick()
	if enabled:
		load_editable_level()
		update_preview()
	else: refresh(true)

func load_editable_level() -> void:
	end_level_stroke()
	level_document = Level.new()
	level_document.read_data(document.data.map)
	topic_positions.clear()
	for index in range(document.data.steps.size()):
		if not document.data.steps[index].has("setup"): continue
		var position := Level.new()
		position.read_data(document.data.steps[index].setup)
		topic_positions.append({"index":index,"document":position})
	level_tools.bind_level(level_document)
	canvas.set_map(level_document.cells)
	map_state.text = "Topic level"
	level_tools.context.text = "Level edits apply to this entire topic, including every prepared exercise position."
	update_level_hint()

func update_level_hint() -> void:
	pick_hint.text = "%s | Drag to paint, right-drag to erase | Wheel: zoom, middle-drag: pan" % level_tools.tool_name()

func begin_level_stroke() -> void:
	commit()
	stroke_changed = false

func paint_level(at: Vector2i, erase: bool) -> void:
	if picking_area:
		paint_target_area(at,erase)
		return
	if not editing_level: return
	var tool: String = level_tools.tool_name()
	var owner_id: int = level_tools.owner_choice.selected-1
	var province_value := int(level_tools.value.value)
	var result: bool = level_document.erase(at,tool) if erase else level_document.paint(at,tool,owner_id,province_value)
	# Apply the same brush to each prepared board, retaining untouched exercise details.
	for position in topic_positions:
		var level = position.document
		var painted: bool = level.erase(at,tool) if erase else level.paint(at,tool,owner_id,province_value)
		if painted:
			document.data.steps[position.index].setup = level.state()
			result = true
	if not result: return
	stroke_changed = true
	store_level()
	canvas.queue_redraw()

func store_level() -> void:
	document.data.map = level_document.state()

func end_level_stroke() -> void:
	if not stroke_changed: return
	stroke_changed = false
	changed()
	commit()
	message("Target area updated. Any selected hex can satisfy the goal." if picking_area else "Level updated. Undo restores the whole brush stroke.")

func play_action(id: int) -> void:
	match id:
		0: playtest(false)
		1: playtest(true)
		2:
			mode_tabs.current_tab = 0
			set_level_mode(false)
			preview_step()
		3: validate_script()

func step_action(id: int) -> void:
	match id:
		0: duplicate_step()
		1: move_step(-1)
		2: move_step(1)
		3: delete_step()

func start_area_pick() -> void:
	cancel_pick()
	if editing_level: set_level_mode(false)
	commit()
	picking_area = true
	canvas.edit_enabled = true
	canvas.framing_dirty = true
	canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
	finish_area_button.show()
	pick_hint.text = "Select area: click or drag to add hexes, right-drag to remove. Done or Esc finishes."
	message("Every selected hex is an allowed target; normal action rules still apply.")

func paint_target_area(at: Vector2i, erase: bool) -> void:
	if absi(at.x) > 100 or absi(at.y) > 100: return
	var step: Dictionary = document.data.steps[step_index]
	if not step.has("targets"): return
	var encoded := [at.x,at.y]
	var index: int = step.targets.find(encoded)
	if erase and index >= 0: step.targets.remove_at(index)
	elif not erase and index < 0 and step.targets.size() < Level.MAX_CELLS: step.targets.append(encoded)
	else: return
	stroke_changed = true
	inspector.update_area_summary()
	update_preview()
