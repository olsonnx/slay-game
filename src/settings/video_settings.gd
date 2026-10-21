extends Node
## User display preferences, separate from game state and save files.
signal changed
signal save_failed(error: Error)

const DEFAULT_PATH := "user://video_settings.cfg"
const RESOLUTIONS := [Vector2i(960, 620), Vector2i(1280, 820), Vector2i(1600, 900), Vector2i(1920, 1080)]
var settings_path := DEFAULT_PATH
var fullscreen := false
var resolution := Vector2i(1280, 820)
var vsync := true
var antialiasing := 2
var shadows := true
var atmospheric_lighting := true
var follow_turn_camera := true
var level_transitions := true
var background := "water"
var stylized_water := false
var internal_borders := 0.5
var save_timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	save_timer = Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = 0.25
	save_timer.timeout.connect(flush_settings)
	add_child(save_timer)
	load_settings()
	apply()

func set_preference(key: StringName, value: Variant, persist := true) -> void:
	match key:
		&"fullscreen": fullscreen = bool(value)
		&"resolution":
			if value not in RESOLUTIONS:
				return
			resolution = value
		&"vsync": vsync = bool(value)
		&"antialiasing": antialiasing = clampi(int(value), 0, 3)
		&"atmospheric_lighting":
			if not value is bool: return
			atmospheric_lighting = value
		&"shadows": shadows = bool(value)
		&"follow_turn_camera": follow_turn_camera = bool(value)
		&"level_transitions": level_transitions = bool(value)
		&"stylized_water":
			if not value is bool: return
			stylized_water = value
		&"internal_borders":
			if not (value is float or value is int) or not is_finite(float(value)):
				return
			internal_borders = snappedf(clampf(float(value), 0.0, 1.0), 0.01)
		&"background":
			if value not in ["water", "sky"]:
				return
			background = value
		_: return
	apply(key)
	if persist:
		save_timer.start()
	changed.emit()

func apply(key: StringName = &"") -> void:
	if key in [&"", &"antialiasing"]:
		get_viewport().msaa_3d = antialiasing
	if DisplayServer.get_name() == "headless":
		return
	if key in [&"", &"fullscreen"]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not fullscreen and key in [&"", &"resolution", &"fullscreen"]:
		DisplayServer.window_set_size(resolution)
	if key in [&"", &"vsync"]:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

func load_settings(path := DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return error
	var saved_resolution = config.get_value("video", "resolution", resolution)
	if saved_resolution in RESOLUTIONS:
		resolution = saved_resolution
	var saved_msaa = config.get_value("video", "antialiasing", antialiasing)
	if saved_msaa is int:
		antialiasing = clampi(saved_msaa, 0, 3)
	for key in [&"fullscreen", &"vsync", &"shadows", &"follow_turn_camera", &"level_transitions", &"atmospheric_lighting"]:
		var value = config.get_value("video", key, get(key))
		if value is bool:
			set(key, value)
	var saved_water = config.get_value("video", "stylized_water", false)
	stylized_water = saved_water if saved_water is bool else false
	var saved_background = config.get_value("video", "background", background)
	if saved_background in ["water", "sky"]:
		background = saved_background
	var saved_borders = config.get_value("video", "internal_borders", 0.5)
	internal_borders = 0.5
	if (saved_borders is float or saved_borders is int) and is_finite(float(saved_borders)):
		internal_borders = snappedf(clampf(float(saved_borders), 0.0, 1.0), 0.01)
	return OK

func flush_settings() -> Error:
	save_timer.stop()
	var config := ConfigFile.new()
	for key in [&"fullscreen", &"resolution", &"vsync", &"antialiasing", &"shadows", &"follow_turn_camera", &"level_transitions", &"background", &"stylized_water", &"internal_borders", &"atmospheric_lighting"]:
		config.set_value("video", key, get(key))
	var error := config.save(settings_path)
	if error != OK:
		save_failed.emit(error)
	return error

func _exit_tree() -> void:
	if is_instance_valid(save_timer) and not save_timer.is_stopped():
		flush_settings()
