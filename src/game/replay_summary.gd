extends RefCounted
## Cheap library previews. Playback still verifies the complete recording.
const Loc = preload("res://src/localization/text.gd")
const Clock = preload("res://src/game/match_clock.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const PREVIEW_BYTES := 256 * 1024
const HEADER_BYTES := 64 * 1024

static func from_records(header: Dictionary, commands: Array) -> Dictionary:
	var metadata = header.get("metadata", {})
	if not metadata is Dictionary: metadata = {}
	var result := {
		"created_utc":header.get("created_utc", ""), "names":header.get("names", []),
		"humans":header.get("humans", []), "rules":header.get("rules", ""),
		"seed":header.get("seed", -1), "map_size":header.get("map_size", ""),
		"kingdoms":header.get("factions", 0), "difficulty":metadata.get("difficulty", ""),
		"mode":metadata.get("mode", ""), "map_title":metadata.get("map_title", ""),
		"factions":metadata.get("factions", []), "match":metadata.get("match", {}),
		"duration_seconds":-1, "rounds":0, "winner":-1, "outcome":"", "result":""}
	if result["mode"] == "" and result["humans"] is Array and result["humans"].size() > 1: result["mode"] = "hotseat"
	var match_data = result["match"]
	var slots = match_data.get("slots", []) if match_data is Dictionary else []
	if slots is Array and not slots.is_empty():
		if result["mode"] == "": result["mode"] = "quick_play"
		var difficulties: Array = []
		for slot in slots:
			if not slot is Dictionary or slot.get("controller") != "ai": continue
			var difficulty = slot.get("difficulty", "")
			if difficulty in ["easy", "normal", "hard"] and difficulty not in difficulties: difficulties.append(difficulty)
		result["difficulty"] = "mixed" if difficulties.size() > 1 else difficulties[0] if not difficulties.is_empty() else ""
	for index in range(commands.size() - 1, -1, -1):
		var row: Dictionary = commands[index]
		if row.get("action") != "result": continue
		var args: Dictionary = row.get("args", {})
		result["rounds"] = int(row.get("round", 0))
		for key in ["winner", "outcome", "result", "duration_seconds", "completed_utc"]:
			if args.has(key): result[key] = args[key]
		break
	return result

static func read_preview(path: String) -> Dictionary:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null: return {"preview_error":true}
	var first := read_line(source, HEADER_BYTES)
	var header = JSON.parse_string(first)
	if not header is Dictionary or header.get("format") != "slay-replay": return {"preview_error":true}
	if header.get("summary") is Dictionary:
		var summary: Dictionary = header["summary"].duplicate(true)
		if not valid_preview(summary): return {"preview_error":true}
		summary["details_available"] = true
		return summary
	# Old v2 files expose their result in readable action lines before the large
	# compressed footer. Stop before that footer: never decompress a library row.
	var result_rows: Array = []
	while source.get_position() < mini(source.get_length(), PREVIEW_BYTES):
		var at := source.get_position()
		var prefix := source.get_buffer(9).get_string_from_utf8()
		source.seek(at)
		if prefix.begins_with('{"data":'): break
		var line := read_line(source, 16384)
		if line == "": break
		if not line.contains('"result"'): continue
		var object = JSON.parse_string(line)
		if not object is Dictionary: continue
		if header.get("version") == 1 and object.get("action") == "result": append_result(result_rows, object.get("args"), object.get("round"))
		elif object.get("result") is Array and object["result"].size() == 4 and object["result"][3] is Dictionary:
			append_result(result_rows, object["result"][3], object["result"][1])
	var summary := from_records(header, result_rows)
	if not valid_preview(summary): return {"preview_error":true}
	summary["details_available"] = header.get("version") == 1
	return summary

static func append_result(rows: Array, args, round_value) -> void:
	if not args is Dictionary or not (round_value is int or round_value is float): return
	if not is_finite(float(round_value)) or round_value != floorf(float(round_value)): return
	rows.append({"action":"result", "round":round_value, "args":args})

static func valid_preview(summary: Dictionary) -> bool:
	for field in ["duration_seconds", "rounds", "winner", "kingdoms", "seed"]:
		var value = summary.get(field, -1)
		if not (value is int or value is float) or not is_finite(float(value)) or value != floorf(float(value)): return false
	for field in ["created_utc", "rules", "map_size", "difficulty", "mode", "map_title", "outcome", "result"]:
		if not summary.get(field, "") is String or summary.get(field, "").length() > 256: return false
	if not summary.get("names", []) is Array or not summary.get("humans", []) is Array: return false
	if summary.get("names", []).size() > 64 or summary.get("humans", []).size() > 64: return false
	for name_value in summary.get("names", []):
		if not name_value is String or name_value.length() > 256: return false
	for seat in summary.get("humans", []):
		if not (seat is int or seat is float) or not is_finite(float(seat)) or seat != floorf(float(seat)) or seat < 0 or seat >= 64: return false
	return summary.get("factions", []) is Array and summary.get("match", {}) is Dictionary

static func read_line(source: FileAccess, budget: int) -> String:
	var at := source.get_position()
	var bytes := source.get_buffer(mini(budget, source.get_length() - at))
	var newline := bytes.find(10)
	if newline < 0: return ""
	source.seek(at + newline + 1)
	return bytes.slice(0, newline).get_string_from_utf8()

static func players(summary: Dictionary) -> String:
	var names = summary.get("names", [])
	var humans = summary.get("humans", [])
	if not names is Array or not humans is Array: return Loc.text("Unknown kingdom")
	var result := PackedStringArray()
	for seat in humans:
		if not (seat is int or seat is float): continue
		var index := int(seat)
		if index >= 0 and index < names.size():
			var name_value: String = str(names[index])
			var match_data = summary.get("match", {})
			var slots = match_data.get("slots", []) if match_data is Dictionary else []
			if slots is Array and index < slots.size() and slots[index] is Dictionary:
				var id = slots[index].get("color", -1)
				if (id is int or id is float) and id >= 0 and id < Catalog.FACTIONS.size() and id == floorf(float(id)) and name_value != Catalog.FACTIONS[int(id)]:
					name_value = Loc.text("%s (%s)") % [Catalog.FACTIONS[int(id)], name_value]
			result.append(name_value)
	return " / ".join(result) if not result.is_empty() else Loc.text("Unknown kingdom")

static func outcome(summary: Dictionary) -> String:
	var kind = summary.get("result", "")
	if kind == "": kind = summary.get("outcome", "")
	if kind == "draw": return Loc.text("Draw")
	if kind == "victory": return Loc.text("Victory")
	if kind == "defeat": return Loc.text("Defeat")
	if kind == "": return Loc.text("Result not recorded")
	var winner := int(summary.get("winner", -1))
	var humans = summary.get("humans", [])
	var names = summary.get("names", [])
	if humans is Array and humans.size() == 1:
		return Loc.text("Victory") if winner == int(humans[0]) else Loc.text("Defeat")
	if winner >= 0 and names is Array and winner < names.size(): return Loc.text("%s won") % str(names[winner])
	return Loc.text("Match finished")

static func mode_name(summary: Dictionary) -> String:
	match summary.get("mode", ""):
		"quick_play": return Loc.text("Quick Play")
		"hotseat": return Loc.text("Local multiplayer")
		"editor": return Loc.text("Custom map")
	return Loc.text("Single player") if summary.get("humans", []).size() == 1 else Loc.text("Not recorded")

static func description(summary: Dictionary) -> String:
	var missing := Loc.text("Not recorded")
	var duration := int(summary.get("duration_seconds", -1))
	var rounds := int(summary.get("rounds", 0))
	var rules: String = str(summary.get("rules", ""))
	var size_id: String = str(summary.get("map_size", ""))
	var difficulty: String = str(summary.get("difficulty", ""))
	var map_title: String = str(summary.get("map_title", ""))
	var date: String = str(summary.get("created_utc", ""))
	var rows := PackedStringArray([
		Loc.text("Duration: %s") % (Clock.display(duration) if duration >= 0 else missing),
		Loc.text("Rounds: %s") % (str(rounds) if rounds > 0 else missing),
		Loc.text("Mode: %s") % mode_name(summary),
		Loc.text("Rules: %s") % (Loc.text(rules.capitalize()) if rules != "" else missing)])
	if map_title != "": rows.append(Loc.text("Map: %s") % map_title)
	if size_id != "": rows.append(Loc.text("Size: %s") % Loc.text(Sizes.spec(size_id)["name"]))
	if difficulty != "": rows.append(Loc.text("Difficulty: %s") % (Loc.text("Mixed") if difficulty == "mixed" else Loc.text(difficulty.capitalize())))
	if int(summary.get("kingdoms", 0)) > 0: rows.append(Loc.text("Kingdoms: %d") % int(summary["kingdoms"]))
	if date != "": rows.append(Loc.text("Started: %s UTC") % date.replace("T", " "))
	if int(summary.get("seed", -1)) >= 0: rows.append(Loc.text("Seed: %s") % str(int(summary["seed"])))
	return "\n".join(rows)
