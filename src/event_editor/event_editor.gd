extends Control
## Native form authoring; the same schema and interpreter power the running game.
const Schema = preload("res://src/game/authored_event_schema.gd")
const Runtime = preload("res://src/game/authored_event_runtime.gd")
const Catalog = preload("res://src/game/event_catalog.gd")
const Templates = preload("res://src/event_editor/event_templates.gd")
const ThemeFactory = preload("res://src/ui/ui_theme.gd")
var data: Dictionary = {}
var installed: Dictionary = {}
var imported: Dictionary = {}
var original_id := ""
var saved: Dictionary = {}
var undo_stack: Array = []
var redo_stack: Array = []
var last_edit := ""
var last_edit_time := 0
var list: ItemList
var search: LineEdit
var tree: Tree
var inspector: VBoxContainer
var status: Label
var heading: Label
var file_dialog: FileDialog
var file_action := ""
var confirmation: ConfirmationDialog
var pending: Callable
var selected_path: Array = []
var pack_error := ""
var preview_dialog
var preview_close: Button
var test_window: Window
var test_form: VBoxContainer
var test_log: RichTextLabel
var context := {"gold":30,"mana":0,"tier":2,"trees":4,"seed":42,"income":3,"modern":true,"second_army":3,"enemy":true,"recruit_space":true,"source":false,"free_spell":false,"trailblaze":false,"steel":false,"rebels":true}
var fixture
var fixture_event: Dictionary
var previewing := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	var background := ColorRect.new()
	background.color = Color("14272e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	margin.add_child(column)
	heading = label(column,"Event workshop",27)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	button(toolbar,"New",new_event)
	button(toolbar,"Duplicate",duplicate_event)
	button(toolbar,"Save to game",save_event)
	button(toolbar,"Undo",undo)
	button(toolbar,"Redo",redo)
	button(toolbar,"Import…",func(): open_file("import"))
	button(toolbar,"Export…",func(): open_file("export"))
	button(toolbar,"Remove override / event",remove_event)
	button(toolbar,"Preview & test",open_test)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(split)
	var library := VBoxContainer.new()
	library.custom_minimum_size.x = 230
	split.add_child(library)
	label(library,"Event library",19)
	search = LineEdit.new()
	search.placeholder_text = "Search title or ID"
	search.text_changed.connect(func(_value): refresh_list())
	library.add_child(search)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(index): guard(select_event.bind(list.get_item_metadata(index))))
	library.add_child(list)
	var right := HSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var outline := VBoxContainer.new()
	outline.custom_minimum_size.x = 290
	right.add_child(outline)
	label(outline,"Story & outcomes",19)
	label(outline,"Select a row to edit it. Effects run top to bottom.",12)
	tree = Tree.new()
	tree.hide_root = false
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(inspect_selected)
	outline.add_child(tree)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.custom_minimum_size.x = 460
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation",10)
	scroll.add_child(inspector)
	status = label(column,"",13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	file_dialog = FileDialog.new()
	file_dialog.theme = theme
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_selected.connect(file_selected)
	add_child(file_dialog)
	confirmation = ConfirmationDialog.new()
	confirmation.theme = theme
	confirmation.title = "Unsaved changes"
	confirmation.dialog_text = "Discard the unsaved changes to this event?"
	confirmation.ok_button_text = "Discard changes"
	confirmation.canceled.connect(refresh_list)
	confirmation.confirmed.connect(func():
		if pending.is_valid(): pending.call())
	add_child(confirmation)
	preview_dialog = load("res://src/ui/event_dialog.gd").new(preview_button)
	add_child(preview_dialog)
	preview_close = Button.new()
	preview_close.text = "Close preview"
	preview_close.position = Vector2(20,20)
	preview_close.pressed.connect(close_preview)
	preview_dialog.add_child(preview_close)
	var pack := Schema.load_pack()
	pack_error = pack.error
	for entry in pack.events: installed[entry.id] = entry
	refresh_list()
	select_event("economist")
	if pack_error != "": notify("The installed pack has errors. It was left untouched: "+pack_error,true)
	else: notify("Choose a built-in template or create a new event. Save to game installs it for the next game launch.")

func label(parent: Node, text: String, size := 15) -> Label:
	var control := Label.new()
	control.text = text
	control.add_theme_font_size_override("font_size",size)
	parent.add_child(control)
	return control

func help_text(parent: Node, text: String) -> void:
	var control := label(parent,text,13)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.modulate = Color("b3c6bc")

func button(parent: Node, caption: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = caption
	control.custom_minimum_size.y = 34
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func dirty() -> bool: return data != saved

func notify(message: String, error := false) -> void:
	status.text = message
	status.modulate = Color("f0aaa0") if error else Color("bed1c3")

func guard(action: Callable) -> void:
	if dirty():
		pending = action
		confirmation.title = "Unsaved changes"
		confirmation.dialog_text = "Discard unsaved changes to this event?"
		confirmation.ok_button_text = "Discard changes"
		confirmation.popup_centered(Vector2i(480,160))
	else: action.call()

func request_close() -> void: guard(func(): get_tree().quit())

func refresh_list() -> void:
	list.clear()
	var entries: Dictionary = Catalog.BUILTIN_EVENTS.duplicate()
	entries.merge(installed,true)
	entries.merge(imported,true)
	for id in entries:
		var title: String = entries[id].title
		if search.text != "" and not (id+" "+title).to_lower().contains(search.text.to_lower()): continue
		var prefix := "Custom · " if installed.has(id) else "Imported · " if imported.has(id) else "Template · "
		var index := list.add_item(prefix+title)
		list.set_item_metadata(index,id)
		list.set_item_tooltip(index,title+"\n"+id)
		if id == original_id: list.select(index)

func select_event(id: String) -> void:
	original_id = id
	data = imported[id].duplicate(true) if imported.has(id) else installed[id].duplicate(true) if installed.has(id) else Templates.template(id)
	saved = data.duplicate(true)
	undo_stack.clear()
	redo_stack.clear()
	selected_path = []
	rebuild_tree()
	refresh_list()
	notify("Editing "+id+(". Saving updates this installed event." if installed.has(id) else ". Duplicate to create another event; saving this ID replaces the built-in." if Catalog.BUILTIN_EVENTS.has(id) else ". Not installed yet."))

func unique_id(base: String) -> String:
	var id := base
	var suffix := 2
	while Catalog.EVENTS.has(id) or installed.has(id) or imported.has(id):
		id = base+"_"+str(suffix)
		suffix += 1
	return id

func new_event() -> void:
	guard(func():
		data = Schema.fresh(unique_id("new_event"))
		original_id = ""
		saved = {}
		undo_stack.clear()
		redo_stack.clear()
		selected_path = []
		rebuild_tree())

func duplicate_event() -> void:
	var duplicate := data.duplicate(true)
	duplicate.id = unique_id(data.id+"_copy")
	duplicate.title += " (copy)"
	guard(func():
		data = duplicate
		original_id = ""
		saved = {}
		undo_stack.clear()
		redo_stack.clear()
		selected_path = []
		rebuild_tree()
		notify("This copy is separate from its source. Give it a name and save it to the game."))

func remember(key := "") -> void:
	var now := Time.get_ticks_msec()
	if key == "" or key != last_edit or now-last_edit_time > 600:
		undo_stack.append(data.duplicate(true))
		if undo_stack.size() > 100: undo_stack.pop_front()
	last_edit = key
	last_edit_time = now
	redo_stack.clear()

func change(object: Dictionary, key: String, value) -> void:
	if object.get(key) == value: return
	remember(str(selected_path)+key)
	object[key] = value
	heading.text = "Event workshop · "+str(data.title)+" *"
	notify("Unsaved changes. Preview & test runs this draft; Save to game installs it.")
	refresh_outline_labels(tree.get_root())

func undo() -> void:
	if undo_stack.is_empty(): return
	redo_stack.append(data.duplicate(true))
	data = undo_stack.pop_back()
	last_edit = ""
	rebuild_tree()

func redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(data.duplicate(true))
	data = redo_stack.pop_back()
	last_edit = ""
	rebuild_tree()

func save_event() -> void:
	var errors := Schema.validate(data)
	if not errors.is_empty(): notify("Cannot save:\n"+"\n".join(errors),true); return
	if pack_error != "": notify("The installed pack is invalid. Repair or restore resources/events/custom_events.json before saving; it has not been overwritten.",true); return
	if data.id != original_id and (installed.has(data.id) or Catalog.BUILTIN_EVENTS.has(data.id)):
		notify("That ID belongs to another event. Select that event to edit it, or choose a unique ID.",true)
		return
	var next := installed.duplicate(true)
	if original_id != "" and original_id != data.id: next.erase(original_id)
	next[data.id] = data.duplicate(true)
	var error := Schema.save_pack(Schema.PACK_PATH,next.values())
	if error != "": notify(error,true); return
	installed = next
	original_id = data.id
	saved = data.duplicate(true)
	imported.erase(data.id)
	Catalog.reload()
	heading.text = "Event workshop · "+str(data.title)
	refresh_list()
	notify("Saved to game. Restart the game to load the updated event pack. A backup is kept alongside it.")

func remove_event() -> void:
	if not installed.has(original_id): notify("This is a built-in template or an unsaved draft. Built-in templates cannot be deleted."); return
	pending = func():
		var next := installed.duplicate(true)
		next.erase(original_id)
		var error := Schema.save_pack(Schema.PACK_PATH,next.values())
		if error != "": notify(error,true); return
		installed = next
		Catalog.reload()
		data = {}
		saved = {}
		select_event("economist")
		notify("Removed the custom event / override. Built-in behavior is restored when applicable.")
	confirmation.title = "Remove event"
	confirmation.dialog_text = "Remove this installed event? If it overrides a built-in event, the original will be restored."
	confirmation.ok_button_text = "Remove"
	confirmation.popup_centered(Vector2i(500,180))

func at(path: Array):
	var object = data
	for key in path: object = object[key]
	return object

func node(parent: TreeItem, caption: String, kind: String, path: Array) -> TreeItem:
	var item := tree.create_item(parent)
	item.set_text(0,caption)
	item.set_tooltip_text(0,caption)
	item.set_metadata(0,{"kind":kind,"path":path})
	if path == selected_path: item.select(0)
	return item

func requirement_nodes(parent: TreeItem, object: Dictionary, path: Array) -> void:
	for i in range(object.get("requires",[]).size()):
		var rule: Dictionary = object.requires[i]
		node(parent,("Not: " if rule.get("not",false) else "Requires: ")+Schema.CONDITIONS.get(rule.kind,rule.kind),"requirement",path+["requires",i])

func choice_nodes(parent: TreeItem, object: Dictionary, path: Array) -> void:
	requirement_nodes(parent,object,path)
	for i in range(object.choices.size()):
		var choice: Dictionary = object.choices[i]
		var choice_path := path+["choices",i]
		var row := node(parent,"Choice %d · %s" % [i+1,choice.label],"choice",choice_path)
		requirement_nodes(row,choice,choice_path)
		var total := 0
		for result in choice.outcomes: total += int(result.weight)
		for j in range(choice.outcomes.size()):
			var result: Dictionary = choice.outcomes[j]
			var result_path := choice_path+["outcomes",j]
			var outcome_row := node(row,"Outcome %d · %.1f%%" % [j+1,100.0*float(result.weight)/maxi(1,total)],"outcome",result_path)
			requirement_nodes(outcome_row,result,result_path)
			for k in range(result.get("effects",[]).size()):
				var effect: Dictionary = result.effects[k]
				node(outcome_row,"Effect · "+Schema.ACTIONS.get(effect.kind,effect.kind),"effect",result_path+["effects",k])

func rebuild_tree() -> void:
	tree.clear()
	if data.is_empty(): return
	heading.text = "Event workshop · "+str(data.title)+( " *" if dirty() else "")
	var root := node(null,"Event · "+str(data.id),"event",[])
	choice_nodes(root,data,[])
	for i in range(data.get("variants",[]).size()):
		var row := node(root,"Conditional story %d" % (i+1),"variant",["variants",i])
		choice_nodes(row,data.variants[i],["variants",i])
	if tree.get_selected() == null: root.select(0)
	inspect_selected()

func add_item(object: Dictionary, key: String, value) -> void:
	remember()
	if not object.has(key): object[key] = []
	object[key].append(value)
	selected_path += [key,object[key].size()-1]
	rebuild_tree()

func remove_selected() -> void:
	if selected_path.is_empty(): return
	remember()
	var container: Array = at(selected_path.slice(0,-1))
	container.remove_at(int(selected_path[-1]))
	selected_path = selected_path.slice(0,-2)
	rebuild_tree()

func move_selected(direction: int) -> void:
	if selected_path.is_empty(): return
	var container: Array = at(selected_path.slice(0,-1))
	var index: int = selected_path[-1]
	if index+direction < 0 or index+direction >= container.size(): return
	remember()
	var value = container[index]
	container[index] = container[index+direction]
	container[index+direction] = value
	selected_path[-1] = index+direction
	rebuild_tree()

func text_field(object: Dictionary, key: String, caption: String, multiline := false) -> void:
	label(inspector,caption,14)
	if multiline:
		var edit := TextEdit.new()
		edit.custom_minimum_size.y = 110
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.text = str(object.get(key,""))
		edit.text_changed.connect(func(): change(object,key,edit.text))
		inspector.add_child(edit)
	else:
		var edit := LineEdit.new()
		edit.text = str(object.get(key,""))
		edit.text_changed.connect(func(value): change(object,key,value))
		inspector.add_child(edit)

func number(object: Dictionary, key: String, caption: String, minimum := -100000, maximum := 100000, target: VBoxContainer = null) -> void:
	var parent: VBoxContainer = inspector if target == null else target
	label(parent,caption,14)
	var edit := SpinBox.new()
	edit.min_value = minimum
	edit.max_value = maximum
	edit.step = 1
	edit.value = float(object.get(key,0))
	edit.value_changed.connect(func(value):
		if target == null: change(object,key,int(value))
		else: object[key] = int(value))
	parent.add_child(edit)

func checkbox(object: Dictionary, key: String, caption: String) -> void:
	var edit := CheckBox.new()
	edit.text = caption
	edit.button_pressed = object.get(key,false)
	edit.toggled.connect(func(value): change(object,key,value))
	inspector.add_child(edit)

func options(object: Dictionary, key: String, caption: String, choices: Dictionary, replace_action := false) -> void:
	label(inspector,caption,14)
	var edit := OptionButton.new()
	for value in choices:
		edit.add_item(choices[value])
		edit.set_item_metadata(edit.item_count-1,value)
		if object.get(key) == value: edit.select(edit.item_count-1)
	edit.item_selected.connect(func(index):
		var value: String = edit.get_item_metadata(index)
		remember()
		if replace_action:
			object.clear()
			object.merge(Schema.action(value))
		else:
			object[key] = value
			if key == "kind" and Schema.CONDITIONS.has(value):
				if not object.has("effect"): object["effect"] = "free_spell"
				if not object.has("value"): object["value"] = 1
				if not object.has("not"): object["not"] = false
		rebuild_tree())
	inspector.add_child(edit)

func add_requirement(object: Dictionary) -> void:
	button(inspector,"+ Requirement",func(): add_item(object,"requires",Templates.requirement("kingdom")))

func inspect_selected() -> void:
	for child in inspector.get_children(): inspector.remove_child(child); child.queue_free()
	if tree.get_selected() == null: return
	var selection: Dictionary = tree.get_selected().get_metadata(0)
	selected_path = selection.path.duplicate()
	var object: Dictionary = at(selected_path)
	label(inspector,selection.kind.capitalize(),22)
	if selection.kind != "event":
		var tools := HBoxContainer.new()
		inspector.add_child(tools)
		button(tools,"Move up",move_selected.bind(-1))
		button(tools,"Move down",move_selected.bind(1))
		button(tools,"Remove",remove_selected)
	match selection.kind:
		"event":
			text_field(object,"id","Event ID · unique lowercase name")
			text_field(object,"title","Title")
			text_field(object,"text","Default story",true)
			checkbox(object,"enabled","Enabled in the game")
			number(object,"weight","Event weight · 0 = authored maps only",0,10000)
			help_text(inspector,"Higher weights make this event more likely. Random maps choose unused event types first; once all types are used, repeats are allowed.")
			text_field(object,"requirements","Requirements explanation for the map editor",true)
			add_requirement(object)
			button(inspector,"+ Choice",func(): add_item(object,"choices",Schema.choice()))
			button(inspector,"+ Conditional story",func(): add_item(object,"variants",{"text":"An alternative story.","requires":[Templates.requirement("forest_overgrown")],"choices":[Schema.choice()]}))
			text_field(object,"painting","Painting · blank uses the game's default")
			button(inspector,"Choose / copy painting…",func(): open_file("painting"))
			text_field(object,"painting_title","Painting title")
			text_field(object,"painting_artist","Artist")
			number(object,"gold_roll_min","Gold rolled once at reveal · minimum",0)
			number(object,"gold_roll_max","Gold rolled once at reveal · maximum · 0 disables",0)
			help_text(inspector,"Text tokens: {gold}, {trees}, {tier}, {treasury}, {scout_upkeep}, {knight_upkeep}. Outcome messages also accept {amount}, {refund}, {cleared}. No code is needed.")
		"variant":
			text_field(object,"text","Conditional story",true)
			help_text(inspector,"The first matching conditional story replaces the default story and choices. Conditions are checked before reveal and the selected story stays fixed.")
			add_requirement(object)
			button(inspector,"+ Choice",func(): add_item(object,"choices",Schema.choice()))
		"choice":
			text_field(object,"label","Button caption")
			text_field(object,"hint","Effects tooltip · include probabilities and consequences",true)
			number(object,"cost_gold","Gold cost · paid once before the outcome",0)
			number(object,"cost_mana","Mana cost · paid once before the outcome",0)
			number(object,"ai_score","AI preference · higher wins among available choices")
			add_requirement(object)
			button(inspector,"+ Weighted outcome",func(): add_item(object,"outcomes",Schema.outcome()))
		"outcome":
			number(object,"weight","Outcome weight · 60 and 40 produce a 60/40 split",1,10000)
			text_field(object,"text","Result message",true)
			add_requirement(object)
			button(inspector,"+ Effect",func(): add_item(object,"effects",Schema.action()))
			help_text(inspector,"Requirements select eligible outcomes before weighting. If an eligible outcome cannot run, the entire choice is disabled. Empty effect lists mean nothing happens.")
		"requirement":
			options(object,"kind","Requirement",Schema.CONDITIONS)
			checkbox(object,"not","Invert this requirement (NOT)")
			if object.kind in ["gold_at_least","income_at_least","mana_at_least","unit_tier_at_least","unit_tier_at_most"]: number(object,"value","Threshold")
			if object.kind in ["has_effect","no_effect"]: options(object,"effect","Temporary effect",{"free_spell":"Next spell free","trailblaze":"Next neutral capture grants another move"})
			help_text(inspector,"All requirements attached to the same row must match. Event requirements control eligibility; choice requirements disable buttons; outcome requirements control conditional branches.")
		"effect":
			options(object,"kind","Effect",Schema.ACTIONS,true)
			match object.kind:
				"gold", "mana":
					number(object,"min","Minimum amount · negative takes resources")
					number(object,"max","Maximum amount · equal values are deterministic")
					if object.kind == "gold": checkbox(object,"use_reveal_roll","Use the event's gold roll from reveal instead")
				"gold_percent": number(object,"percent","Treasury change in percent · -100 empties it",-100,1000)
				"promote":
					number(object,"steps","Ranks gained",1,2)
					number(object,"max_rank_gold","Gold awarded if already a Knight",0)
				"recruit":
					number(object,"tier","Army rank · 1 Scout / 2 Soldier / 3 Knight",1,3)
				"clear_trees":
					number(object,"gold_per_tree","Gold per cleared tree",0)
					checkbox(object,"adaptive","No gold when trees block more than half of kingdom income")
				"disband": number(object,"refund_percent","Recruitment price refunded · percent",0,100)
				"neutralize", "revolt": number(object,"radius","Region radius in hexes · 1 includes adjacent land",0,4)
				"landmark":
					number(object,"income_min","Permanent local income · minimum")
					number(object,"income_max","Permanent local income · maximum")
					number(object,"mana_min","Permanent mana regeneration · minimum")
					number(object,"mana_max","Permanent mana regeneration · maximum")
					checkbox(object,"steel","Owner's Knight wages -25% (does not stack)")
					checkbox(object,"soldier_discount","Owner's Soldier wages -50% (does not stack)")
					checkbox(object,"scout_discount","Owner's Scout wages -50% (does not stack)")
					checkbox(object,"development_discount","Local development cost -50% (friendly radius 1)")
					checkbox(object,"defense_aura","Defense +1 here and to adjacent friendly units")
					help_text(inspector,"The shared landmark cannot be destroyed. Its rewards and penalties transfer with conquest. One landmark effect can contain all three bonuses.")
				"mana_source": checkbox(object,"enabled","Enable mana source")
				"temporary_effect":
					options(object,"effect","Effect",{"free_spell":"Next spell free","trailblaze":"Next neutral capture grants another move"})
					checkbox(object,"enabled","Grant effect · uncheck to remove")
				"building": options(object,"building","Ordinary building",{"city":"City","tower":"Tower"})
				"tile_value": number(object,"amount","Province value change")
				_: help_text(inspector,"This effect needs no additional settings.")
			help_text(inspector,"Effects run in order. Place death, disbanding or territorial changes last. Validate with Preview & test before saving.")

func open_file(action: String) -> void:
	file_action = action
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if action == "export" else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Event artwork"]) if action == "painting" else PackedStringArray(["*.json ; Event pack"])
	file_dialog.title = "Choose event painting" if action == "painting" else "Export this event" if action == "export" else "Import an event pack"
	if action == "export": file_dialog.current_file = str(data.id)+".json"
	file_dialog.popup_centered_ratio(0.72)

func file_selected(path: String) -> void:
	match file_action:
		"export":
			var error := Schema.save_pack(path,[data])
			notify("Exported "+path if error == "" else error,error != "")
		"import":
			var pack := Schema.load_pack(path)
			if pack.error != "": notify(pack.error,true); return
			if pack.events.is_empty(): notify("This pack has no events."); return
			guard(func():
				for entry in pack.events: imported[entry.id] = entry
				# Imported drafts take precedence while viewing, but are never installed implicitly.
				var first: Dictionary = pack.events[0]
				original_id = first.id
				data = first.duplicate(true)
				saved = {}
				undo_stack.clear()
				redo_stack.clear()
				selected_path = []
				rebuild_tree()
				refresh_list()
				notify("Imported %d events. Select and Save to game each event you want installed." % pack.events.size()))
		"painting":
			var image := Image.load_from_file(path)
			if image == null or image.is_empty(): notify("Could not read that image.",true); return
			var directory := "res://assets/paintings/events"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			var target := directory+"/"+path.get_file().get_basename().validate_filename()+"_"+str(Time.get_unix_time_from_system()).replace(".","_")+".png"
			var error := image.save_png(target)
			if error != OK: notify("Could not copy artwork: "+error_string(error),true); return
			change(data,"painting",target)
			rebuild_tree()
			notify("Artwork copied into the project's assets folder and assigned to this event.")

func preview_button(parent: Node, caption: String, rectangle: Rect2, action: Callable, hint: String, _primary: bool) -> Button:
	var control := Button.new()
	control.text = caption
	control.tooltip_text = hint
	control.position = rectangle.position
	control.size = rectangle.size
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func open_test() -> void:
	var errors := Schema.validate(data)
	if not errors.is_empty(): notify("Fix these before testing:\n"+"\n".join(errors),true); return
	if test_window == null:
		test_window = Window.new()
		test_window.title = "Event sandbox · draft only"
		test_window.size = Vector2i(760,700)
		test_window.min_size = Vector2i(600,500)
		test_window.theme = theme
		var background := ColorRect.new()
		background.color = Color("14272e")
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		test_window.add_child(background)
		test_window.close_requested.connect(test_window.hide)
		add_child(test_window)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
		test_window.add_child(margin)
		var columns := HBoxContainer.new()
		margin.add_child(columns)
		var left := VBoxContainer.new()
		left.custom_minimum_size.x = 300
		columns.add_child(left)
		button(left,"Preview real game dialog",preview)
		button(left,"Test every eligible outcome",test_all_outcomes)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		left.add_child(scroll)
		test_form = VBoxContainer.new()
		test_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(test_form)
		for row in [["seed","Random seed",0,100000],["gold","Local gold",0,100000],["mana","Stored mana",0,20],["tier","Arriving army rank",1,3],["trees","Trees in the local kingdom",0,24],["income","Value of each province",1,6],["second_army","Second army rank · 0 = absent",0,3]]:
			number(context,row[0],row[1],row[2],row[3],test_form)
		for row in [["enemy","Other faction alive"],["recruit_space","Free recruitment space"],["source","Tile is a mana source"],["free_spell","Next spell already free"],["trailblaze","Trailblaze already active"],["steel","Owns steel landmark"],["rebels","Spare rebel identity"]]:
			var check := CheckBox.new()
			check.text = row[1]
			check.button_pressed = context[row[0]]
			var key: String = row[0]
			check.toggled.connect(func(value): context[key] = value)
			test_form.add_child(check)
		help_text(test_form,"Change the seed to try different weighted results. Clicking a preview choice runs the real effect code on a fresh sandbox position; your game is never changed.")
		test_log = RichTextLabel.new()
		test_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		test_log.bbcode_enabled = false
		columns.add_child(test_log)
	test_log.text = "Draft validation passed.\n\n"+effect_summary(data)
	test_window.popup_centered()

func sandbox():
	var state = load("res://src/game/kingdom_rules.gd").new()
	state.rule_mode = "modern"
	state.faction_count = 2
	state.human_factions = [0]
	state.rng.seed = int(context.seed)
	for q in range(-2,4):
		for r in range(-2,3):
			state.cells[Vector2i(q,r)] = state.make_cell(0)
			state.cells[Vector2i(q,r)].value = int(context.income)
	for q in range(4,7): state.cells[Vector2i(q,0)] = state.make_cell(1)
	state.cells[Vector2i.ZERO].capital = 0
	state.cells[Vector2i(6,0)].capital = 1
	for coord in [Vector2i.ZERO,Vector2i(-1,0),Vector2i(-1,1),Vector2i(-1,-1)]: state.cells[coord].mana_source = true
	state.cells[Vector2i(2,0)].unit = int(context.tier)
	state.cells[Vector2i(1,-1)].unit = int(context.second_army)
	state.cells[Vector2i(5,0)].unit = 1
	var trees := 0
	for coord in state.cells:
		if trees >= int(context.trees): break
		if state.cells[coord].owner == 0 and state.cells[coord].unit == 0 and state.cells[coord].capital < 0:
			state.cells[coord].tree = true
			trees += 1
	state.cells[Vector2i(2,0)].mana_source = context.source
	state.set_effect(0,"free_spell",context.free_spell)
	state.set_effect(0,"trailblaze",context.trailblaze)
	if context.steel: load("res://src/game/event_sites.gd").create(state,Vector2i(-2,0),"sandbox_steel",0,0,true)
	if not context.enemy:
		for coord in state.cells:
			if state.cells[coord].owner == 1: state.cells[coord] = state.make_cell(-1)
	if not context.rebels:
		state.human_factions = []
		for i in range(state.faction_names.size()): state.human_factions.append(i)
	if not context.recruit_space:
		for cell in state.cells.values():
			if cell.owner == 0 and cell.unit == 0 and cell.capital < 0 and cell.building == "" and not cell.tree: cell.building = "city"
	state.rebuild_kingdoms()
	for bank in state.kingdoms.values(): bank.gold = int(context.gold)
	state.set_mana(0,int(context.mana))
	return state

func summary(state) -> String:
	var gold := 0
	var income := 0
	var armies := 0
	var landmarks := 0
	for bank in state.kingdoms.values():
		if bank.owner == 0: gold += bank.gold; income += state.income(bank)
	for cell in state.cells.values():
		if cell.owner == 0 and cell.unit > 0: armies += 1
		if cell.building == "monument": landmarks += 1
	return "Gold: %d\nIncome: %d / turn\nMana: %d / %d\nMana regeneration: %d\nFriendly armies: %d\nLandmarks: %d\nFactions: %d" % [gold,income,state.get_mana(0),state.mana_capacity(0),state.mana_regeneration(0),armies,landmarks,state.faction_count]

func effect_summary(document: Dictionary) -> String:
	var lines := PackedStringArray(["Default story"])
	var stories: Array = [document]+document.get("variants",[])
	for index in range(stories.size()):
		if index > 0: lines.append("\nConditional story %d" % index)
		for choice in stories[index].choices:
			lines.append("\n"+str(choice.label))
			var total := 0
			for result in choice.outcomes: total += int(result.weight)
			for result in choice.outcomes:
				lines.append("  %.1f%% · %s" % [100.0*float(result.weight)/maxi(1,total),result.text])
				for effect in result.effects: lines.append("    "+Schema.ACTIONS[effect.kind])
	return "\n".join(lines)

func preview() -> void:
	var errors := Schema.validate(data)
	if not errors.is_empty(): test_log.text = "\n".join(errors); return
	fixture = sandbox()
	fixture_event = {"id":data.id,"coord":Vector2i(2,0),"faction":0}
	Runtime.prepare(fixture,data,fixture_event)
	var eligible := Runtime.available(fixture,data,fixture_event)
	test_log.text = ("Event is eligible." if eligible else "Event requirements are not met; the game would draw a replacement.")+"\n\nBEFORE\n"+summary(fixture)
	test_window.hide()
	previewing = true
	preview_dialog.present(Runtime.definition(fixture,data,fixture_event),func(index):
		var before := summary(fixture)
		var result := Runtime.resolve(fixture,data,fixture_event,index) if eligible else "Requirements unmet: no changes applied."
		close_preview()
		test_window.popup_centered()
		test_log.text = "Result:\n"+result+"\n\nBEFORE\n"+before+"\n\nAFTER\n"+summary(fixture))
	preview_close.move_to_front()
	preview_close.show()

func close_preview() -> void:
	previewing = false
	preview_dialog.close_dialog()
	if test_window != null: test_window.popup_centered()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and previewing: close_preview(); get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_S: save_event(); get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_Z and not get_viewport().gui_get_focus_owner() is TextEdit: undo(); get_viewport().set_input_as_handled()

func test_all_outcomes() -> void:
	var errors := Schema.validate(data)
	if not errors.is_empty(): test_log.text = "\n".join(errors); return
	var lines := PackedStringArray()
	var probe = sandbox()
	var event := {"id":data.id,"coord":Vector2i(2,0),"faction":0}
	Runtime.prepare(probe,data,event)
	if not Runtime.available(probe,data,event):
		test_log.text = "Event requirements are unmet in this sandbox. Change the context first."
		return
	var choices: Array = Runtime.story(data,event).choices
	for i in range(choices.size()):
		lines.append("\nCHOICE: "+str(choices[i].label))
		for j in range(choices[i].outcomes.size()):
			var state = sandbox()
			var attempt := {"id":data.id,"coord":Vector2i(2,0),"faction":0}
			Runtime.prepare(state,data,attempt)
			var result := Runtime.resolve(state,data,attempt,i,j)
			lines.append("Outcome %d: %s" % [j+1,result if result != "" else "Unavailable for this context"])
			if result != "": lines.append(summary(state))
	test_log.text = "Each outcome runs independently on a fresh sandbox.\n"+"\n".join(lines)

func refresh_outline_labels(item: TreeItem) -> void:
	if item == null: return
	var metadata: Dictionary = item.get_metadata(0)
	var object: Dictionary = at(metadata.path)
	match metadata.kind:
		"event": item.set_text(0,"Event · "+str(object.id))
		"choice": item.set_text(0,"Choice %d · %s" % [int(metadata.path[-1])+1,object.label])
		"outcome":
			var siblings: Array = at(metadata.path.slice(0,-1))
			var total := 0
			for sibling in siblings: total += int(sibling.weight)
			item.set_text(0,"Outcome %d · %.1f%%" % [int(metadata.path[-1])+1,100.0*float(object.weight)/maxi(1,total)])
	item.set_tooltip_text(0,item.get_text(0))
	var child := item.get_first_child()
	while child != null:
		refresh_outline_labels(child)
		child = child.get_next()
