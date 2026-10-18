extends SceneTree
## Identical seeded departure trace, tracking cap/earth edge pixels.
func _initialize() -> void:
	call_deferred("run")

func exposed_earth(cap: Mesh) -> ArrayMesh:
	var corners: Array[Vector3] = []
	for vertex in cap.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if vertex.y > 0.03 and Vector2(vertex.x, vertex.z).length() > 0.5:
			var point := Vector3(vertex.x, 0.28, vertex.z)
			if not corners.any(func(existing: Vector3): return existing.is_equal_approx(point)):
				corners.append(point)
	corners.sort_custom(func(a: Vector3, b: Vector3): return atan2(a.z, a.x) < atan2(b.z, b.x))
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_smooth_group(-1)
	for edge in range(6):
		var next := (edge + 1) % 6
		var a := Vector3(cos(-5 * PI / 6 + edge * PI / 3), 0.28, sin(-5 * PI / 6 + edge * PI / 3))
		var b := Vector3(cos(-5 * PI / 6 + next * PI / 3), 0.28, sin(-5 * PI / 6 + next * PI / 3))
		var c: Vector3 = corners[edge]
		var d: Vector3 = corners[next]
		var low_a := a - Vector3(0, 0.56, 0)
		var low_b := b - Vector3(0, 0.56, 0)
		for vertex in [a, c, b, c, d, b, a, b, low_b, a, low_b, low_a, Vector3(0, -0.28, 0), low_a, low_b]:
			builder.add_vertex(vertex)
	builder.generate_normals()
	return builder.commit()

func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"vsync", false, false)
	var reports: Array = []
	for variant in ["legacy_joins", "visible_joins"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 820)
		viewport.own_world_3d = true
		viewport.msaa_3d = video.antialiasing
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var map = load("res://src/rendering/decorative_map.gd").new()
		map.initial_seed = 42
		viewport.add_child(map)
		map.active = true
		map.layout_camera(1280.0 / 820)
		map.visible_kingdom_joins = variant != "legacy_joins"
		map.sync_menu_batches()
		if variant == "no_shadows":
			map.sun.shadow_enabled = false
		if variant == "near_plane":
			map.camera.near = 2.0
		if variant == "exposed_rim":
			var meshes: Dictionary = {}
			for slot in map.slots.values():
				var surface: MeshInstance3D = slot["node"].get_meta("surface")
				var id := surface.mesh.get_instance_id()
				if not meshes.has(id):
					meshes[id] = exposed_earth(surface.mesh)
				for child in slot["node"].get_children():
					if child is MeshInstance3D and child != surface:
						child.mesh = meshes[id]
			map.static_batches.source_cache.clear()
			map.sync_menu_batches()
		if variant in ["no_cap_shadows", "no_terrain_shadows"]:
			for slot in map.slots.values():
				slot["node"].get_meta("surface").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if variant == "no_terrain_shadows":
					for child in slot["node"].get_children():
						if child is MeshInstance3D:
							child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			map.static_batches.source_cache.clear()
			map.sync_menu_batches()
		var previous: Dictionary = {}
		var changes := 0.0
		var maximum := 0.0
		var samples := 0
		var shots := 0
		for frame in range(360):
			map.advance(1.0 / 60)
			await process_frame
			await RenderingServer.frame_post_draw
			var picture: Image = viewport.get_texture().get_image()
			var next: Dictionary = {}
			var departing := false
			for id in map.slots:
				var slot: Dictionary = map.slots[id]
				if slot["state"] == "leaving" and slot["cell"]["owner"] >= 0:
					departing = true
				if slot["state"] != "settled" or slot["cell"]["owner"] < 0:
					continue
				var point: Vector2 = map.camera.unproject_position(slot["node"].global_position + Vector3(0.825, 0.012, 0.0))
				if point.x < 0 or point.x >= 1280 or point.y < 0 or point.y >= 820:
					continue
				var color := picture.get_pixel(clampi(roundi(point.x), 0, 1279), clampi(roundi(point.y), 0, 819))
				next[id] = color.get_luminance()
				if previous.has(id):
					var amount: float = absf(next[id] - previous[id])
					maximum = maxf(maximum, amount)
					changes += amount
					samples += 1
			previous = next
			if departing and shots < 4 and frame % 20 == 0:
				picture.save_png("res://artifacts/menu_edge_%s_%d.png" % [variant, shots])
				shots += 1
		reports.append({"variant": variant, "mean_step": changes / maxi(1, samples), "max_step": maximum, "samples": samples})
		print(JSON.stringify(reports[-1]))
		viewport.queue_free()
		await process_frame
	FileAccess.open("res://artifacts/menu_edge_probe.json", FileAccess.WRITE).store_string(JSON.stringify(reports, "\t"))
	quit()
