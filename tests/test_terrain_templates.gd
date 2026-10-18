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
func faces(vertices: PackedVector3Array, normals: PackedVector3Array) -> Dictionary:
	var result := {}
	for index in range(0, vertices.size(), 3):
		var corners: Array = []
		for point in range(3):
			var vertex := vertices[index + point]
			var normal := normals[index + point]
			corners.append(str(Vector3i(roundi(vertex.x * 10000), roundi(vertex.y * 10000), roundi(vertex.z * 10000))) + ":" + str(Vector3i(roundi(normal.x * 10000), roundi(normal.y * 10000), roundi(normal.z * 10000))))
		var rotations := ["|".join(corners), "|".join([corners[1], corners[2], corners[0]]), "|".join([corners[2], corners[0], corners[1]])]
		rotations.sort()
		result[rotations[0]] = result.get(rotations[0], 0) + 1
	return result
func run() -> void:
	for visibility in [0.0, 0.5, 1.0]:
		for mask in range(64):
			var builder := SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			builder.set_smooth_group(-1)
			var cap := Terrain.corners(mask, visibility)
			var outer := Terrain.corners(63, 0.0)
			var up := Vector3(0, 0.0105, 0)
			var down := Vector3(0, -0.56, 0)
			for edge in range(6):
				var previous := (edge + 5) % 6
				var a: Vector3 = cap[previous]
				var b: Vector3 = cap[edge]
				var oa: Vector3 = outer[previous]
				var ob: Vector3 = outer[edge]
				Terrain.triangle(builder, up, b + up, a + up, Color.WHITE)
				Terrain.triangle(builder, oa, b, ob, Color.WHITE)
				Terrain.triangle(builder, oa, a, b, Color.WHITE)
				if not mask & (1 << edge) or visibility > 0.0:
					Terrain.triangle(builder, a + up, b, a, Color.WHITE)
					Terrain.triangle(builder, a + up, b + up, b, Color.WHITE)
				Terrain.triangle(builder, oa, ob + down, oa + down, Color.WHITE)
				Terrain.triangle(builder, oa, ob, ob + down, Color.WHITE)
			builder.generate_normals()
			var legacy: Array = builder.commit().surface_get_arrays(0)
			var parts := Terrain.template(mask, visibility, 63)
			var vertices: PackedVector3Array = parts[0].duplicate()
			vertices.append_array(parts[2])
			var normals: PackedVector3Array = parts[1].duplicate()
			normals.append_array(parts[3])
			expect(faces(vertices, normals) == faces(legacy[Mesh.ARRAY_VERTEX], legacy[Mesh.ARRAY_NORMAL]), "Cached terrain preserves every face, winding and flat normal")
	print("Terrain template checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
