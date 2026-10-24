extends Node
## One local kingdom identity; cosmetic edits never replace its history.
signal changed
signal save_failed(error: Error)
const DEFAULT_PATH := "user://player_profile.cfg"
const Progress = preload("res://src/settings/account_progress.gd")
const PATTERNS := ["solid", "horizontal", "vertical", "diagonal", "cross", "saltire", "border"]
const SYMBOLS := ["crown", "star", "sun", "tower", "tree", "sword", "diamond", "none"]
const PLACEMENTS := ["center", "upper_left", "upper_right", "lower_left", "lower_right", "left", "right"]
var settings_path := DEFAULT_PATH
var data: Dictionary = {}
var tutorial_prompt_seen := false
var statistics := {"matches":0, "wins":0, "losses":0, "draws":0, "seconds":0, "rounds":0, "streak":0, "best_streak":0, "longest":0, "xp":0}
var recorded_matches: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()

func exists() -> bool: return not data.is_empty()

func delete_profile() -> Error:
	var tree := Engine.get_main_loop() as SceneTree
	var gameplay = tree.root.get_node_or_null("Gameplay") if tree != null else null
	var previous_tutorials: Dictionary = gameplay.completed_tutorials.duplicate() if gameplay != null else {}
	var previous_choice: bool = gameplay.quick_play_use_profile if gameplay != null else true
	if gameplay != null:
		gameplay.completed_tutorials.clear()
		gameplay.quick_play_use_profile = true
		var save_error: Error = gameplay.flush_settings()
		if save_error != OK:
			gameplay.completed_tutorials = previous_tutorials
			gameplay.quick_play_use_profile = previous_choice
			return save_error
	# Remove recovery files too, so a deliberately deleted profile cannot return.
	for suffix in [".bak", ".tmp", ""]:
		var path: String = settings_path + suffix
		if not FileAccess.file_exists(path): continue
		var error := DirAccess.remove_absolute(path)
		if error != OK:
			if gameplay != null:
				gameplay.completed_tutorials = previous_tutorials
				gameplay.quick_play_use_profile = previous_choice
				gameplay.flush_settings()
			save_failed.emit(error)
			return error
	data.clear()
	tutorial_prompt_seen = false
	recorded_matches.clear()
	for key in statistics: statistics[key] = 0
	if gameplay != null: gameplay.changed.emit()
	changed.emit()
	return OK

static func default_identity() -> Dictionary:
	return {"name":"", "motto":"", "color":"86b998", "flag":{
		"pattern":"cross", "field":"283b3e", "accent":"86b998", "symbol":"crown",
		"ink":"ede7d4", "placement":"center", "scale":0.38}}

static func normalize_identity(value: Dictionary) -> Dictionary:
	var result := default_identity()
	result.name = str(value.get("name", "")).strip_edges().replace("\n", " ").replace("\r", " ").left(32)
	result.motto = str(value.get("motto", "")).strip_edges().replace("\n", " ").replace("\r", " ").left(64)
	var color = value.get("color", result.color)
	if color is String and Color.html_is_valid(color): result.color = Color(color).to_html(false)
	var flag = value.get("flag", {})
	if flag is Dictionary:
		for key in ["field", "accent", "ink"]:
			if flag.get(key) is String and Color.html_is_valid(flag[key]): result.flag[key] = Color(flag[key]).to_html(false)
		for entry in [["pattern", PATTERNS], ["symbol", SYMBOLS], ["placement", PLACEMENTS]]:
			if flag.get(entry[0]) in entry[1]: result.flag[entry[0]] = flag[entry[0]]
		var scale_value = flag.get("scale", 0.38)
		if (scale_value is float or scale_value is int) and is_finite(float(scale_value)):
			result.flag.scale = clampf(float(scale_value), 0.2, 0.65)
	return result

func save_identity(value: Dictionary) -> Error:
	var identity := normalize_identity(value)
	if identity.name.is_empty(): return ERR_INVALID_PARAMETER
	var previous := data.duplicate(true)
	identity["id"] = data.get("id", Crypto.new().generate_random_bytes(16).hex_encode())
	data = identity
	var error := flush_settings()
	if error != OK: data = previous
	else: changed.emit()
	return error

func acknowledge_tutorial() -> Error:
	var previous := tutorial_prompt_seen
	tutorial_prompt_seen = true
	var error := flush_settings()
	if error != OK: tutorial_prompt_seen = previous
	return error

func average_seconds() -> int:
	return int(statistics.seconds / maxi(1, statistics.matches))

func record_match(match_id: String, result: String, seconds: int, rounds: int, settings: Dictionary = {}) -> Error:
	if not exists() or match_id.is_empty() or match_id in recorded_matches or result not in ["victory", "defeat", "draw"]: return OK
	var before := statistics.duplicate(true)
	var previous_ids := recorded_matches.duplicate()
	statistics.matches += 1
	statistics.seconds += maxi(0, seconds)
	statistics.rounds += maxi(0, rounds)
	statistics.longest = maxi(statistics.longest, seconds)
	statistics[{"victory":"wins", "defeat":"losses", "draw":"draws"}[result]] += 1
	statistics.streak = statistics.streak + 1 if result == "victory" else 0
	statistics.best_streak = maxi(statistics.best_streak, statistics.streak)
	statistics.xp += Progress.reward(result, settings)
	recorded_matches.append(match_id)
	if recorded_matches.size() > 256: recorded_matches.pop_front()
	var error := flush_settings()
	if error != OK:
		statistics = before
		recorded_matches = previous_ids
	else: changed.emit()
	return error

func load_settings(path := DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK: return recover_backup(path, error)
	var identity = config.get_value("profile", "identity", {})
	if not identity is Dictionary: return recover_backup(path, ERR_INVALID_DATA)
	var normalized := normalize_identity(identity)
	if normalized.name.is_empty() or not identity.get("id") is String or identity.id.is_empty(): return recover_backup(path, ERR_INVALID_DATA)
	normalized.id = identity.id
	data = normalized
	tutorial_prompt_seen = config.get_value("profile", "tutorial_prompt_seen", false) == true
	var saved = config.get_value("profile", "statistics", {})
	for key in statistics:
		statistics[key] = maxi(0, int(saved.get(key, 0))) if saved is Dictionary and saved.get(key, 0) is int else 0
	var ids = config.get_value("profile", "recorded_matches", [])
	recorded_matches = ids.filter(func(value): return value is String).slice(-256) if ids is Array else []
	return OK

func recover_backup(path: String, error: Error) -> Error:
	if not path.ends_with(".bak") and FileAccess.file_exists(path + ".bak"):
		return load_settings(path + ".bak")
	return error

func flush_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("profile", "version", 2)
	config.set_value("profile", "identity", data)
	config.set_value("profile", "tutorial_prompt_seen", tutorial_prompt_seen)
	config.set_value("profile", "statistics", statistics)
	config.set_value("profile", "recorded_matches", recorded_matches)
	# A backup protects the previous profile if writing a new file is interrupted.
	var error := config.save(settings_path + ".tmp")
	if error == OK:
		if FileAccess.file_exists(settings_path):
			error = DirAccess.copy_absolute(settings_path, settings_path + ".bak")
		if error == OK: error = DirAccess.rename_absolute(settings_path + ".tmp", settings_path)
	if error != OK: save_failed.emit(error)
	return error
