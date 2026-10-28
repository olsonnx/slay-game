extends TabContainer
## Text and rule forms edit plain document dictionaries; no game state lives here.
signal changed
signal pick_requested(field: LineEdit)
const Doc = preload("res://src/tutorial_editor/tutorial_document.gd")
var fields: Dictionary = {}
var groups: Dictionary = {}
var step: Dictionary = {}
var course: Dictionary = {}
var loading := true
var conditions: ItemList
var orders: ItemList

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
	line(text_page,"Step ID","id")
	line(text_page,"Exercise group (blank = individual objective)","exercise")
	line(text_page,"Heading","title")
	label(text_page,"Explanation")
	var text := TextEdit.new()
	text.custom_minimum_size.y = 120
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_page.add_child(text)
	fields.text = text
	text.text_changed.connect(collect)
	line(text_page,"Short objective","task")
	coord_field(text_page,"Highlight tile (optional)","highlight")
	coord_field(text_page,"Camera focus tile (optional)","focus")
	var goal_page := page("Goal")
	choice(goal_page,"Advance after","kind",Doc.ACTIONS)
	coord_field(goal_page,"Target tile (blank = any)","target")
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
	label(goal_page,"Required actions (different capture tiles count once each)")
	fields.count = SpinBox.new()
	fields.count.min_value = 1
	fields.count.max_value = 20
	goal_page.add_child(fields.count)
	fields.count.value_changed.connect(func(_v): collect())
	fields.allow_turns = check(goal_page,"Allow End turn during this objective")
	fields.allow_turns.toggled.connect(func(_v): collect())
	fields.wildlife_turn = check(goal_page,"Run wildlife during this End turn")
	fields.wildlife_turn.toggled.connect(func(_v): collect())
	line(goal_page,"Status icon (effect ID)","effect")
	fields.matching = Label.new()
	fields.matching.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_page.add_child(fields.matching)
	button(goal_page,"Clear extra matching restrictions",func(): step["criteria"] = {}; fields.matching.text = "No extra matching restrictions."; changed.emit())
	var conditions_page := page("Conditions")
	label(conditions_page,"Conditions must pass as well as the selected action. Use any to watch the board during free play.")
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
	button(row,"Update",func(): save_condition(true))
	button(row,"Remove",remove_condition)
	label(conditions_page,"Board conditions: unit/value/gold/mana/round/territory/income use at least. Owner and building use equality. Continue waits for a click; any watches conditions while allowing free play.")
	var enemy_page := page("Opponent")
	label(enemy_page,"Orders run in sequence on this End turn step. Select scripted opponent turns to use them. Factions: 1 Ember, 2 Tide, 3 Ochre, 4 Aster, 5 Cove.")
	orders = ItemList.new()
	orders.custom_minimum_size.y = 140
	enemy_page.add_child(orders)
	orders.item_selected.connect(select_order)
	choice(enemy_page,"Order","op_kind",Doc.ORDERS,false)
	fields.op_kind.item_selected.connect(func(_index): fields.op_value.text = {"recruit":"1","build":"city","spell":"summon"}.get(selected("op_kind"),""))
	line(enemy_page,"Faction","op_faction",false)
	coord_field(enemy_page,"From","op_source",false)
	coord_field(enemy_page,"To","op_target",false)
	line(enemy_page,"Parameter (tier / building / spell)","op_value",false)
	row = HBoxContainer.new()
	enemy_page.add_child(row)
	button(row,"Add",func(): save_order(false))
	button(row,"Update",func(): save_order(true))
	button(row,"Remove",remove_order)
	row = HBoxContainer.new()
	enemy_page.add_child(row)
	button(row,"Move up",func(): move_order(-1))
	button(row,"Move down",func(): move_order(1))
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
	for value in values: node.add_item(value)
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
	if live: node.text_changed.connect(func(_v): collect())

func check(parent: Node, text: String) -> CheckBox:
	var node := CheckBox.new()
	node.text = text
	parent.add_child(node)
	return node

func button(parent: Node, text: String, callback: Callable) -> void:
	var node := Button.new()
	node.text = text
	node.pressed.connect(callback)
	parent.add_child(node)

func selected(key: String) -> String:
	return fields[key].get_item_text(fields[key].selected)

func select_value(key: String, value: String) -> void:
	var node: OptionButton = fields[key]
	for index in range(node.item_count):
		if node.get_item_text(index) == value: node.select(index); return
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
	fields.course_title.text = course.title
	fields.description.text = course.get("description","")
	select_value("category",course.category)
	select_value("opponent_mode",course.get("opponent_mode","scripted"))
	fields.require_victory.set_pressed_no_signal(course.get("require_victory",true))
	fields.gold.value = course.map.gold
	for key in ["id","title","text","task"]: fields[key].text = step.get(key,"")
	fields.exercise.text = step.get("exercise","")
	fields.count.value = step.get("count",1)
	fields.allow_turns.set_pressed_no_signal(step.get("allow_turns",false))
	fields.wildlife_turn.set_pressed_no_signal(step.get("wildlife_turn",false))
	fields.effect.text = step.get("details",{}).get("effect","")
	fields.matching.text = matching_summary(step.get("criteria",{}))
	select_value("kind",step.kind)
	fields.target.text = coord_text(step.get("target"))
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
	fields.cond_value.text = "0"
	fields.cond_faction.text = "0"
	fields.op_faction.text = "1"
	fields.op_value.text = "1"
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
	course.map.gold = int(fields.gold.value)
	if course.steps[0].has("setup"): course.steps[0].setup.gold = course.map.gold
	for key in ["id","title","text","task"]: step[key] = fields[key].text
	if fields.exercise.text.strip_edges() == "": step.erase("exercise")
	else: step.exercise = fields.exercise.text.strip_edges()
	step.count = int(fields.count.value)
	step.allow_turns = fields.allow_turns.button_pressed
	step.wildlife_turn = fields.wildlife_turn.button_pressed
	step.kind = selected("kind")
	step.target = parse_coord(fields.target.text) if step.kind in ["recruit","move","build","spell","select","inspect","develop","entrench","relocate_capital","road","rename_settlement","kingdom","animal"] else null
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
	update_visibility()
	changed.emit()

func update_visibility() -> void:
	var kind: String = step.get("kind","continue")
	groups.target.visible = kind in ["recruit","move","build","spell","select","inspect","develop","entrench","relocate_capital","road","rename_settlement","kingdom","animal"]
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
	fields.restrict_actions.visible = kind not in ["any","continue"]

func refresh_lists() -> void:
	conditions.clear()
	for item in step.get("conditions",[]): conditions.add_item("%s %s : %s (f%d)" % [item.type,coord_text(item.get("target")),str(item.get("value",0)),int(item.get("faction",0))])
	orders.clear()
	for order in step.get("opponent",[]): orders.add_item("f%d %s %s > %s" % [int(order.get("faction",1)),order.kind,coord_text(order.get("source")),coord_text(order.get("target"))])

func condition_defaults() -> void:
	var kind := selected("cond_type")
	fields.cond_faction.text = "-1" if kind == "victory" else "0"
	fields.cond_value.text = {"unit":"1","building":"city","gold":"10","mana":"1","round":"2","territory":"1","value":"2"}.get(kind,"0")
	if kind in ["mana","round","victory","territory","income"]: fields.cond_target.text = ""

func select_condition(index: int) -> void:
	var value: Dictionary = step.conditions[index]
	select_value("cond_type",value.type)
	fields.cond_target.text = coord_text(value.get("target"))
	fields.cond_value.text = str(value.get("value",0))
	fields.cond_faction.text = str(value.get("faction",0))

func save_condition(update: bool) -> void:
	var value: Variant = fields.cond_value.text
	if selected("cond_type") != "building" and fields.cond_value.text.is_valid_int(): value = fields.cond_value.text.to_int()
	var faction: Variant = fields.cond_faction.text.to_int() if fields.cond_faction.text.is_valid_int() else fields.cond_faction.text
	var condition := {"type":selected("cond_type"),"target":parse_coord(fields.cond_target.text),"value":value,"faction":faction}
	if not step.has("conditions"): step.conditions = []
	if update and not conditions.get_selected_items().is_empty(): step.conditions[conditions.get_selected_items()[0]] = condition
	elif not update: step.conditions.append(condition)
	refresh_lists()
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

func save_order(update: bool) -> void:
	var order := {"kind":selected("op_kind"),"target":parse_coord(fields.op_target.text),"faction":fields.op_faction.text.to_int()}
	if order.kind == "move": order.source = parse_coord(fields.op_source.text)
	if order.kind == "recruit": order.tier = fields.op_value.text.to_int()
	if order.kind == "build": order.building = fields.op_value.text
	if order.kind == "spell": order.spell = fields.op_value.text
	if not step.has("opponent"): step.opponent = []
	if update and not orders.get_selected_items().is_empty(): step.opponent[orders.get_selected_items()[0]] = order
	elif not update: step.opponent.append(order)
	refresh_lists()
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
