extends RefCounted
## Stable positions shared by terrain, units, playback and picking.
const LANDMARK_STRUCTURE_OFFSET := Vector3(-0.22, 0, -0.14)
const LANDMARK_UNIT_OFFSET := Vector3(0.42, 0, 0.30)
const MANA_OFFSET := Vector3(0, 0, -0.64)
const ORE_OFFSET := Vector3(-0.56, 0, 0.34)
const DEVELOPMENT_OFFSETS := [Vector3(-0.65,0,-0.20), Vector3(0.65,0,-0.20), Vector3(-0.13,0,0.70), Vector3(-0.40,0,-0.62), Vector3(0.40,0,-0.62), Vector3(0.27,0,0.57)]
const DEVELOPMENT_HOUSE_SCALE := 0.34
const DEVELOPMENT_ROOF_HALF_EXTENTS := Vector2(0.39, 0.35)

static func constrain_house_position(position: Vector3, yaw: float) -> Vector3:
	# Fit the entire rotated roof inside the smallest tile cap, including a small inset.
	# Radial correction retains its corner and leaves rotation / random variation intact.
	var half_extents := DEVELOPMENT_ROOF_HALF_EXTENTS * DEVELOPMENT_HOUSE_SCALE
	var axis_x := Vector2(cos(yaw), -sin(yaw))
	var axis_z := Vector2(sin(yaw), cos(yaw))
	var center := Vector2(position.x, position.z)
	var apothem := 0.968 * sqrt(3.0) * 0.5 - 0.01
	var factor := 1.0
	for side in range(6):
		var normal := Vector2.from_angle(side * TAU / 6.0)
		var footprint := absf(normal.dot(axis_x)) * half_extents.x + absf(normal.dot(axis_z)) * half_extents.y
		var limit := apothem - footprint
		var projection := normal.dot(center)
		if projection > limit: factor = minf(factor, limit / projection)
	return Vector3(position.x * factor, position.y, position.z * factor)

static func unit_offset(cell: Dictionary) -> Vector3:
	if cell.get("building", "") in ["monument","city","tower"] or cell.get("capital", -1) >= 0: return LANDMARK_UNIT_OFFSET
	return Vector3.ZERO
static func unit_scale(_cell: Dictionary) -> float:
	return 1.0
static func landmark_offset(cell: Dictionary) -> Vector3:
	return LANDMARK_STRUCTURE_OFFSET if cell.get("unit", 0) > 0 else Vector3.ZERO
static func landmark_scale(cell: Dictionary) -> float:
	return 0.80 if cell.get("unit", 0) > 0 else 1.0
static func development_count(cell: Dictionary) -> int:
	return clampi(int(cell.get("value", 1)) - 2, 0, 4) if cell.get("owner", -1) >= 0 and not cell.get("mountain", false) and cell.get("building", "") != "bridge" else 0

static func development_house_slots(coord: Vector2i, cell: Dictionary) -> Array[int]:
	# Shuffle all six sites, rather than filling every corner before adding pairs.
	# Each corner has two sites; taking a stable prefix adds houses without moving old ones.
	var slots: Array[int] = [0, 1, 2, 3, 4, 5]
	var variation := RandomNumberGenerator.new()
	variation.seed = hash(Vector3i(coord.x, coord.y, 0xD3F))
	for index in range(slots.size() - 1, 0, -1):
		var other := variation.randi_range(0, index)
		var swap := slots[index]
		slots[index] = slots[other]
		slots[other] = swap
	slots.resize(development_count(cell))
	return slots
