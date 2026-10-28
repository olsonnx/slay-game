extends RefCounted
## Compact, portable names derived from the recorded match, not live settings.
const Summary = preload("res://src/game/replay_summary.gd")

static func component(value: String, byte_limit: int) -> String:
	var allowed := RegEx.create_from_string("[^\\p{L}\\p{N}_.-]+")
	var result := allowed.sub(value, "-", true).strip_edges().trim_prefix("-").trim_suffix("-")
	while result.to_utf8_buffer().size() > byte_limit:
		result = result.left(result.length() - 1)
	return result if result != "" else "Unknown"

static func filename(header: Dictionary, commands: Array) -> String:
	var summary := Summary.from_records(header, commands)
	var modes := {"quick_play":"QP", "hotseat":"LM", "editor":"CM", "steam_online":"SM"}
	var mode: String = modes.get(summary.mode, "SP")
	var date: String = header.get("created_utc", "")
	if date == "": date = Time.get_datetime_string_from_system(true)
	date = date.replace("-", "").replace(":", "").replace("T", "-").trim_suffix("Z") + "Z"
	var parts := PackedStringArray([
		component(date, 16), mode, component(Summary.players(summary), 32)])
	var sizes := {"very_small":"VS", "small":"T", "medium":"S", "large":"STD", "very_large":"L", "huge":"H"}
	parts.append(sizes.get(summary.get("map_size", ""), "U"))
	var difficulty: String = summary.get("difficulty", "")
	var difficulties := {"easy":"E", "normal":"N", "hard":"H", "mixed":"M"}
	if difficulties.has(difficulty): parts.append(difficulties[difficulty])
	parts.append(result_code(summary))
	parts.append("v" + component(str(header.get("game_version", "Unknown")), 14))
	parts.append("s" + component(str(header.get("seed", -1)), 11))
	return "_".join(parts) + ".jsonl"

static func result_code(summary: Dictionary) -> String:
	var result: String = summary.get("result", "")
	if result == "": result = summary.get("outcome", "")
	if result == "victory": return "W"
	if result == "defeat": return "L"
	if result == "draw": return "D"
	var winner := int(summary.get("winner", -1))
	var humans: Array = summary.get("humans", [])
	if winner >= 0 and humans.size() == 1: return "W" if winner == int(humans[0]) else "L"
	var names: Array = summary.get("names", [])
	if winner >= 0 and winner < names.size(): return "W-" + component(str(names[winner]), 16)
	return "F" if result != "" else "U"

static func available_path(directory: String, name_value: String) -> String:
	var target := directory.path_join(name_value)
	var suffix := 2
	while FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target) or FileAccess.file_exists(target + ".tmp"):
		target = directory.path_join(name_value.get_basename() + "_%d.jsonl" % suffix)
		suffix += 1
	return target
