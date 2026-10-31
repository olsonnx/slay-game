extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## Session generation bounds, population and terrain budgets.
# Stable generation IDs preserve existing maps and replays. Retired profiles
# remain readable but are no longer offered for new maps.
const IDS := ["small", "medium", "large", "very_large", "huge"]
const DEFAULT_KINGDOMS := 4
const MAX_NATIONS := 10
# About 28 nominal tiles per nation, rounded to an even roster, with four
# allowed on the smallest profiles and a global ceiling of ten.
const MAX_KINGDOMS := {"very_small": 4, "small": 4, "medium": 6, "large": 8, "very_large": 10, "huge": 10}
const APPROX_TILES := {"very_small": 40, "small": 80, "medium": 150, "large": 250, "very_large": 500, "huge": 1000}
# Nominal bounds set home-layout proportions; generation_bounds() supplies a
# separate, generous safety envelope so rotated land never hits these edges.
const SPECS := {
	"very_small": {"name": "Very Small", "min_factions": 2, "max_factions": 3, "bounds": Vector2(9.8, 7.5), "radius_min": 2, "radius_max": 2, "core": 1, "outer_dense": 2, "min_land": 28, "zoom": 18.0, "mountain_groups": 1},
	"small": {"name": "Tiny", "min_factions": 4, "max_factions": 4, "bounds": Vector2(12.3, 7.5), "radius_min": 2, "radius_max": 3, "core": 1, "outer_dense": 2, "min_land": 70, "zoom": 22.0, "mountain_groups": 3},
	"medium": {"name": "Small", "min_factions": 4, "max_factions": 5, "bounds": Vector2(19.0, 12.0), "radius_min": 3, "radius_max": 4, "core": 2, "outer_dense": 3, "min_land": 120, "zoom": 30.0, "mountain_groups": 4},
	"large": {"name": "Standard", "min_factions": 6, "max_factions": 6, "bounds": Vector2(24.0, 15.5), "radius_min": 4, "radius_max": 5, "core": 2, "outer_dense": 3, "min_land": 210, "zoom": 38.0, "mountain_groups": 6},
	"very_large": {"name": "Large", "min_factions": 6, "max_factions": 6, "bounds": Vector2(24.0, 15.5) * sqrt(500.0 / 210.0), "radius_min": 6, "radius_max": 8, "core": 3, "outer_dense": 4, "min_land": 500, "zoom": 38.0 * sqrt(500.0 / 210.0), "mountain_groups": 14},
	"huge": {"name": "Huge", "min_factions": 6, "max_factions": 6, "bounds": Vector2(24.0, 15.5) * sqrt(1000.0 / 210.0), "radius_min": 9, "radius_max": 11, "core": 4, "outer_dense": 5, "min_land": 1000, "zoom": 38.0 * sqrt(1000.0 / 210.0), "mountain_groups": 29}
}

static func choice_label(size_id: String) -> String:
	var label := Loc.text("%s · ~%s tiles") % [Loc.text(spec(size_id)["name"]), "1,000" if size_id == "huge" else str(APPROX_TILES.get(size_id, APPROX_TILES["small"]))]
	return label + " · " + Loc.text("Demanding") if size_id == "huge" else label

static func size_warning(size_id: String) -> String:
	return Loc.text("Warning: Huge maps can slow the game and require extensive micromanagement.") if size_id == "huge" else ""

static func tile_tooltip(size_id: String) -> String:
	var description := Loc.text("About %s land tiles, including mountains.\nThe island varies with the seed and kingdom count.") % ("1,000" if size_id == "huge" else str(APPROX_TILES.get(size_id, APPROX_TILES["small"])))
	return description + "\n\n" + size_warning(size_id) if size_id == "huge" else description

static func spec(size_id: String) -> Dictionary:
	return SPECS.get(size_id, SPECS["small"])

static func generation_bounds(size_id: String) -> Vector2:
	# A generous circular safety envelope, not a coastline stencil. Allow the
	# home layout and its lobes to rotate freely without hitting rectangular walls.
	var profile := spec(size_id)
	var old: Vector2 = profile["bounds"]
	return Vector2.ONE * (maxf(old.x, old.y) + profile["radius_max"] * 3.5 + 5.0)

static func clamp_kingdom_count(size_id: String, count: int) -> int:
	return clampi(count, 2, MAX_KINGDOMS.get(size_id, MAX_KINGDOMS["small"]))

static func fallback_sites(size_id: String, count := 0) -> Array:
	# Only used after bounded random packing retries. These layouts fit full
	# seven-hex homes with at least five steps between every capital pair.
	if size_id == "very_small":
		return [Vector2i(-3, -2), Vector2i(5, -2), Vector2i(-5, 3), Vector2i(3, 3)]
	if size_id == "small":
		return [Vector2i(-4, -3), Vector2i(1, -3), Vector2i(6, -3), Vector2i(-7, 3), Vector2i(-2, 3), Vector2i(3, 3)]
	if count > 6:
		# Triangular lattice: ten full home rings, all capitals at least five
		# hexes apart. The generous generation envelope contains every ring.
		return [Vector2i(-5,-5),Vector2i(0,-5),Vector2i(5,-5),Vector2i(-5,0),Vector2i(0,0),Vector2i(5,0),Vector2i(-5,5),Vector2i(0,5),Vector2i(5,5),Vector2i(0,-10)]
	var radius := 6 if size_id == "medium" else 9
	var result: Array = []
	for direction in preload("res://src/game/hex_grid.gd").DIRECTIONS:
		result.append(direction * radius)
	return result

