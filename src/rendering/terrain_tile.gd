extends RefCounted
## Shared terrain, props and adjustable kingdom rims for gameplay and menu islands.
const Grid = preload("res://src/game/hex_grid.gd")
# The coloured layer ends at the soil top. Extending flush joined walls
# below this plane creates coplanar coloured/earth faces and depth flicker.
const CAP_HEIGHT := 0.0105
const CAP_CENTER := CAP_HEIGHT / 2.0

static func color_at(assets, coord: Vector2i, cell: Dictionary) -> Color:
	var color: Color = assets.COLORS[cell["owner"]] if cell["owner"] >= 0 else assets.NEUTRAL
	if cell.get("mountain", false):
		color = Color("858779")
	return color.lightened(0.045 * sin(float(coord.x * 7 + coord.y * 13)))

static func joined_mask(cells: Dictionary, coord: Vector2i) -> int:
	var cell: Dictionary = cells[coord]
	if cell["owner"] < 0 or cell["building"] == "bridge" or cell.get("kingdom", Grid.NONE) == Grid.NONE:
		return 0
	var mask := 0
	for edge in range(6):
		var next: Vector2i = coord + Grid.DIRECTIONS[edge]
		var neighbor: Dictionary = cells.get(next, {})
		if not neighbor.is_empty() and neighbor["building"] != "bridge" and neighbor["owner"] == cell["owner"] and neighbor.get("kingdom", Grid.NONE) == cell["kingdom"]:
			mask |= 1 << edge
	return mask

static func cap_mesh(assets, mask: int) -> Mesh:
	if mask == 0 or assets.internal_border_visibility >= 1.0:
		return assets.cylinder_mesh(0.968, 0.968, CAP_HEIGHT, 6)
	var key := "kingdom_cap:%d" % mask
	if assets.mesh_cache.has(key):
		return assets.mesh_cache[key]
	# Blend shared edges between flush and the original inset. Exterior edges
	# retain their full earth rim around the kingdom/coastline.
	var normals: Array[Vector2] = []
	var offsets: Array[float] = []
	for edge in range(6):
		var world := Grid.to_world(Grid.DIRECTIONS[edge])
		normals.append(Vector2(world.x, world.z).normalized())
		var radius: float = lerpf(1.0, 0.968, assets.internal_border_visibility) if mask & (1 << edge) else 0.968
		offsets.append(sqrt(3.0) * 0.5 * radius)
	var corners: Array[Vector3] = []
	for edge in range(6):
		var next := (edge + 1) % 6
		var a: Vector2 = normals[edge]
		var b: Vector2 = normals[next]
		var determinant := a.x * b.y - a.y * b.x
		corners.append(Vector3((offsets[edge] * b.y - offsets[next] * a.y) / determinant, CAP_CENTER,
			(a.x * offsets[next] - b.x * offsets[edge]) / determinant))
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_smooth_group(-1)
	for edge in range(6):
		var a: Vector3 = corners[edge]
		var b: Vector3 = corners[(edge + 1) % 6]
		var bottom_a := a - Vector3(0, CAP_HEIGHT, 0)
		var bottom_b := b - Vector3(0, CAP_HEIGHT, 0)
		for vertex in [Vector3(0, CAP_CENTER, 0), b, a, Vector3(0, -CAP_CENTER, 0), bottom_a, bottom_b,
			a, bottom_b, bottom_a, a, b, bottom_b]:
			builder.add_vertex(vertex)
	builder.generate_normals()
	var mesh := builder.commit()
	assets.mesh_cache[key] = mesh
	return mesh

static func update_join(assets, tile: Node3D, cell: Dictionary, mask: int) -> void:
	if cell["building"] == "bridge" or (tile.get_meta("joined_mask", 0) == mask and is_equal_approx(tile.get_meta("border_visibility", -1.0), assets.internal_border_visibility)):
		return
	tile.get_meta("surface").mesh = cap_mesh(assets, mask)
	tile.set_meta("joined_mask", mask)
	tile.set_meta("border_visibility", assets.internal_border_visibility)

static func build(assets, parent: Node3D, coord: Vector2i, cell: Dictionary, mask := 0) -> Node3D:
	var tile := Node3D.new()
	tile.set_meta("hex", coord)
	tile.position = Grid.to_world(coord)
	parent.add_child(tile)
	var color := color_at(assets, coord, cell)
	var surface: MeshInstance3D
	if cell["building"] == "bridge":
		var deck := Node3D.new()
		deck.name = "BridgeDeck"
		tile.add_child(deck)
		surface = assets.add_bridge(deck)
	else:
		var earth: MeshInstance3D = assets.piece(tile, assets.cylinder_mesh(1.0, 1.0, 0.56, 6), Vector3(0, -0.28, 0), Color("776a51"))
		earth.set_meta("terrain_role", "earth")
		tile.set_meta("earth", earth)
		surface = assets.piece(tile, cap_mesh(assets, mask), Vector3(0, CAP_CENTER, 0), color)
		surface.set_meta("terrain_role", "cap")
	tile.set_meta("joined_mask", mask)
	tile.set_meta("border_visibility", assets.internal_border_visibility)
	tile.set_meta("surface", surface)
	populate(assets, tile, coord, cell, color)
	return tile

static func populate(assets, tile: Node3D, coord: Vector2i, cell: Dictionary, color: Color) -> void:
	var features := Node3D.new()
	features.name = "Features"
	tile.add_child(features)
	if not cell.get("land", true):
		return
	if cell.get("mountain", false):
		assets.add_mountain(features, coord)
	elif cell["unit"] == 0 and cell["capital"] < 0 and cell["building"] == "" and not cell["tree"] and not cell["grave"] and cell.get("event", "") == "" and cell.get("treasure", 0) == 0:
		assets.grass_details(features, coord, color)
	if cell["tree"]:
		assets.add_tree(features, Vector3(-0.40, 0, -0.04) if cell.get("event", "") != "" or cell.get("treasure", 0) > 0 else Vector3(0.13, 0, 0))
	if cell["grave"]:
		assets.add_grave(features, Vector3(0.15, 0, 0))
	if cell["building"] == "tower":
		assets.add_tower(features, Vector3.ZERO, color)
	elif cell["building"] == "house":
		assets.add_house(features, Vector3.ZERO)
	if cell["capital"] >= 0:
		assets.add_capital(features, Vector3(-0.20, 0, -0.12) if cell["unit"] > 0 or cell["grave"] or cell["tree"] else Vector3.ZERO, color)
	if cell.get("treasure", 0) > 0:
		assets.add_treasure(features)
	if cell.get("mana_source", false):
		assets.add_mana_source(tile)

static func refresh(assets, tile: Node3D, coord: Vector2i, cell: Dictionary, mask := 0) -> void:
	# Used only for offscreen menu recycling. The board retains its own dirty sync.
	for name in ["Features", "ManaSource"]:
		var old := tile.get_node_or_null(name)
		if old != null:
			tile.remove_child(old)
			old.queue_free()
	var color := color_at(assets, coord, cell)
	tile.get_meta("surface").material_override = assets.material(color)
	update_join(assets, tile, cell, mask)
	populate(assets, tile, coord, cell, color)
