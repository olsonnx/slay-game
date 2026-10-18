extends Node
## Rules preference applies to newly generated sessions, never a live rules model.
signal changed
signal save_failed(error: Error)
const DEFAULT_PATH := "user://gameplay_settings.cfg"
var settings_path := DEFAULT_PATH
var rule_mode := "modern"
var difficulty := "normal"
var clear_indicators := true
var multiplayer_setup: Dictionary = {}
var quick_play_kingdom := -1

func set_quick_play_kingdom(value: int, persist := true) -> void:
	if value < -1 or value >= preload("res://src/game/game_catalog.gd").FACTIONS.size() or value == quick_play_kingdom: return
	quick_play_kingdom = value
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

func set_rules(mode: String, persist := true) -> void:
	if mode not in ["classic", "modern"] or mode == rule_mode:
		return
	rule_mode = mode
	if persist:
		flush_settings()
	changed.emit()

func load_settings(path := DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == OK:
		var saved_kingdom = config.get_value("gameplay", "quick_play_kingdom", -1)
		quick_play_kingdom = saved_kingdom if saved_kingdom is int and saved_kingdom >= -1 and saved_kingdom < preload("res://src/game/game_catalog.gd").FACTIONS.size() else -1
		var saved_setup = config.get_value("gameplay", "multiplayer_setup", {})
		multiplayer_setup = preload("res://src/game/match_setup.gd").normalize(saved_setup) if saved_setup is Dictionary else {}
		var saved_indicators = config.get_value("gameplay", "clear_indicators", true)
		clear_indicators = saved_indicators if saved_indicators is bool else true
		var saved_difficulty = config.get_value("gameplay", "difficulty", "normal")
		difficulty = saved_difficulty if saved_difficulty in ["easy", "normal", "hard"] else "normal"
		var mode = config.get_value("gameplay", "rules", rule_mode)
		if mode in ["classic", "modern"]:
			rule_mode = mode
	return error

func flush_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("gameplay", "multiplayer_setup", multiplayer_setup)
	config.set_value("gameplay", "quick_play_kingdom", quick_play_kingdom)
	config.set_value("gameplay", "rules", rule_mode)
	config.set_value("gameplay", "difficulty", difficulty)
	config.set_value("gameplay", "clear_indicators", clear_indicators)
	var error := config.save(settings_path)
	if error != OK:
		save_failed.emit(error)
	return error
