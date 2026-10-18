extends RefCounted
const Records = preload("res://src/rendering/batch_records.gd")
## Settled terrain only. Full source tiles remain available for transitions.
const Grid = preload("res://src/game/hex_grid.gd")
static var templates: Dictionary = {}

static func triangle(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).length_squared() < 0.000000001:
		return
	builder.set_color(color)
	for vertex in [a, b, c]:
		builder.add_vertex(vertex)

static func corners(mask: int, visibility: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for edge in range(6):
		var next := (edge + 1) % 6
		var aw := Grid.to_world(Grid.DIRECTIONS[edge])
		var bw := Grid.to_world(Grid.DIRECTIONS[next])
		var a := Vector2(aw.x, aw.z).normalized()
		var b := Vector2(bw.x, bw.z).normalized()
		var ar := lerpf(1.0, 0.968, visibility) if mask & (1 << edge) else 0.968
		var br := lerpf(1.0, 0.968, visibility) if mask & (1 << next) else 0.968
		var ap := ar * sqrt(3.0) / 2.0
		var bp := br * sqrt(3.0) / 2.0
		var determinant := a.x * b.y - a.y * b.x
		result.append(Vector3((ap * b.y - bp * a.y) / determinant, 0, (a.x * bp - b.x * ap) / determinant))
	return result

static func append_face(vertices: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000000001: return
	# Godot's SurfaceTool uses clockwise front faces.
	normal = -normal.normalized()
	vertices.append_array(PackedVector3Array([a, b, c]))
	normals.append_array(PackedVector3Array([normal, normal, normal]))

static func template(mask: int, visibility: float, cliffs: int) -> Array:
	var key := str(mask) + ":" + str(visibility) + ":" + str(cliffs)
	if templates.has(key): return templates[key]
	if templates.size() >= 512: templates.clear()
	var cap_vertices := PackedVector3Array()
	var cap_normals := PackedVector3Array()
	var soil_vertices := PackedVector3Array()
	var soil_normals := PackedVector3Array()
	var cap := corners(mask, visibility)
	var outer := corners(63, 0.0)
	var up := Vector3(0, 0.0105, 0)
	var down := Vector3(0, -0.56, 0)
	for edge in range(6):
		var previous := (edge + 5) % 6
		var a: Vector3 = cap[previous]
		var b: Vector3 = cap[edge]
		var oa: Vector3 = outer[previous]
		var ob: Vector3 = outer[edge]
		append_face(cap_vertices, cap_normals, up, b + up, a + up)
		append_face(soil_vertices, soil_normals, oa, b, ob)
		append_face(soil_vertices, soil_normals, oa, a, b)
		if not (mask & (1 << edge)) or visibility > 0.0:
			append_face(cap_vertices, cap_normals, a + up, b, a)
			append_face(cap_vertices, cap_normals, a + up, b + up, b)
		if cliffs & (1 << edge):
			append_face(soil_vertices, soil_normals, oa, ob + down, oa + down)
			append_face(soil_vertices, soil_normals, oa, ob, ob + down)
	var result := [cap_vertices, cap_normals, soil_vertices, soil_normals]
	templates[key] = result
	return result

static func build(records: Array, tiles: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var soil: Dictionary = {}
	var soil_ids: Dictionary = {}
	var ranges: Dictionary = {}
	for record in records:
		var node: MeshInstance3D = record[Records.Source.NODE]
		if node.get_meta("terrain_role") == "earth":
			soil[node.get_parent().get_meta("hex")] = record[Records.Source.COLOR]
			soil_ids[node.get_parent().get_meta("hex")] = record[Records.Source.ID]
	for record in records:
		var node: MeshInstance3D = record[Records.Source.NODE]
		if node.get_meta("terrain_role") != "cap":
			continue
		var tile: Node3D = node.get_parent()
		var coord: Vector2i = tile.get_meta("hex")
		var offset: Vector3 = record[Records.Source.TRANSFORM].origin - node.position
		var cap_color: Color = record[Records.Source.COLOR]
		var soil_color: Color = soil.get(coord, Color("776a51"))
		var cliffs := 0
		for edge in range(6):
			var neighbor: Node3D = tiles.get(coord + Grid.DIRECTIONS[edge])
			if neighbor == null or not neighbor.has_meta("earth"): cliffs |= 1 << edge
		var parts := template(tile.get_meta("joined_mask", 0), tile.get_meta("border_visibility", 1.0), cliffs)
		ranges[node.get_instance_id()] = [vertices.size(), parts[0].size(), cap_color]
		if soil_ids.has(coord): ranges[soil_ids[coord]] = [vertices.size() + parts[0].size(), parts[2].size(), soil_color]
		var transform := Transform3D(Basis.IDENTITY, offset)
		for part in range(2):
			var local_vertices: PackedVector3Array = parts[part * 2]
			vertices.append_array(transform * local_vertices)
			normals.append_array(parts[part * 2 + 1])
			var part_colors := PackedColorArray()
			part_colors.resize(local_vertices.size())
			part_colors.fill(cap_color if part == 0 else soil_color)
			colors.append_array(part_colors)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh.set_meta("cap_ranges", ranges)
	return mesh

static func recolor(mesh: ArrayMesh, records: Array) -> bool:
	if not mesh.has_meta("cap_ranges"): return false
	var format := mesh.surface_get_format(0)
	# This mesh contains positions, normals and RGBA8 colors only. Check the
	# engine-reported layout instead of assuming it for arbitrary ArrayMeshes.
	if RenderingServer.mesh_surface_get_format_attribute_stride(format, mesh.surface_get_array_len(0)) != 4: return false
	var ranges: Dictionary = mesh.get_meta("cap_ranges")
	for record in records:
		var id: int = record[Records.Source.ID]
		if not ranges.has(id): continue
		var entry: Array = ranges[id]
		var color: Color = record[Records.Source.COLOR]
		if entry[2] == color: continue
		# RenderingServer packs color channels as clamped, truncated RGBA8.
		var rgba: int = int(clampf(color.r, 0, 1) * 255) | (int(clampf(color.g, 0, 1) * 255) << 8) | (int(clampf(color.b, 0, 1) * 255) << 16) | (int(clampf(color.a, 0, 1) * 255) << 24)
		var packed := PackedInt32Array()
		packed.resize(entry[1])
		packed.fill(rgba)
		mesh.surface_update_attribute_region(0, entry[0] * 4, packed.to_byte_array())
		entry[2] = color
	return true
