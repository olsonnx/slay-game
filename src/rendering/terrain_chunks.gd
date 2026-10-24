extends RefCounted
const Records = preload("res://src/rendering/batch_records.gd")
## Settled terrain only. Full source tiles remain available for transitions.
const Grid = preload("res://src/game/hex_grid.gd")
static var templates: Dictionary = {}
# Keep tops at their original gameplay plane; the molded lip drops into the base.
const TOP := 0.0105
const SHOULDER := -0.025
const BEVEL := 0.045
const BASE_COLOR := Color("50555e")

static func triangle(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).length_squared() < 0.000000001:
		return
	builder.set_color(color)
	for vertex in [a, b, c]:
		builder.add_vertex(vertex)

static func corners(mask: int, visibility: float, inset := 0.0) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for edge in range(6):
		var next := (edge + 1) % 6
		var aw := Grid.to_world(Grid.DIRECTIONS[edge])
		var bw := Grid.to_world(Grid.DIRECTIONS[next])
		var a := Vector2(aw.x, aw.z).normalized()
		var b := Vector2(bw.x, bw.z).normalized()
		var ar := lerpf(1.0, 0.968, visibility) if mask & (1 << edge) else 0.968
		var br := lerpf(1.0, 0.968, visibility) if mask & (1 << next) else 0.968
		ar -= inset * (0.0 if mask & (1 << edge) else 1.0)
		br -= inset * (0.0 if mask & (1 << next) else 1.0)
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

static func template(mask: int, visibility: float, cliffs: int, plastic := true) -> Array:
	var key := str(mask) + ":" + str(visibility) + ":" + str(cliffs) + ":" + str(plastic)
	if templates.has(key): return templates[key]
	if templates.size() >= 512: templates.clear()
	var cap_vertices := PackedVector3Array()
	var cap_normals := PackedVector3Array()
	var soil_vertices := PackedVector3Array()
	var soil_normals := PackedVector3Array()
	var cap := corners(mask, visibility)
	var top := corners(mask, visibility, BEVEL if plastic else 0.0)
	var outer := corners(63, 0.0)
	var up := Vector3(0, TOP, 0)
	var shoulder := Vector3(0, SHOULDER if plastic else 0.0, 0)
	var down := Vector3(0, -0.56, 0)
	for edge in range(6):
		var previous := (edge + 5) % 6
		var a: Vector3 = cap[previous] + shoulder
		var b: Vector3 = cap[edge] + shoulder
		var ta: Vector3 = top[previous] + up
		var tb: Vector3 = top[edge] + up
		var oa: Vector3 = outer[previous] + shoulder
		var ob: Vector3 = outer[edge] + shoulder
		append_face(cap_vertices, cap_normals, up, tb, ta)
		append_face(soil_vertices, soil_normals, oa, b, ob)
		append_face(soil_vertices, soil_normals, oa, a, b)
		if not (mask & (1 << edge)) or visibility > 0.0:
			append_face(cap_vertices, cap_normals, ta, b, a)
			append_face(cap_vertices, cap_normals, ta, tb, b)
		if cliffs & (1 << edge):
			append_face(soil_vertices, soil_normals, oa, outer[edge] + down, outer[previous] + down)
			append_face(soil_vertices, soil_normals, oa, ob, outer[edge] + down)
	var result := [cap_vertices, cap_normals, soil_vertices, soil_normals]
	templates[key] = result
	return result

static func build(records: Array, tiles: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var ranges: Dictionary = {}
	# Tops and bases may be separate material groups. Each source contributes
	# only its own faces, retaining in-place recoloring and hidden-face culling.
	for record in records:
		var node: MeshInstance3D = record[Records.Source.NODE]
		var tile: Node3D = node.get_parent()
		var coord: Vector2i = tile.get_meta("hex")
		var offset: Vector3 = record[Records.Source.TRANSFORM].origin - node.position
		var color: Color = record[Records.Source.COLOR]
		var cliffs := 0
		for edge in range(6):
			var neighbor: Node3D = tiles.get(coord + Grid.DIRECTIONS[edge])
			if neighbor == null or not neighbor.has_meta("earth"): cliffs |= 1 << edge
		var parts := template(tile.get_meta("joined_mask", 0), tile.get_meta("border_visibility", 1.0), cliffs, tile.get_meta("plastic_tiles", true))
		var part := 0 if node.get_meta("terrain_role") == "cap" else 2
		var local_vertices: PackedVector3Array = parts[part]
		ranges[node.get_instance_id()] = [vertices.size(), local_vertices.size(), color]
		vertices.append_array(Transform3D(Basis.IDENTITY, offset) * local_vertices)
		normals.append_array(parts[part + 1])
		var part_colors := PackedColorArray()
		part_colors.resize(local_vertices.size())
		part_colors.fill(color)
		colors.append_array(part_colors)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	# An interior base group can be fully enclosed by joined tiles.
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh.set_meta("cap_ranges", ranges)
	return mesh

static func recolor(mesh: ArrayMesh, records: Array) -> bool:
	if not mesh.has_meta("cap_ranges"): return false
	if mesh.get_surface_count() == 0: return true
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
