extends TabContainer
## Text and rule forms edit plain document dictionaries; no game state lives here.
signal changed
signal pick_requested(field: LineEdit)
signal preview_changed
signal area_pick_requested
const Doc = preload("res://src/tutorial_editor/tutorial_document.gd")
var fields: Dictionary = {}
var groups: Dictionary = {}
var step: Dictionary = {}
var course: Dictionary = {}
var loading := true
var conditions: ItemList
var orders: ItemList
var row_buttons: Dictionary = {}
var substeps_editor
const FRIENDLY := {
	"read":"No condition (read and continue)", "continue":"Continue after board conditions", "end_turn":"End a round",
	"rename_settlement":"Name a settlement", "relocate_capital":"Relocate the capital",
	"finance":"Open the gold tooltip", "status":"Open a status tooltip",
	"kingdom":"Select a friendly kingdom", "animal":"Inspect a predator",
	"ai":"Normal AI", "idle":"Wait / do nothing", "scripted":"Scripted orders",
	"all":"All conditions must pass", "unit":"Army rank", "value":"Province value",
	"clear":"No trees or graves", "victory":"Opponent defeated",
	"isolated":"Army cut off from its kingdom", "no_unit":"No army on tile",
	"owner":"Tile owner", "entrenched":"Entrenched army"
}

func _ready() -> void:
	var text_page := page("Text")
	var course_page := page("Course")
	line(course_page,"Course title","course_title")
	line(course_page,"Category menu description","description")
	choice(course_page,"Topic","category",Doc.CATEGORIES)
	choice(course_page,"Opponent turns","opponent_mode",["scripted","ai","idle"])
	fields.require_victory = check(course_page,"Require opponent defeat to finish")
	fields.require_victory.toggled.connect(func(_v): collect())
	label(course_page,"Opening gold (each kingdom)")
	var gold := SpinBox.new()
	gold.min_value = 0
	gold.max_value = 9999
	course_page.add_child(gold)
	fields.gold = gold
	gold.value_changed.connect(func(_v): collect())
	line(text_page,"Heading","title")
	label(text_page,"Explanation")
	var text := TextEdit.new()
	text.custom_minimum_size.y = 120
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_page.add_child(text)
	fields.text = text
	text.text_changed.connect(collect)
	fields.read_before_action = check(text_page,"Require Continue before actions")
	fields.read_before_action.tooltip_text = "Keep moves, purchases, spells and End turn blocked until the player acknowledges this text. Map inspection and camera controls stay available."
	fields.read_before_action.toggled.connect(func(_value): collect())
	var substeps_box := fold(text_page,"Extra reading sub-steps")
	substeps_editor = preload("res://src/tutorial_editor/reading_substeps.gd").new()
	substeps_box.add_child(substeps_editor)
	substeps_editor.changed.connect(func(): changed.emit())
	substeps_editor.preview_changed.connect(func(): preview_changed.emit())
	line(text_page,"Short objective","task")
	var extras := fold(text_page,"Optional: camera and highlighting")
	coord_field(extras,"Highlight tile","highlight")
	coord_field(extras,"Camera focus tile","focus")
	var identifiers := fold(text_page,"Advanced: exercise grouping and ID")
	line(identifiers,"Exercise group (blank = individual objective)","exercise")
	line(identifiers,"Step ID","id")
	var goal_page := page("Goal")
	choice(goal_page,"Advance after","kind",Doc.ACTIONS)
	fields.read_help = Label.new()
	fields.read_help.text = "The player reads the explanation and clicks Continue when ready. Board actions stay blocked until Continue; map inspection and camera controls remain available."
	fields.read_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_page.add_child(fields.read_help)
	fields.use_area = check(goal_page,"Accept any hex in a selected area")
	fields.use_area.toggled.connect(area_mode_changed)
	coord_field(goal_page,"Target tile (blank = any)","target")
	var area_group := VBoxContainer.new()
	goal_page.add_child(area_group)
	groups.target_area = area_group
	fields.area_summary = Label.new()
	area_group.add_child(fields.area_summary)
	button(area_group,"Select area on map",func(): area_pick_requested.emit())
	coord_field(goal_page,"Source unit (blank = any)","source")
	choice(goal_page,"Unit tier","tier",["any","Scout","Soldier","Knight"])
	choice(goal_page,"Building","building",["any","city","tower","bridge"])
	choice(goal_page,"Spell","spell",["any","trailblaze","summon","shatter"])
	choice(goal_page,"Move result","outcome",["any","move","attack","merge","blocked_attack","knight_duel"])
	choice(goal_page,"View/Stats state","state",["any","on / open","off / closed"])
	fields.restrict_actions = check(goal_page,"Allow only the requested action")
	fields.restrict_actions.toggled.connect(func(_v): collect())
	fields.confirm = check(goal_page,"Keep details open until Continue")
	fields.confirm.toggled.connect(func(_v): collect())
	var more_goal := fold(goal_page,"More goal options")
	groups.goal_more = more_goal
	label(more_goal,"Required actions (distinct target tiles)")
	fields.count = SpinBox.new()
	fields.count.min_value = 1
	fields.count.max_value = 20
	more_goal.add_child(fields.count)
	fields.count.value_changed.connect(func(_v): collect())
	fields.allow_turns = check(more_goal,"Allow End turn during this objective")
	fields.allow_turns.toggled.connect(func(_v): collect())
	fields.wildlife_turn = check(goal_page,"Run wildlife during this End turn")
	fields.wildlife_turn.toggled.connect(func(_v): collect())
	line(goal_page,"Status icon (effect ID)","effect")
	fields.matching = Label.new()
	fields.matching.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_page.add_child(fields.matching)
	fields.clear_matching = button(goal_page,"Clear extra matching restrictions",func(): step["criteria"] = {}; fields.matching.text = "No extra matching restrictions."; changed.emit())
	var conditions_page := page("Conditions")
	label(conditions_page,"Conditions must pass as well as the selected action. Use the free play goal to watch the board. Select a row to edit it, then Update selected; Add creates another condition.")
	choice(conditions_page,"Combine conditions","condition_mode",["all","any"])
	conditions = ItemList.new()
	conditions.custom_minimum_size.y = 105
	conditions_page.add_child(conditions)
	conditions.item_selected.connect(select_condition)
	choice(conditions_page,"Condition","cond_type",Doc.PREDICATES,false)
	fields.cond_type.item_selected.connect(func(_index): condition_defaults())
	coord_field(conditions_page,"Condition tile","cond_target",false)
	line(conditions_page,"Value (minimum, owner ID, or building)","cond_value",false)
	line(conditions_page,"Faction (-1 = all enemies for victory)","cond_faction",false)
	var row := HBoxContainer.new()
	conditions_page.add_child(row)
	button(row,"Add",func(): save_condition(false))
	row_buttons.condition_update = button(row,"Update selected",func(): save_condition(true))
	row_buttons.condition_remove = button(row,"Remove selected",remove_condition)
	label(conditions_page,"Board conditions: unit/value/gold/mana/round/territory/income use at least. Owner and building use equality. Continue waits for a click; any watches conditions while allowing free play.")
	var enemy_page := page("Opponent")
	label(enemy_page,"Orders run in sequence on this End turn step. Choose Scripted orders in Course to use them. Add creates an order; Update selected applies your edits. Factions: 1 Ember, 2 Tide, 3 Ochre, 4 Aster, 5 Cove.")
	orders = ItemList.new()
	orders.custom_minimum_size.y = 140
	enemy_page.add_child(orders)
	orders.item_selected.connect(select_order)
	choice(enemy_page,"Order","op_kind",Doc.ORDERS,false)
	fields.op_kind.item_selected.connect(func(_index):
		fields.op_value.text = {"recruit":"1","build":"city","spell":"summon"}.get(selected("op_kind"),"")
		update_rule_forms())
	line(enemy_page,"Faction","op_faction",false)
	coord_field(enemy_page,"From","op_source",false)
	coord_field(enemy_page,"To","op_target",false)
	line(enemy_page,"Parameter (tier / building / spell)","op_value",false)
	row = HBoxContainer.new()
	enemy_page.add_child(row)
	button(row,"Add",func(): save_order(false))
	row_buttons.order_update = button(row,"Update selected",func(): save_order(true))
	row_buttons.order_remove = button(row,"Remove selected",remove_order)
	row = HBoxContainer.new()
	enemy_page.add_child(row)
	row_buttons.order_up = button(row,"Move up",func(): move_order(-1))
	row_buttons.order_down = button(row,"Move down",func(): move_order(1))
	move_child(course_page.get_parent(),get_child_count()-1)

func page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",8)
	scroll.add_child(box)
	return box

func label(parent: Node, text: String) -> void:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size",13)
	parent.add_child(node)

func line(parent: Node, title: String, key: String, live := true) -> void:
	var group := VBoxContainer.new()
	parent.add_child(group)
	groups[key] = group
	parent = group
	label(parent,title)
	var node := LineEdit.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	fields[key] = node
	if live: node.text_changed.connect(func(_v): collect())

func choice(parent: Node, title: String, key: String, values: Array, live := true) -> void:
	var group := VBoxContainer.new()
	parent.add_child(group)
	groups[key] = group
	parent = group
	label(parent,title)
	var node := OptionButton.new()
	node.fit_to_longest_item = false
	for value in values:
		var title_text: String = FRIENDLY.get(value,str(value).replace("_"," ").capitalize())
		if value == "any":
			title_text = "Any condition may pass" if key == "condition_mode" else "Meet board conditions (free play)" if key == "kind" else "Any"
		node.add_item(title_text)
		node.set_item_metadata(node.item_count-1,value)
	parent.add_child(node)
	fields[key] = node
	if live: node.item_selected.connect(func(_v): collect())

func coord_field(parent: Node, title: String, key: String, live := true) -> void:
	var group := VBoxContainer.new()
	group.name = title
	parent.add_child(group)
	groups[key] = group
	parent = group
	label(parent,title)
	var row := HBoxContainer.new()
	parent.add_child(row)
	var node := LineEdit.new()
	node.placeholder_text = "q, r"
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(node)
	fields[key] = node
	button(row,"Pick",func(): pick_requested.emit(node))
	button(row,"Clear",func(): node.text = ""; node.text_changed.emit(""))
	if live: node.text_changed.connect(func(_v): collect())

func check(parent: Node, text: String) -> CheckBox:
	var node := CheckBox.new()
	node.text = text
	parent.add_child(node)
	return node

func button(parent: Node, text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func selected(key: String) -> String:
	return str(fields[key].get_item_metadata(fields[key].selected))

func select_value(key: String, value: String) -> void:
	var node: OptionButton = fields[key]
	for index in range(node.item_count):
		if node.get_item_metadata(index) == value: node.select(index); return
	node.select(0)

static func coord_text(value: Variant) -> String:
	if value == null: return ""
	if value is String: return value
	var at := Doc.coord(value)
	return "" if at == Doc.NONE else "%d, %d" % [at.x,at.y]

static func parse_coord(text: String) -> Variant:
	if text.strip_edges().is_empty(): return null
	var pieces := text.replace(" ","").split(",")
	if pieces.size() != 2 or not pieces[0].is_valid_int() or not pieces[1].is_valid_int(): return text
	return [pieces[0].to_int(),pieces[1].to_int()]

func bind(document: Dictionary, value: Dictionary) -> void:
	loading = true
	course = document
	step = value
	substeps_editor.bind(value)
	fields.course_title.text = course.title
	fields.description.text = course.get("description","")
	select_value("category",course.category)
	select_value("opponent_mode",course.get("opponent_mode","scripted"))
	fields.require_victory.set_pressed_no_signal(course.get("require_victory",true))
	fields.gold.value = course.map.gold
	for key in ["id","title","text","task"]: fields[key].text = step.get(key,"")
	fields.read_before_action.set_pressed_no_signal(step.get("read_before_action",false))
	fields.exercise.text = step.get("exercise","")
	fields.count.value = step.get("count",1)
	fields.allow_turns.set_pressed_no_signal(step.get("allow_turns",false))
	fields.wildlife_turn.set_pressed_no_signal(step.get("wildlife_turn",false))
	fields.effect.text = step.get("details",{}).get("effect","")
	fields.matching.text = matching_summary(step.get("criteria",{}))
	select_value("kind",step.kind)
	fields.target.text = coord_text(step.get("target"))
	fields.use_area.set_pressed_no_signal(step.has("targets"))
	fields.highlight.text = coord_text(step.get("highlight"))
	fields.focus.text = coord_text(step.get("focus"))
	var details: Dictionary = step.get("details",{})
	fields.source.text = coord_text(details.get("source"))
	fields.tier.select(int(details.get("tier",0)))
	for key in ["building","spell","outcome"]: select_value(key,details.get(key,"any"))
	fields.state.select(1 if details.get("open",details.get("active",null)) == true else 2 if details.get("open",details.get("active",null)) == false else 0)
	fields.restrict_actions.set_pressed_no_signal(step.get("restrict_actions",true))
	fields.confirm.set_pressed_no_signal(step.get("confirm",false))
	select_value("condition_mode",step.get("condition_mode","all"))
	select_value("cond_type","owner")
	fields.cond_target.text = ""
	fields.op_source.text = ""
	fields.op_target.text = ""
	select_value("op_kind","move")
	fields.cond_value.text = "0"
	fields.cond_faction.text = "0"
	fields.op_faction.text = "1"
	fields.op_value.text = ""
	refresh_lists()
	update_visibility()
	loading = false

func collect() -> void:
	if loading or step.is_empty(): return
	course.title = fields.course_title.text
	course.description = fields.description.text
	course.category = selected("category")
	course.opponent_mode = selected("opponent_mode")
	course.require_victory = fields.require_victory.button_pressed
	var opening_gold := int(fields.gold.value)
	if opening_gold != int(course.map.gold):
		for objective in course.steps:
			if objective.has("setup"): objective.setup.gold = opening_gold
	course.map.gold = opening_gold
	for key in ["id","title","text","task"]: step[key] = fields[key].text
	if fields.exercise.text.strip_edges() == "": step.erase("exercise")
	else: step.exercise = fields.exercise.text.strip_edges()
	step.count = int(fields.count.value)
	step.allow_turns = fields.allow_turns.button_pressed
	step.wildlife_turn = fields.wildlife_turn.button_pressed
	step.kind = selected("kind")
	if fields.read_before_action.button_pressed and step.kind != "read": step.read_before_action = true
	else: step.erase("read_before_action")
	step.target = parse_coord(fields.target.text) if step.kind in Doc.TILE_ACTIONS and not fields.use_area.button_pressed else null
	if step.kind not in Doc.TILE_ACTIONS or not fields.use_area.button_pressed: step.erase("targets")
	elif not step.has("targets"): step.targets = []
	var focus = parse_coord(fields.focus.text)
	if focus == null: step.erase("focus")
	else: step.focus = focus
	var highlight = parse_coord(fields.highlight.text)
	if highlight == null: step.erase("highlight")
	else: step.highlight = highlight
	step.condition_mode = selected("condition_mode")
	step.restrict_actions = fields.restrict_actions.button_pressed
	step.confirm = fields.confirm.button_pressed if step.kind in ["inspect","stats","finance"] else false
	var details := {}
	if step.kind == "status" and fields.effect.text != "": details.effect = fields.effect.text
	if step.kind in ["move","road"]:
		var source = parse_coord(fields.source.text)
		if source != null: details.source = source
		if step.kind == "move" and selected("outcome") != "any": details.outcome = selected("outcome")
	if step.kind == "recruit" and fields.tier.selected > 0: details.tier = fields.tier.selected
	if step.kind == "build" and selected("building") != "any": details.building = selected("building")
	if step.kind == "spell" and selected("spell") != "any": details.spell = selected("spell")
	if step.kind in ["stats","heatmap"] and fields.state.selected > 0: details["open" if step.kind == "stats" else "active"] = fields.state.selected == 1
	step.details = details
	if step.kind == "read":
		step.conditions = []
		step.criteria = {}
		step.opponent = []
		step.count = 1
		step.restrict_actions = false
		step.allow_turns = false
		step.wildlife_turn = false
		fields.count.set_value_no_signal(1)
		fields.restrict_actions.set_pressed_no_signal(false)
		fields.allow_turns.set_pressed_no_signal(false)
		fields.wildlife_turn.set_pressed_no_signal(false)
		fields.confirm.set_pressed_no_signal(false)
		fields.matching.text = matching_summary({})
		refresh_lists()
	update_visibility()
	changed.emit()

func update_visibility() -> void:
	var kind: String = step.get("kind","continue")
	fields.use_area.visible = kind in Doc.TILE_ACTIONS
	groups.target.visible = kind in Doc.TILE_ACTIONS and not fields.use_area.button_pressed
	groups.target_area.visible = kind in Doc.TILE_ACTIONS and fields.use_area.button_pressed
	update_area_summary()
	groups.source.visible = kind in ["move","road"]
	groups.source.get_child(0).text = "Source structure (blank = any)" if kind == "road" else "Source unit (blank = any)"
	fields.wildlife_turn.visible = kind == "end_turn"
	groups.effect.visible = kind == "status"
	fields.confirm.visible = kind in ["inspect","stats","finance"]
	groups.tier.visible = kind == "recruit"
	groups.building.visible = kind == "build"
	groups.spell.visible = kind == "spell"
	groups.outcome.visible = kind == "move"
	groups.state.visible = kind in ["heatmap","stats"]
	var reading := kind == "read"
	fields.read_before_action.visible = not reading
	fields.read_help.visible = reading
	fields.restrict_actions.visible = kind not in ["any","continue","read"]
	fields.matching.visible = not reading
	fields.clear_matching.visible = not reading
	var toggle: CheckButton = groups.goal_more.get_meta("toggle")
	toggle.visible = not reading
	groups.goal_more.visible = not reading and toggle.button_pressed
	set_tab_disabled(2,reading)
	set_tab_disabled(3,reading)
	update_rule_forms()

func refresh_lists() -> void:
	conditions.clear()
	for item in step.get("conditions",[]): conditions.add_item("%s %s : %s (f%d)" % [item.type,coord_text(item.get("target")),str(item.get("value",0)),int(item.get("faction",0))])
	orders.clear()
	for order in step.get("opponent",[]): orders.add_item("f%d %s %s > %s %s" % [int(order.get("faction",1)),order.kind,coord_text(order.get("source")),coord_text(order.get("target")),str(order.get("tier",order.get("building",order.get("spell",""))))])
	update_row_buttons()

func condition_defaults() -> void:
	var kind := selected("cond_type")
	fields.cond_faction.text = "-1" if kind == "victory" else "0"
	fields.cond_value.text = {"unit":"1","building":"city","gold":"10","mana":"1","round":"2","territory":"1","value":"2"}.get(kind,"0")
	if kind in ["mana","round","victory","territory","income"]: fields.cond_target.text = ""
	update_rule_forms()

func select_condition(index: int) -> void:
	var value: Dictionary = step.conditions[index]
	select_value("cond_type",value.type)
	fields.cond_target.text = coord_text(value.get("target"))
	fields.cond_value.text = str(value.get("value",0))
	fields.cond_faction.text = str(value.get("faction",0))
	update_rule_forms()
	update_row_buttons()

func save_condition(update: bool) -> void:
	if update and conditions.get_selected_items().is_empty(): return
	var index: int = conditions.get_selected_items()[0] if update else step.get("conditions",[]).size()
	var value: Variant = fields.cond_value.text
	if selected("cond_type") != "building" and fields.cond_value.text.is_valid_int(): value = fields.cond_value.text.to_int()
	var faction: Variant = fields.cond_faction.text.to_int() if fields.cond_faction.text.is_valid_int() else fields.cond_faction.text
	var condition := {"type":selected("cond_type"),"target":parse_coord(fields.cond_target.text),"value":value,"faction":faction}
	if not step.has("conditions"): step.conditions = []
	if update and not conditions.get_selected_items().is_empty(): step.conditions[conditions.get_selected_items()[0]] = condition
	elif not update: step.conditions.append(condition)
	refresh_lists()
	conditions.select(index)
	select_condition(index)
	changed.emit()

func remove_condition() -> void:
	if conditions.get_selected_items().is_empty(): return
	step.conditions.remove_at(conditions.get_selected_items()[0])
	refresh_lists()
	changed.emit()

func select_order(index: int) -> void:
	var order: Dictionary = step.opponent[index]
	select_value("op_kind",order.kind)
	fields.op_faction.text = str(order.get("faction",1))
	fields.op_source.text = coord_text(order.get("source"))
	fields.op_target.text = coord_text(order.get("target"))
	fields.op_value.text = str(order.get("tier",order.get("building",order.get("spell",""))))
	update_rule_forms()
	update_row_buttons()

func save_order(update: bool) -> void:
	if update and orders.get_selected_items().is_empty(): return
	var index: int = orders.get_selected_items()[0] if update else step.get("opponent",[]).size()
	var order := {"kind":selected("op_kind"),"target":parse_coord(fields.op_target.text),"faction":fields.op_faction.text.to_int()}
	if order.kind == "move": order.source = parse_coord(fields.op_source.text)
	if order.kind == "recruit": order.tier = fields.op_value.text.to_int()
	if order.kind == "build": order.building = fields.op_value.text
	if order.kind == "spell": order.spell = fields.op_value.text
	if not step.has("opponent"): step.opponent = []
	if update and not orders.get_selected_items().is_empty(): step.opponent[orders.get_selected_items()[0]] = order
	elif not update: step.opponent.append(order)
	refresh_lists()
	orders.select(index)
	select_order(index)
	changed.emit()

func remove_order() -> void:
	if orders.get_selected_items().is_empty(): return
	step.opponent.remove_at(orders.get_selected_items()[0])
	refresh_lists()
	changed.emit()

func move_order(direction: int) -> void:
	if orders.get_selected_items().is_empty(): return
	var index := orders.get_selected_items()[0]
	var next := index+direction
	if next < 0 or next >= step.opponent.size(): return
	var value = step.opponent.pop_at(index)
	step.opponent.insert(next,value)
	refresh_lists()
	orders.select(next)
	update_row_buttons()
	changed.emit()

func matching_summary(criteria: Dictionary) -> String:
	if criteria.is_empty(): return "No extra matching restrictions."
	var lines: PackedStringArray = []
	for key in criteria:
		var value = criteria[key]
		match key:
			"animal_before": lines.append("Predator before capture: %s" % str(value).capitalize())
			"owner_before": lines.append("Previously neutral land" if int(value) == -1 else "Previously owned by faction %d" % int(value))
			"plain":
				if value: lines.append("Empty ordinary land: no objects or rewards")
			"unit_before","unit","source_tier":
				var rank: String = ["No army","Scout","Soldier","Knight"][int(value)]
				lines.append({"unit_before":"Before action: %s","unit":"Current army: %s","source_tier":"Moving army: %s"}[key] % rank)
			"value_before": lines.append("Previous province value: %d" % int(value))
			"min_value": lines.append("Minimum province value: %d" % int(value))
			"building": lines.append("Current building: %s" % str(value).capitalize())
	return "Matching restrictions:\n" + "\n".join(lines)

func update_rule_forms() -> void:
	var kind := selected("cond_type")
	groups.cond_target.visible = kind in ["owner","unit","building","gold","value","clear","entrenched","isolated","no_unit"]
	groups.cond_value.visible = kind not in ["clear","entrenched","victory","isolated","no_unit"]
	groups.cond_faction.visible = kind in ["unit","gold","mana","victory","entrenched","isolated","territory","income"]
	groups.cond_value.get_child(0).text = "Building (city, tower, bridge, road)" if kind == "building" else "Owner ID (-1 neutral, 0 player, 1–5 opponents)" if kind == "owner" else "Minimum required"
	groups.cond_target.get_child(0).text = "Kingdom tile (blank = faction total)" if kind == "gold" else "Condition tile"
	var order := selected("op_kind")
	groups.op_source.visible = order == "move"
	groups.op_value.visible = order in ["recruit","build","spell"]
	groups.op_value.get_child(0).text = {"recruit":"Army rank (1 Scout, 2 Soldier, 3 Knight)","build":"Building (city, tower, bridge)","spell":"Spell (trailblaze, summon, shatter)"}.get(order,"Parameter")

func update_row_buttons() -> void:
	var condition_selected := not conditions.get_selected_items().is_empty()
	row_buttons.condition_update.disabled = not condition_selected
	row_buttons.condition_remove.disabled = not condition_selected
	var selected_orders := orders.get_selected_items()
	row_buttons.order_update.disabled = selected_orders.is_empty()
	row_buttons.order_remove.disabled = selected_orders.is_empty()
	row_buttons.order_up.disabled = selected_orders.is_empty() or selected_orders[0] == 0
	row_buttons.order_down.disabled = selected_orders.is_empty() or selected_orders[0] == orders.item_count-1

func fold(parent: Node, title: String) -> VBoxContainer:
	var toggle := CheckButton.new()
	toggle.text = title
	parent.add_child(toggle)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation",8)
	parent.add_child(contents)
	contents.hide()
	contents.set_meta("toggle",toggle)
	toggle.toggled.connect(func(open): contents.visible = open)
	return contents

func area_mode_changed(enabled: bool) -> void:
	if loading: return
	if enabled:
		var target = parse_coord(fields.target.text)
		step.targets = [target] if target != null and Doc.valid_coord(target) else []
	else:
		fields.target.text = coord_text(step.get("targets",[])[0]) if not step.get("targets",[]).is_empty() else ""
	collect()

func update_area_summary() -> void:
	var count: int = step.get("targets",[]).size()
	fields.area_summary.text = "%d hex%s selected" % [count,"" if count == 1 else "es"]
