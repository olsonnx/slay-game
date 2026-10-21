extends Node3D
const Records = preload("res://src/rendering/batch_records.gd")
## Retained chunked opaque instancing. Source nodes retain their scene semantics.
var startup_max_batch_usec := 0
var chunk_size := 12
var terrain_group_size := 0
var shadow_min_size := 0.0
var merge_terrain := false
var detail_visible := true
const DETAIL_FADE_SECONDS := 0.22
var detail_alpha := 1.0
var fade_materials: Dictionary = {}
var source_fade_materials: Dictionary = {}
var detail_sources: Dictionary = {}
var visible_instance_count := 0
var mute_source_notifications := false
var cache_sources := false
var source_cache: Dictionary = {}
var tile_records: Dictionary = {}
var chunk_tiles: Dictionary = {}
var chunks: Dictionary = {}
var suppressed: Dictionary = {}
var materials: Dictionary = {}
var source_material_keys: Dictionary = {}
var material_features: Dictionary = {}
var enabled := true
var suspended := false
var rebuild_count := 0
var terrain_rebuild_count := 0
var instance_count := 0
var profile_sync := false
var last_scan_usec := 0
var last_build_usec := 0
var last_rebuilt := 0
var last_tiles_scanned := 0
var profile_samples: Array = []
var sync_count := 0
var material_scan_count := 0

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	advance_detail_fade(delta)

func detail_is_drawn() -> bool:
	return detail_visible or detail_alpha > 0.0

func register_fade_material(material: StandardMaterial3D, source_material := false) -> void:
	var registry := source_fade_materials if source_material else fade_materials
	registry[material.get_instance_id()] = weakref(material)
	var color := material.albedo_color
	color.a = detail_alpha
	material.albedo_color = color

func advance_detail_fade(delta: float) -> void:
	var target := 1.0 if detail_visible else 0.0
	if detail_alpha == target:
		set_process(false)
		return
	detail_alpha = move_toward(detail_alpha, target, maxf(delta, 0.0) / DETAIL_FADE_SECONDS)
	update_fade_materials(fade_materials)
	if suspended or not enabled:
		update_fade_materials(source_fade_materials)
	if detail_alpha == target:
		apply_lod()
		update_detail_sources()
		set_process(false)

func update_fade_materials(registry: Dictionary) -> void:
	for id in registry.keys():
		var material: StandardMaterial3D = registry[id].get_ref()
		if material == null:
			registry.erase(id)
		else:
			var color := material.albedo_color
			color.a = detail_alpha
			material.albedo_color = color

func register_detail(node: MeshInstance3D) -> void:
	detail_sources[node.get_instance_id()] = [weakref(node), node.get_meta("lod_layers", node.layers)]
	register_fade_material(node.material_override, true)
	if suspended or not enabled:
		preload("res://src/rendering/batch_source_lifetime.gd").set_layers(node, int(node.get_meta("lod_layers", node.layers)) if detail_is_drawn() else 0)

func set_detail_visible(value: bool) -> void:
	if detail_visible == value:
		return
	detail_visible = value
	apply_lod()
	update_detail_sources()
	set_process(true)

func update_detail_sources() -> void:
	if suspended or not enabled:
		update_fade_materials(source_fade_materials)
	for id in detail_sources.keys():
		var node: MeshInstance3D = detail_sources[id][0].get_ref()
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			detail_sources.erase(id)
		elif not suppressed.has(id):
			preload("res://src/rendering/batch_source_lifetime.gd").set_layers(node, detail_sources[id][1] if detail_is_drawn() else 0)

func set_shadow_cutoff(value: float) -> void:
	if is_equal_approx(shadow_min_size, value):
		return
	shadow_min_size = value
	apply_lod()

func apply_lod() -> void:
	visible_instance_count = 0
	for chunk in chunks.values():
		for render in chunk["batches"].values():
			render.visible = detail_is_drawn() or not render.get_meta("lod_detail", false)
			render.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if render.get_meta("shadow_size", INF) < shadow_min_size else render.get_meta("base_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
			if render.visible and enabled and not suspended:
				visible_instance_count += int(render.get_meta("represented_sources", render.multimesh.instance_count))

func eligible(node: MeshInstance3D) -> bool:
	var material = node.material_override
	return node.mesh != null and node.mesh.get_surface_count() == 1 and material is StandardMaterial3D and (material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or node.get_meta("lod_detail", false) and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA) and material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and material.albedo_texture == null and material.normal_enabled == false and material.next_pass == null and not material.vertex_color_use_as_albedo

func collect(node: Node, output: Array) -> void:
	# Units and wards retain their own moving/temporary rendering paths.
	if node is Node3D and (node.has_meta("unit_role") or node.name in ["UnitActor", "Fortification"]):
		return
	if node is MeshInstance3D and eligible(node) and node.is_visible_in_tree():
		output.append(node)
	for child in node.get_children():
		collect(child, output)

func invalidate_tile(tile: Node3D) -> void:
	source_cache.erase(tile.get_instance_id())

func refresh_cached_mesh(tile: Node3D, node: MeshInstance3D) -> void:
	var id := tile.get_instance_id()
	if not source_cache.has(id):
		return
	for part in source_cache[id]:
		if part[Records.Source.NODE] == node:
			part[Records.Source.KEY] = str(node.mesh.get_rid()) + ":" + str(part[Records.Source.LAYERS]) + ":" + str(node.cast_shadow) + ":" + part[Records.Source.MATERIAL_KEY]
			return

func parts_for_tile(tile: Node3D) -> Array:
	var tile_id := tile.get_instance_id()
	if cache_sources and source_cache.has(tile_id):
		return source_cache[tile_id]
	var nodes: Array = []
	collect(tile, nodes)
	var parts: Array = []
	var inverse := tile.global_transform.affine_inverse()
	for node in nodes:
		var id: int = node.get_instance_id()
		var layers: int = suppressed[id][Records.Suppressed.LAYERS] if suppressed.has(id) else node.layers
		if node.get_meta("lod_detail", false):
			layers = node.get_meta("lod_layers", layers)
			register_detail(node)
		if layers == 0:
			continue
		var material: StandardMaterial3D = node.material_override
		var feature := material_key(material)
		var key: String = str(node.mesh.get_rid()) + ":" + str(layers) + ":" + str(node.cast_shadow) + ":" + feature
		var casting: int = node.cast_shadow
		key = str(node.mesh.get_rid()) + ":" + str(layers) + ":" + str(casting) + ":" + feature
		if merge_terrain and node.has_meta("terrain_role"):
			key = "terrain:" + str(layers) + ":" + str(casting) + ":" + feature
			if terrain_group_size > 0:
				var coord: Vector2i = tile.get_meta("hex")
				key += ":region:" + str(Vector2i(floori(float(coord.x) / terrain_group_size), floori(float(coord.y) / terrain_group_size)))
		if node.get_meta("lod_detail", false):
			key += ":detail"
		var color: Color = material.albedo_color
		if node.get_meta("lod_detail", false):
			color.a = 1.0 # Opacity belongs to the material, never the instance buffer.
		parts.append(Records.source(node, key, inverse * node.global_transform, color, layers, feature, material.get_instance_id(), casting))
	if cache_sources:
		source_cache[tile_id] = parts
	return parts

func material_key(material: StandardMaterial3D) -> String:
	var id := material.get_instance_id()
	if source_material_keys.has(id):
		return source_material_keys[id][1]
	# Full material state, excluding the two intentionally instance-driven fields.
	var values: Array = []
	for property in material.get_property_list():
		var name_value: String = property["name"]
		if property["usage"] & PROPERTY_USAGE_STORAGE and name_value not in ["albedo_color", "vertex_color_use_as_albedo", "resource_name", "resource_local_to_scene", "resource_path", "script"]:
			values.append(material.get(name_value))
	# Group keys stay compact even when a material exposes hundreds of fields.
	var fingerprint := str(values)
	if not material_features.has(fingerprint):
		material_features[fingerprint] = str(material_features.size())
	var key: String = material_features[fingerprint]
	# Switching the value filter temporarily swaps materials. Keep their keys
	# while the resources live, without keeping removed board props alive.
	source_material_keys[id] = [weakref(material), key]
	material_scan_count += 1
	return key

func set_source_visual_transform(source: MeshInstance3D, transform: Transform3D) -> void:
	# Keep cached scene geometry canonical; only the displayed instance animates.
	source.set_meta("visual_transform", transform)
	RenderingServer.instance_set_transform(source.get_instance(), transform)
	var slot: Array = source.get_meta("visual_batch_slot", [])
	if slot.is_empty(): return
	var render: MultiMeshInstance3D = slot[0].get_ref()
	if is_instance_valid(render) and int(slot[1]) < render.multimesh.instance_count:
		render.multimesh.set_instance_transform(slot[1], render.global_transform.affine_inverse()*transform)

func reset_source_visual_transform(source: MeshInstance3D) -> void:
	set_source_visual_transform(source, source.global_transform)
	source.remove_meta("visual_transform")
	if source.has_meta("visual_batch_slot"): source.remove_meta("visual_batch_slot")

func restore_layers() -> void:
	update_fade_materials(source_fade_materials)
	for record in suppressed.values():
		var node = record[Records.Suppressed.NODE]
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			restore_source(record)
	suppressed.clear()
	instance_count = 0
	visible_instance_count = 0

func restore_source(record: Array) -> void:
	var node: MeshInstance3D = record[Records.Suppressed.NODE]
	if record[Records.Suppressed.TRANSFORM_NOTIFICATION] != -1:
		node.set_notify_transform(bool(record[Records.Suppressed.TRANSFORM_NOTIFICATION]))
		# A source can reappear after its scrolling parent has moved many frames.
		if node.is_inside_tree():
			RenderingServer.instance_set_transform(node.get_instance(), node.get_meta("visual_transform", node.global_transform))
	preload("res://src/rendering/batch_source_lifetime.gd").set_layers(node, 0 if node.get_meta("lod_detail", false) and not detail_is_drawn() else record[Records.Suppressed.LAYERS])

func suppress_cached_sources() -> void:
	# Transition completion reuses existing uploads. Restore suppression without
	# rescanning source geometry or rebuilding the merged terrain meshes.
	for tile in tile_records.values():
		for record in tile["records"]:
			var node: MeshInstance3D = record[Records.Source.NODE]
			if not is_instance_valid(node) or node.is_queued_for_deletion(): continue
			var id: int = record[Records.Source.ID]
			if suppressed.has(id): continue
			var notification: int = int(node.is_transform_notification_enabled()) if mute_source_notifications else -1
			suppressed[id] = [node, record[Records.Source.LAYERS], notification]
			preload("res://src/rendering/batch_source_lifetime.gd").set_layers(node, 0)
			if mute_source_notifications: node.set_notify_transform(false)
	instance_count = suppressed.size()
	apply_lod()

func set_suspended(value: bool) -> void:
	suspended = value
	visible = enabled and not value
	if value:
		restore_layers()

func set_enabled(value: bool) -> void:
	enabled = value
	visible = value and not suspended
	if not value:
		restore_layers()

func clear_chunks() -> void:
	for chunk in chunks.values():
		chunk["root"].free()
	chunks.clear()
	chunk_tiles.clear()
	instance_count = 0
	visible_instance_count = 0

func same_signature(a: Array, b: Array, include_color := true) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if a[index][Records.Signature.ID] != b[index][Records.Signature.ID] or a[index][Records.Signature.KEY] != b[index][Records.Signature.KEY] or (include_color and a[index][Records.Signature.COLOR] != b[index][Records.Signature.COLOR]) or a[index][Records.Signature.GEOMETRY] != b[index][Records.Signature.GEOMETRY] or not a[index][Records.Signature.TRANSFORM].is_equal_approx(b[index][Records.Signature.TRANSFORM]):
			return false
	return true

# A nonzero startup budget yields only under the opaque loading screen.
# Ordinary board updates retain their synchronous, atomic behavior.
func sync_tiles(tiles: Dictionary, dirty_ids: Dictionary = {}, force_all := true, terrain_tiles: Dictionary = {}, startup_budget_usec := 0) -> void:
	if suspended or not enabled:
		return
	visible = true
	sync_count += 1
	last_tiles_scanned = 0
	var started := Time.get_ticks_usec() if profile_sync else 0
	var before_rebuilds := rebuild_count
	var groups: Dictionary = {}
	var seen: Dictionary = {}
	var current_tiles: Dictionary = {}
	var dirty_chunks: Dictionary = {}
	# Incremental publication scans source geometry only in touched chunks.
	# Keep the small tile registry pass for additions/removals and chunk lookup.
	var scoped := cache_sources and not force_all
	var indexed := scoped and tiles.size() == tile_records.size() and not chunk_tiles.is_empty()
	for id in dirty_ids:
		if not tile_records.has(id): indexed = false
	var work_tiles := tiles
	if indexed:
		work_tiles = {}
		for id in dirty_ids: dirty_chunks[tile_records[id]["chunk"]] = true
		for chunk in dirty_chunks:
			for coord in chunk_tiles.get(chunk, {}):
				work_tiles[coord] = tiles[coord]
	var cleanup_ids: Dictionary = {}
	if scoped and not indexed:
		for coord in tiles:
			var id: int = tiles[coord].get_instance_id()
			current_tiles[id] = true
			if dirty_ids.has(id) or not tile_records.has(id):
				dirty_chunks[Vector2i(floori(float(coord.x) / chunk_size), floori(float(coord.y) / chunk_size))] = true
		for id in tile_records:
			if dirty_ids.has(id) or not current_tiles.has(id): dirty_chunks[tile_records[id]["chunk"]] = true
		for entry in tile_records.values():
			if dirty_chunks.has(entry["chunk"]): cleanup_ids.merge(entry["source_ids"])
	elif indexed:
		for tile in work_tiles.values(): cleanup_ids.merge(tile_records[tile.get_instance_id()]["source_ids"])
	var inverse := global_transform.affine_inverse()
	var batch_started := Time.get_ticks_usec()
	if startup_budget_usec > 0: startup_max_batch_usec = 0
	for coord in work_tiles:
		var tile: Node3D = work_tiles[coord]
		var tile_id := tile.get_instance_id()
		current_tiles[tile_id] = true
		var chunk_coord := Vector2i(floori(float(coord.x) / chunk_size), floori(float(coord.y) / chunk_size))
		if scoped and not dirty_chunks.has(chunk_coord): continue
		if startup_budget_usec > 0 and Time.get_ticks_usec() - batch_started >= startup_budget_usec:
			startup_max_batch_usec = maxi(startup_max_batch_usec, Time.get_ticks_usec() - batch_started)
			await get_tree().process_frame
			batch_started = Time.get_ticks_usec()
		last_tiles_scanned += 1
		if not groups.has(chunk_coord):
			groups[chunk_coord] = []
		var records: Array
		var cached: bool = cache_sources and not force_all and not dirty_ids.has(tile_id) and tile_records.has(tile_id) and tile_records[tile_id]["chunk"] == chunk_coord
		if cached:
			records = tile_records[tile_id]["records"]
			seen.merge(tile_records[tile_id]["source_ids"])
		else:
			var parts := parts_for_tile(tile)
			var tile_transform := inverse * tile.global_transform
			records = []
			var source_ids: Dictionary = {}
			for part in parts:
				records.append([part[Records.Source.NODE], part[Records.Source.ID], part[Records.Source.KEY], tile_transform * part[Records.Source.TRANSFORM], part[Records.Source.COLOR], part[Records.Source.LAYERS], part[Records.Source.MATERIAL_KEY], part[Records.Source.MATERIAL_ID], part[Records.Source.SHADOW]])
				source_ids[part[Records.Source.ID]] = true
			if tile_records.has(tile_id):
				dirty_chunks[tile_records[tile_id]["chunk"]] = true
			dirty_chunks[chunk_coord] = true
			tile_records[tile_id] = {"chunk": chunk_coord, "coord": coord, "records": records, "source_ids": source_ids}
		groups[chunk_coord].append_array(records)
		if cached: continue
		for record in records:
			var node: MeshInstance3D = record[Records.Source.NODE]
			var id: int = record[Records.Source.ID]
			seen[id] = true
			if not suppressed.has(id):
				var notification: int = int(node.is_transform_notification_enabled()) if mute_source_notifications else -1
				suppressed[id] = [node, record[Records.Source.LAYERS], notification]
				preload("res://src/rendering/batch_source_lifetime.gd").set_layers(node, 0)
				if mute_source_notifications:
					node.set_notify_transform(false)
	if not indexed:
		for id in tile_records.keys():
			if not current_tiles.has(id):
				dirty_chunks[tile_records[id]["chunk"]] = true
				tile_records.erase(id)
		chunk_tiles.clear()
		for entry in tile_records.values():
			if not chunk_tiles.has(entry["chunk"]): chunk_tiles[entry["chunk"]] = {}
			chunk_tiles[entry["chunk"]][entry["coord"]] = true
	# Hidden/removed sources must never remain in a batch or have lost layers.
	if not scoped:
		for id in source_material_keys.keys():
			if source_material_keys[id][0].get_ref() == null:
				source_material_keys.erase(id)
	for id in cleanup_ids.keys() if scoped else detail_sources.keys():
		if not seen.has(id):
			detail_sources.erase(id)
			source_material_keys.erase(id)
	for id in cleanup_ids.keys() if scoped else suppressed.keys():
		if not seen.has(id) and suppressed.has(id):
			var saved_source: Array = suppressed[id]
			if is_instance_valid(saved_source[Records.Suppressed.NODE]) and not saved_source[Records.Suppressed.NODE].is_queued_for_deletion():
				restore_source(saved_source)
			suppressed.erase(id)
	for coord in chunks.keys():
		if scoped and not dirty_chunks.has(coord): continue
		if not groups.has(coord):
			chunks[coord]["root"].free()
			chunks.erase(coord)
	if startup_budget_usec > 0:
		startup_max_batch_usec = maxi(startup_max_batch_usec, Time.get_ticks_usec() - batch_started)
		await get_tree().process_frame
	var build_started := Time.get_ticks_usec() if profile_sync else 0
	for coord in groups:
		if not force_all and chunks.has(coord) and not dirty_chunks.has(coord):
			continue
		# Progressive initial publication still needs the complete neighborhood to
		# cull shared terrain faces correctly at the edges of unpublished regions.
		if startup_budget_usec > 0:
			await publish_chunk(coord, groups[coord], tiles if terrain_tiles.is_empty() else terrain_tiles, startup_budget_usec)
		else:
			publish_chunk(coord, groups[coord], tiles if terrain_tiles.is_empty() else terrain_tiles)
	instance_count = suppressed.size()
	apply_lod()
	if profile_sync:
		last_scan_usec = build_started - started
		last_build_usec = Time.get_ticks_usec() - build_started
		last_rebuilt = rebuild_count - before_rebuilds
		profile_samples.append({"frame":Engine.get_process_frames(),"scan_ms": last_scan_usec / 1000.0, "build_ms": last_build_usec / 1000.0, "rebuilt": last_rebuilt, "tiles_scanned": last_tiles_scanned})

func publish_chunk(coord: Vector2i, records: Array, tiles: Dictionary, startup_budget_usec := 0) -> void:
	var batch_started := Time.get_ticks_usec()
	# Publish only changed geometry; retain batches and recolor terrain in place.
	var signature: Array = []
	for record in records:
		var geometry: Array = [record[Records.Source.NODE].mesh.get_rid()]
		if record[Records.Source.KEY].begins_with("terrain:"):
			var tile: Node3D = record[Records.Source.NODE].get_parent()
			var tile_coord: Vector2i = tile.get_meta("hex")
			for direction in preload("res://src/game/hex_grid.gd").DIRECTIONS:
				var neighbor: Node3D = tiles.get(tile_coord + direction)
				geometry.append(neighbor != null and neighbor.has_meta("earth"))
		signature.append([record[Records.Source.ID], record[Records.Source.KEY], record[Records.Source.TRANSFORM], record[Records.Source.COLOR], geometry])
	if chunks.has(coord) and same_signature(chunks[coord]["signature"], signature):
		return
	if not chunks.has(coord):
		var chunk := Node3D.new()
		add_child(chunk)
		chunks[coord] = {"root": chunk, "signature": signature, "batches": {}}
	else:
		chunks[coord]["signature"] = signature
	rebuild_count += 1
	var batches: Dictionary = {}
	var batch_signatures: Dictionary = {}
	for index in range(records.size()):
		var record: Array = records[index]
		if not batches.has(record[Records.Source.KEY]):
			batches[record[Records.Source.KEY]] = []
			batch_signatures[record[Records.Source.KEY]] = []
		batches[record[Records.Source.KEY]].append(record)
		batch_signatures[record[Records.Source.KEY]].append(signature[index])
	var retained: Dictionary = chunks[coord]["batches"]
	for key in retained.keys():
		if not batches.has(key):
			retained[key].free()
			retained.erase(key)
	for key in batches:
		if startup_budget_usec > 0 and Time.get_ticks_usec() - batch_started >= startup_budget_usec:
			startup_max_batch_usec = maxi(startup_max_batch_usec, Time.get_ticks_usec() - batch_started)
			await get_tree().process_frame
			batch_started = Time.get_ticks_usec()
		var batch: Array = batches[key]
		var source: MeshInstance3D = batch[0][Records.Source.NODE]
		var terrain: bool = key.begins_with("terrain:")
		var render: MultiMeshInstance3D
		if retained.has(key):
			render = retained[key]
			if same_signature(render.get_meta("batch_signature", []), batch_signatures[key]):
				continue
			if terrain and same_signature(render.get_meta("batch_signature", []), batch_signatures[key], false) and preload("res://src/rendering/terrain_chunks.gd").recolor(render.multimesh.mesh, batch):
				render.set_meta("batch_signature", batch_signatures[key])
				continue
		else:
			render = MultiMeshInstance3D.new()
			var instances := MultiMesh.new()
			instances.transform_format = MultiMesh.TRANSFORM_3D
			instances.use_colors = true
			instances.mesh = source.mesh
			render.multimesh = instances
			render.layers = batch[0][Records.Source.LAYERS]
			render.cast_shadow = batch[0][Records.Source.SHADOW]
			var feature_key: String = batch[0][Records.Source.MATERIAL_KEY]
			if not materials.has(feature_key):
				var material: StandardMaterial3D = source.material_override.duplicate()
				material.albedo_color = Color.WHITE
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = true
				materials[feature_key] = material
			render.material_override = materials[feature_key]
			chunks[coord]["root"].add_child(render)
			retained[key] = render
		render.set_meta("batch_signature", batch_signatures[key])
		render.set_meta("lod_detail", source.get_meta("lod_detail", false))
		if source.get_meta("lod_detail", false):
			register_fade_material(render.material_override)
		render.set_meta("base_shadow", batch[0][Records.Source.SHADOW])
		render.set_meta("shadow_size", source.mesh.get_aabb().size.length())
		if terrain:
			terrain_rebuild_count += 1
			render.multimesh.mesh = preload("res://src/rendering/terrain_chunks.gd").build(batch, tiles)
			render.multimesh.instance_count = 1
			render.multimesh.set_instance_transform(0, Transform3D.IDENTITY)
			render.multimesh.set_instance_color(0, Color.WHITE)
			render.set_meta("represented_sources", batch.size())
			continue
		if render.multimesh.instance_count != batch.size():
			render.multimesh.instance_count = batch.size()
		for index in range(batch.size()):
			var node: MeshInstance3D = batch[index][Records.Source.NODE]
			var transform: Transform3D = batch[index][Records.Source.TRANSFORM]
			if node.has_meta("visual_transform"):
				transform = render.global_transform.affine_inverse()*node.get_meta("visual_transform")
				node.set_meta("visual_batch_slot", [weakref(render), index])
			render.multimesh.set_instance_transform(index, transform)
			render.multimesh.set_instance_color(index, batch[index][Records.Source.COLOR])
	if startup_budget_usec > 0:
		startup_max_batch_usec = maxi(startup_max_batch_usec, Time.get_ticks_usec() - batch_started)
		await get_tree().process_frame

func _exit_tree() -> void:
	restore_layers()

func refresh_lighting_materials(rich: bool, simple_shadow: Texture2D) -> void:
	for value in materials.values():
		preload("res://src/rendering/lighting_style.gd").apply_material(value,rich,simple_shadow)
