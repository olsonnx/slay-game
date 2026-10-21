extends "res://src/rendering/board_assets.gd"
## Real 3D terrain and architecture with original billboard pixel characters.

const NONE := Vector2i(999, 999)
const Grid = preload("res://src/game/hex_grid.gd")
const BoardPicker = preload("res://src/rendering/board_picker.gd")
const BoardPlayback = preload("res://src/rendering/board_playback.gd")
const BoardTransition = preload("res://src/rendering/board_transition.gd")
const BoardOverlays = preload("res://src/rendering/board_overlays.gd")
const TileEffects = preload("res://src/rendering/board_tile_effects.gd")
const PLACEMENT_COLOR := Color("ead29e")

signal action_started(action: Dictionary)
signal action_finished(action: Dictionary)
signal motion_stage(action: Dictionary, stage: String)
signal visible_board_changed
signal manual_camera_moved
signal level_transition_finished
var navigation = preload("res://src/rendering/board_navigation.gd").new()
var active := true
var lighting
var land_ambience
var island_transition
var overlays
var level_transitioning: bool:
	get:
		return island_transition != null and island_transition.running

var board_root: Node3D
var overlay_root: Node3D
var animation_root: Node3D
var camera: Camera3D
var tile_nodes: Dictionary = {}
var unit_presentation = preload("res://src/rendering/unit_presentation.gd").new(self, tile_nodes)
var units: Array[Sprite3D]:
	get: return unit_presentation.units
var hovered_unit: Sprite3D:
	get: return unit_presentation.hovered_unit
var unit_hover_tweens: Dictionary:
	get: return unit_presentation.unit_hover_tweens
var unit_actors: Dictionary:
	get: return unit_presentation.unit_actors
var playback
var value_heatmap
var static_batches
var unit_batches
var unit_spawn_effects
var birds
var wildlife
var batch_dirty_ids: Dictionary = {}
var batch_update_pending := false
var bulk_rebuilding := false
var static_refresh_pending := false
var batch_incremental_event := false
# Nonempty only while delivering a scoped visible-state notification.
var visible_change_coords: Dictionary = {}
var active_motions: Dictionary:
	get:
		return playback.active_motions
var is_animating: bool:
	get:
		return playback.is_animating
var intent_preview: Node3D
var dirty_tiles: Dictionary = {}
var profile_capture := false
var capture_samples: Array = []
var batch_last_flush_frame := -1
const CAPTURE_BATCH_BUDGET_USEC := 1500
var tiles_built := 0
var sun: DirectionalLight3D
var background_environment: Environment
var sky_backdrop: CanvasLayer
var water: MeshInstance3D
var camera_pan_tween: Tween:
	get: return navigation.camera_pan_tween
	set(value): navigation.camera_pan_tween = value
const VISUAL_FIELDS := ["owner", "unit", "moved", "capital", "tree", "grave", "building", "mana_source", "unit_owner", "fortified", "entrenched_by", "mountain", "barrier_by", "event", "treasure", "animal", "animal_home", "animal_target", "lair"]
const PROP_FIELDS := ["capital", "tree", "grave", "building", "mana_source", "fortified", "entrenched_by", "barrier_by", "event", "treasure", "lair"]
var cells: Dictionary = {}
var focus: Vector3:
	get: return navigation.focus
	set(value): navigation.focus = value
var yaw: float:
	get: return navigation.yaw
	set(value): navigation.yaw = value
var pitch: float:
	get: return navigation.pitch
	set(value): navigation.pitch = value
var zoom: float:
	get: return navigation.zoom
	set(value): navigation.zoom = value
var default_zoom: float:
	get: return navigation.default_zoom
	set(value): navigation.default_zoom = value
var map_center: Vector3:
	get: return navigation.map_center
	set(value): navigation.map_center = value
var navigation_limits: Vector2:
	get: return navigation.navigation_limits
	set(value): navigation.navigation_limits = value
var max_zoom: float:
	get: return navigation.max_zoom
	set(value): navigation.max_zoom = value
var top_down: bool:
	get: return navigation.top_down
	set(value): navigation.top_down = value
var saved_yaw: float:
	get: return navigation.saved_yaw
	set(value): navigation.saved_yaw = value
var saved_pitch: float:
	get: return navigation.saved_pitch
	set(value): navigation.saved_pitch = value
var rotating: bool:
	get: return navigation.rotating
	set(value):
		navigation.rotating = value
		if not value: zoom_reference = Vector2(-1, -1)
var zoom_reference: Vector2:
	get: return navigation.zoom_reference
	set(value): navigation.zoom_reference = value
var controls_enabled: bool:
	get: return navigation.controls_enabled
	set(value): navigation.controls_enabled = value
var cap_mesh: CylinderMesh
var earth_mesh: CylinderMesh
var outline_mesh: ArrayMesh
var cached_pick_key: Array = []
var cached_pick: Dictionary = {}
var startup_timings: Dictionary = {}

func _init() -> void:
	# Ownership starts before entering the tree, including abandoned previews.
	add_child(navigation)
	add_child(unit_presentation)

func build_initial_cells(new_cells: Dictionary) -> void:
	# Initial construction only. Ordinary commands keep their atomic render path.
	assert(tile_nodes.is_empty())
	var was_rebuilding := bulk_rebuilding
	bulk_rebuilding = true
	cells = new_cells.duplicate(true)
	var started := Time.get_ticks_usec()
	var batch_started := started
	var cpu_usec := 0
	var max_batch_usec := 0
	var batches := 0
	for coord in cells:
		build_tile(coord, cells[coord])
		var elapsed := Time.get_ticks_usec() - batch_started
		if elapsed >= 4000:
			cpu_usec += elapsed
			max_batch_usec = maxi(max_batch_usec, elapsed)
			batches += 1
			await get_tree().process_frame
			batch_started = Time.get_ticks_usec()
	var elapsed := Time.get_ticks_usec() - batch_started
	cpu_usec += elapsed
	max_batch_usec = maxi(max_batch_usec, elapsed)
	startup_timings = {"scene_build_ms": cpu_usec / 1000.0, "build_wall_ms": (Time.get_ticks_usec() - started) / 1000.0, "max_batch_ms": max_batch_usec / 1000.0, "batches": batches + 1}
	dirty_tiles.clear()
	var publish_started := Time.get_ticks_usec()
	if not was_rebuilding:
		await static_batches.sync_tiles(tile_nodes, {}, true, {}, 4000)
		startup_timings["max_publish_batch_ms"] = static_batches.startup_max_batch_usec / 1000.0
		batch_dirty_ids.clear()
		batch_update_pending = false
	visible_board_changed.emit()
	bulk_rebuilding = was_rebuilding
	if not was_rebuilding: wildlife.sync()
	startup_timings["publish_wall_ms"] = (Time.get_ticks_usec() - publish_started) / 1000.0
	if not was_rebuilding:
		unit_batches.queue_sync()
		unit_batches.sync()

func retire_cells() -> void:
	# A restarted playtest must not free thousands of source nodes in one frame.
	bulk_rebuilding = true
	static_batches.suspended = true
	# Covered retirement no longer needs picking or idle animation registries.
	# Clear them once instead of scanning the army again for every removed tile.
	unit_presentation.clear_unit_hover()
	unit_presentation.units.clear()
	unit_presentation.idle_units.clear()
	birds.clear()
	wildlife.clear()
	var batch_started := Time.get_ticks_usec()
	var retired := 0
	for coord in tile_nodes.keys():
		remove_tile(coord)
		retired += 1
		if retired >= 24 or Time.get_ticks_usec() - batch_started >= 3000:
			await get_tree().process_frame
			batch_started = Time.get_ticks_usec()
			retired = 0
	await get_tree().process_frame

func replace_cells(new_cells: Dictionary) -> void:
	# Editor loads replace the whole island, while normal painting stays atomic.
	stop_camera_pan()
	birds.clear()
	wildlife.clear()
	bulk_rebuilding = true
	static_batches.suspended = true
	unit_batches.hide()
	var batch_started := Time.get_ticks_usec()
	for coord in tile_nodes.keys():
		remove_tile(coord)
		if Time.get_ticks_usec() - batch_started >= 4000:
			await get_tree().process_frame
			batch_started = Time.get_ticks_usec()
	# Retire old uploads before building the replacement; keep source visibility
	# available to batch collection beneath the opaque preparation screen.
	unit_batches.restore_sources()
	static_batches.suspended = false
	static_batches.sync_tiles({})
	batch_dirty_ids.clear()
	batch_update_pending = false
	await build_initial_cells(new_cells)
	# Publish one retained region per frame, with the full terrain neighborhood
	# available for coastline culling even before its region is uploaded.
	var regions: Dictionary = {}
	for coord in tile_nodes:
		var region := Vector2i(floori(float(coord.x) / static_batches.chunk_size), floori(float(coord.y) / static_batches.chunk_size))
		if not regions.has(region): regions[region] = {}
		regions[region][coord] = tile_nodes[coord]
	var published: Dictionary = {}
	for region_tiles in regions.values():
		published.merge(region_tiles)
		var ids := {}
		for tile in region_tiles.values(): ids[tile.get_instance_id()] = true
		static_batches.sync_tiles(published, ids, false, tile_nodes)
		await get_tree().process_frame
	bulk_rebuilding = false
	batch_dirty_ids.clear()
	batch_update_pending = false
	wildlife.sync()
	unit_batches.queue_sync()
	unit_batches.sync()
	invalidate_pick()

func _ready() -> void:
	overlays = BoardOverlays.new(self)
	visible_board_changed.connect(overlays.invalidate)
	set_internal_border_visibility(Video.internal_borders)
	visible_board_changed.connect(invalidate_pick)
	playback = BoardPlayback.new(self)
	add_child(playback)
	board_root = Node3D.new()
	add_child(board_root)
	overlay_root = Node3D.new()
	add_child(overlay_root)
	animation_root = Node3D.new()
	add_child(animation_root)
	cap_mesh = cylinder_mesh(0.968, 0.968, 0.075, 6)
	earth_mesh = cylinder_mesh(1.0, 1.0, 0.56, 6)
	outline_mesh = ring_mesh()
	playback.prepare_effects()
	unit_spawn_effects = preload("res://src/rendering/unit_spawn_effects.gd").new(self)
	unit_spawn_effects.name = "UnitSpawnEffects"
	board_root.add_child(unit_spawn_effects)
	shadow_texture = make_shadow()
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	background_environment = settings
	settings.background_mode = Environment.BG_CANVAS
	settings.background_canvas_max_layer = -1
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b8c8d1")
	settings.ambient_light_energy = 0.42
	environment.environment = settings
	add_child(environment)
	var backdrop_layer := CanvasLayer.new()
	sky_backdrop = backdrop_layer
	backdrop_layer.name = "VoidBackdrop"
	backdrop_layer.layer = -100
	add_child(backdrop_layer)
	var backdrop := ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop_material := ShaderMaterial.new()
	backdrop_material.shader = preload("res://resources/shaders/void_backdrop.gdshader")
	backdrop.material = backdrop_material
	backdrop_layer.add_child(backdrop)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_color = Color("fff0d3")
	sun.light_energy = 0.88
	sun.shadow_enabled = Video.shadows
	# One stable projection avoids changing shadow shaders during zoom.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	Video.changed.connect(_apply_video_settings)
	sun.directional_shadow_max_distance = 75
	add_child(sun)
	water = MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	water.mesh = plane
	water.position.y = -0.48
	var water_material: ShaderMaterial = preload("res://src/rendering/water_surface.gd").material(false, Video.stylized_water)
	water.material_override = water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 1000
	camera.current = true
	add_child(camera)
	navigation.camera = camera
	navigation.changed.connect(_on_camera_changed)
	navigation.manual_moved.connect(func(): manual_camera_moved.emit())
	sprite_lighting = preload("res://src/rendering/sprite_lighting.gd").new()
	add_child(sprite_lighting)
	lighting = preload("res://src/rendering/board_lighting.gd").new(self)
	add_child(lighting)
	visible_board_changed.connect(lighting.refresh_sources)
	lighting.apply_style("atmospheric" if Video.atmospheric_lighting else "simple")
	land_ambience = preload("res://src/audio/land_ambience.gd").new(self)
	add_child(land_ambience)
	_apply_background()
	add_child(preload("res://src/rendering/screen_edge_softening.gd").new())
	island_transition = BoardTransition.new(self)
	island_transition.finished.connect(func(): level_transition_finished.emit())
	island_transition.finished.connect(lighting.update_camera)
	value_heatmap = preload("res://src/rendering/value_heatmap.gd").new(self)
	add_child(value_heatmap)
	visible_board_changed.connect(value_heatmap.sync)
	static_batches = preload("res://src/rendering/static_batches.gd").new()
	static_batches.name = "StaticBatches"
	static_batches.cache_sources = true
	static_batches.shadow_min_size = 0.35
	# Bound capture uploads to one terrain region per chunk.
	static_batches.chunk_size = 12
	static_batches.terrain_group_size = 12
	static_batches.merge_terrain = true
	board_root.add_child(static_batches)
	unit_batches = preload("res://src/rendering/army_batches.gd").new(self)
	unit_batches.name = "ArmyBatches"
	board_root.add_child(unit_batches)
	unit_presentation.unit_batches = unit_batches
	visible_board_changed.connect(refresh_static_batches)
	birds = preload("res://src/rendering/ambient_birds.gd").new(self)
	board_root.add_child(birds)
	visible_board_changed.connect(birds.sync)
	wildlife = preload("res://src/rendering/wildlife_presentation.gd").new(self)
	board_root.add_child(wildlife)
	visible_board_changed.connect(wildlife.sync)
	overlays.prepare_building_previews()
	value_heatmap.changed.connect(refresh_static_batches)
	value_heatmap.changed.connect(lighting.update_camera)

func refresh_static_batches() -> void:
	if bulk_rebuilding: return
	if unit_batches != null and not batch_incremental_event:
		unit_batches.queue_sync()
	if batch_incremental_event:
		queue_batch_update()
		return
	if static_batches != null and level_transitioning:
		static_refresh_pending = true
		return
	if static_batches != null:
		static_refresh_pending = false
		static_batches.source_cache.clear()
		static_batches.sync_tiles(tile_nodes)
		batch_dirty_ids.clear()
		batch_update_pending = false

func mark_batch_dirty(coord: Vector2i) -> void:
	if static_batches != null and tile_nodes.has(coord):
		var tile: Node3D = tile_nodes[coord]
		static_batches.invalidate_tile(tile)
		batch_dirty_ids[tile.get_instance_id()] = true

func queue_batch_update() -> void:
	if not batch_update_pending:
		batch_update_pending = true
		flush_batch_update.call_deferred(CAPTURE_BATCH_BUDGET_USEC)

func flush_batch_update(budget_usec := 0) -> void:
	if bulk_rebuilding or not batch_update_pending or static_batches == null or level_transitioning:
		return
	var frame := Engine.get_process_frames()
	if budget_usec > 0 and batch_last_flush_frame == frame: return
	batch_last_flush_frame = frame
	var topology_changed: bool = static_batches.tile_records.size() != tile_nodes.size()
	for id in batch_dirty_ids:
		if not static_batches.tile_records.has(id): topology_changed = true
	if budget_usec == 0 or topology_changed:
		if not batch_dirty_ids.is_empty() or static_batches.tile_records.size() != tile_nodes.size():
			static_batches.sync_tiles(tile_nodes, batch_dirty_ids, false)
		batch_dirty_ids.clear()
	else:
		# One coherent chunk is the smallest upload transaction. Other chunks
		# retain their previous geometry until their turn; repeated edits coalesce.
		var groups: Dictionary = {}
		for id in batch_dirty_ids:
			if static_batches.tile_records.has(id):
				var chunk: Vector2i = static_batches.tile_records[id]["chunk"]
				if not groups.has(chunk): groups[chunk] = {}
				groups[chunk][id] = true
		var started := Time.get_ticks_usec()
		for ids in groups.values():
			static_batches.sync_tiles(tile_nodes, ids, false)
			for id in ids: batch_dirty_ids.erase(id)
			if Time.get_ticks_usec() - started >= budget_usec: break
		# IDs whose source was removed are handled by the topology path above.
		if groups.is_empty(): batch_dirty_ids.clear()
	batch_update_pending = not batch_dirty_ids.is_empty()

func notify_visible_board_changed(changed_coords: Dictionary = {}, army_coords = null) -> void:
	var started := Time.get_ticks_usec() if profile_capture else 0
	if unit_batches != null:
		if army_coords == null:
			unit_batches.queue_sync(changed_coords if not changed_coords.is_empty() else dirty_tiles, false)
		elif not army_coords.is_empty(): unit_batches.queue_sync(army_coords, false)
	# Signal listeners see the complete visible state. Concurrent tween callbacks
	# share one batch update before drawing instead of rescanning per actor.
	var previous_coords := visible_change_coords
	visible_change_coords = changed_coords if not changed_coords.is_empty() else dirty_tiles
	batch_incremental_event = true
	visible_board_changed.emit()
	visible_change_coords = previous_coords
	batch_incremental_event = false
	if profile_capture: record_capture_sample({"stage": "visible_listeners", "ms": (Time.get_ticks_usec() - started) / 1000.0})

func _process(delta: float) -> void:
	if batch_update_pending: flush_batch_update(CAPTURE_BATCH_BUDGET_USEC)
	if controls_enabled:
		var input := Vector2.ZERO
		input.x = float(Keys.held("pan_right")) - float(Keys.held("pan_left"))
		input.y = float(Keys.held("pan_down")) - float(Keys.held("pan_up"))
		pan(input, delta)

func _apply_video_settings() -> void:
	if set_internal_border_visibility(Video.internal_borders):
		var terrain = preload("res://src/rendering/terrain_tile.gd")
		for coord in tile_nodes:
			terrain.update_join(self, tile_nodes[coord], cells[coord], terrain.joined_mask(cells, coord))
		refresh_static_batches()
	sun.shadow_enabled = Video.shadows
	if lighting != null: lighting.apply_style("atmospheric" if Video.atmospheric_lighting else "simple")
	_apply_background()
	if not Video.follow_turn_camera:
		stop_camera_pan()
	if not Video.level_transitions and level_transitioning:
		island_transition.finish()

func _apply_background() -> void:
	preload("res://src/rendering/water_surface.gd").set_style(water.material_override, Video.stylized_water)
	var use_water: bool = Video.background == "water"
	water.visible = use_water
	sky_backdrop.visible = active and not use_water
	navigation.water_background = use_water
	background_environment.background_mode = Environment.BG_COLOR if use_water else Environment.BG_CANVAS
	background_environment.background_color = Color("253d47")
	update_camera()

func start_level_transition(entering: bool) -> void:
	playback.clear_tree_growth()
	value_heatmap.set_active(false)
	clear_unit_hover()
	island_transition.start(entering)
	if lighting != null: lighting.update_camera()

func cancel_level_transition() -> void:
	if island_transition != null:
		island_transition.cancel()

func coord_position(coord: Vector2i) -> Vector3:
	return Grid.to_world(coord)

func update_camera() -> void:
	navigation.update_camera()

func configure_map(size_id: String, bounds: Vector2, layout: Dictionary = {}) -> void:
	if birds != null: birds.clear()
	if wildlife != null: wildlife.clear()
	if unit_spawn_effects != null: unit_spawn_effects.clear()
	navigation.configure_map(size_id, bounds, layout)

func pan(direction: Vector2, delta: float) -> void:
	navigation.pan(direction, delta)

func orbit(relative: Vector2) -> void:
	navigation.orbit(relative)

func drag_pan(relative: Vector2) -> void:
	navigation.drag_pan(relative)

func change_zoom(steps: float, cursor := Vector2(-1, -1)) -> void:
	navigation.change_zoom(steps, cursor)

func toggle_top_down() -> void:
	navigation.toggle_top_down()

func reset_camera() -> void:
	navigation.reset_camera()

func stop_camera_pan() -> void:
	navigation.stop_camera_pan()

func smooth_pan_to(target: Vector3) -> void:
	navigation.smooth_pan_to(target)

func _set_camera_focus(value: Vector3) -> void:
	navigation._set_camera_focus(value)

func hex_at_screen(screen: Vector2, include_water := false) -> Vector2i:
	return pick_at_screen(screen, include_water)["coord"]

func pick_at_screen(screen: Vector2, include_water := false) -> Dictionary:
	# Animated actors can move between board notifications; always query them live.
	if is_animating or level_transitioning:
		return BoardPicker.pick_at_screen(self, screen, include_water)
	var key := [screen, include_water, camera.global_transform, camera.projection,
		camera.size, camera.fov, camera.near, get_viewport().get_visible_rect()]
	if cached_pick_key != key:
		cached_pick = BoardPicker.pick_at_screen(self, screen, include_water)
		cached_pick_key = key
	return cached_pick.duplicate()

func invalidate_pick() -> void:
	cached_pick_key.clear()

func render_cells(new_cells: Dictionary, partial := false, animate_trees := false) -> void:
	var started := Time.get_ticks_usec() if profile_capture else 0
	clear_unit_hover()
	if level_transitioning:
		cancel_level_transition()
	var previous := cells
	# Cell records are private to the visible board. Copy only changed records;
	# the rules may already be several commands ahead of animation playback.
	var changed: Dictionary = dirty_tiles.duplicate()
	if not partial:
		for coord in previous:
			if not new_cells.has(coord): changed[coord] = true
	for coord in new_cells:
		if previous.get(coord, {}) != new_cells[coord]: changed[coord] = true
	# Settlement often submits the already displayed snapshot again.
	if changed.is_empty() and animation_root.get_child_count() == 0:
		if wildlife != null and wildlife.sync_required: wildlife.sync()
		return
	cells = previous.duplicate()
	for coord in changed:
		if new_cells.has(coord): cells[coord] = new_cells[coord].duplicate(true)
		elif not partial: cells.erase(coord)
	var copied := Time.get_ticks_usec() if profile_capture else 0
	for child in animation_root.get_children():
		animation_root.remove_child(child)
		child.queue_free()
	for coord in changed:
		if not cells.has(coord):
			remove_tile(coord)
	var affected := changed.duplicate()
	var army_changed := {}
	for coord in changed:
		var old: Dictionary = previous.get(coord, {})
		var cell: Dictionary = cells.get(coord, {})
		var protected: bool = old.get("fortified", false) or cell.get("fortified", false) or old.get("entrenched_by", -1) >= 0 or cell.get("entrenched_by", -1) >= 0 or old.get("barrier_by", -1) >= 0 or cell.get("barrier_by", -1) >= 0
		if old.is_empty() or cell.is_empty() or protected or old.get("unit", 0) > 0 or cell.get("unit", 0) > 0 or unit_actors.has(coord):
			army_changed[coord] = true
		else:
			for field in ["fortified", "entrenched_by", "barrier_by"]:
				if old.get(field) != cell.get(field): army_changed[coord] = true
	for coord in changed:
		for direction in Grid.DIRECTIONS:
			if cells.has(coord + direction): affected[coord + direction] = true
	for coord in affected:
		if not cells.has(coord): continue
		var old: Dictionary = previous.get(coord, {})
		var cell: Dictionary = cells[coord]
		var terrain_changed: bool = old.is_empty() or old.get("mountain", false) != cell.get("mountain", false) or (old["building"] == "bridge") != (cell["building"] == "bridge")
		if terrain_changed:
			remove_tile(coord)
			build_tile(coord, cell)
		else:
			var terrain = preload("res://src/rendering/terrain_tile.gd")
			var props_changed: bool = tile_nodes[coord].get_meta("scenery_state", []) != scenery_state(cell)
			if props_changed:
				for name_value in ["Fortification", "Barrier"]:
					var decoration: Node = tile_nodes[coord].get_node_or_null(name_value)
					if decoration != null:
						tile_nodes[coord].remove_child(decoration)
						decoration.queue_free()
				terrain.refresh(self, tile_nodes[coord], coord, cell, terrain.joined_mask(cells, coord))
				populate_tile_decorations(tile_nodes[coord], cell)
				mark_batch_dirty(coord)
			refresh_unit(coord, cell)
			var before_mesh: Mesh = tile_nodes[coord].get_meta("surface").mesh
			terrain.update_join(self, tile_nodes[coord], cell, terrain.joined_mask(cells, coord))
			if tile_nodes[coord].get_meta("surface").mesh != before_mesh:
				mark_batch_dirty(coord)
	dirty_tiles.clear()
	if profile_capture:
		record_capture_sample({"stage": "visible_copy", "ms": (copied - started) / 1000.0, "changed": changed.size()})
		record_capture_sample({"stage": "tile_updates", "ms": (Time.get_ticks_usec() - copied) / 1000.0, "affected": affected.size()})
	if animate_trees or (wildlife != null and wildlife.is_playing):
		for coord in changed:
			if cells.get(coord, {}).get("tree", false) and not previous.get(coord, {}).get("tree", false):
				playback.grow_tree(coord)
	notify_visible_board_changed(affected, army_changed)
	flush_batch_update(CAPTURE_BATCH_BUDGET_USEC)

func remove_unit(coord: Vector2i) -> void:
	unit_presentation.remove_unit(coord)

func settle_unit(actor: Node3D, source: Vector2i, target: Vector2i) -> void:
	unit_presentation.settle_unit(actor, source, target, cells)

func refresh_unit(coord: Vector2i, cell: Dictionary) -> void:
	unit_presentation.refresh_unit(coord, cell)

func remove_tile(coord: Vector2i) -> void:
	remove_unit(coord)
	if tile_nodes.has(coord):
		var tile: Node3D = tile_nodes[coord]
		if static_batches != null:
			static_batches.invalidate_tile(tile)
			batch_dirty_ids[tile.get_instance_id()] = true
		board_root.remove_child(tile)
		tile.queue_free()
		tile_nodes.erase(coord)
		for direction in Grid.DIRECTIONS:
			mark_batch_dirty(coord + direction)

func build_tile(coord: Vector2i, cell: Dictionary) -> void:
	tiles_built += 1
	var terrain = preload("res://src/rendering/terrain_tile.gd")
	var tile: Node3D = terrain.build(self, board_root, coord, cell, terrain.joined_mask(cells, coord))
	tile_nodes[coord] = tile
	populate_tile_decorations(tile, cell)
	refresh_unit(coord, cell)
	mark_batch_dirty(coord)
	for direction in Grid.DIRECTIONS:
		mark_batch_dirty(coord + direction)

func scenery_state(cell: Dictionary) -> Array:
	# Movement dirties actors too; retain scenery unless its drawn state changed.
	# Store the drawn state because playback updates cells before settling actors.
	var result: Array = [cell["owner"], cell.get("land", true)]
	for field in PROP_FIELDS: result.append(cell.get(field))
	result.append(cell["capital"] >= 0 and cell["unit"] > 0)
	return result

func populate_tile_decorations(tile: Node3D, cell: Dictionary) -> void:
	tile.set_meta("scenery_state", scenery_state(cell))
	if cell.get("fortified", false) or cell.get("entrenched_by", -1) >= 0:
		add_fortification(tile, cell.get("entrenched_by", -1) >= 0)
	if cell.get("barrier_by", -1) >= 0:
		add_barrier(tile)
	if cell.get("event", "") != "":
		add_event_relief(tile.get_node("Features"), cell["tree"])

func add_event_relief(features: Node3D, wooded: bool) -> void:
	TileEffects.add_event_relief(self, features, wooded)

func add_barrier(tile: Node3D) -> void:
	TileEffects.add_barrier(self, tile)

func add_fortification(tile: Node3D, entrenched := false) -> void:
	TileEffects.add_fortification(self, tile, entrenched)

func add_unit(parent: Node3D, tier: int, owner: int, moved: bool, on_capital: bool) -> Node3D:
	return unit_presentation.add_unit(parent, tier, owner, moved, on_capital)

func set_unit_hover(coord: Vector2i, kind := "unit") -> void:
	var enabled := not is_animating and not level_transitioning
	unit_presentation.set_unit_hover(coord if kind == "unit" else NONE, enabled)
	wildlife.set_hover(coord if kind == "wildlife" and enabled else NONE)

func fade_unit_hover(unit: Sprite3D, highlighted: bool) -> void:
	unit_presentation.fade_unit_hover(unit, highlighted)

func clear_unit_hover() -> void:
	unit_presentation.clear_unit_hover()
	if wildlife != null: wildlife.clear_hover()

func action_marker(coord: Vector2i, color: Color) -> void:
	playback.action_marker(coord, color)

func spawn_unit_effect(coord: Vector2i, rank: int) -> float:
	return unit_spawn_effects.play(coord, rank)

func play_preparation(actions: Array, new_cells: Dictionary, partial := false) -> void:
	await playback.play_preparation(actions, new_cells, partial)

func animate_moves(actions: Array, final_cells: Dictionary) -> void:
	await playback.animate_moves(actions, final_cells)

func cancel_motion(restored_cells: Dictionary) -> void:
	playback.cancel_motion(restored_cells)

func outline(coord: Vector2i, color: Color) -> void:
	overlays.outline(coord, color)

func show_overlays(selected: Vector2i, hovered: Vector2i, valid: Dictionary, path: Array, active_capital: Vector2i, intent: Dictionary = {}, protector: Vector2i = NONE, inspected: Vector2i = NONE) -> void:
	overlays.show_overlays(selected, hovered, valid, path, active_capital, intent, protector, inspected)

func intent_color(intent: Dictionary) -> Color:
	return overlays.intent_color(intent)

func show_intent(coord: Vector2i, intent: Dictionary, path: Array) -> void:
	overlays.show_intent(coord, intent, path)

func update_upgrade_indicator() -> void:
	overlays.update_upgrade_indicator()

func record_capture_sample(sample: Dictionary) -> void:
	sample["frame"] = Engine.get_process_frames()
	capture_samples.append(sample)

func _on_camera_changed() -> void:
	if lighting != null: lighting.update_camera()
	update_upgrade_indicator()

func set_active(value: bool) -> void:
	active = value
	controls_enabled = value
	camera.current = value
	if not value:
		zoom_reference = Vector2(-1, -1)
		stop_camera_pan()
		clear_unit_hover()
		sky_backdrop.hide()
		if Video.changed.is_connected(_apply_video_settings): Video.changed.disconnect(_apply_video_settings)
	else:
		if not Video.changed.is_connected(_apply_video_settings): Video.changed.connect(_apply_video_settings)
		_apply_video_settings()
	if lighting != null: lighting.update_camera()
