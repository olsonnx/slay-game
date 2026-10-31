extends RefCounted
## Shared pointy-top axial geometry, independent of window size or camera.
const NONE := Vector2i(999, 999)
const DIRECTIONS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return maxi(absi(d.x), maxi(absi(d.y), absi(d.x + d.y)))

static func to_world(coord: Vector2i) -> Vector3:
	return Vector3(sqrt(3.0) * (coord.x + coord.y * 0.5), 0, 1.5 * coord.y)

static func from_world(point: Vector3) -> Vector2i:
	var r := point.z / 1.5
	var q := point.x / sqrt(3.0) - r * 0.5
	var cube := Vector3(q, -q - r, r)
	var rounded := Vector3(roundf(cube.x), roundf(cube.y), roundf(cube.z))
	var difference := (rounded - cube).abs()
	if difference.x > difference.y and difference.x > difference.z:
		rounded.x = -rounded.y - rounded.z
	elif difference.y > difference.z:
		rounded.y = -rounded.x - rounded.z
	else:
		rounded.z = -rounded.x - rounded.y
	return Vector2i(int(rounded.x), int(rounded.z))

## Exposed hex sides only, including the contours around holes and separate islands.
static func boundary_edges(region: Dictionary) -> Array:
	var edges: Array = []
	for coord in region:
		for side in range(6):
			if not region.has(coord+DIRECTIONS[side]): edges.append([coord,side])
	return edges

static func boundary_segment(coord: Vector2i, side: int) -> PackedVector2Array:
	var center := to_world(coord)
	var normal := to_world(DIRECTIONS[side])
	var angle := atan2(normal.z,normal.x)
	return PackedVector2Array([
		Vector2(center.x,center.z)+Vector2.from_angle(angle-PI/6),
		Vector2(center.x,center.z)+Vector2.from_angle(angle+PI/6)
	])
