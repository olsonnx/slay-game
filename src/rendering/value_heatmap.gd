extends Node3D
## A value tint on the existing 3D island, with retained outlines/hover labels.
const Grid = preload("res://src/game/hex_grid.gd")
const Strokes = preload("res://src/rendering/flat_strokes.gd")
const LOW := Color("bf7b6c")
const HIGH := Color("91b77e")
signal changed
var board
var active := false
var maximum := 0
var tiles: Dictionary = {}
var boundary_signature: Array = []
var borders: MeshInstance3D
var painted: Dictionary = {}
var hidden: Dictionary = {}
var prop_materials: Dictionary = {}
var hovered := Grid.NONE

func _init(view) -> void:
	board = view
	visible = false

static func tile_value(cell: Dictionary) -> int:
	return 0 if cell.get("mountain", false) or cell.get("building", "") == "bridge" or not cell.get("land", true) else maxi(0, int(cell.get("value", 1)))

static func value_color(value: float, highest: int) -> Color:
	if value <= 0:
		return Color.BLACK
	if highest <= 1:
		return LOW
	if value >= highest:
		return HIGH
	var amount := clampf(float(value - 1) / (highest - 1), 0, 1)
	return LOW.lerp(Color("d6c08b"), amount * 2) if amount <= 0.5 else Color("d6c08b").lerp(HIGH, (amount - 0.5) * 2)

func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	visible = value
	board.clear_unit_hover()
	board.animation_root.visible = not value
	board.overlay_root.visible = not value and not board.level_transitioning
	board.invalidate_pick()
	if value:
		sync()
		var previous_hover := hovered
		hovered = Grid.NONE
		set_hovered(previous_hover)
	else:
		restore()
		set_hovered(Grid.NONE)
	changed.emit()

func paint(mesh: MeshInstance3D, material: Material) -> void:
	var id := mesh.get_instance_id()
	if not painted.has(id) or mesh.material_override != painted[id]["filter"]:
		painted[id] = {"node": mesh, "original": mesh.material_override, "filter": material}
	else:
		painted[id]["filter"] = material
	if mesh.material_override != material:
		mesh.material_override = material
		mark_source_dirty(mesh)

func mark_source_dirty(node: Node) -> void:
	var parent := node
	while parent != null and parent != board.board_root and parent != board.animation_root:
		if parent.has_meta("surface"):
			board.mark_batch_dirty(parent.get_meta("hex"))
			return
		parent = parent.get_parent()

func hide_detail(node: Node3D, role := "prop") -> void:
	var id := node.get_instance_id()
	if not hidden.has(id):
		hidden[id] = {"node": node, "original": node.visible, "role": role}
	if node.visible:
		node.hide()
		if role == "prop":
			mark_source_dirty(node)

func restore() -> void:
	for record in painted.values():
		var node = record["node"]
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.material_override == record["filter"]:
			node.material_override = record["original"]
	for record in hidden.values():
		var node = record["node"]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var show_original: bool = record["original"]
		if record["role"] == "unit":
			show_original = show_original and board.cells.get(node.get_meta("hex", Grid.NONE), {}).get("unit", 0) > 0
			# Occupation briefly leaves the old defender registered alongside
			# the arriving actor. Restore the traveler, never the defeated unit.
			if node.get_parent() != board.animation_root:
				for actor in board.unit_actors.values():
					if actor != node and actor.get_parent() == board.animation_root and actor.get_meta("hex") == node.get_meta("hex"):
						show_original = false
		elif record["role"] == "ward":
			var cell: Dictionary = board.cells.get(node.get_parent().get_meta("hex", Grid.NONE), {})
			show_original = show_original and (cell.get("fortified", false) or cell.get("entrenched_by", -1) >= 0 or cell.get("barrier_by", -1) >= 0)
		node.visible = show_original
	painted.clear()
	hidden.clear()

func mute_props(node: Node, mountain: bool, skip: MeshInstance3D = null) -> void:
	if node is MeshInstance3D and node != skip:
		var id := node.get_instance_id()
		var original = painted[id]["original"] if painted.has(id) and node.material_override == painted[id]["filter"] else node.material_override
		if original is StandardMaterial3D:
			var cache_key := str(original.get_instance_id()) + str(mountain)
			if not prop_materials.has(cache_key):
				var material: StandardMaterial3D = original.duplicate()
				var color: Color = original.albedo_color
				material.albedo_color = color.darkened(0.55) if mountain else color.lerp(Color("929387"), 0.72).darkened(0.08)
				material.albedo_color.a = color.a
				prop_materials[cache_key] = material
			paint(node, prop_materials[cache_key])
	for child in node.get_children():
		mute_props(child, mountain, skip)

func set_hovered(coord: Vector2i) -> void:
	if hovered == coord:
		return
	if tiles.has(hovered):
		tiles[hovered].get_node("Value").hide()
	hovered = coord
	if active and tiles.has(coord):
		tiles[coord].get_node("Value").show()

func sync() -> void:
	if not active:
		return
	# Drop references to props/tiles replaced during normal board playback.
	for records in [painted, hidden]:
		for id in records.keys():
			if not is_instance_valid(records[id]["node"]) or records[id]["node"].is_queued_for_deletion():
				records.erase(id)
	var next_maximum := 0
	var next_boundaries: Array = []
	for coord in board.cells:
		var cell: Dictionary = board.cells[coord]
		next_maximum = maxi(next_maximum, tile_value(cell))
		next_boundaries.append([coord, cell["owner"], cell.get("kingdom", Grid.NONE), cell["building"] == "bridge"])
	var range_changed := maximum != next_maximum
	maximum = next_maximum
	for coord in tiles.keys():
		if not board.cells.has(coord):
			remove_child(tiles[coord])
			tiles[coord].queue_free()
			tiles.erase(coord)
	for coord in board.cells:
		if not board.tile_nodes.has(coord):
			continue
		var cell: Dictionary = board.cells[coord]
		var original_tile: Node3D = board.tile_nodes[coord]
		var surface: MeshInstance3D = original_tile.get_meta("surface")
		var id := original_tile.get_instance_id()
		var filter_is_current: bool = (board.batch_incremental_event and not range_changed
			and not board.batch_dirty_ids.has(id) and tiles.has(coord)
			and tiles[coord].get_meta("source_tile", 0) == id and painted.has(surface.get_instance_id())
			and surface.material_override == painted[surface.get_instance_id()]["filter"]
			and tiles[coord].get_node("Value").text == str(tile_value(cell)))
		if filter_is_current:
			continue
		paint(surface, board.material(value_color(tile_value(cell), maximum)))
		if cell["building"] == "bridge":
			# Keep the wooden deck's volume, but darken all planks/supports so
			# they agree with the zero-value tint on its underlying surface.
			mute_props(original_tile.get_node("BridgeDeck"), true, original_tile.get_meta("surface"))
		mute_props(original_tile.get_node("Features"), cell.get("mountain", false))
		for name in ["Tree", "ManaSource", "Fortification"]:
			var detail := original_tile.get_node_or_null("Features/Tree" if name == "Tree" else name)
			if detail != null:
				hide_detail(detail, "ward" if name == "Fortification" else "prop")
		for child in original_tile.get_children():
			if child is Label3D:
				hide_detail(child)
		if not tiles.has(coord):
			build_label(coord)
		tiles[coord].set_meta("source_tile", id)
		tiles[coord].get_node("Value").text = str(tile_value(cell))
	for actor in board.unit_actors.values():
		if is_instance_valid(actor):
			hide_detail(actor, "unit")
	if boundary_signature != next_boundaries:
		boundary_signature = next_boundaries
		rebuild_borders()
	if range_changed:
		changed.emit()

func build_label(coord: Vector2i) -> void:
	var tile := Node3D.new()
	tile.position = Grid.to_world(coord)
	add_child(tile)
	tiles[coord] = tile
	var number := Label3D.new()
	number.name = "Value"
	number.position.y = 0.13
	number.font_size = 48
	number.pixel_size = 0.009
	number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	number.modulate = Color("ede7d4")
	number.outline_modulate = Color("25342d")
	number.outline_size = 3
	number.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	number.no_depth_test = true
	number.visible = hovered == coord
	tile.add_child(number)

func rebuild_borders() -> void:
	if borders == null:
		borders = MeshInstance3D.new()
		borders.name = "KingdomBorders"
		borders.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		borders.material_override = material
		add_child(borders)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := 0
	for coord in board.cells:
		var cell: Dictionary = board.cells[coord]
		if cell["owner"] < 0 or cell["building"] == "bridge":
			continue
		for direction in Grid.DIRECTIONS:
			var neighbor: Dictionary = board.cells.get(coord + direction, {})
			if not neighbor.is_empty() and neighbor["owner"] == cell["owner"] and neighbor.get("kingdom", Grid.NONE) == cell.get("kingdom", Grid.NONE) and neighbor["building"] != "bridge":
				continue
			var normal := Grid.to_world(direction)
			var angle := atan2(normal.z, normal.x)
			var center := Grid.to_world(coord)
			var a := center + Vector3(cos(angle - PI / 6), 0, sin(angle - PI / 6))
			var b := center + Vector3(cos(angle + PI / 6), 0, sin(angle + PI / 6))
			Strokes.segment(builder, a, b, 0.075, 0.06, Color("374038"))
			Strokes.segment(builder, a, b, 0.035, 0.09, board.COLORS[cell["owner"]].lightened(0.15))
			edges += 1
	borders.mesh = builder.commit() if edges > 0 else null
	borders.set_meta("edge_count", edges)

