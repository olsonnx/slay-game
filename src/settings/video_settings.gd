extends Node
## User display preferences, separate from game state and save files.
signal changed
signal save_failed(error: Error)

const DEFAULT_PATH := "user://video_settings.cfg"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840,2160)]
const BASE_SIZE := Vector2i(1280, 720)
const EXTRA_DEFAULTS := {"ui_scale":1.0, "tooltip_delay":0.65, "show_fps":false, "reduced_motion":false, "menu_animation":true, "depth_of_field":true, "clouds":true, "ambient_occlusion":true, "brightness":1.0, "frame_limit":0, "background_frame_limit":30}
const FRAME_LIMITS := [0,30,60,90,120,144,165,240]
var ui_scale := 1.0
var tooltip_delay := 0.65
var show_fps := false
var reduced_motion := false
var menu_animation := true
var depth_of_field := true
var clouds := true
var ambient_occlusion := true
var brightness := 1.0
var frame_limit := 0
var background_frame_limit := 30
var focused := true
var settings_path := DEFAULT_PATH
var fullscreen := false
var resolution := BASE_SIZE
var vsync := true
var antialiasing := 2
var shadows := true
var atmospheric_lighting := true
var plastic_tiles := true
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
	get_window().size_changed.connect(update_render_resolution)
	apply()

func set_preference(key: StringName, value: Variant, persist := true) -> void:
	if String(key) in EXTRA_DEFAULTS:
		if not valid_extra(String(key), value): return
		set(key, value)
		apply(key)
		if persist: save_timer.start()
		changed.emit()
		return
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
		&"plastic_tiles":
			if not value is bool: return
			plastic_tiles = value
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
	apply_ui_scale()
	if key in [&"", &"tooltip_delay"]:
		ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", tooltip_delay)
	apply_frame_limit()
	if key in [&"", &"resolution", &"fullscreen"]:
		get_window().content_scale_size = BASE_SIZE
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		update_render_resolution()
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
	if key in [&"", &"resolution", &"fullscreen"]:
		update_render_resolution()

func update_render_resolution() -> void:
	# Fullscreen keeps the monitor's native mode. Scale the 3D scene separately
	# so choosing a lower resolution saves GPU work without blurring UI text.
	get_viewport().scaling_3d_scale = render_scale(get_window().size)
	apply_ui_scale()

func effective_ui_scale() -> float:
	var output := Vector2(get_window().size)
	var base_scale := minf(output.x / BASE_SIZE.x, output.y / BASE_SIZE.y)
	var logical := output / maxf(base_scale, 0.01)
	return minf(ui_scale, minf(logical.x / 960.0, logical.y / 620.0))

func apply_ui_scale() -> void:
	get_window().content_scale_factor = effective_ui_scale()

func apply_frame_limit() -> void:
	var limit := frame_limit
	if not focused and background_frame_limit > 0:
		limit = background_frame_limit if limit == 0 else mini(limit,background_frame_limit)
	Engine.max_fps = limit

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: focused = false; apply_frame_limit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: focused = true; apply_frame_limit()

static func valid_extra(key: String, value: Variant) -> bool:
	if key in ["frame_limit", "background_frame_limit"]: return value is int and value in FRAME_LIMITS
	if EXTRA_DEFAULTS[key] is bool: return value is bool
	if not (value is float or value is int) or not is_finite(float(value)): return false
	match key:
		"ui_scale": return value >= 0.75 and value <= 1.5
		"tooltip_delay": return value >= 0.0 and value <= 1.5
		"brightness": return value >= 0.7 and value <= 1.3
	return false

func render_scale(output_size: Vector2i) -> float:
	return clampf(float(resolution.y) / maxf(output_size.y, 1), 0.25, 2.0) if fullscreen else 1.0

func load_settings(path := DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return error
	for key in EXTRA_DEFAULTS:
		var value = config.get_value("video", key, EXTRA_DEFAULTS[key])
		set(key, value if valid_extra(key, value) else EXTRA_DEFAULTS[key])
	var saved_resolution = config.get_value("video", "resolution", resolution)
	if saved_resolution in [Vector2i(960, 620), Vector2i(1280, 820)]:
		saved_resolution = BASE_SIZE
	if saved_resolution in RESOLUTIONS:
		resolution = saved_resolution
	var saved_msaa = config.get_value("video", "antialiasing", antialiasing)
	if saved_msaa is int:
		antialiasing = clampi(saved_msaa, 0, 3)
	for key in [&"fullscreen", &"vsync", &"shadows", &"follow_turn_camera", &"level_transitions", &"atmospheric_lighting", &"plastic_tiles"]:
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
	for key in EXTRA_DEFAULTS: config.set_value("video", key, get(key))
	for key in [&"fullscreen", &"resolution", &"vsync", &"antialiasing", &"shadows", &"follow_turn_camera", &"level_transitions", &"background", &"stylized_water", &"internal_borders", &"atmospheric_lighting", &"plastic_tiles"]:
		config.set_value("video", key, get(key))
	var error := config.save(settings_path)
	if error != OK:
		save_failed.emit(error)
	return error

func _exit_tree() -> void:
	if is_instance_valid(save_timer) and not save_timer.is_stopped():
		flush_settings()
