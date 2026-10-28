extends RefCounted
## Flat ground paint, attached to tiles so island transitions carry it with terrain.
const Grid = preload("res://src/game/hex_grid.gd")
const Strokes = preload("res://src/rendering/flat_strokes.gd")
const WIDTH := 0.30
const DARKENING := 0.30
var signature: Array = []
static var shared_material: StandardMaterial3D
static var mesh_cache: Dictionary = {}
const PREVIEW_BORDER := Color("eed3a1")
var material: StandardMaterial3D:
	get: return paint_material()

static func network(cells: Dictionary) -> Dictionary:
	var edges := {}
	for coord in cells:
		var cell: Dictionary = cells[coord]
		if not cell.get("road", false) or cell.owner < 0 or cell.get("mountain", false): continue
		for direction in Grid.DIRECTIONS:
			var next: Vector2i = coord + direction
			if not cells.has(next): continue
			var other: Dictionary = cells[next]
			var connected: bool = preload("res://src/game/logistics.gd").road_connected(cell, other, coord, next)
			if other.building == "bridge": connected = next in cell.get("road_links", []) and coord in other.get("road_links", [])
			if connected and (other.owner == cell.owner or other.building == "bridge"):
				var pair := [coord, next] if coord_before(coord, next) else [next, coord]
				edges[pair] = true
	return edges

static func coord_before(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or a.x == b.x and a.y < b.y

static func ordered_coords(coords: Dictionary) -> Array:
	var result := coords.keys()
	result.sort_custom(coord_before)
	return result

func sync(board) -> void:
	var next_signature: Array = [board.COLORS.duplicate()]
	for coord in board.cells:
		var cell: Dictionary = board.cells[coord]
		next_signature.append([coord,cell.owner,cell.capital,cell.building,cell.get("kingdom",Grid.NONE),cell.get("mountain",false),cell.get("road",false),cell.get("road_links", []).duplicate(),board.tile_nodes[coord].get_instance_id() if board.tile_nodes.has(coord) else 0])
	if signature == next_signature: return
	signature = next_signature
	var masks := {}
	for pair in network(board.cells):
		add_edge(masks, board.cells, pair[0], pair[1])
	for coord in board.tile_nodes:
		var tile: Node3D = board.tile_nodes[coord]
		var old: MeshInstance3D = tile.get_node_or_null("RoadPaint")
		var mask: int = masks.get(coord, 0)
		if mask == 0:
			if old != null:
				tile.remove_child(old)
				old.queue_free()
			continue
		var color: Color = board.COLORS[board.cells[coord].owner].darkened(DARKENING)
		var key := mesh_key(mask, color)
		if old != null and old.get_meta("road_mesh_key", "") == key: continue
		if old == null:
			old = paint(mask, color, "RoadPaint")
			tile.add_child(old)
		else: old.mesh = tile_mesh(mask, color)
		old.set_meta("road_mesh_key", key)

static func paint_material() -> StandardMaterial3D:
	if shared_material == null:
		shared_material = Strokes.vertex_material()
		shared_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		shared_material.roughness = 0.92
		shared_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return shared_material

static func mesh_key(mask: int, color: Color, border := false) -> String:
	return "%d:%s:%s" % [mask, color.to_html(), border]

static func tile_mesh(mask: int, color: Color, border := false) -> ArrayMesh:
	var key := mesh_key(mask, color, border)
	if mesh_cache.has(key): return mesh_cache[key]
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_normal(Vector3.UP)
	for index in range(Grid.DIRECTIONS.size()):
		if mask & (1 << index):
			Strokes.segment(builder, Vector3.ZERO, Grid.to_world(Grid.DIRECTIONS[index]) * 0.5, WIDTH + (0.08 if border else 0.0), 0.014, color)
	var mesh := builder.commit()
	# Cache immutable CPU/GPU resources for previews, placement and later matches.
	mesh_cache[key] = mesh
	return mesh

static func paint(mask: int, color: Color, label: String, border := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = tile_mesh(mask, color, border)
	node.material_override = paint_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func add_edge(masks: Dictionary, cells: Dictionary, a: Vector2i, b: Vector2i) -> void:
	for pair in [[a, b], [b, a]]:
		if cells[pair[0]].building == "bridge": continue
		var direction: int = Grid.DIRECTIONS.find(pair[1] - pair[0])
		if direction >= 0: masks[pair[0]] = int(masks.get(pair[0], 0)) | (1 << direction)

func show_preview(board, path: Array) -> void:
	if path.size() < 2: return
	var masks := {}
	for index in range(path.size() - 1): add_edge(masks, board.cells, path[index], path[index + 1])
	# Include existing junction arms so the preview matches the resulting mesh.
	for pair in network(board.cells):
		if masks.has(pair[0]) or masks.has(pair[1]):
			var existing := {}
			add_edge(existing, board.cells, pair[0], pair[1])
			for coord in existing:
				if masks.has(coord): masks[coord] |= existing[coord]
	var container := Node3D.new()
	container.name = "RoadPreview"
	board.overlay_root.add_child(container)
	for coord in masks:
		var mask: int = masks[coord]
		var color: Color = board.COLORS[board.cells[coord].owner].darkened(DARKENING)
		var border := paint(mask, PREVIEW_BORDER, "RoadPreviewBorder", true)
		border.position = board.coord_position(coord) + Vector3(0, 0.008, 0)
		container.add_child(border)
		var surface := paint(mask, color, "RoadPreviewSurface")
		surface.position = board.coord_position(coord) + Vector3(0, 0.010, 0)
		surface.set_meta("hex", coord)
		container.add_child(surface)

func prepare(parent: Node3D, colors: Array) -> void:
	var started := Time.get_ticks_usec()
	for mask in range(1, 64):
		tile_mesh(mask, PREVIEW_BORDER, true)
		for color in colors: tile_mesh(mask, color.darkened(DARKENING))
		if Time.get_ticks_usec() - started >= 4000:
			await parent.get_tree().process_frame
			started = Time.get_ticks_usec()
	# The exact shared lit vertex-color material must be submitted to the GPU.
	# A generic scenery box does not compile this road pipeline.
	var sample := paint(9, Color.WHITE.darkened(DARKENING), "WarmupRoadSurface")
	parent.add_child(sample)
	var border := paint(9, PREVIEW_BORDER, "WarmupRoadBorder", true)
	border.position.y = -0.002
	parent.add_child(border)
