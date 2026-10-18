extends "res://src/rendering/board_assets.gd"
## A scrolling strip: only its incoming/outgoing borders animate or recycle.
const Grid = preload("res://src/game/hex_grid.gd")
const Landscape = preload("res://src/game/decorative_terrain.gd")
const Tile = preload("res://src/rendering/terrain_tile.gd")
const ROW_COUNT := 41
const HALF_COLUMNS := Landscape.HALF_COLUMNS
const ROW_STEP := 1.5
const SCROLL_SPEED := 1.10
const ENTRY_SEAM := -22.0
const EXIT_SEAM := 22.0
var rng := RandomNumberGenerator.new()
var landscape
var rows: Array[Dictionary] = []
var slots: Dictionary = {}
var motions: Dictionary = {}
var camera: Camera3D
var water: MeshInstance3D
var environment: Environment
var sun: DirectionalLight3D
var initial_seed := -1
var scroll_offset := 0.0
var scroll_steps := 0
var changed_tiles := 0
var active := false
var camera_time := 0.0
var camera_aspect := 1.56
var camera_yaw := 0.33
var camera_pitch := 0.55
var skip_hidden_row_updates := true
var freeze_row_motion := false
var freeze_camera_motion := false
var static_batches
var batches_dirty := true
var dirty_batch_tiles: Dictionary = {}
var batch_origin_step := 0
var force_batch_sync := true
var visible_kingdom_joins := false
var slot_by_node: Dictionary = {}
var slot_by_coord: Dictionary = {}

func _ready() -> void:
	set_internal_border_visibility(Video.internal_borders)
	if initial_seed < 0:
		rng.randomize()
	else:
		rng.seed = initial_seed
	landscape = Landscape.new(rng.randi())
	shadow_texture = make_shadow()
	build_world()
	static_batches = preload("res://src/rendering/static_batches.gd").new()
	static_batches.name = "StaticBatches"
	static_batches.mute_source_notifications = true
	static_batches.cache_sources = true
	add_child(static_batches)
	for index in range(ROW_COUNT):
		var world_row := index - ROW_COUNT / 2
		var node := Node3D.new()
		add_child(node)
		var height := world_row * ROW_STEP
		var state := "waiting" if height < ENTRY_SEAM else "gone" if height > EXIT_SEAM else "settled"
		var row := {"index": world_row, "z": height, "node": node, "slots": [], "state": state, "time": 0.0, "rendering": false}
		node.position.z = height
		for column in range(-HALF_COLUMNS, HALF_COLUMNS + 1):
			var id := slots.size()
			var cell: Dictionary = landscape.cell_for(column, world_row)
			var style_coord: Vector2i = cell["decoration_coord"]
			var mask: int = landscape.joined_mask(column, world_row)
			var tile := Tile.build(self, node, style_coord, cell, mask)
			var base := Vector3(sqrt(3.0) * (column + posmod(world_row, 2) * 0.5), 0, 0)
			tile.position = base
			slots[id] = {"node": tile, "cell": cell, "coord": Landscape.coord_at(column, world_row),
				"column": column, "base": base, "style": style_coord, "joined_mask": mask, "logical_joined_mask": mask, "parked": false, "notify_records": []}
			slot_by_node[tile.get_instance_id()] = slots[id]
			slot_by_coord[slots[id]["coord"]] = slots[id]
			configure_timing(slots[id], height)
			row["rendering"] = row["rendering"] or tile.visible
			row["slots"].append(id)
		rows.append(row)
	sync_menu_batches()
	apply_background()

func collect_meshes(node: Node, result: Array) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		collect_meshes(child, result)

func park_hidden_slot(slot: Dictionary) -> void:
	if slot["parked"] or slot["node"].visible:
		return
	var meshes: Array = []
	collect_meshes(slot["node"], meshes)
	for mesh in meshes:
		slot["notify_records"].append([mesh, mesh.is_transform_notification_enabled()])
		mesh.set_notify_transform(false)
	slot["parked"] = true

func wake_slot(slot: Dictionary) -> void:
	if not slot["parked"]:
		return
	for record in slot["notify_records"]:
		var node = record[0]
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.set_notify_transform(record[1])
			RenderingServer.instance_set_transform(node.get_instance(), node.global_transform)
	slot["notify_records"].clear()
	slot["parked"] = false

func refresh_visible_joins(force_all: bool) -> void:
	if not visible_kingdom_joins and not force_all:
		return
	var candidates: Dictionary = {}
	if force_all:
		candidates = slot_by_node.duplicate()
	else:
		for id in dirty_batch_tiles.keys():
			var slot: Dictionary = slot_by_node[id]
			candidates[id] = slot
			for direction in Grid.DIRECTIONS:
				var neighbor: Dictionary = slot_by_coord.get(slot["coord"] + direction, {})
				if not neighbor.is_empty():
					candidates[neighbor["node"].get_instance_id()] = neighbor
	for slot in candidates.values():
		var mask: int = slot["logical_joined_mask"]
		if mask == 0 and slot["joined_mask"] == 0:
			continue
		if visible_kingdom_joins:
			var visible_mask := 0
			if slot["state"] == "settled" and slot["cell"]["land"]:
				for edge in range(6):
					var neighbor: Dictionary = slot_by_coord.get(slot["coord"] + Grid.DIRECTIONS[edge], {})
					if neighbor.get("state") == "settled" and neighbor["cell"]["land"]:
						visible_mask |= 1 << edge
			mask &= visible_mask
		if slot["joined_mask"] != mask:
			slot["joined_mask"] = mask
			Tile.update_join(self, slot["node"], slot["cell"], mask)
			static_batches.refresh_cached_mesh(slot["node"], slot["node"].get_meta("surface"))
			dirty_batch_tiles[slot["node"].get_instance_id()] = true

func sync_menu_batches(force_all := true) -> void:
	refresh_visible_joins(force_all)
	var tiles: Dictionary = {}
	for row in rows:
		for id in row["slots"]:
			var slot: Dictionary = slots[id]
			if slot["state"] == "settled" and slot["cell"]["land"]:
				# Bounded physical columns/rows, independent of streamed style IDs.
				tiles[Vector2i(slot["column"], row["index"] + batch_origin_step)] = slot["node"]
	static_batches.sync_tiles(tiles, dirty_batch_tiles, force_all)
	for slot in slots.values():
		park_hidden_slot(slot)
	batches_dirty = false
	dirty_batch_tiles.clear()
	force_batch_sync = false

func build_world() -> void:
	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("213b45")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8c8d1")
	environment.ambient_light_energy = 0.42
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_color = Color("fff0d3")
	sun.light_energy = 0.88
	# Orthographic scenery needs one shadow projection, without cascade passes.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	# Falling border tiles must not be clipped by the shadow camera's near plane.
	sun.directional_shadow_pancake_size = 0.0
	# The whole visible island fits this range; avoid a moving fade across it.
	sun.directional_shadow_fade_start = 1.0
	sun.shadow_bias = 0.15
	sun.shadow_normal_bias = 2.0
	# Closed hex/prop meshes can use their back faces for the depth pass,
	# keeping the lit surface from sampling its own imprecise shadow depth.
	sun.shadow_reverse_cull_face = true
	sun.shadow_blur = 1.3
	sun.shadow_enabled = Video.shadows
	add_child(sun)
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	water.mesh = plane
	water.position.y = -0.48
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var water_material: ShaderMaterial = preload("res://src/rendering/water_surface.gd").material(true, Video.stylized_water)
	water.material_override = water_material
	add_child(water)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# The default 4,000-unit far plane wastes precision on this compact scene.
	camera.near = 0.1
	camera.far = 90.0
	camera.current = true
	camera.size = 21.5
	add_child(camera)

func layout_camera(aspect: float) -> void:
	camera_aspect = aspect
	update_cinematic_camera()

func update_cinematic_camera() -> void:
	# Low oblique view with a slow, restrained orbit. World-Z scrolling reads diagonally.
	camera_yaw = 0.33 + sin(camera_time * 0.15) * 0.10
	camera_pitch = 0.55 + sin(camera_time * 0.11) * 0.025
	var right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var focus := -right * camera.size * camera_aspect * 0.19
	var direction := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch))
	camera.position = focus + direction * 52.0
	camera.look_at(focus, Vector3.UP)

func apply_background() -> void:
	preload("res://src/rendering/water_surface.gd").set_style(water.material_override, Video.stylized_water)
	if set_internal_border_visibility(Video.internal_borders):
		static_batches.source_cache.clear()
		for slot in slots.values():
			Tile.update_join(self, slot["node"], slot["cell"], slot["joined_mask"])
		sync_menu_batches()
	sun.shadow_enabled = Video.shadows
	water.visible = Video.background == "water"
	environment.background_color = Color("213b45") if water.visible else Color("172e39")

func recycle_row() -> void:
	# This row has already fallen below the viewport. Its existing tiles are reused.
	for row in rows:
		row["z"] += ROW_STEP
	var recycled: Dictionary = rows.pop_back()
	recycled["index"] = rows[0]["index"] - 1
	recycled["z"] = rows[0]["z"] - ROW_STEP
	recycled["state"] = "waiting"
	recycled["time"] = 0.0
	recycled["rendering"] = false
	for id in recycled["slots"]:
		var slot: Dictionary = slots[id]
		wake_slot(slot)
		slot_by_coord.erase(slot["coord"])
		var tile: Node3D = slot["node"]
		tile.hide()
		motions.erase(id)
		var world_row: int = recycled["index"]
		var column: int = slot["column"]
		slot["cell"] = landscape.cell_for(column, world_row)
		slot["coord"] = Landscape.coord_at(column, world_row)
		slot_by_coord[slot["coord"]] = slot
		slot["style"] = slot["cell"]["decoration_coord"]
		slot["joined_mask"] = landscape.joined_mask(column, world_row)
		slot["logical_joined_mask"] = slot["joined_mask"]
		slot["base"] = Vector3(sqrt(3.0) * (column + posmod(world_row, 2) * 0.5), 0, 0)
		tile.position = slot["base"]
		Tile.refresh(self, tile, slot["style"], slot["cell"], slot["joined_mask"])
		static_batches.invalidate_tile(tile)
		configure_timing(slot, recycled["z"])
		recycled["rendering"] = recycled["rendering"] or tile.visible
		changed_tiles += 1
	rows.push_front(recycled)
	scroll_steps += 1
	# Recycled tiles are currently hidden; their entry will add fresh instances.
	landscape.prune(rows[0]["index"], rows[-1]["index"])

func advance(delta: float) -> void:
	if not active:
		return
	camera_time += delta
	if not freeze_camera_motion:
		update_cinematic_camera()
	scroll_offset += delta * SCROLL_SPEED
	while scroll_offset >= ROW_STEP:
		scroll_offset -= ROW_STEP
		recycle_row()
	if scroll_steps - batch_origin_step >= 120:
		batch_origin_step = scroll_steps
		batches_dirty = true
		force_batch_sync = true
	static_batches.position.z = (scroll_steps - batch_origin_step) * ROW_STEP + scroll_offset
	for row in rows:
		var z: float = row["z"] + scroll_offset
		# Hidden overscan must not propagate transforms through thousands of
		# source parts. Visible/leaving tiles always finish their existing motion.
		if skip_hidden_row_updates and not row["rendering"] and (z < -24.0 or z > 25.0):
			continue
		if not freeze_row_motion:
			row["node"].position.z = z
		# Interior rows only need their parent transform; individual scheduling is
		# confined to the two border bands even at high-refresh render rates.
		if row["state"] == "settled" and z > -18.0 and z < 20.0:
			continue
		var falling := false
		var membership_changed := false
		var rendering := false
		for id in row["slots"]:
			var previous_state: String = slots[id]["state"]
			advance_tile(id, z, delta)
			membership_changed = membership_changed or slots[id]["cell"]["land"] and ((slots[id]["state"] == "settled") != (previous_state == "settled"))
			if slots[id]["cell"]["land"] and ((slots[id]["state"] == "settled") != (previous_state == "settled")):
				dirty_batch_tiles[slots[id]["node"].get_instance_id()] = true
			rendering = rendering or slots[id]["node"].visible
			if slots[id]["state"] in ["entering", "leaving"]:
				falling = true
		row["state"] = "moving" if falling else "settled"
		row["rendering"] = rendering
		if membership_changed:
			batches_dirty = true
	if batches_dirty:
		sync_menu_batches(force_batch_sync)

func border_random(coord: Vector2i, salt: int) -> float:
	return float(posmod(coord.x * 73856093 + coord.y * 19349663 + landscape.seed_value + salt, 104729)) / 104729.0

func configure_timing(slot: Dictionary, z: float) -> void:
	var coord: Vector2i = slot["coord"]
	slot["entry_z"] = ENTRY_SEAM + (border_random(coord, 193) - 0.5) * 3.8
	slot["exit_z"] = EXIT_SEAM + (border_random(coord, 719) - 0.5) * 3.8
	slot["entry_duration"] = 0.75 + border_random(coord, 313) * 0.45
	slot["exit_duration"] = 0.60 + border_random(coord, 997) * 0.30
	slot["time"] = 0.0
	slot["state"] = "waiting" if z < slot["entry_z"] else "gone" if z > slot["exit_z"] else "settled"
	slot["node"].position = slot["base"]
	slot["node"].visible = slot["cell"]["land"] and slot["state"] == "settled"

func advance_tile(id: int, z: float, delta: float) -> void:
	var slot: Dictionary = slots[id]
	if not slot["cell"]["land"]:
		# Water slots have no visible arrival/departure to animate.
		slot["state"] = "waiting" if z < slot["entry_z"] else "settled" if z < slot["exit_z"] else "gone"
		return
	if slot["state"] == "waiting" and z >= slot["entry_z"]:
		if slot["cell"]["land"]:
			wake_slot(slot)
		slot["state"] = "entering"
		slot["time"] = 0.0
	elif slot["state"] == "settled" and z >= slot["exit_z"]:
		slot["state"] = "leaving"
		slot["time"] = 0.0
	if slot["state"] not in ["entering", "leaving"]:
		return
	slot["time"] += delta
	var entering: bool = slot["state"] == "entering"
	var duration: float = slot["entry_duration"] if entering else slot["exit_duration"]
	var time := clampf(slot["time"] / duration, 0.0, 1.0)
	var amount := smoothstep(0.0, 1.0, time)
	var tile: Node3D = slot["node"]
	var travel := camera.global_basis.y * camera.size * 0.65
	if not entering:
		# A screen-plane slide with cancelled height moved toward the camera,
		# crossing in front of neighbours. Gravity keeps the tile's footprint
		# fixed so foreground land naturally occludes it as it drops.
		var home: Vector3 = tile.get_parent().global_transform * slot["base"]
		var screen_height := camera.global_basis.y.dot(home - camera.global_position)
		# Clear the bottom edge with room for the tallest decorative props.
		var distance := maxf(camera.size * 0.5, (screen_height + camera.size * 0.5 + 4.0) / camera.global_basis.y.y)
		travel = Vector3.DOWN * distance
	tile.visible = slot["cell"]["land"]
	tile.position = slot["base"] + travel * (1.0 - amount if entering else amount)
	if time >= 1.0:
		slot["state"] = "settled" if entering else "gone"
		tile.position = slot["base"]
		tile.visible = slot["cell"]["land"] and entering
		motions.erase(id)
	elif slot["cell"]["land"]:
		motions[id] = slot["state"]
