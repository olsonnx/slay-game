extends Node
## Saved gameplay and match setup preferences.
signal changed
signal save_failed(error: Error)
const DEFAULT_PATH := "user://gameplay_settings.cfg"
var settings_path := DEFAULT_PATH
var rule_mode: String:
	get: return "modern"
	set(_value): pass
var difficulty := "normal"
var clear_indicators := true
var multiplayer_setup: Dictionary = {}
var quick_play_kingdom := -1
var quick_play_use_profile := true
var completed_tutorials: Dictionary = {}
const PRESENTATION_DEFAULTS := {"camera_speed":1.0, "rotation_speed":1.0, "zoom_speed":1.0, "invert_zoom":false, "invert_vertical":false, "playback_speed":1.0, "pause_on_focus_loss":false}
var camera_speed := 1.0
var rotation_speed := 1.0
var zoom_speed := 1.0
var invert_zoom := false
var invert_vertical := false
var playback_speed := 1.0
var pause_on_focus_loss := false

func set_preference(key: String, value: Variant, persist := true) -> void:
	if not valid_preference(key, value): return
	set(key,value)
	if persist: flush_settings()
	changed.emit()

static func valid_preference(key: String, value: Variant) -> bool:
	if key not in PRESENTATION_DEFAULTS: return false
	if PRESENTATION_DEFAULTS[key] is bool: return value is bool
	return (value is float or value is int) and is_finite(float(value)) and value >= 0.25 and value <= (3.0 if key == "playback_speed" else 2.0)

func complete_tutorial(category: String) -> void:
	if category.is_empty() or completed_tutorials.get(category,false): return
	completed_tutorials[category] = true
	flush_settings()
	changed.emit()

func set_quick_play_kingdom(value: int, persist := true) -> void:
	if value < -1 or value >= preload("res://src/game/game_catalog.gd").FACTIONS.size(): return
	if value == quick_play_kingdom and not quick_play_use_profile: return
	quick_play_kingdom = value
	quick_play_use_profile = false
	if persist: flush_settings()
	changed.emit()

func set_quick_play_country(value: int, persist := true) -> void:
	if value != -2:
		set_quick_play_kingdom(value, persist)
		return
	quick_play_use_profile = true
	if persist: flush_settings()
	changed.emit()

func set_multiplayer_setup(config: Dictionary, persist := true) -> void:
	multiplayer_setup = preload("res://src/game/match_setup.gd").normalize(config)
	if persist: flush_settings()
	changed.emit()

func set_clear_indicators(value: bool, persist := true) -> void:
	clear_indicators = value
	if persist:
		flush_settings()
	changed.emit()

func set_difficulty(value: String, persist := true) -> void:
	if value not in ["easy", "normal", "hard"] or value == difficulty:
		return
	difficulty = value
	if persist:
		flush_settings()
	changed.emit()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()

func set_rules(_mode: String, _persist := true) -> void:
	pass

func load_settings(path := DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == OK:
		for key in PRESENTATION_DEFAULTS:
			var value = config.get_value("presentation", key, PRESENTATION_DEFAULTS[key])
			set(key, value if valid_preference(key,value) else PRESENTATION_DEFAULTS[key])
		completed_tutorials.clear()
		var saved_tutorials = config.get_value("tutorial", "completed", {})
		if saved_tutorials is Dictionary:
			for category in saved_tutorials:
				if category is String and saved_tutorials[category] is bool and saved_tutorials[category]: completed_tutorials[category] = true
		var saved_kingdom = config.get_value("gameplay", "quick_play_kingdom", -1)
		quick_play_kingdom = saved_kingdom if saved_kingdom is int and saved_kingdom >= -1 and saved_kingdom < preload("res://src/game/game_catalog.gd").FACTIONS.size() else -1
		quick_play_use_profile = config.get_value("gameplay", "quick_play_use_profile", true) == true
		var saved_setup = config.get_value("gameplay", "multiplayer_setup", {})
		multiplayer_setup = preload("res://src/game/match_setup.gd").normalize(saved_setup) if saved_setup is Dictionary else {}
		var saved_indicators = config.get_value("gameplay", "clear_indicators", true)
		clear_indicators = saved_indicators if saved_indicators is bool else true
		var saved_difficulty = config.get_value("gameplay", "difficulty", "normal")
		difficulty = saved_difficulty if saved_difficulty in ["easy", "normal", "hard"] else "normal"
	return error

func flush_settings() -> Error:
	var config := ConfigFile.new()
	for key in PRESENTATION_DEFAULTS: config.set_value("presentation", key, get(key))
	config.set_value("tutorial", "completed", completed_tutorials)
	config.set_value("gameplay", "multiplayer_setup", multiplayer_setup)
	config.set_value("gameplay", "quick_play_kingdom", quick_play_kingdom)
	config.set_value("gameplay", "quick_play_use_profile", quick_play_use_profile)
	config.set_value("gameplay", "difficulty", difficulty)
	config.set_value("gameplay", "clear_indicators", clear_indicators)
	var error := config.save(settings_path)
	if error != OK:
		save_failed.emit(error)
	return error
