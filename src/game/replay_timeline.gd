extends RefCounted
## Read-only reconstruction. No rules, AI, RNG or recorder is run by the viewer.
const Replay = preload("res://src/game/replay_log.gd")
var header: Dictionary = {}
var commands: Array = []
var steps: Array[int] = [0]
var cursor := 0
var applied := 0
var position: Dictionary = {}
const MAX_CHECKPOINTS := 32
var checkpoint_interval := 64
var checkpoints: Dictionary = {}
var patches: Array[Dictionary] = []
var reverse_patches: Array[Dictionary] = []
var last_seek_patches := 0
var all_steps: Array[int] = [0]
var movement_steps: Array[int] = [0]
var movement_only := false

func open(data: Dictionary, cancelled := Callable()) -> String:
	if data.get("error", "Invalid replay") != "": return data.get("error", "Invalid replay")
	var initial = Replay.decode(data["header"]["initial"])
	if not initial is Dictionary or not valid_cells(initial.get("cells")): return "This replay has an unsupported board."
	header = data["header"].duplicate(true)
	commands = data["commands"]
	steps = [0]
	all_steps = [0]
	movement_steps = [0]
	movement_only = false
	patches.clear()
	reverse_patches.clear()
	checkpoints.clear()
	checkpoint_interval = maxi(64, ceili(float(commands.size()) / MAX_CHECKPOINTS))
	var working: Dictionary = Replay.copy_index(initial)
	checkpoints[0] = Replay.copy_index(working)
	for index in range(commands.size()):
		if cancelled.is_valid() and cancelled.call(): return "Replay loading cancelled"
		var patch: Dictionary = Replay.decode(commands[index]["delta"])
		var cell_patch: Dictionary = patch.get("cells", {})
		if cell_patch.has("value") or not valid_cells(cell_patch.get("set", {})): return "This replay has an unsupported board."
		patches.append(patch)
		reverse_patches.append(invert_patch(working, patch))
		apply_patch(working, patch)
		if (index + 1) % checkpoint_interval == 0:
			checkpoints[index + 1] = Replay.copy_index(working)
		# Diagnostic records have no state changes and need no screen time.
		if commands[index]["action"] != "ai_decision": all_steps.append(index + 1)
		if commands[index]["action"] == "move" or commands[index]["action"].begins_with("wildlife_"): movement_steps.append(index + 1)
	# Keep even a diagnostic-only tail reconstructable.
	if all_steps[-1] != commands.size(): all_steps.append(commands.size())
	# The final position remains reachable even if settlement follows the last move.
	if movement_steps[-1] != commands.size(): movement_steps.append(commands.size())
	steps = all_steps
	cursor = 0
	applied = 0
	position = Replay.copy_index(initial)
	return ""

func set_movement_only(enabled: bool) -> void:
	var anchor := applied
	movement_only = enabled
	steps = movement_steps if enabled else all_steps
	var index := steps.bsearch(anchor)
	if index >= steps.size() or steps[index] > anchor: index -= 1
	seek(maxi(0, index))

func before_step(step: int) -> Dictionary:
	var target := maxi(0, steps[clampi(step, 0, steps.size() - 1)] - 1)
	var checkpoint: int = (target / checkpoint_interval) * checkpoint_interval
	var result := Replay.copy_index(checkpoints[checkpoint])
	for index in range(checkpoint, target): apply_patch(result, patches[index])
	return result

static func invert_patch(before: Dictionary, patch: Dictionary) -> Dictionary:
	var result := {}
	for section in patch:
		var change: Dictionary = patch[section]
		if change.has("value"):
			result[section] = {"value":before[section]}
		else:
			var restore := {}
			var erase: Array = []
			for key in change["set"]:
				if before[section].has(key): restore[key] = before[section][key]
				else: erase.append(key)
			for key in change["erase"]:
				if before[section].has(key): restore[key] = before[section][key]
			result[section] = {"set":restore, "erase":erase}
	return result

static func apply_patch(target: Dictionary, patch: Dictionary) -> void:
	# Patches have already passed the archive reader's complete validation.
	# Values are immutable; only the top-level section indexes are private.
	for section in patch:
		var change: Dictionary = patch[section]
		if change.has("value"): target[section] = change["value"]
		else:
			for key in change["erase"]: target[section].erase(key)
			for key in change["set"]: target[section][key] = change["set"][key]

static func valid_cells(cells) -> bool:
	if not cells is Dictionary: return false
	for coord in cells:
		var cell = cells[coord]
		if not coord is Vector2i or not cell is Dictionary: return false
		for field in ["owner", "unit", "capital"]:
			if not cell.get(field) is int: return false
		for field in ["moved", "tree", "grave"]:
			if not cell.get(field) is bool: return false
		if not cell.get("building") is String: return false
		if cell.owner < -1 or cell.owner >= 12 or cell.capital < -1 or cell.capital >= 12 or cell.unit < 0 or cell.unit > 3: return false
		if int(cell.get("unit_owner", -1)) < -1 or int(cell.get("unit_owner", -1)) >= 12: return false
		for field in ["animal","lair"]:
			if cell.get(field, "") not in ["","bear","wolf","boar"]: return false
		if cell.get("animal", "") != "" and not cell.get("animal_home") is Vector2i: return false
		if cell.has("animal_target") and (cell.get("animal", "") == "" or not cell.animal_target is Vector2i): return false
		if cell.has("lair_wait") and (not cell.lair_wait is int or cell.lair_wait < 0 or cell.lair_wait > 3): return false
	return true

func wildlife_action(before: Dictionary) -> Dictionary:
	var row := current_command()
	var action: String = row.get("action", "")
	if not action.begins_with("wildlife_"): return {}
	var args: Dictionary = Replay.decode(row["args"])
	if not before.has(args.get("source")) or not before.has(args.get("target")): return {}
	var changes := {}
	for coord in position.cells:
		if before.get(coord) != position.cells[coord]: changes[coord] = position.cells[coord].duplicate(true)
	return {"source":args.source,"target":args.target,"home":args.home,"animal":args.animal,"kind":action.trim_prefix("wildlife_"),"changes":changes,"alert":args.get("alert",false),"aggro_target":args.get("aggro_target",Vector2i(999,999))}

func seek(step: int) -> void:
	cursor = clampi(step, 0, steps.size() - 1)
	var target := steps[cursor]
	last_seek_patches = 0
	if target == applied: return
	var checkpoint: int = (target / checkpoint_interval) * checkpoint_interval
	if absi(target - applied) > target - checkpoint:
		position = Replay.copy_index(checkpoints[checkpoint])
		applied = checkpoint
	else:
		position = Replay.copy_index(position)
	while applied > target:
		applied -= 1
		apply_patch(position, reverse_patches[applied])
		last_seek_patches += 1
	while applied < target:
		apply_patch(position, patches[applied])
		applied += 1
		last_seek_patches += 1

func current_command() -> Dictionary:
	return commands[applied - 1] if applied > 0 else {}

func movement(before: Dictionary) -> Dictionary:
	var row := current_command()
	if row.get("action") != "move": return {}
	var args: Dictionary = Replay.decode(row["args"])
	var source = args.get("source")
	var target = args.get("target")
	var after: Dictionary = position["cells"]
	if not before.has(source) or not before.has(target) or not after.has(source) or not after.has(target): return {}
	var path = args.get("path", [])
	if not path is Array or path.size() < 2 or before[source]["unit"] <= 0: return {}
	for coord in path:
		if not coord is Vector2i: return {}
	var kind: String = args.get("outcome", "move")
	if kind not in ["move", "attack", "merge", "blocked_attack", "knight_duel"]: return {}
	var action := {"kind":kind, "source":source, "target":target, "path":path,
		"faction":int(row["faction"]), "before_source":before[source].duplicate(true),
		"before_target":before[target].duplicate(true), "after_source":after[source].duplicate(true),
		"after_target":after[target].duplicate(true), "capture":before[target]["owner"] != after[target]["owner"], "annexed":{}}
	for coord in after:
		if coord != target and before.has(coord) and before[coord]["owner"] != after[coord]["owner"]:
			action["annexed"][coord] = after[coord].duplicate(true)
	if kind == "blocked_attack":
		var landing = args.get("landing", source)
		if not before.has(landing) or not after.has(landing): return {}
		action["landing"] = landing
		action["before_landing"] = before[landing].duplicate(true)
		action["after_landing"] = after[landing].duplicate(true)
	return action
