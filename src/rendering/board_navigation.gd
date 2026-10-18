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

func update_camera() -> void:
	camera.size = zoom
	# Keep the whole orthographic view above the ocean at wide, shallow angles.
	var distance_from_focus := 42.0
	if water_background:
		distance_from_focus = maxf(42.0, (zoom * 0.5 * cos(pitch) + 2.0) / sin(pitch))
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance_from_focus
	camera.look_at(focus, Vector3.UP)
	changed.emit()

func configure_map(size_id: String, bounds: Vector2, layout: Dictionary = {}) -> void:
	default_zoom = preload("res://src/game/map_sizes.gd").spec(size_id)["zoom"]
	map_center = Vector3.ZERO
	if not layout.is_empty():
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for coord in layout:
			var at := Grid.to_world(coord)
			low = low.min(Vector2(at.x, at.z))
			high = high.max(Vector2(at.x, at.z))
		map_center = Vector3((low.x + high.x) * 0.5, 0, (low.y + high.y) * 0.5)
		var span := high - low + Vector2.ONE * 3.0
		var aspect := get_viewport().get_visible_rect().size.x / maxf(1.0, get_viewport().get_visible_rect().size.y)
		var projected_width := cos(0.18) * span.x + sin(0.18) * span.y
		var projected_height := sin(0.92) * (sin(0.18) * span.x + cos(0.18) * span.y) + 4.0
		default_zoom = maxf(default_zoom, maxf(projected_height, projected_width / aspect) * 1.18)
	navigation_limits = Vector2(maxf(18, bounds.x), maxf(14, bounds.y))
	max_zoom = maxf(38, default_zoom * 1.7)

func pan(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx():
		return
	stop_camera_pan()
	manual_moved.emit()
	var movement := direction.normalized()
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var backward := Vector3(sin(yaw), 0, cos(yaw))
	focus += (right * movement.x + backward * movement.y) * zoom * 0.48 * delta
	focus.x = clampf(focus.x, -navigation_limits.x, navigation_limits.x)
	focus.z = clampf(focus.z, -navigation_limits.y, navigation_limits.y)
	update_camera()

func orbit(relative: Vector2) -> void:
	stop_camera_pan()
	manual_moved.emit()
	if top_down:
		top_down = false
		pitch = saved_pitch
		yaw = saved_yaw
	yaw -= relative.x * 0.006
	pitch = clampf(pitch + relative.y * 0.004, 0.44, 1.37)
	update_camera()

func drag_pan(relative: Vector2) -> void:
	if relative.is_zero_approx() or not controls_enabled:
		return
	stop_camera_pan()
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

func change_zoom(steps: float) -> void:
	stop_camera_pan()
	manual_moved.emit()
	zoom = clampf(zoom * pow(0.88, steps), 8.0, max_zoom)
	update_camera()

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
	update_camera()

func reset_camera() -> void:
	stop_camera_pan()
	manual_moved.emit()
	focus = map_center
	yaw = 0.18
	pitch = 0.92
	zoom = default_zoom
	top_down = false
	rotating = false
	update_camera()

func stop_camera_pan() -> void:
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
