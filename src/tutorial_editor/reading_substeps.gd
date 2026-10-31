extends VBoxContainer
## Extra reading pages belong to one objective, never to the main step sequence.
signal changed
signal preview_changed
const MAX_PAGES := preload("res://src/tutorial_editor/tutorial_document.gd").MAX_SUBSTEPS
var step: Dictionary = {}
var selector: OptionButton
var actions: PopupMenu
var add_button: Button
var title_field: LineEdit
var text_field: TextEdit
var editor: VBoxContainer
var loading := false

func _ready() -> void:
	var heading := Label.new()
	heading.text = "Reading sub-steps (optional)"
	add_child(heading)
	var hint := Label.new()
	hint.text = "Extra text pages appear before this objective. The player clicks Continue through them. They stay out of the step list."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	var row := HBoxContainer.new()
	add_child(row)
	selector = OptionButton.new()
	selector.fit_to_longest_item = false
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.item_selected.connect(func(_index): refresh_fields(); preview_changed.emit())
	row.add_child(selector)
	add_button = Button.new()
	add_button.text = "Add"
	add_button.pressed.connect(add_page)
	row.add_child(add_button)
	var menu := MenuButton.new()
	menu.text = "Page actions"
	row.add_child(menu)
	actions = menu.get_popup()
	actions.add_item("Move earlier",0)
	actions.add_item("Move later",1)
	actions.add_item("Remove sub-step",2)
	actions.id_pressed.connect(page_action)
	editor = VBoxContainer.new()
	add_child(editor)
	title_field = LineEdit.new()
	title_field.placeholder_text = "Sub-step heading (optional)"
	title_field.max_length = 100
	editor.add_child(title_field)
	title_field.text_changed.connect(func(_text): collect())
	text_field = TextEdit.new()
	text_field.custom_minimum_size.y = 120
	text_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.add_child(text_field)
	text_field.text_changed.connect(collect)

func bind(value: Dictionary) -> void:
	step = value
	refresh(0)

func pages() -> Array:
	return step.get("substeps",[])

func refresh(selected: int) -> void:
	loading = true
	selector.clear()
	selector.add_item("Main text")
	for index in range(pages().size()):
		var title: String = pages()[index].get("title","")
		selector.add_item("%d. %s" % [index+1,title if title != "" else "Extra text"])
	selector.select(clampi(selected,0,pages().size()))
	loading = false
	refresh_fields()

func refresh_fields() -> void:
	loading = true
	var index := selector.selected-1
	editor.visible = index >= 0
	actions.set_item_disabled(0,index <= 0)
	actions.set_item_disabled(1,index < 0 or index >= pages().size()-1)
	actions.set_item_disabled(2,index < 0)
	add_button.disabled = pages().size() >= MAX_PAGES
	if index >= 0:
		title_field.text = pages()[index].get("title","")
		text_field.text = pages()[index].text
	loading = false

func collect() -> void:
	if loading or selector.selected <= 0: return
	var index := selector.selected-1
	pages()[index] = {"title":title_field.text,"text":text_field.text}
	selector.set_item_text(index+1,"%d. %s" % [index+1,title_field.text if title_field.text != "" else "Extra text"])
	changed.emit()

func add_page() -> void:
	if pages().size() >= MAX_PAGES: return
	if not step.has("substeps"): step.substeps = []
	step.substeps.append({"title":"","text":""})
	refresh(pages().size())
	text_field.grab_focus()
	changed.emit()

func page_action(action: int) -> void:
	var index := selector.selected-1
	if index < 0: return
	if action == 2:
		step.substeps.remove_at(index)
		if step.substeps.is_empty(): step.erase("substeps")
		refresh(mini(index+1,pages().size()))
	else:
		var next := index+(-1 if action == 0 else 1)
		if next < 0 or next >= pages().size(): return
		var value = step.substeps.pop_at(index)
		step.substeps.insert(next,value)
		refresh(next+1)
	changed.emit()

func preview_page() -> Dictionary:
	return pages()[selector.selected-1] if selector.selected > 0 else {}
