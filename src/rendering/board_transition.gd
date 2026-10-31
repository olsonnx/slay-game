extends RefCounted
## Cosmetic island lifecycle. Tweens belong to the board and pause with gameplay.
signal finished
var board
var tween: Tween
var running := false
var entering := true
var destinations: Dictionary = {}
var moving_batches
var departure_far := -1.0

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
	board.navigation.stop_camera_pan(true,true)
	var travel: float = board.camera.size + 18.0
	var offset: Vector3 = board.camera.global_basis.y * travel
	var departure_move := Vector3.ZERO
	if not entering:
		for tile in board.tile_nodes.values():
			var home: Vector3 = board.coord_position(tile.get_meta("hex"))
			var candidate := departure_offset(tile.get_parent().global_transform * home)
			if candidate.length_squared() > departure_move.length_squared(): departure_move = candidate
	# As in the menu, water becomes a backdrop only while tiles fall below it.
	board.water.material_override.set_shader_parameter("backdrop_depth", not entering)
	for coord in board.tile_nodes:
		var tile: Node3D = board.tile_nodes[coord]
		var home: Vector3 = board.coord_position(coord)
		# One displacement keeps neighboring tiles from converging on a common
		# screen-edge endpoint. Only their existing stagger changes the fall timing.
		destinations[tile] = home if entering else home + departure_move
		if entering:
			tile.position = home + offset
	if not Video.level_transitions or Video.reduced_motion or destinations.is_empty():
		finish()
		return
	if not entering:
		departure_far = board.camera.far
		extend_departure_depth()
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
	# Normal views keep gravity and each tile's footprint. Near overhead, blend
	# toward screen-down so the island leaves the frame instead of a depth plane.
	var pitch := asin(clampf(camera.global_basis.z.y, -1.0, 1.0))
	var overhead := smoothstep(deg_to_rad(65.0), deg_to_rad(85.0), pitch)
	var direction := Vector3.DOWN.lerp(-camera.global_basis.y, overhead * 0.8).normalized()
	var screen_speed := -camera.global_basis.y.dot(direction)
	# Include the full tile and its tallest scenery beyond the bottom edge.
	var screen_distance := (screen_height + camera.size * 0.5 + 4.0) / maxf(screen_speed, 0.1)
	return direction * maxf(camera.size * 0.5, screen_distance)

func extend_departure_depth() -> void:
	for tile in destinations:
		var endpoint: Vector3 = tile.get_parent().global_transform * destinations[tile]
		board.camera.far = maxf(board.camera.far, -board.camera.to_local(endpoint).z + 6.0)

func camera_changed() -> void:
	if departure_far < 0.0: return
	# Navigation recomputed the normal depth range, e.g. after resizing or a
	# paused video-setting change. Retain that range for restoration afterwards.
	departure_far = board.camera.far
	extend_departure_depth()

func restore_camera_depth() -> void:
	if departure_far < 0.0: return
	board.camera.far = departure_far
	departure_far = -1.0

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
	restore_camera_depth()
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
	restore_camera_depth()
	board.water.material_override.set_shader_parameter("backdrop_depth", false)
	running = false
	board.controls_enabled = true
	if board.static_batches != null and was_running:
		restore_settled_batches()
	board.overlay_root.visible = not board.get_tree().paused
