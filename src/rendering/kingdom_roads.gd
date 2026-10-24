extends RefCounted
## Flat ground paint, attached to tiles so island transitions carry it with terrain.
const Grid = preload("res://src/game/hex_grid.gd")
const Strokes = preload("res://src/rendering/flat_strokes.gd")
const WIDTH := 0.30
const DARKENING := 0.30
var signature: Array = []
var material: StandardMaterial3D

static func network(cells: Dictionary) -> Dictionary:
	var groups := {}
	for coord in cells:
		var cell: Dictionary = cells[coord]
		var capital: Vector2i = cell.get("kingdom",Grid.NONE)
		if capital == Grid.NONE or cell.owner < 0 or cell.get("mountain",false): continue
		if not groups.has(capital): groups[capital] = {"land":{},"sites":{}}
		groups[capital].land[coord] = true
		if cell.capital >= 0 or cell.building != "": groups[capital].sites[coord] = true
	# Neutral bridge decks connect a kingdom's land; keep their existing artwork.
	for group in groups.values():
		var land: Dictionary = group.land.duplicate()
		for coord in cells:
			if cells[coord].building != "bridge": continue
			group.land[coord] = true
			for direction in Grid.DIRECTIONS:
				if land.has(coord+direction):
					group.sites[coord] = true
					break
	var edges := {}
	for group in groups.values():
		var remaining: Dictionary = group.sites.duplicate()
		# Grow a tree from existing roads. A new branch only meets the tree at
		# its endpoint, so opposite searches cannot create two equal routes.
		for start in ordered_coords(group.sites):
			if not remaining.has(start): continue
			remaining.erase(start)
			var connected := {start:true}
			while not remaining.is_empty():
				var parents := {}
				var pending := ordered_coords(connected)
				for coord in pending: parents[coord] = coord
				var cursor := 0
				var found: Vector2i = Grid.NONE
				while cursor < pending.size() and found == Grid.NONE:
					var current: Vector2i = pending[cursor]
					cursor += 1
					for direction in Grid.DIRECTIONS:
						var next: Vector2i = current + direction
						if not group.land.has(next) or parents.has(next): continue
						parents[next] = current
						pending.append(next)
						if remaining.has(next):
							found = next
							break
				if found == Grid.NONE: break # Other land components start their own tree.
				remaining.erase(found)
				while not connected.has(found):
					var previous: Vector2i = parents[found]
					var pair := [previous,found] if coord_before(previous, found) else [found,previous]
					edges[pair] = true
					connected[found] = true
					found = previous

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
		next_signature.append([coord,cell.owner,cell.capital,cell.building,cell.get("kingdom",Grid.NONE),cell.get("mountain",false),board.tile_nodes[coord].get_instance_id() if board.tile_nodes.has(coord) else 0])
	if signature == next_signature: return
	signature = next_signature
	for tile in board.tile_nodes.values():
		var old = tile.get_node_or_null("RoadPaint")
		if old != null:
			tile.remove_child(old)
			old.queue_free()
	var builders := {}
	for pair in network(board.cells):
		var midpoint: Vector3 = (Grid.to_world(pair[0])+Grid.to_world(pair[1]))*0.5
		for coord in pair:
			if board.cells[coord].building == "bridge": continue
			if not builders.has(coord):
				var builder := SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				builder.set_normal(Vector3.UP)
				builders[coord] = builder
			var color: Color = board.COLORS[board.cells[coord].owner]
			Strokes.segment(builders[coord],Vector3.ZERO,midpoint-Grid.to_world(coord),WIDTH,0.014,color.darkened(DARKENING))
	if material == null:
		material = Strokes.vertex_material()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		material.roughness = 0.92
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for coord in builders:
		if not board.tile_nodes.has(coord): continue
		var paint := MeshInstance3D.new()
		paint.name = "RoadPaint"
		paint.mesh = builders[coord].commit()
		paint.material_override = material
		paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		board.tile_nodes[coord].add_child(paint)
