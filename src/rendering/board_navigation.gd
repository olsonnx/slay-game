extends Node
## Owns orthographic camera/navigation state; signals carry presentation updates.
const Grid = preload("res://src/game/hex_grid.gd")
signal changed
signal manual_moved
var camera: Camera3D
var water_background := true
var focus := Vector3.ZERO
var yaw := 0.18
var pitch := 0.92
var zoom := 22.0
var default_zoom := 22.0
var map_center := Vector3.ZERO
var navigation_limits := Vector2(18, 14)
var max_zoom := 38.0
var top_down := false
var saved_yaw := 0.18
var saved_pitch := 0.92
var rotating := false
var controls_enabled := true
var camera_pan_tween: Tween
var zoom_target := 22.0
var zooming := false
var zoom_cursor := Vector2.ZERO
var zoom_reference := Vector2(-1, -1)
var zoom_uses_reference := false
var zoom_recenters := true
var map_span := Vector2.ZERO
var preset_zoom := 22.0
var viewport_size := Vector2.ZERO

func _process(delta: float) -> void:
	if camera == null:
		return
	var size := get_viewport().get_visible_rect().size
	if size != viewport_size:
		_refresh_zoom_limits()
		zoom = minf(zoom, max_zoom)
		zoom_target = minf(zoom_target, max_zoom)
		update_camera()
	if not controls_enabled:
		zooming = false
	if not zooming:
		return
	var before := zoom
	var ground := _ground_at(zoom_cursor)
	zoom = lerpf(zoom, zoom_target, 1.0 - exp(-delta * 18.0))
	if absf(zoom - zoom_target) < 0.002:
		zoom = zoom_target
		zooming = false
	# The same board point stays beneath the pointer throughout a zoom-in.
	camera.size = zoom
	if zoom < before or zoom_uses_reference:
		focus += ground - _ground_at(zoom_cursor)
	elif zoom_recenters:
		# Gradually return to the island so the widest view always fits it.
		focus = focus.lerp(map_center, clampf((zoom - before) / maxf(0.001, max_zoom - before), 0.0, 1.0))
	if is_equal_approx(zoom, max_zoom) and not zoom_uses_reference and zoom_recenters:
		focus = map_center
	update_camera()

func _ground_at(screen: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	return origin - ray * origin.y / ray.y

func _fit_zoom(angle: float, tilt: float) -> float:
	var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
	var width := absf(cos(angle)) * map_span.x + absf(sin(angle)) * map_span.y
	var height := sin(tilt) * (absf(sin(angle)) * map_span.x + absf(cos(angle)) * map_span.y) + 4.0
	return maxf(height, width / maxf(0.1, aspect)) * 1.18

func _refresh_zoom_limits() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	default_zoom = maxf(preset_zoom, _fit_zoom(0.18, 0.92)) if map_span != Vector2.ZERO else preset_zoom
	max_zoom = maxf(default_zoom, _fit_zoom(yaw, pitch)) * 1.08

func update_camera() -> void:
	camera.size = zoom
	# Keep the whole orthographic view above the ocean at wide, shallow angles.
	var distance_from_focus := 42.0
	if water_background:
		distance_from_focus = maxf(42.0, (zoom * 0.5 * cos(pitch) + 2.0) / sin(pitch))
	# Orthographic shadows use the camera depth range. Keep it around the board,
	# rather than spending the shadow map on the old 1,000-unit far plane.
	var depth_extent := maxf(12.0,zoom*0.5/maxf(sin(pitch),0.1))+8.0
	camera.near = maxf(0.1,distance_from_focus-depth_extent)
	camera.far = distance_from_focus+depth_extent
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance_from_focus
	camera.look_at(focus, Vector3.UP)
	preload("res://src/rendering/depth_of_field.gd").update(camera, focus)
	changed.emit()

func configure_map(size_id: String, bounds: Vector2, layout: Dictionary = {}) -> void:
	stop_camera_pan()
	preset_zoom = preload("res://src/game/map_sizes.gd").spec(size_id)["zoom"]
	map_span = Vector2.ZERO
	map_center = Vector3.ZERO
	if not layout.is_empty():
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for coord in layout:
			var at := Grid.to_world(coord)
			low = low.min(Vector2(at.x, at.z))
			high = high.max(Vector2(at.x, at.z))
		map_center = Vector3((low.x + high.x) * 0.5, 0, (low.y + high.y) * 0.5)
		map_span = high - low + Vector2.ONE * 3.0
	navigation_limits = Vector2(maxf(18, bounds.x), maxf(14, bounds.y))
	_refresh_zoom_limits()

func pan(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx():
		return
	stop_camera_pan(false)
	if zooming: zoom_recenters = false
	manual_moved.emit()
	var movement := direction.normalized()
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var backward := Vector3(sin(yaw), 0, cos(yaw))
	focus += (right * movement.x + backward * movement.y) * zoom * 0.48 * delta
	focus.x = clampf(focus.x, -navigation_limits.x, navigation_limits.x)
	focus.z = clampf(focus.z, -navigation_limits.y, navigation_limits.y)
	update_camera()

func orbit(relative: Vector2) -> void:
	stop_camera_pan(false)
	manual_moved.emit()
	if top_down:
		top_down = false
		pitch = saved_pitch
		yaw = saved_yaw
	yaw -= relative.x * 0.006
	pitch = clampf(pitch + relative.y * 0.004, 0.44, 1.37)
	_refresh_zoom_limits()
	zoom = minf(zoom, max_zoom)
	zoom_target = minf(zoom_target, max_zoom)
	update_camera()

func drag_pan(relative: Vector2) -> void:
	if relative.is_zero_approx() or not controls_enabled:
		return
	stop_camera_pan(false)
	if zooming: zoom_recenters = false
	manual_moved.emit()
	# Translate screen displacement onto the board plane at any view angle.
	var ray := camera.project_ray_normal(Vector2.ZERO)
	var first := camera.project_ray_origin(Vector2.ZERO)
	var second := camera.project_ray_origin(relative)
	var first_ground := first - ray * first.y / ray.y
	var second_ground := second - ray * second.y / ray.y
	focus += first_ground - second_ground
	focus.x = clampf(focus.x, -navigation_limits.x, navigation_limits.x)
	focus.z = clampf(focus.z, -navigation_limits.y, navigation_limits.y)
	update_camera()

func change_zoom(steps: float, cursor := Vector2(-1, -1)) -> void:
	var previous_target := zoom_target if zooming else zoom
	stop_camera_pan()
	_refresh_zoom_limits()
	manual_moved.emit()
	zoom_cursor = get_viewport().get_mouse_position() if cursor == Vector2(-1, -1) else cursor
	zoom_recenters = true
	zoom_uses_reference = zoom_reference != Vector2(-1, -1)
	if zoom_uses_reference:
		zoom_cursor = zoom_reference
	zoom_target = clampf(previous_target * pow(0.88, steps), 8.0, max_zoom)
	zooming = not is_equal_approx(zoom, zoom_target)

func toggle_top_down() -> void:
	stop_camera_pan()
	manual_moved.emit()
	top_down = not top_down
	if top_down:
		saved_yaw = yaw
		saved_pitch = pitch
		yaw = 0.0
		pitch = deg_to_rad(89.9)
	else:
		yaw = saved_yaw
		pitch = saved_pitch
	_refresh_zoom_limits()
	zoom = minf(zoom, max_zoom)
	update_camera()

func reset_camera() -> void:
	stop_camera_pan()
	manual_moved.emit()
	focus = map_center
	yaw = 0.18
	pitch = 0.92
	_refresh_zoom_limits()
	zoom = default_zoom
	top_down = false
	rotating = false
	zoom_reference = Vector2(-1, -1)
	update_camera()

func stop_camera_pan(cancel_zoom := true) -> void:
	if cancel_zoom:
		zooming = false
	if camera_pan_tween != null and camera_pan_tween.is_valid():
		camera_pan_tween.kill()

func smooth_pan_to(target: Vector3) -> void:
	stop_camera_pan()
	if focus.is_equal_approx(target):
		return
	camera_pan_tween = create_tween()
	camera_pan_tween.tween_method(_set_camera_focus, focus, target, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _set_camera_focus(value: Vector3) -> void:
	focus = value
	update_camera()
