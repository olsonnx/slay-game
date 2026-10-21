extends RefCounted
## Coplanar filled outlines and joined strokes for board annotations.

static func triangle(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	builder.set_color(color)
	for point in [a, b, c]:
		builder.add_vertex(point)

static func segment(builder: SurfaceTool, a: Vector3, b: Vector3, width: float, height: float, color: Color) -> void:
	a.y = height
	b.y = height
	var offset := Vector3(-(b - a).z, 0, (b - a).x).normalized() * width * 0.5
	triangle(builder, a - offset, b - offset, b + offset, color)
	triangle(builder, a - offset, b + offset, a + offset, color)
	# Endpoint caps also join all meeting edges without inset corner gaps.
	for center in [a, b]:
		for edge in range(16):
			var first: Vector3 = center + Vector3(cos(edge * TAU / 16), 0, sin(edge * TAU / 16)) * width * 0.5
			var second: Vector3 = center + Vector3(cos((edge + 1) * TAU / 16), 0, sin((edge + 1) * TAU / 16)) * width * 0.5
			triangle(builder, center, first, second, color)

static func polygon_offset(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var sign_value := 1.0 if Geometry2D.is_polygon_clockwise(points) else -1.0
	for index in range(points.size()):
		var incoming := (points[index] - points[(index - 1 + points.size()) % points.size()]).normalized()
		var outgoing := (points[(index + 1) % points.size()] - points[index]).normalized()
		var a := Vector2(-incoming.y, incoming.x) * sign_value
		var b := Vector2(-outgoing.y, outgoing.x) * sign_value
		var miter := (a + b).normalized()
		var divisor := miter.dot(b)
		result.append(points[index] + miter * distance / maxf(divisor, 0.15))
	return result

static func outlined_polygon(points: PackedVector2Array, width: float, height: float, color: Color, border: Color) -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := polygon_offset(points, width)
	var triangles := Geometry2D.triangulate_polygon(points)
	for index in range(0, triangles.size(), 3):
		var a := points[triangles[index]]
		var b := points[triangles[index + 1]]
		var c := points[triangles[index + 2]]
		triangle(builder, Vector3(a.x, height, a.y), Vector3(b.x, height, b.y), Vector3(c.x, height, c.y), color)
	for index in range(points.size()):
		var next := (index + 1) % points.size()
		var a := Vector3(points[index].x, height, points[index].y)
		var b := Vector3(points[next].x, height, points[next].y)
		var c := Vector3(outer[index].x, height, outer[index].y)
		var d := Vector3(outer[next].x, height, outer[next].y)
		triangle(builder, a, c, d, border)
		triangle(builder, a, d, b, border)
	return builder.commit()

static func vertex_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
