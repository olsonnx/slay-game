extends ScrollContainer
## Small, contextual palette backed by the same document tools as the level editor.
signal brush_changed
signal gold_changed(value: int)
const TOOL_GROUPS := {
	"Terrain":["Land","Water","Mountain","Tree","Grave","Mana source","Ore source"],
	"Kingdoms":["Owner","Value","Capital"],
	"Armies":["Scout","Soldier","Knight"],
	"Structures":["City","Tower","Bridge","Road"],
	"Clear":["Clear objects"]
}
var context: Label
var group: OptionButton
var tool: OptionButton
var owner_choice: OptionButton
var value: SpinBox
var gold: SpinBox
var owner_group: VBoxContainer
var value_group: VBoxContainer

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",12)
	add_child(box)
	heading(box,"LEVEL")
	context = heading(box,"")
	heading(box,"Paint")
	group = OptionButton.new()
	for name in TOOL_GROUPS: group.add_item(name)
	box.add_child(group)
	group.item_selected.connect(func(_index): populate_tools())
	tool = OptionButton.new()
	box.add_child(tool)
	tool.item_selected.connect(func(_index): update_fields(); brush_changed.emit())
	owner_group = VBoxContainer.new()
	box.add_child(owner_group)
	heading(owner_group,"Kingdom")
	owner_choice = OptionButton.new()
	owner_group.add_child(owner_choice)
	value_group = VBoxContainer.new()
	box.add_child(value_group)
	heading(value_group,"Province value")
	value = SpinBox.new()
	value.min_value = 1
	value.max_value = 6
	value.value = 1
	value_group.add_child(value)
	heading(box,"Opening gold per kingdom (entire topic)")
	gold = SpinBox.new()
	gold.min_value = 0
	gold.max_value = 9999
	box.add_child(gold)
	gold.value_changed.connect(func(amount): gold_changed.emit(int(amount)))
	heading(box,"Click or drag on the map to paint. Right-drag clears objects; with a terrain brush it removes tiles. Water also removes tiles. Place land and assign its kingdom before adding an army or structure. Undo restores an entire stroke.")
	populate_tools()

func heading(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func tool_name() -> String:
	return "City" if tool.get_item_text(tool.selected) == "Castle" else tool.get_item_text(tool.selected)

func populate_tools() -> void:
	tool.clear()
	for name in TOOL_GROUPS[group.get_item_text(group.selected)]: tool.add_item("Castle" if name == "City" else name)
	update_fields()
	brush_changed.emit()

func update_fields() -> void:
	owner_group.visible = tool_name() in ["Land","Owner"]
	value_group.visible = tool_name() in ["Land","Value"]

func bind_level(document) -> void:
	var previous := owner_choice.selected
	owner_choice.clear()
	owner_choice.add_item("Neutral")
	for index in range(mini(6,document.factions.size())):
		owner_choice.add_item("%s%s" % [document.factions[index].name," (player)" if index == 0 else ""])
	owner_choice.select(clampi(previous,0,owner_choice.item_count-1))
	gold.set_value_no_signal(document.starting_gold)
