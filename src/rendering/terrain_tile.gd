extends RefCounted
## Shared terrain, props and adjustable kingdom rims for gameplay and menu islands.
const Grid = preload("res://src/game/hex_grid.gd")
# Keep the gameplay surface height while the molded bevel drops into the base.
const CAP_HEIGHT := 0.0105
const CAP_CENTER := CAP_HEIGHT / 2.0

static func color_at(assets, coord: Vector2i, cell: Dictionary) -> Color:
	var color: Color = assets.COLORS[cell["owner"]] if cell["owner"] >= 0 else assets.NEUTRAL
	if cell.get("mountain", false):
		color = Color("858779")
	return color.lightened((0.012 if assets.plastic_tiles else 0.045) * sin(float(coord.x * 7 + coord.y * 13)))

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
	var key := "kingdom_cap:%d" % mask
	if assets.mesh_cache.has(key):
		return assets.mesh_cache[key]
	# Share the exact molded top geometry with the settled chunk renderer.
	var parts := preload("res://src/rendering/terrain_chunks.gd").template(mask, assets.internal_border_visibility, 0, assets.plastic_tiles)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices: PackedVector3Array = parts[0].duplicate()
	for index in range(vertices.size()):
		vertices[index].y -= CAP_CENTER
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = parts[1]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	assets.mesh_cache[key] = mesh
	return mesh

static func update_join(assets, tile: Node3D, cell: Dictionary, mask: int) -> void:
	if cell["building"] == "bridge" or (tile.get_meta("joined_mask", 0) == mask and is_equal_approx(tile.get_meta("border_visibility", -1.0), assets.internal_border_visibility) and tile.get_meta("plastic_tiles", not assets.plastic_tiles) == assets.plastic_tiles):
		return
	tile.get_meta("surface").mesh = cap_mesh(assets, mask)
	tile.set_meta("joined_mask", mask)
	tile.set_meta("border_visibility", assets.internal_border_visibility)
	tile.set_meta("plastic_tiles", assets.plastic_tiles)

static func base_color(assets) -> Color:
	return preload("res://src/rendering/terrain_chunks.gd").BASE_COLOR if assets.plastic_tiles else Color("776a51")

static func apply_appearance(assets, tile: Node3D, coord: Vector2i, cell: Dictionary) -> void:
	if cell["building"] == "bridge": return
	tile.get_meta("surface").material_override = assets.tile_material(color_at(assets, coord, cell))
	var earth: MeshInstance3D = tile.get_meta("earth")
	earth.mesh = base_mesh(assets)
	earth.material_override = assets.tile_material(base_color(assets), true)

static func base_mesh(assets) -> ArrayMesh:
	var key := "tile_base:%s" % assets.plastic_tiles
	if assets.mesh_cache.has(key):
		return assets.mesh_cache[key]
	# Flat side normals match the settled mesh, including during tile motion.
	var parts := preload("res://src/rendering/terrain_chunks.gd").template(0, 1.0, 63, assets.plastic_tiles)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = parts[2]
	arrays[Mesh.ARRAY_NORMAL] = parts[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	assets.mesh_cache[key] = mesh
	return mesh

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
		var earth: MeshInstance3D = assets.piece(tile, base_mesh(assets), Vector3.ZERO, base_color(assets))
		earth.material_override = assets.tile_material(base_color(assets), true)
		earth.set_meta("terrain_role", "earth")
		tile.set_meta("earth", earth)
		surface = assets.piece(tile, cap_mesh(assets, mask), Vector3(0, CAP_CENTER, 0), color)
		surface.material_override = assets.tile_material(color)
		surface.set_meta("terrain_role", "cap")
	tile.set_meta("joined_mask", mask)
	tile.set_meta("border_visibility", assets.internal_border_visibility)
	tile.set_meta("plastic_tiles", assets.plastic_tiles)
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
	if cell["tree"]:
		assets.add_tree(features, Vector3(-0.40, 0, -0.04) if cell.get("event", "") != "" or cell.get("treasure", 0) > 0 else Vector3(0.13, 0, 0))
	if cell["grave"]:
		assets.add_grave(features, Vector3(0.15, 0, 0))
	if cell["building"] == "tower":
		var tower := Node3D.new()
		tower.position = preload("res://src/rendering/tile_layout.gd").landmark_offset(cell)
		tower.scale = Vector3.ONE * 0.68 * preload("res://src/rendering/tile_layout.gd").landmark_scale(cell)
		features.add_child(tower)
		assets.add_tower(tower, Vector3.ZERO, color)
	elif cell["building"] == "city":
		assets.add_city(features, preload("res://src/rendering/tile_layout.gd").landmark_offset(cell))
	if cell["building"] == "monument":
		assets.add_event_landmark(features, color, preload("res://src/rendering/tile_layout.gd").landmark_offset(cell), cell.get("site_source", ""))
	if cell["capital"] >= 0:
		assets.add_capital(features, preload("res://src/rendering/tile_layout.gd").landmark_offset(cell), color)
	if cell["capital"] >= 0 or cell["building"] in ["city", "tower"]:
		assets.add_structure_tier(features, cell)
	assets.add_development(tile, cell)
	if cell.get("ore_source", false): assets.add_ore_source(tile)
	if cell.get("treasure", 0) > 0:
		assets.add_treasure(features)
	if cell.get("lair", "") != "":
		preload("res://src/rendering/wildlife_presentation.gd").add_lair(assets,features,cell.lair)
	if cell.get("mana_source", false):
		assets.add_mana_source(tile)

static func refresh(assets, tile: Node3D, coord: Vector2i, cell: Dictionary, mask := 0) -> void:
	# Rebuild changed scenery while retaining the tile and its terrain buffers.
	for name in ["Features", "ManaSource", "OreSource", "Development"]:
		var old := tile.get_node_or_null(name)
		if old != null:
			tile.remove_child(old)
			old.queue_free()
	var color := color_at(assets, coord, cell)
	if cell["building"] == "bridge":
		tile.get_meta("surface").material_override = assets.material(color)
	else:
		apply_appearance(assets, tile, coord, cell)
	update_join(assets, tile, cell, mask)
	populate(assets, tile, coord, cell, color)
