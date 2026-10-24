extends RefCounted
## Serializable authoring document; vectors are encoded as [q, r] in files.
const Level = preload("res://src/editor/level_document.gd")
const NONE := Vector2i(999,999)
const ACTIONS := ["continue","any","recruit","move","build","spell","end_turn","select","inspect","develop","entrench","relocate_capital","event","view","heatmap","stats","finance","status","kingdom","animal"]
const PREDICATES := ["owner","unit","building","gold","mana","round","victory","value","clear","entrenched","territory","income"]
const ORDERS := ["move","recruit","build","spell","entrench","develop"]
const MAX_BYTES := 8000000
const CATEGORIES := ["armies","economy","construction","conquest","magic","exploration","practice"]
var data: Dictionary = {}
var path := ""
var saved := ""

static func new_step() -> Dictionary:
	return {"id":"step_1","title":"New step","text":"","task":"","kind":"continue","target":null,"details":{},"conditions":[],"condition_mode":"all","restrict_actions":false,"opponent":[]}

static func encode(value: Variant) -> Variant:
	if value is Vector2i: return null if value == NONE else [value.x,value.y]
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = encode(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(encode(item))
		return result
	return value

static func coord(value: Variant) -> Vector2i:
	return Vector2i(int(value[0]),int(value[1])) if value is Array and value.size() == 2 else value if value is Vector2i else NONE

static func valid_coord(value: Variant) -> bool:
	if value == null: return true
	if not value is Array or value.size() != 2: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(number) or number != int(number) or abs(number) > 100: return false
	return true

static func validate(value: Variant) -> String:
	if not value is Dictionary or value.get("format") != "slay-tutorial" or value.get("version") != 1: return "Unsupported tutorial file."
	if not value.get("title") is String or value.title.strip_edges().is_empty() or value.title.length() > 120: return "Give the tutorial a title (up to 120 characters)."
	if not value.get("description","") is String or value.get("description","").length() > 200: return "Keep the menu description under 200 characters."
	if value.get("category") not in CATEGORIES: return "Choose a tutorial topic."
	if value.get("opponent_mode","scripted") not in ["scripted","ai","idle"]: return "Unknown opponent mode."
	if not value.get("require_victory",true) is bool: return "Victory requirement must be a checkbox."
	var level := Level.new()
	var error := level.read_data(value.get("map"))
	if error != "": return "Map: " + error
	var rules = level.build_rules()
	if rules.territory(0) < 2: return "The map needs a player kingdom owned by Fern (owner 0)."
	if not value.get("steps") is Array or value.steps.is_empty() or value.steps.size() > 200: return "Use between 1 and 200 steps."
	var ids := {}
	for index in range(value.steps.size()):
		var step = value.steps[index]
		var prefix := "Step %d: " % (index+1)
		if not step is Dictionary: return prefix + "Invalid step."
		for field in ["id","title","text","task"]:
			if not step.get(field) is String or step[field].length() > {"id":80,"title":100,"text":4000,"task":160}[field]: return prefix + "Invalid " + field
		if step.id.strip_edges().is_empty() or ids.has(step.id): return prefix + "Step IDs must be unique and nonempty."
		if not step.get("exercise",step.id) is String: return prefix + "Exercise must have a name."
		if not integer(step.get("count",1),1,20): return prefix + "Objective count must be between 1 and 20."
		if not step.get("wildlife_turn",false) is bool: return prefix + "Wildlife turn must be a checkbox."
		if not step.get("allow_turns",false) is bool: return prefix + "Turn permission must be a checkbox."
		if step.has("setup"):
			var setup_error := Level.new().read_data(step.setup)
			if setup_error != "": return prefix + "Practice position: " + setup_error
		if not step.get("criteria",{}) is Dictionary: return prefix + "Invalid objective criteria."
		for key in step.get("criteria",{}):
			var expected = step.criteria[key]
			match key:
				"animal_before":
					if expected not in ["bear","wolf","boar"]: return prefix + "Unknown predator."
				"owner_before":
					if not integer(expected,-1,rules.faction_count-1): return prefix + "Invalid previous owner."
				"unit_before","unit","source_tier":
					if not integer(expected,0,3): return prefix + "Invalid objective rank."
				"value_before","min_value":
					if not integer(expected,1,6): return prefix + "Invalid objective value."
				"plain":
					if not expected is bool: return prefix + "Plain land must be a checkbox."
				"building":
					if expected not in ["house","tower","bridge","monument",""]: return prefix + "Invalid objective building."
				_: return prefix + "Unknown objective criterion."
		ids[step.id] = true
		if step.get("kind") not in ACTIONS or not valid_coord(step.get("target")): return prefix + "Invalid action or target coordinates."
		if not valid_coord(step.get("highlight")): return prefix + "Invalid highlight tile."
		if not valid_coord(step.get("focus")): return prefix + "Invalid camera focus tile."
		if not step.get("details",{}) is Dictionary: return prefix + "Invalid action options."
		if not valid_coord(step.get("details",{}).get("source")): return prefix + "Invalid source coordinates."
		if step.get("condition_mode","all") not in ["all","any"] or not step.get("restrict_actions",true) is bool: return prefix + "Invalid condition options."
		if not step.get("confirm",false) is bool: return prefix + "Continue confirmation must be a checkbox."
		if step.get("confirm",false) and step.kind not in ["inspect","stats"]: return prefix + "Continue confirmation is available for inspection and Stats."
		if not step.get("conditions",[]) is Array or step.get("conditions",[]).size() > 30: return prefix + "Too many conditions."
		for condition in step.get("conditions",[]):
			if not condition is Dictionary or condition.get("type") not in PREDICATES or not valid_coord(condition.get("target")): return prefix + "Invalid board condition."
			if condition.type in ["owner","unit","building","value","clear","entrenched"] and condition.get("target") == null: return prefix + "This board condition needs a tile."
			if not integer(condition.get("faction",0),-1 if condition.type == "victory" else 0,rules.faction_count-1): return prefix + "Invalid condition faction."
			if condition.type == "building":
				if condition.get("value") not in ["","house","tower","bridge"]: return prefix + "Unknown condition building."
			elif not integer(condition.get("value",0),-1,99999): return prefix + "Condition value must be a whole number."
			if condition.type == "unit" and not integer(condition.get("value"),1,3): return prefix + "A unit condition needs tier 1, 2 or 3."
			if condition.type == "owner" and not integer(condition.get("value"),-1,rules.faction_count-1): return prefix + "An owner condition needs faction -1 through 5."
		if step.kind == "any" and step.get("conditions",[]).is_empty(): return prefix + "A board-state step needs at least one condition."
		if not step.get("opponent",[]) is Array or step.get("opponent",[]).size() > 100: return prefix + "Invalid opponent orders."
		for order in step.get("opponent",[]):
			if not order is Dictionary or order.get("kind") not in ORDERS or not valid_coord(order.get("target")) or order.get("target") == null or not valid_coord(order.get("source")): return prefix + "Invalid opponent order."
			if not integer(order.get("faction",1),1,rules.faction_count-1): return prefix + "Opponent faction must be 1 through 5."
			if order.kind == "move" and order.get("source") == null: return prefix + "An opponent move needs a source tile."
			var option_error := validate_options(order)
			if option_error != "": return prefix + option_error
		if not step.get("opponent",[]).is_empty() and step.kind != "end_turn": return prefix + "Opponent orders belong on an End turn step."
		var option_error := validate_options(step.get("details",{}))
		if option_error != "": return prefix + option_error
	return ""

static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value == int(value) and value >= minimum and value <= maximum

static func validate_options(options: Dictionary) -> String:
	if options.has("tier") and not integer(options.tier,1,3): return "Unit tier must be 1, 2 or 3."
	if options.has("building") and options.building not in ["house","tower","bridge"]: return "Unknown building."
	if options.has("spell") and options.spell not in ["trailblaze","summon","shatter"]: return "Unknown spell."
	if options.has("outcome") and options.outcome not in ["move","attack","merge","blocked_attack","knight_duel"]: return "Unknown movement outcome."
	if options.has("open") and not options.open is bool: return "Open/active must be a checkbox."
	if options.has("active") and not options.active is bool: return "Open/active must be a checkbox."
	return ""

func read_data(value: Variant) -> String:
	var error := validate(value)
	if error != "": return error
	data = value.duplicate(true)
	saved = JSON.stringify(data)
	return ""

func load_file(filename: String) -> String:
	if not FileAccess.file_exists(filename): return "File does not exist."
	var file := FileAccess.open(filename,FileAccess.READ)
	if file == null: return "Cannot open file: " + error_string(FileAccess.get_open_error())
	if file.get_length() > MAX_BYTES: return "Tutorial file is too large."
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK: return "JSON line %d: %s" % [json.get_error_line(),json.get_error_message()]
	var error := read_data(json.data)
	if error == "": path = filename
	return error

func save_file(filename: String) -> String:
	var error := validate(data)
	if error != "": return error
	error = write_atomic(filename,data)
	if error == "":
		path = filename
		saved = JSON.stringify(data)
	return error

static func write_atomic(filename: String, value: Dictionary) -> String:
	var temporary := filename + ".%d.tmp" % Time.get_ticks_usec()
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return "Cannot write: " + error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(value,"\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary,filename)
	if error != OK: DirAccess.remove_absolute(temporary)
	return "" if error == OK else error_string(error)

func dirty() -> bool:
	return JSON.stringify(data) != saved

func runtime_steps() -> Array:
	var result: Array = data.steps.duplicate(true)
	for step in result:
		step.target = coord(step.get("target"))
		if step.has("highlight"): step.highlight = coord(step.highlight)
		if step.has("focus"): step.focus = coord(step.focus)
		if step.get("details",{}).has("source"): step.details.source = coord(step.details.source)
		for condition in step.get("conditions",[]): condition.target = coord(condition.get("target"))
		for order in step.get("opponent",[]):
			order.target = coord(order.target)
			if order.has("source"): order.source = coord(order.source)
	return result

func level_data() -> Dictionary:
	var result: Dictionary = data.map.duplicate(true)
	result["tutorial"] = true
	result["tutorial_category"] = data.category
	result["tutorial_title"] = data.title
	result["tutorial_steps"] = runtime_steps()
	result["tutorial_opponent_mode"] = data.get("opponent_mode","scripted")
	result["tutorial_require_victory"] = data.get("require_victory",true)
	result["tutorial_custom"] = true
	return result
