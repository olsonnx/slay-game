extends RefCounted
## Screen picking is independent of rendering and never changes board state.
const Grid = preload("res://src/game/hex_grid.gd")
const NONE = Grid.NONE

static func candidates(board, origin: Vector3, direction: Vector3) -> Array[Vector2i]:
	# Conservative ray footprint across the full prop/soldier height interval.
	# Expands automatically at shallow angles; never assumes just one ground hex.
	var low := origin + direction * (-origin.y / direction.y)
	var high := origin + direction * ((4.0 - origin.y) / direction.y)
	var corners: Array[Vector2i] = []
	for x in [minf(low.x, high.x) - 2.0, maxf(low.x, high.x) + 2.0]:
		for z in [minf(low.z, high.z) - 2.0, maxf(low.z, high.z) + 2.0]:
			corners.append(Grid.from_world(Vector3(x, 0, z)))
	var q_min := corners[0].x
	var q_max := q_min
	var r_min := corners[0].y
	var r_max := r_min
	for corner in corners:
		q_min = mini(q_min, corner.x)
		q_max = maxi(q_max, corner.x)
		r_min = mini(r_min, corner.y)
		r_max = maxi(r_max, corner.y)
	var result: Array[Vector2i] = []
	for q in range(q_min - 1, q_max + 2):
		for r in range(r_min - 1, r_max + 2):
			var coord := Vector2i(q, r)
			if board.cells.has(coord):
				result.append(coord)
	return result

static func pick_at_screen(board, screen: Vector2, include_water := false, exhaustive := false) -> Dictionary:
	var origin: Vector3 = board.camera.project_ray_origin(screen)
	var direction: Vector3 = board.camera.project_ray_normal(screen)
	if direction.y >= -0.001:
		return {"coord": NONE, "kind": "terrain"}
	var floor_distance: float = -origin.y / direction.y
	var point: Vector3 = origin + direction * floor_distance
	var ground_hex := terrain_at_point(board, point)
	var heatmap: bool = board.get("value_heatmap") != null and board.value_heatmap.active
	var closest: float = floor_distance
	var object_hex := NONE
	var object_kind := "terrain"
	var region: Array = board.cells.keys() if exhaustive else candidates(board, origin, direction)
	# Tall objects and billboard silhouettes are pickable at their visible position.
	for coord in region:
		var cell: Dictionary = board.cells[coord]
		var size := Vector3.ZERO
		if cell.get("mountain", false):
			# Peaks must not steal a neighboring province's ground footprint.
			if ground_hex != NONE and ground_hex != coord:
				continue
			size = Vector3(1.55, 1.70, 1.50)
		elif cell["capital"] >= 0:
			size = Vector3(0.95, 1.35, 0.85)
		elif cell["building"] == "tower":
			size = Vector3(0.68, 1.48, 0.68)
		elif cell["building"] == "house":
			size = Vector3(0.92, 1.10, 0.80)
		elif cell["tree"] and not heatmap:
			size = Vector3(0.86, 1.50, 0.86)
		elif cell.get("treasure", 0) > 0:
			size = Vector3(0.76, 0.56, 0.58)
		elif cell["grave"]:
			size = Vector3(0.46, 0.48, 0.30)
		if size != Vector3.ZERO:
			var at: Vector3 = board.coord_position(coord) - Vector3(size.x * 0.5, 0, size.z * 0.5)
			var distance: float = ray_box(origin, direction, at, at + size)
			if distance < closest:
				closest = distance
				object_hex = coord
				object_kind = "structure"
	var scale_factor: float = board.get_viewport().get_visible_rect().size.y / board.camera.size
	var sprites: Array = []
	if exhaustive or board.is_animating or board.level_transitioning:
		sprites = board.units
	else:
		for coord in region:
			var actor: Node3D = board.unit_actors.get(coord)
			if is_instance_valid(actor):
				for child in actor.get_children():
					if child is Sprite3D:
						sprites.append(child)
	for unit in sprites:
		if not unit.is_visible_in_tree():
			continue
		var pixel_scale: float = unit.pixel_size * scale_factor
		var size := Vector2(unit.texture.get_width(), unit.texture.get_height()) * pixel_scale
		var center: Vector2 = board.camera.unproject_position(unit.global_position)
		var rect := Rect2(center - size * 0.5, size)
		if not rect.has_point(screen):
			continue
		var image: Image = unit.get_meta("image")
		var pixel := (screen - rect.position) / pixel_scale
		if unit.flip_h: pixel.x = image.get_width()-1-floorf(pixel.x)
		if image.get_pixel(clampi(int(pixel.x), 0, image.get_width() - 1), clampi(int(pixel.y), 0, image.get_height() - 1)).a < 0.1:
			continue
		var distance: float = (unit.global_position - origin).dot(direction)
		# Opaque soldier pixels take priority over coarse prop bounding boxes.
		# This keeps a soldier beside/on a castle independently selectable.
		if object_kind != "unit" or distance < closest:
			closest = distance
			object_hex = unit.get_parent().get_meta("hex")
			object_kind = "unit"
	if object_hex != NONE:
		return {"coord": object_hex, "kind": "terrain" if heatmap else object_kind}
	return {"coord": ground_hex if ground_hex != NONE else Grid.from_world(point) if include_water else NONE, "kind": "terrain"}

static func terrain_at_point(board, point: Vector3) -> Vector2i:
	# Axial rounding identifies the one candidate hex; gaps remain unpickable.
	var coord := Grid.from_world(point)
	if not board.cells.has(coord):
		return NONE
	var center := Grid.to_world(coord)
	var local := Vector2(point.x - center.x, point.z - center.z).abs()
	# The pointy-top hex has vertical sides and four 30-degree slopes.
	var half_width := sqrt(3.0) * 0.49
	if local.x <= half_width and local.y <= 0.98 - local.x / sqrt(3.0):
		return coord
	return NONE

static func ray_box(origin: Vector3, direction: Vector3, low: Vector3, high: Vector3) -> float:
	var near_hit := 0.0
	var far_hit := 10000.0
	for axis in range(3):
		if absf(direction[axis]) < 0.00001:
			if origin[axis] < low[axis] or origin[axis] > high[axis]:
				return INF
			continue
		var a: float = (low[axis] - origin[axis]) / direction[axis]
		var b: float = (high[axis] - origin[axis]) / direction[axis]
		near_hit = maxf(near_hit, minf(a, b))
		far_hit = minf(far_hit, maxf(a, b))
		if near_hit > far_hit:
			return INF
	return near_hit

