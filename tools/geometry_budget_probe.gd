extends SceneTree
## Disposable geometry/shadow experiments for the low-spec rendering review.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"vsync", false, false)
	root.get_node("Sound").set_muted(true, false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	var background = app.menus.menu_background
	var map = background.map
	var records: Array = []
	for slot in map.slots.values():
		for child in slot["node"].get_children():
			if child is MeshInstance3D and child.mesh is CylinderMesh:
				records.append([child, child.mesh, child.cast_shadow])
	var reports: Array = []
	for mode in ["current", "rings_zero", "no_bottom", "no_cap_casters", "current"]:
		var meshes: Dictionary = {}
		for record in records:
			var node: MeshInstance3D = record[0]
			node.mesh = record[1]
			node.cast_shadow = record[2]
			if mode in ["rings_zero", "no_bottom"]:
				var id: int = record[1].get_instance_id()
				if not meshes.has(id):
					var mesh: CylinderMesh = record[1].duplicate()
					if mode == "rings_zero": mesh.rings = 0
					if mode == "no_bottom": mesh.cap_bottom = false
					meshes[id] = mesh
				node.mesh = meshes[id]
			if mode == "no_cap_casters" and node == node.get_parent().get_meta("surface"):
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		map.static_batches.source_cache.clear()
		map.sync_menu_batches()
		await create_timer(1.0).timeout
		var frames := 0
		var start := Time.get_ticks_usec()
		while Time.get_ticks_usec() - start < 3000000:
			await RenderingServer.frame_post_draw
			frames += 1
		var rid: RID = background.viewport.get_viewport_rid()
		var report := {"mode": mode, "fps": frames * 1000000.0 / (Time.get_ticks_usec() - start), "draws": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME), "visible_triangles": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME), "shadow_triangles": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)}
		reports.append(report)
		print(JSON.stringify(report))
	FileAccess.open("res://artifacts/geometry_budget_probe.json", FileAccess.WRITE).store_string(JSON.stringify(reports, "\t"))
	quit()
