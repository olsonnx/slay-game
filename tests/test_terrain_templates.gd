extends SceneTree
const Terrain = preload("res://src/rendering/terrain_chunks.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var assets = preload("res://src/rendering/board_assets.gd").new()
	var tile = preload("res://src/rendering/terrain_tile.gd")
	for visibility in [0.0, 0.5, 1.0]:
		assets.set_internal_border_visibility(visibility)
		for mask in range(64):
			var parts := Terrain.template(mask, visibility, 63)
			var source: Array = tile.cap_mesh(assets, mask).surface_get_arrays(0)
			var source_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
			for index in range(source_vertices.size()):
				source_vertices[index].y += tile.CAP_CENTER
			var matching: bool = source_vertices.size() == parts[0].size()
			for index in range(source_vertices.size()):
				matching = matching and source_vertices[index].is_equal_approx(parts[0][index]) and source[Mesh.ARRAY_NORMAL][index].dot(parts[1][index]) > 0.9999
			expect(matching, "Transition and settled tile tops match within GPU normal compression precision")
			var valid := true
			var has_bevel := false
			for part in [0, 2]:
				for index in range(parts[part].size()):
					var vertex: Vector3 = parts[part][index]
					var normal: Vector3 = parts[part + 1][index]
					valid = valid and vertex.is_finite() and normal.is_normalized() and vertex.y <= Terrain.TOP + 0.00001 and vertex.y >= -0.56001
					if part == 0 and normal.y > 0.05 and normal.y < 0.95: has_bevel = true
			expect(valid, "All tile variants retain valid normals and the existing top and bottom planes")
			expect(has_bevel or mask == 63, "Exposed edges catch light on a sloped bevel")
			var base := Terrain.corners(mask, visibility)
			var top := Terrain.corners(mask, visibility, Terrain.BEVEL)
			for edge in range(6):
				if not mask & (1 << edge): continue
				var world := Terrain.Grid.to_world(Terrain.Grid.DIRECTIONS[edge])
				var direction := Vector2(world.x, world.z).normalized()
				for corner in [edge, (edge + 5) % 6]:
					var difference: Vector3 = top[corner] - base[corner]
					expect(absf(Vector2(difference.x, difference.z).dot(direction)) < 0.00001, "Shared kingdom edges have no bevel at any border visibility")
	var plastic: StandardMaterial3D = assets.tile_material(Color.RED)
	var rubber: StandardMaterial3D = assets.tile_material(Terrain.BASE_COLOR, true)
	expect(plastic.metallic == 0 and rubber.metallic == 0 and plastic.roughness < rubber.roughness, "Satin tops and rubber bases keep distinct nonmetallic finishes")
	expect(assets.material(Color.RED) != plastic, "Tile finishes do not mutate shared prop materials")
	assets.free()
	print("Terrain template checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
