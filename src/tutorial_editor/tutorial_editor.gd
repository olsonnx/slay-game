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
	button(bar,"New",func(): guard(new_document))
	template = OptionButton.new()
	for course in Lessons.categories(): template.add_item(course.title)
	bar.add_child(template)
	button(bar,"Load template",func(): guard(load_template))
	button(bar,"Open",func(): guard(func(): choose_file("open")))
	button(bar,"Save",save)
	button(bar,"Save as",func(): choose_file("save"))
	button(bar,"Import map",func(): choose_file("map"))
	button(bar,"Recover autosave",func(): guard(recover))
	var bar2 := HBoxContainer.new()
	layout.add_child(bar2)
	button(bar2,"Undo",undo)
	button(bar2,"Redo",redo)
	button(bar2,"Check script",validate_script)
	button(bar2,"Preview step",preview_step)
	button(bar2,"Playtest",func(): playtest(false))
	button(bar2,"Play this step",func(): playtest(true))
	button(bar2,"Use in game",install)
	file_label = Label.new()
	file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_label.clip_text = true
	layout.add_child(file_label)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",14)
	layout.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 190
	body.add_child(left)
	label(left,"STEPS")
	steps_list = ItemList.new()
	steps_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	steps_list.item_selected.connect(select_step)
	left.add_child(steps_list)
	var row := HBoxContainer.new()
	left.add_child(row)
	button(row,"Add",add_step)
	button(row,"Duplicate",duplicate_step)
	row = HBoxContainer.new()
	left.add_child(row)
	button(row,"Up",func(): move_step(-1))
	button(row,"Down",func(): move_step(1))
	button(row,"Delete",delete_step)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	label(center,"MAP / Wheel: zoom. Middle-drag: pan. Pick a field, then click a tile. Fern is player 0.")
	canvas = preload("res://src/tutorial_editor/map_canvas.gd").new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.picked.connect(tile_picked)
	center.add_child(canvas)
	label(center,"PLAYER PROMPT PREVIEW")
	preview = Label.new()
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.custom_minimum_size.y = 150
	preview.max_lines_visible = 7
	preview.clip_text = true
	center.add_child(preview)
	inspector = preload("res://src/tutorial_editor/step_inspector.gd").new()
	inspector.custom_minimum_size.x = 390
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.size_flags_stretch_ratio = 0.8
	inspector.changed.connect(changed)
	inspector.pick_requested.connect(func(field: LineEdit): pick_field = field; message("Click a map hex to set " + field.get_parent().get_parent().name))
	body.add_child(inspector)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 42
	layout.add_child(status)
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; JSON files"])
	dialog.size = Vector2i(900,600)
	dialog.current_dir = ProjectSettings.globalize_path("res://")
	dialog.file_selected.connect(file_chosen)
	add_child(dialog)
	confirmation = ConfirmationDialog.new()
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

func button(parent: Node, text: String, callback: Callable) -> void:
	var node := Button.new()
	node.text = text
	node.pressed.connect(callback)
	parent.add_child(node)

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
	document.data = {"format":"slay-tutorial","version":1,"title":Lessons.category_title(category),"description":Lessons.categories()[template.selected].description,"category":category,"opponent_mode":"ai" if category == "practice" else "scripted","require_victory":category == "practice","map":Lessons.Scenarios.map_data(category),"steps":Doc.encode(Lessons.builtin_lessons(category))}
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
	message("New draft. Import a custom map, write a prompt, and choose how each step advances.")

func refresh(reset_map := false) -> void:
	step_index = clampi(step_index,0,document.data.steps.size()-1)
	refresh_list()
	inspector.bind(document.data,document.data.steps[step_index])
	if reset_map:
		var level := Level.new()
		level.read_data(document.data.map)
		canvas.set_map(level.cells)
	update_preview()

func refresh_list() -> void:
	steps_list.clear()
	for index in range(document.data.steps.size()): steps_list.add_item("%02d  %s" % [index+1,document.data.steps[index].title])
	steps_list.select(step_index)

func update_preview() -> void:
	var step: Dictionary = document.data.steps[step_index]
	canvas.target = Doc.coord(step.get("highlight",step.get("target")))
	canvas.source = Doc.coord(step.get("details",{}).get("source"))
	canvas.queue_redraw()
	preview.text = step.title + "\n\n" + step.text + "\n\n" + step.task
	file_label.text = ("* " if document.dirty() else "") + (document.path if document.path != "" else "Unsaved tutorial") + " | " + document.data.title + " | Map: " + document.data.map.title

func select_step(index: int) -> void:
	commit()
	step_index = index
	pick_field = null
	refresh(true)
	message("Starting map. Use Preview step to see the board at this point in the match.")

func changed() -> void:
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

func tile_picked(coord: Vector2i) -> void:
	if pick_field == null: message("Tile %d, %d. Use a Pick button to assign it to a rule." % [coord.x,coord.y]); return
	pick_field.text = "%d, %d" % [coord.x,coord.y]
	pick_field.text_changed.emit(pick_field.text)
	pick_field = null
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
	commit()
	var result: Dictionary = Simulator.run(document,step_index)
	if result.rules != null: canvas.set_map(result.rules.cells)
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
	if app != null or not event is InputEventKey or not event.pressed or event.echo or not event.ctrl_pressed: return
	match event.keycode:
		KEY_S:
			if event.shift_pressed: choose_file("save")
			else: save()
		KEY_Z: undo()
		KEY_Y: redo()
		_: return
	get_viewport().set_input_as_handled()
