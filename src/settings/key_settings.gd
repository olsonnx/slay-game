extends Node
const Loc = preload("res://src/localization/text.gd")
## One physical key per action; menu choices intentionally share opening keys.
signal changed
signal save_failed(error: Error)
const DEFAULT_PATH := "user://key_settings.cfg"
const DEFAULTS := {"recruit": KEY_Q, "build": KEY_E, "spells": KEY_R, "view": KEY_TAB, "heatmap": KEY_F, "develop": KEY_G, "end_turn": KEY_SPACE, "cancel": KEY_ESCAPE, "speed": KEY_CTRL, "choice_1": KEY_Q, "choice_2": KEY_E, "choice_3": KEY_R, "pan_up": KEY_W, "pan_left": KEY_A, "pan_down": KEY_S, "pan_right": KEY_D}
const TITLES := {"recruit": "Recruit", "build": "Build", "spells": "Spells", "view": "Change view", "heatmap": "Value heatmap", "develop": "Develop province", "end_turn": "End turn", "cancel": "Cancel / pause", "speed": "Hold to speed up", "choice_1": "Left choice", "choice_2": "Middle choice", "choice_3": "Right choice", "pan_up": "Pan forward", "pan_left": "Pan left", "pan_down": "Pan backward", "pan_right": "Pan right"}
var settings_path := DEFAULT_PATH
var bindings: Dictionary = DEFAULTS.duplicate()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()

func key_name(action: String) -> String:
	return Loc.text(OS.get_keycode_string(bindings[action]))

func matches(event: InputEventKey, action: String) -> bool:
	return (event.physical_keycode if event.physical_keycode != 0 else event.keycode) == bindings[action]

func held(action: String) -> bool:
	return Input.is_physical_key_pressed(bindings[action])

func conflict(action: String, code: int, candidate: Dictionary = {}) -> String:
	if candidate.is_empty():
		candidate = bindings
	for other in candidate:
		if other == action or candidate[other] != code:
			continue
		# Only menu-opening actions may share keys with contextual choices.
		if (action in ["recruit", "build", "spells"] and other.begins_with("choice_")) or (other in ["recruit", "build", "spells"] and action.begins_with("choice_")):
			continue
		return other
	return ""

func valid_key(value) -> bool:
	return value is int and value > 0 and value < (1 << 23) and OS.find_keycode_from_string(OS.get_keycode_string(value)) == value

func set_binding(action: String, code: int, persist := true) -> String:
	if not DEFAULTS.has(action) or not valid_key(code):
		return Loc.text("Choose a keyboard key.")
	if code == KEY_ESCAPE and action != "cancel":
		return Loc.text("Escape is reserved for cancelling and menu navigation.")
	if code == KEY_F3:
		return Loc.text("F3 is reserved for the FPS display.")
	var other := conflict(action, code)
	if other != "":
		return Loc.text("Already used by %s. Choose another key.") % Loc.text(TITLES[other])
	if bindings[action] != code:
		bindings[action] = code
		if persist:
			flush_settings()
		changed.emit()
	return ""

func reset_defaults(persist := true) -> void:
	bindings = DEFAULTS.duplicate()
	if persist:
		flush_settings()
	changed.emit()

func load_settings(path := DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	bindings = DEFAULTS.duplicate()
	if error == OK:
		for action in DEFAULTS:
			var value = config.get_value("keys", action, DEFAULTS[action])
			if valid_key(value) and value != KEY_F3 and (value != KEY_ESCAPE or action == "cancel"):
				bindings[action] = value
		# Preserve older customised F bindings when introducing the heatmap.
		# Its normal default stays F; an existing conflict gets a free fallback.
		for introduced in ["heatmap", "develop"]:
			if not config.has_section_key("keys", introduced) and conflict(introduced, bindings[introduced]) != "":
				for alternative in [KEY_H, KEY_G] + range(KEY_F1, KEY_F12 + 1) + range(KEY_A, KEY_Z + 1):
					if alternative != KEY_F3 and conflict(introduced, alternative) == "":
						bindings[introduced] = alternative
						break
		# Load the full set first so valid permutations survive. Resolve corrupt
		# conflicting overrides back to defaults without leaving ambiguous keys.
		for attempt in range(DEFAULTS.size()):
			var repaired := false
			for action in DEFAULTS:
				if bindings[action] != DEFAULTS[action] and conflict(action, bindings[action]) != "":
					bindings[action] = DEFAULTS[action]
					repaired = true
			if not repaired:
				break
	changed.emit()
	return error

func flush_settings() -> Error:
	var config := ConfigFile.new()
	for action in bindings:
		config.set_value("keys", action, bindings[action])
	var error := config.save(settings_path)
	if error != OK:
		save_failed.emit(error)
	return error
