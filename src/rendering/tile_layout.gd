extends RefCounted
## Shared settled and playback placement keeps garrisons clear of architecture.
const LANDMARK_STRUCTURE_OFFSET := Vector3(-0.26,0,-0.18)
const LANDMARK_UNIT_OFFSET := Vector3(0.42,0,0.32)

static func unit_offset(cell: Dictionary) -> Vector3:
	if cell.get("building", "") in ["monument","city","tower"]: return LANDMARK_UNIT_OFFSET
	return Vector3(0.35,0,0.30) if cell.get("capital",-1) >= 0 else Vector3.ZERO

static func landmark_offset(cell: Dictionary) -> Vector3:
	return LANDMARK_STRUCTURE_OFFSET if cell.get("unit",0) > 0 else Vector3.ZERO
