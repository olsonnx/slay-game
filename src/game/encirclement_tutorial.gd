extends RefCounted
## A single shared teaching board: remove a Knight's last connection, not the Knight.
const Loc = preload("res://src/localization/text.gd")
const Level = preload("res://src/editor/level_document.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const Doc = preload("res://src/tutorial_editor/tutorial_document.gd")
const SOURCE := Vector2i(0,1)
const CONNECTION := Vector2i(2,0)
const ENEMY := Vector2i(1,0)
const CAPITAL := Vector2i(5,0)

static func map_data() -> Dictionary:
	var level := Level.new()
	level.title = Loc.text("Cutting off armies")
	level.map_size = "small"
	level.seed_value = 73022
	level.starting_gold = 100
	for q in range(-3,1):
		for r in range(-1,2): add_tile(level,Vector2i(q,r),0)
	for at in [Vector2i(1,-1),Vector2i(2,-1),Vector2i(1,1)]: add_tile(level,at,0)
	for q in range(3,6):
		for r in range(-1,2): add_tile(level,Vector2i(q,r),1)
	for at in [CONNECTION,ENEMY]: add_tile(level,at,1)
	level.cells[Vector2i(-3,0)].capital = 0
	level.cells[CAPITAL].capital = 1
	level.cells[SOURCE].unit = 3
	level.cells[ENEMY].unit = 3
	level.player_start = Vector2i(-3,0)
	return level.state()

static func add_tile(level, at: Vector2i, faction: int) -> void:
	var cell: Dictionary = Rules.new().make_cell(faction)
	cell.value = 2
	level.cells[at] = cell

static func lesson(id: String, title: String, text: String, kind := "read", target: Variant = null, details: Dictionary = {}) -> Dictionary:
	var step := Doc.new_step()
	step.merge({"id":id,"title":title,"task":title,"text":text,"kind":kind,"target":target,"details":details,"exercise":"encirclement","restrict_actions":kind != "read"},true)
	return step

static func authored_steps() -> Array:
	var opening := lesson("supply",Loc.text("Cutting off an army"),Loc.text("Units need a connection to their kingdom to survive. You can defeat a strong unit by cutting off its land instead of attacking it."))
	opening.setup = map_data()
	opening.highlight = [ENEMY.x,ENEMY.y]
	opening.substeps = [{"title":"","text":Loc.text("The enemy Knight has only one connection to the rest of its kingdom. Capture that connection and it will be left on a single tile, without a treasury to support it.")}]
	var inspect := lesson("inspect_knight",Loc.text("Inspect the enemy Knight"),Loc.text("Click the gold-ringed Knight to inspect it. Its land is still connected to Ember's capital through the narrow strip on its right. Read its details, then click Continue."),"inspect",[ENEMY.x,ENEMY.y])
	inspect.confirm = true
	var cut := lesson("cut_connection",Loc.text("Cut the connection"),Loc.text("Click your blue-ringed Knight, then the gold-ringed land behind the enemy Knight. Conquering that tile removes its last connection to the kingdom."),"move",[CONNECTION.x,CONNECTION.y],{"source":[SOURCE.x,SOURCE.y]})
	cut.read_before_action = true
	cut.criteria = {"owner_before":1}
	cut.conditions = [{"type":"isolated","target":[ENEMY.x,ENEMY.y],"faction":1},{"type":"unit","target":[ENEMY.x,ENEMY.y],"faction":1,"value":3}]
	var isolated := lesson("isolated",Loc.text("Cut off, but still alive"),Loc.text("The enemy Knight is surrounded by your land now. It is still on the map, but has no kingdom to pay for it. It will die at the start of Ember's next turn."))
	isolated.highlight = [ENEMY.x,ENEMY.y]
	isolated.substeps = [{"title":"","text":Loc.text("Cutting a border is not always enough. A larger pocket of connected land can form its own kingdom. Here, the Knight is left on just one tile, which cannot support it.")}]
	var wait := lesson("wait_for_isolation",Loc.text("End turn to remove the Knight"),Loc.text("End your turn. Ember's turn comes next, and its unsupported Knight will disappear. You do not need to attack it."),"end_turn")
	wait.read_before_action = true
	wait.highlight = [ENEMY.x,ENEMY.y]
	wait.conditions = [{"type":"no_unit","target":[ENEMY.x,ENEMY.y]}]
	var finish := lesson("positioning",Loc.text("Win with positioning"),Loc.text("The enemy Knight is gone, while yours survived. Look for narrow connections before attacking a strong army. The same can happen to your units - keep them connected to a kingdom."))
	finish.highlight = [ENEMY.x,ENEMY.y]
	return [opening,inspect,cut,isolated,wait,finish]

static func runtime_steps() -> Array:
	var document := Doc.new()
	document.data = {"steps":authored_steps()}
	return document.runtime_steps()
