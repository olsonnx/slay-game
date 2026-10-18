extends RefCounted
## Tile status geometry. Cached assets belong to the supplied board factory.

static func add_event_relief(assets, features: Node3D, wooded: bool) -> void:
	var mark := MeshInstance3D.new()
	mark.name = "EventRelief"
	mark.mesh = assets.event_relief_mesh()
	features.add_child(mark)
	if wooded:
		mark.position.x = 0.34
		mark.scale = Vector3(0.72, 1, 0.72)

static func add_barrier(assets, tile: Node3D, status_name := "Barrier", emphasized := false) -> void:
	var barrier := Node3D.new()
	barrier.name = status_name
	tile.add_child(barrier)
	var wall_key := "entrenchment_magic_wall" if emphasized else "barrier_wall_alpha"
	var rim_key := "entrenchment_magic_rim" if emphasized else "barrier_rim_alpha"
	var wall_material: StandardMaterial3D = assets.material_cache.get(wall_key)
	if wall_material == null:
		wall_material = assets.material(Color(0.94, 0.73, 0.50, 0.30 if emphasized else 0.26), true, true).duplicate()
		wall_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		assets.cache_material(wall_key, wall_material)
	wall_material = assets.material_cache[wall_key]
	var rim_material: StandardMaterial3D = assets.material_cache.get(rim_key)
	if rim_material == null:
		rim_material = assets.material(Color(0.98, 0.80, 0.58, 0.82 if emphasized else 0.60), true, true).duplicate()
		rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		assets.cache_material(rim_key, rim_material)
	rim_material = assets.material_cache[rim_key]
	add_hex_walls(assets, barrier, 0.88, wall_material, rim_material, 0.015, 0.026 if emphasized else 0.018)

static func add_hex_walls(assets, parent: Node3D, height: float, wall_material: Material, rim_material: Material, floor_y := 0.015, rim_width := 0.018) -> void:
	# Share the previous barrier's panel/rim geometry, including army batches.
	if not assets.mesh_cache.has("barrier_wall"):
		var panel := QuadMesh.new()
		panel.size = Vector2(0.968, 0.88)
		assets.mesh_cache["barrier_wall"] = panel
		var rim := BoxMesh.new()
		rim.size = Vector3(0.968, 0.018, 0.018)
		assets.mesh_cache["barrier_rim"] = rim
	for side in range(6):
		var angle := (side + 0.5) * TAU / 6.0
		var midpoint := Vector3(sin(angle), 0, cos(angle)) * (sqrt(3.0) * 0.5 * 0.968)
		var wall := MeshInstance3D.new()
		wall.name = "Wall%d" % side
		wall.mesh = assets.mesh_cache["barrier_wall"]
		wall.position = midpoint + Vector3(0, floor_y + height * 0.5, 0)
		wall.scale.y = height / 0.88
		wall.rotation.y = angle
		wall.material_override = wall_material
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(wall)
		var rim := MeshInstance3D.new()
		rim.mesh = assets.mesh_cache["barrier_rim"]
		rim.name = "Rim%d" % side
		rim.position = midpoint + Vector3(0, floor_y + height, 0)
		rim.scale = Vector3(1, rim_width / 0.018, rim_width / 0.018)
		rim.rotation.y = angle
		rim.material_override = rim_material
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(rim)

static func add_fortification(assets, tile: Node3D, entrenched := false) -> void:
	if entrenched:
		add_barrier(assets, tile, "Fortification", true)
		return
	var ward := Node3D.new()
	ward.name = "Fortification"
	tile.add_child(ward)
	var ring := MeshInstance3D.new()
	ring.mesh = assets.outline_mesh
	ring.position.y = 0.08
	var rim_material: StandardMaterial3D = assets.material(Color("91e2ef"), true, true)
	ring.material_override = rim_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ward.add_child(ring)
	if not assets.mesh_cache.has("fortification_dome"):
		var dome := SphereMesh.new()
		dome.radius = 0.92
		dome.height = 1.84
		dome.radial_segments = 32
		dome.rings = 16
		assets.mesh_cache["fortification_dome"] = dome
	var shield := MeshInstance3D.new()
	shield.mesh = assets.mesh_cache["fortification_dome"]
	shield.position.y = 0.65
	if not assets.material_cache.has("fortification_alpha"):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.45, 0.85, 1, 0.10)
		assets.cache_material("fortification_alpha", mat)
	shield.material_override = assets.material_cache["fortification_alpha"]
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ward.add_child(shield)
