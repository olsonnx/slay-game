extends Node3D
## Settled army instances; source actors remain available for picking and motion.
var board
var enabled := true
var batches: Dictionary = {}
var suppressed: Dictionary = {}
var sprite_meshes: Dictionary = {}
var sprite_materials: Dictionary = {}
var shadow_mesh: PlaneMesh
var shadow_material: StandardMaterial3D
var sync_pending := false
var upload_count := 0
var sprite_slots: Dictionary = {}
var pending_chunks: Dictionary = {}
var full_sync_pending := true
var chunk_sources: Dictionary = {}
var chunk_coords: Dictionary = {}

func animate_idle(tick: int) -> void:
	# Swap a shared texture per rank/faction/facing; instance buffers stay intact.
	for material in sprite_materials.values():
		if not material.has_meta("idle_unit"): continue
		var unit: Vector2i = material.get_meta("idle_unit")
		var count: int = preload("res://src/rendering/unit_sprite_library.gd").clip(unit.x,"idle")[1]
		material.albedo_texture = board.unit_sprites.frame(unit.x,board.COLORS[unit.y],"idle",tick % count).texture

func tint(sprite: Sprite3D, color: Color) -> void:
	var slot: Array = sprite_slots.get(sprite.get_instance_id(), [])
	if slot.is_empty(): return
	var render: MultiMeshInstance3D = slot[0].get_ref()
	if is_instance_valid(render) and slot[1] < render.multimesh.instance_count:
		render.multimesh.set_instance_color(slot[1], color)
		render.get_meta("signature")[slot[1]][1] = color

func _init(view) -> void:
	board = view
	shadow_mesh = PlaneMesh.new()
	shadow_mesh.size = Vector2(0.9, 0.9)
	shadow_material = StandardMaterial3D.new()
	shadow_material.albedo_texture = board.shadow_texture
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	shadow_material.vertex_color_use_as_albedo = true

func queue_sync(coords: Dictionary = {}, full := true) -> void:
	full_sync_pending = full_sync_pending or full
	for coord in coords:
		var chunk := Vector2i(floori(float(coord.x) / 12), floori(float(coord.y) / 12))
		pending_chunks[chunk] = true
		if not chunk_coords.has(chunk): chunk_coords[chunk] = {}
		if board.tile_nodes.has(coord): chunk_coords[chunk][coord] = true
		else: chunk_coords[chunk].erase(coord)
	if not sync_pending:
		sync_pending = true
		sync.call_deferred(true)

func restore_sources() -> void:
	for reference in suppressed.values():
		var source: GeometryInstance3D = reference.get_ref()
		if is_instance_valid(source):
			source.layers = source.get_meta("army_layers", 1)
	suppressed.clear()
	sprite_slots.clear()
	chunk_sources.clear()

func sync(queued := false) -> void:
	var started := Time.get_ticks_usec() if board.profile_capture else 0
	sync_pending = false
	if not is_inside_tree(): return
	if not enabled or board.level_transitioning or board.static_batches.suspended:
		visible = false
		restore_sources()
		return
	visible = true
	var scoped := queued and not full_sync_pending
	var touched := pending_chunks.duplicate()
	pending_chunks.clear()
	full_sync_pending = false
	var cleanup: Dictionary = {}
	var coords_to_scan: Dictionary = {}
	if scoped:
		for chunk in touched:
			coords_to_scan.merge(chunk_coords.get(chunk, {}))
			cleanup.merge(chunk_sources.get(chunk, {}))
			chunk_sources.erase(chunk)
		for id in cleanup: sprite_slots.erase(id)
	else:
		sprite_slots.clear()
		chunk_sources.clear()
		chunk_coords.clear()
		for coord in board.tile_nodes:
			var chunk := Vector2i(floori(float(coord.x) / 12), floori(float(coord.y) / 12))
			if not chunk_coords.has(chunk): chunk_coords[chunk] = {}
			chunk_coords[chunk][coord] = true
		coords_to_scan = board.tile_nodes
	var groups: Dictionary = {}
	var seen: Dictionary = {}
	var inverse := global_transform.affine_inverse()
	for coord in coords_to_scan:
		var chunk := Vector2i(floori(float(coord.x) / 12), floori(float(coord.y) / 12))
		if scoped and not touched.has(chunk): continue
		var actor: Node3D = board.unit_actors.get(coord)
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not actor.is_visible_in_tree() or actor.get_parent() != board.tile_nodes.get(coord) or actor.get_meta("sprite_action_active",false):
			continue
		for child in actor.get_children():
			if child is Sprite3D:
				var idle_texture: Texture2D = child.get_meta("idle_texture", child.texture)
				var ready: bool = child.get_meta("unit_ready", false)
				var key := str(idle_texture.get_rid()) + (":left" if child.flip_h else ":right") + (":ready" if ready else ":spent")
				if not sprite_meshes.has(key):
					var mesh := QuadMesh.new()
					mesh.size = Vector2(child.texture.get_width(), child.texture.get_height()) * child.pixel_size
					sprite_meshes[key] = mesh
					var material := StandardMaterial3D.new()
					material.albedo_texture = child.texture
					if child.flip_h:
						material.uv1_scale.x = -1
						material.uv1_offset.x = 1
					material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
					material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					material.alpha_scissor_threshold = child.alpha_scissor_threshold
					material.cull_mode = BaseMaterial3D.CULL_DISABLED
					material.vertex_color_use_as_albedo = true
					sprite_materials[key] = material
				if ready:
					var animator = actor.get_node("UnitAnimation")
					sprite_materials[key].set_meta("idle_unit",Vector2i(animator.tier,animator.faction_id))
				sprite_materials[key].albedo_texture = child.texture
				append(groups, seen, "sprite:" + key, chunk, child, sprite_meshes[key], sprite_materials[key], inverse, child.modulate)
			elif child is MeshInstance3D:
				append(groups, seen, "shadow", chunk, child, shadow_mesh, shadow_material, inverse, Color.WHITE)
			elif child.name == "Pips":
				for pip in child.get_children():
					append(groups, seen, "pip:" + str(pip.mesh.get_rid()), chunk, pip, pip.mesh, pip.material_override, inverse, Color.WHITE)
	# Temporary protection still has scene nodes for playback/heatmap semantics.
	# Equal panels and shields share spatial draw groups with retained materials.
	for coord in coords_to_scan:
		var chunk := Vector2i(floori(float(coord.x) / 12), floori(float(coord.y) / 12))
		if scoped and not touched.has(chunk): continue
		var tile: Node3D = board.tile_nodes.get(coord)
		if not is_instance_valid(tile): continue
		for name_value in ["Barrier", "Fortification"]:
			var effect := tile.get_node_or_null(name_value)
			if effect == null: continue
			for piece in effect.get_children():
				if piece is MeshInstance3D:
					append(groups, seen, "effect:" + str(piece.mesh.get_rid()) + ":" + str(piece.material_override.get_rid()), chunk, piece, piece.mesh, piece.material_override, inverse, Color.WHITE)
	for id in cleanup.keys() if scoped else suppressed.keys():
		if not seen.has(id) and suppressed.has(id):
			var source: GeometryInstance3D = suppressed[id].get_ref()
			if is_instance_valid(source): source.layers = source.get_meta("army_layers", 1)
			suppressed.erase(id)
	for key in batches.keys():
		if scoped and not touched.has(batches[key].get_meta("chunk")): continue
		if not groups.has(key):
			batches[key].free()
			batches.erase(key)
	for key in groups:
		var group: Dictionary = groups[key]
		var records: Array = group["records"]
		var render: MultiMeshInstance3D = batches.get(key)
		if render != null and render.get_meta("signature") == records:
			register_slots(key, render, records)
			continue
		if render == null:
			render = MultiMeshInstance3D.new()
			render.set_meta("chunk", group["chunk"])
			render.material_override = group["material"]
			render.cast_shadow = group["casting"]
			render.layers = group["layers"]
			var instances := MultiMesh.new()
			instances.transform_format = MultiMesh.TRANSFORM_3D
			instances.use_colors = true
			instances.mesh = group["mesh"]
			render.multimesh = instances
			add_child(render)
			batches[key] = render
		render.multimesh.instance_count = records.size()
		var low: Vector3 = records[0][0].origin
		var high := low
		for index in range(records.size()):
			render.multimesh.set_instance_transform(index, records[index][0])
			render.multimesh.set_instance_color(index, records[index][1])
			low = low.min(records[index][0].origin)
			high = high.max(records[index][0].origin)
		# Billboard rotation must not be culled using a zero-depth quad AABB.
		render.multimesh.custom_aabb = AABB(low - Vector3.ONE * 2, high - low + Vector3.ONE * 4)
		render.set_meta("signature", records)
		register_slots(key, render, records)
		upload_count += 1
	if board.profile_capture: board.capture_samples.append({"stage": "army_sync", "ms": (Time.get_ticks_usec() - started) / 1000.0})

func register_slots(key: String, render: MultiMeshInstance3D, records: Array) -> void:
	if ":sprite:" in key:
		for index in range(records.size()):
			sprite_slots[records[index][2]] = [weakref(render), index]

func append(groups: Dictionary, seen: Dictionary, kind: String, chunk: Vector2i, source: GeometryInstance3D, mesh: Mesh, material: Material, inverse: Transform3D, color: Color) -> void:
	if not source.is_visible_in_tree(): return
	var id := source.get_instance_id()
	if not source.has_meta("army_layers"): source.set_meta("army_layers", source.layers)
	var layers: int = source.get_meta("army_layers")
	if layers == 0: return
	var key := str(chunk) + ":" + kind + ":" + str(layers)
	if not groups.has(key):
		groups[key] = {"records": [], "mesh": mesh, "material": material, "layers": layers, "casting": source.cast_shadow, "chunk": chunk}
	groups[key]["records"].append([inverse * source.global_transform, color, id])
	seen[id] = true
	if not chunk_sources.has(chunk): chunk_sources[chunk] = {}
	chunk_sources[chunk][id] = true
	suppressed[id] = weakref(source)
	source.layers = 0

func _exit_tree() -> void:
	restore_sources()
