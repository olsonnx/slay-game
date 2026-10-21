extends RefCounted
## Cosmetic island lifecycle. Tweens belong to the board and pause with gameplay.
signal finished
var board
var tween: Tween
var running := false
var entering := true
var destinations: Dictionary = {}
var moving_batches

func _init(owner_board) -> void:
	board = owner_board

func start(arriving: bool) -> void:
	cancel()
	board.birds.set_loading(not arriving)
	board.birds.hide()
	if board.static_batches != null:
		board.static_batches.set_suspended(true)
	if board.unit_batches != null:
		board.unit_batches.sync()
	entering = arriving
	board.stop_camera_pan()
	var travel: float = board.camera.size + 18.0
	var offset: Vector3 = board.camera.global_basis.y * travel
	# As in the menu, water becomes a backdrop only while tiles fall below it.
	board.water.material_override.set_shader_parameter("backdrop_depth", not entering)
	for coord in board.tile_nodes:
		var tile: Node3D = board.tile_nodes[coord]
		var home: Vector3 = board.coord_position(coord)
		destinations[tile] = home if entering else home + departure_offset(tile.get_parent().global_transform * home)
		if entering:
			tile.position = home + offset
	if not Video.level_transitions or destinations.is_empty():
		finish()
		return
	moving_batches = preload("res://src/rendering/transition_batches.gd").new(board)
	board.board_root.add_child(moving_batches)
	moving_batches.capture()
	running = true
	board.controls_enabled = false
	board.overlay_root.hide()
	# App preparation absorbs loading frames before this render-rate animation.
	tween = board.create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE).set_parallel(true)
	for tile in destinations:
		var coord: Vector2i = tile.get_meta("hex")
		var delay := float(posmod(coord.x * 7 + coord.y * 11, 13)) * 0.018
		if entering:
			tween.tween_property(tile, "position", destinations[tile], 0.72).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			tween.tween_method(_departing_position.bind(tile, destinations[tile]), 0.0, 1.0, 0.72).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(finish)

func departure_offset(world_home: Vector3) -> Vector3:
	var camera: Camera3D = board.camera
	var screen_height := camera.global_basis.y.dot(world_home - camera.global_position)
	# Preserve X/Z so a rear tile cannot slide through foreground land. Include
	# the tallest props when clearing the lower screen edge, just like the menu.
	var screen_distance := (screen_height + camera.size * 0.5 + 4.0) / maxf(camera.global_basis.y.y, 0.0001)
	var depth := -camera.to_local(world_home).z
	# In overhead view gravity projects almost entirely into depth. Stop beyond
	# the far plane rather than sending tiles tens of thousands of units away.
	var depth_distance := (camera.far - depth + 4.0) / maxf(camera.global_basis.z.y, 0.0001)
	return Vector3.DOWN * minf(maxf(camera.size * 0.5, screen_distance), maxf(0.0, depth_distance))

func _departing_position(amount: float, tile: Node3D, destination: Vector3) -> void:
	var home: Vector3 = board.coord_position(tile.get_meta("hex"))
	tile.position = home.lerp(destination, amount)

func release_batches() -> void:
	if is_instance_valid(moving_batches):
		moving_batches.release()
		moving_batches.queue_free()
	moving_batches = null

func restore_settled_batches() -> void:
	board.static_batches.set_suspended(false)
	# Tile home transforms are unchanged: keep the already-uploaded settled
	# meshes unless a setting or visible-board change actually invalidated them.
	if board.static_refresh_pending:
		board.refresh_static_batches()
	else:
		board.static_batches.suppress_cached_sources()
		if board.batch_update_pending: board.flush_batch_update(0)
	board.unit_batches.queue_sync()
	board.unit_batches.sync()

func finish() -> void:
	release_batches()
	if tween != null and tween.is_valid():
		tween.kill()
	for tile in destinations:
		if is_instance_valid(tile):
			tile.position = destinations[tile]
	destinations.clear()
	board.water.material_override.set_shader_parameter("backdrop_depth", false)
	running = false
	board.birds.update_visibility()
	if not entering: board.birds.hide()
	board.controls_enabled = entering
	if board.static_batches != null and entering:
		restore_settled_batches()
	board.overlay_root.visible = entering and not board.get_tree().paused
	finished.emit()

func cancel() -> void:
	var was_running: bool = running or not destinations.is_empty()
	release_batches()
	if tween != null and tween.is_valid():
		tween.kill()
	for tile in destinations:
		if is_instance_valid(tile):
			tile.position = board.coord_position(tile.get_meta("hex"))
	destinations.clear()
	board.water.material_override.set_shader_parameter("backdrop_depth", false)
	running = false
	board.controls_enabled = true
	if board.static_batches != null and was_running:
		restore_settled_batches()
	board.overlay_root.visible = not board.get_tree().paused
