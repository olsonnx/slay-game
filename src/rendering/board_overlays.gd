extends RefCounted
const Strokes = preload("res://src/rendering/flat_strokes.gd")
const Movement = preload("res://src/game/kingdom_movement.gd")
const PROTECTION_COLOR := Color("edbd75")
## Selection, routes and command previews; owned by a single board's lifetime.
var board
var signature: Array = []
var overlay_count := -1
var land_by_kingdom: Dictionary = {}
var board_order: Dictionary = {}
var reachable_signature: Array = []
var kingdom_signature: Array = []
var kingdom_batch: MultiMeshInstance3D
var kingdom_slots: Dictionary = {}
var kingdom_hidden: Dictionary = {}

func _init(view) -> void:
	board = view

func invalidate() -> void:
	land_by_kingdom.clear()
	board_order.clear()
	signature.clear()
	reachable_signature.clear()
	kingdom_signature.clear()

func outline(coord: Vector2i, color: Color) -> void:
	var node := MeshInstance3D.new()
	node.mesh = board.outline_mesh
	node.position = board.coord_position(coord) + Vector3(0, 0.026, 0)
	node.material_override = board.material(color, true, true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.overlay_root.add_child(node)

func show_overlays(selected: Vector2i, hovered: Vector2i, valid: Dictionary, path: Array, active_capital: Vector2i, intent: Dictionary = {}, protector: Vector2i = Vector2i(999, 999)) -> void:
	if board.value_heatmap != null and board.value_heatmap.active:
		return
	var protected_tiles := Movement.unit_protection(board.cells, protector)
	var protection_strength: int = board.cells.get(protector, {}).get("unit", 0)
	var next_signature := [selected, hovered, valid.keys(), path.duplicate(), active_capital, intent.duplicate(true), Gameplay.clear_indicators, protector, protected_tiles.keys(), protection_strength]
	if signature == next_signature and board.overlay_root.get_child_count() == overlay_count:
		update_upgrade_indicator()
		return
	signature = next_signature
	var clear_move: bool = Gameplay.clear_indicators and selected != board.NONE
	var next_reachable := [selected, valid.keys()]
	var retain_reachable: bool = clear_move and reachable_signature == next_reachable and board.overlay_root.has_node("ReachableArea") and board.overlay_root.has_node("ReachWash")
	var show_kingdom: bool = not clear_move and protected_tiles.is_empty() and active_capital != board.NONE
	var retain_kingdom: bool = show_kingdom and kingdom_signature == [active_capital] and is_instance_valid(kingdom_batch) and kingdom_batch.get_parent() == board.overlay_root
	for child in board.overlay_root.get_children():
		if retain_reachable and child.name in ["ReachBacking", "ReachableArea", "ReachWash"]:
			continue
		if retain_kingdom and child == kingdom_batch:
			continue
		board.overlay_root.remove_child(child)
		child.queue_free()
	board.intent_preview = null
	if clear_move and not retain_reachable:
		show_reachable_area(selected, valid)
	reachable_signature = next_reachable if clear_move else []
	if not protected_tiles.is_empty():
		show_protection(protector, protected_tiles, protection_strength)
	# Pointer motion should not rescan every neutral province to find the same
	# seven home tiles. Cache membership until visible board state changes.
	if board_order.is_empty():
		for coord in board.cells:
			board_order[coord] = board_order.size()
			var cell: Dictionary = board.cells[coord]
			if cell["owner"] == 0:
				var kingdom: Vector2i = cell["kingdom"]
				if not land_by_kingdom.has(kingdom):
					land_by_kingdom[kingdom] = []
				land_by_kingdom[kingdom].append(coord)
	var candidates: Dictionary = {} if clear_move else valid.duplicate()
	for coord in [selected, hovered]:
		if board.cells.has(coord):
			candidates[coord] = true
	if show_kingdom:
		if not retain_kingdom:
			build_kingdom_outline(active_capital)
		var hidden: Dictionary = valid.duplicate()
		hidden[selected] = true
		hidden[hovered] = true
		for coord in kingdom_hidden:
			if not hidden.has(coord): set_kingdom_slot(coord, true)
		for coord in hidden:
			if not kingdom_hidden.has(coord): set_kingdom_slot(coord, false)
		kingdom_hidden = hidden
	else:
		kingdom_signature.clear()
	var ordered: Array = candidates.keys().filter(func(coord): return board.cells.has(coord))
	ordered.sort_custom(func(a, b): return board_order[a] < board_order[b])
	for coord in ordered:
		if coord == selected:
			if clear_move:
				tile_marker(coord, Color("fff0c2"), true)
			else:
				board.outline(coord, Color("ffe2a1"))
		elif clear_move and valid.has(coord):
			if coord == hovered:
				tile_marker(coord, destination_color(coord), true)
		elif coord == hovered and intent.is_empty():
			board.outline(coord, Color("f2eed6"))
		elif valid.has(coord):
			board.outline(coord, Color("c7d7a7"))
		elif not clear_move and protected_tiles.is_empty() and board.cells[coord]["owner"] == 0 and board.cells[coord]["kingdom"] == active_capital and active_capital != board.NONE:
			board.outline(coord, Color("a3c394"))
	for coord in valid:
		if not board.cells.has(coord):
			board.outline(coord, Color("95c9ee"))
	var path_color: Color = board.intent_color(intent) if not intent.is_empty() else Color("ffdea0")
	if clear_move and path.size() > 1:
		show_route(path, path_color)
	for index in range(0 if clear_move else path.size() - 1):
		var a: Vector3 = board.coord_position(path[index])
		var b: Vector3 = board.coord_position(path[index + 1])
		for step in range(1, 5):
			var p := a.lerp(b, step / 5.0)
			var dot: MeshInstance3D = board.cylinder(board.overlay_root, p + Vector3(0, 0.05, 0), 0.045, 0.045, 0.02, path_color, 8)
			dot.material_override = board.material(path_color, true)
	if not intent.is_empty() and (board.cells.has(hovered) or intent["kind"] == "bridge"):
		board.show_intent(hovered, intent, path)
	overlay_count = board.overlay_root.get_child_count()

func build_kingdom_outline(capital: Vector2i) -> void:
	kingdom_slots.clear()
	kingdom_hidden.clear()
	kingdom_signature = [capital]
	kingdom_batch = MultiMeshInstance3D.new()
	kingdom_batch.name = "KingdomOutline"
	kingdom_batch.material_override = board.material(Color("a3c394"), true, true)
	kingdom_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = board.outline_mesh
	var coords: Array = land_by_kingdom.get(capital, [])
	instances.instance_count = coords.size()
	kingdom_batch.multimesh = instances
	board.overlay_root.add_child(kingdom_batch)
	for index in range(coords.size()):
		kingdom_slots[coords[index]] = index
		set_kingdom_slot(coords[index], true)

func set_kingdom_slot(coord: Vector2i, shown: bool) -> void:
	if kingdom_slots.has(coord):
		var basis := Basis.IDENTITY if shown else Basis.from_scale(Vector3.ZERO)
		kingdom_batch.multimesh.set_instance_transform(kingdom_slots[coord], Transform3D(basis, board.coord_position(coord) + Vector3(0, 0.026, 0)))

func intent_color(intent: Dictionary) -> Color:
	if not intent.get("valid", true):
		return Color("ec7773")
	match intent.get("kind", "move"):
		"attack": return Color("f09b79")
		"capture": return Color("f2d08c")
		"recruit": return Color("a1e7b1")
		"tower", "house", "bridge": return Color("95c9ee")
		"merge", "upgrade": return Color("c9adf1")
		"spell": return Color("bda2fa")
	return Color("8ee1dc")

func destination_color(coord: Vector2i) -> Color:
	var cell: Dictionary = board.cells[coord]
	if cell["building"] == "bridge":
		if cell["unit"] > 0:
			return intent_color({"kind": "merge" if cell["unit_owner"] == 0 else "attack"})
		return intent_color({"kind": "move"})
	if cell["owner"] != 0:
		return intent_color({"kind": "attack" if cell["unit"] > 0 or cell["building"] != "" or cell["capital"] >= 0 else "capture"})
	return intent_color({"kind": "merge" if cell["unit"] > 0 else "move"})

func marker_mesh(outer: float, inner: float) -> ArrayMesh:
	var key := "move_ring:%s:%s" % [outer, inner]
	if board.mesh_cache.has(key):
		return board.mesh_cache[key]
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in range(6):
		var a := Vector3(sin(edge * TAU / 6), 0, cos(edge * TAU / 6))
		var b := Vector3(sin((edge + 1) * TAU / 6), 0, cos((edge + 1) * TAU / 6))
		for vertex in [a * outer, b * outer, a * inner, a * inner, b * outer, b * inner]:
			builder.add_vertex(vertex)
	var mesh := builder.commit()
	board.mesh_cache[key] = mesh
	return mesh

func flat_piece(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, name_value: String) -> MeshInstance3D:
	var node: MeshInstance3D = board.piece(parent, mesh, at, color)
	node.name = name_value
	node.material_override = board.material(color, true, true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func tile_marker(coord: Vector2i, color: Color, emphasized: bool) -> void:
	var marker := Node3D.new()
	marker.name = "ReachableTile" if coord != signature[0] else "SelectedTile"
	marker.set_meta("movement_role", "reachable" if coord != signature[0] else "selected")
	marker.set_meta("hex", coord)
	marker.position = board.coord_position(coord)
	board.overlay_root.add_child(marker)
	# Leave the terrain, props and ownership readable beneath a restrained wash.
	var fill := flat_piece(marker, board.cylinder_mesh(0.90, 0.90, 0.002, 6), Vector3(0, 0.025, 0), color, "Wash")
	var mat := board.material(color, true, true).duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.28 if emphasized else 0.18
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fill.material_override = mat
	flat_piece(marker, marker_mesh(0.925, 0.80 if emphasized else 0.825), Vector3(0, 0.060, 0), Color("253d43"), "BorderBacking")
	flat_piece(marker, marker_mesh(0.915, 0.815 if emphasized else 0.84), Vector3(0, 0.085, 0), color, "Border")

func area_edges(region: Dictionary) -> Array:
	var edges: Array = []
	var grid = preload("res://src/game/hex_grid.gd")
	for coord in region:
		for edge in range(6):
			if not region.has(coord + grid.DIRECTIONS[edge]):
				edges.append([coord, edge])
	return edges

func show_protection(source: Vector2i, region: Dictionary, strength: int) -> void:
	# Shared area geometry; gold takes precedence on coincident reach edges.
	var node := show_area(region, PROTECTION_COLOR, "ProtectionBacking", "UnitProtection", "ProtectionWash", 0.035)
	node.set_meta("protected", region.keys())
	node.set_meta("source", source)
	node.set_meta("strength", strength)

func show_reachable_area(selected: Vector2i, valid: Dictionary) -> void:
	var region := valid.duplicate()
	region[selected] = true
	var node := show_area(region, Color("8ee1dc"), "ReachBacking", "ReachableArea", "ReachWash")
	node.set_meta("reachable", valid.keys())

func show_area(region: Dictionary, color: Color, backing_name: String, border_name: String, wash_name: String, elevation := 0.0) -> MeshInstance3D:
	var grid = preload("res://src/game/hex_grid.gd")
	var edges := area_edges(region)
	var border: MeshInstance3D
	for layer in range(2):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var width := 0.14 if layer == 0 else 0.09
		for edge in edges:
			var normal: Vector3 = grid.to_world(grid.DIRECTIONS[edge[1]]).normalized()
			var angle := atan2(normal.z, normal.x)
			var a := Vector3(cos(angle - PI / 6), 0, sin(angle - PI / 6))
			var b := Vector3(cos(angle + PI / 6), 0, sin(angle + PI / 6))
			var center: Vector3 = board.coord_position(edge[0])
			Strokes.segment(builder, center + a, center + b, width, 0.060 + layer * 0.03 + elevation, Color.WHITE)
		if not edges.is_empty():
			var node := flat_piece(board.overlay_root, builder.commit(), Vector3.ZERO, Color("253d43") if layer == 0 else color, backing_name if layer == 0 else border_name)
			if layer == 1:
				border = node
				node.set_meta("boundary_edges", edges)
	var wash := SurfaceTool.new()
	wash.begin(Mesh.PRIMITIVE_TRIANGLES)
	for coord in region:
		var center: Vector3 = board.coord_position(coord) + Vector3(0, 0.025 + elevation, 0)
		for edge in range(6):
			for vertex in [Vector3.ZERO, Vector3(sin(edge * TAU / 6), 0, cos(edge * TAU / 6)), Vector3(sin((edge + 1) * TAU / 6), 0, cos((edge + 1) * TAU / 6))]:
				wash.add_vertex(center + vertex)
	var fill := flat_piece(board.overlay_root, wash.commit(), Vector3.ZERO, color, wash_name)
	var mat := board.material(color, true, true).duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.09
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fill.material_override = mat
	return border

func show_route(path: Array, color: Color) -> void:
	# Round the route's corners, then terminate the entire ribbon in one head.
	var centers: Array[Vector3] = []
	for coord in path:
		centers.append(board.coord_position(coord))
	var final_direction := (centers[-1] - centers[-2]).normalized()
	var tip: Vector3 = centers[-1]
	centers[0] += (centers[1] - centers[0]).normalized() * 0.45
	centers[-1] -= final_direction * 0.42
	var points: Array[Vector3] = [centers[0]]
	for index in range(1, centers.size() - 1):
		var corner: Vector3 = centers[index]
		var before := corner + (centers[index - 1] - corner).normalized() * 0.28
		var after := corner + (centers[index + 1] - corner).normalized() * 0.28
		points.append(before)
		for step in range(1, 7):
			var t := step / 6.0
			points.append(before.lerp(corner, t).lerp(corner.lerp(after, t), t))
	points.append(centers[-1])
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in range(points.size()):
		var before: Vector3 = points[maxi(0, index - 1)]
		var after: Vector3 = points[mini(points.size() - 1, index + 1)]
		var direction := (after - before).normalized()
		var side := Vector3(-direction.z, 0, direction.x) * 0.075
		left.append(Vector2(points[index].x + side.x, points[index].z + side.z))
		right.append(Vector2(points[index].x - side.x, points[index].z - side.z))
	var head_side := Vector3(-final_direction.z, 0, final_direction.x) * 0.28
	var polygon := left.duplicate()
	polygon.append(Vector2(centers[-1].x + head_side.x, centers[-1].z + head_side.z))
	polygon.append(Vector2(tip.x, tip.z))
	polygon.append(Vector2(centers[-1].x - head_side.x, centers[-1].z - head_side.z))
	for index in range(right.size() - 1, -1, -1):
		polygon.append(right[index])
	var node := flat_piece(board.overlay_root, Strokes.outlined_polygon(polygon, 0.04, 0.17, color, Color("253d43")), Vector3.ZERO, Color.WHITE, "MovementRoute")
	node.material_override = Strokes.vertex_material()
	node.set_meta("arrowheads", 1)

func show_intent(coord: Vector2i, intent: Dictionary, path: Array) -> void:
	var color: Color = board.intent_color(intent)
	var clear_move: bool = Gameplay.clear_indicators and intent.has("source")
	if not clear_move or not intent["valid"]:
		board.outline(coord, color)
	board.intent_preview = Node3D.new()
	board.intent_preview.name = "IntentPreview"
	board.intent_preview.position = board.coord_position(coord)
	board.intent_preview.set_meta("kind", intent["kind"])
	board.intent_preview.set_meta("valid", intent["valid"])
	board.intent_preview.set_meta("hex", coord)
	board.overlay_root.add_child(board.intent_preview)
	if clear_move and intent["valid"] and intent["kind"] in ["move", "capture", "attack"]:
		return
	var fill := MeshInstance3D.new()
	fill.mesh = board.cylinder_mesh(0.93, 0.93, 0.005, 6)
	fill.position.y = 0.018
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.0 if clear_move and intent["valid"] else 0.28)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fill.material_override = mat
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.intent_preview.add_child(fill)
	if not intent["valid"] or intent["kind"] in ["move", "capture", "attack", "merge", "upgrade", "spell"]:
		var badge: MeshInstance3D = board.cylinder(board.intent_preview, Vector3(0, 0.047, 0.60 if intent["kind"] in ["merge", "upgrade"] and intent["valid"] else 0.0), 0.39, 0.39, 0.01, Color("253d43"), 24)
		if clear_move and intent["valid"]:
			badge.position.y = 0.20
		badge.material_override = board.material(Color("253d43"), true)
		badge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not intent["valid"]:
		for angle in [-PI / 4, PI / 4]:
			var stroke: MeshInstance3D = board.box(board.intent_preview, Vector3(0, 0.06, 0), Vector3(0.10, 0.015, 0.60), color)
			stroke.rotation.y = angle
			stroke.material_override = board.material(color, true)
		return
	match intent["kind"]:
		"spell":
			var symbol := Label3D.new()
			symbol.name = "SpellPreview"
			symbol.text = intent.get("glyph", "✦")
			symbol.font_size = 48
			symbol.pixel_size = 0.016
			symbol.position = Vector3(0, 0.07, 0)
			symbol.rotation.x = -PI / 2
			symbol.modulate = color
			symbol.outline_size = 0
			symbol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			board.intent_preview.add_child(symbol)
		"recruit":
			var ghost := Sprite3D.new()
			ghost.name = "GhostUnit"
			ghost.texture = board.soldier_texture(intent["tier"], intent.get("faction", maxi(0, board.cells[coord]["owner"])))
			ghost.pixel_size = preload("res://src/rendering/unit_sprite_library.gd").pixel_size(intent["tier"])
			ghost.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			ghost.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			ghost.position = Vector3(0, preload("res://src/rendering/unit_sprite_library.gd").height(intent["tier"]), 0)
			ghost.modulate = Color(0.8, 1.0, 0.85, 0.65)
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			board.intent_preview.add_child(ghost)
			for size in [Vector3(0.34, 0.015, 0.075), Vector3(0.075, 0.015, 0.34)]:
				var stroke: MeshInstance3D = board.box(board.intent_preview, Vector3(0, 0.06, 0.58), size, color)
				stroke.material_override = board.material(color, true)
		"tower", "house", "bridge":
			var ghost := Node3D.new()
			ghost.name = "GhostBuilding"
			board.intent_preview.add_child(ghost)
			if intent["kind"] == "tower":
				board.add_tower(ghost, Vector3.ZERO, color)
			elif intent["kind"] == "bridge":
				board.add_bridge(ghost)
			else:
				board.add_house(ghost, Vector3.ZERO)
			for node in ghost.find_children("*", "MeshInstance3D", true, false):
				var ghost_mat: StandardMaterial3D = node.material_override.duplicate()
				ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ghost_mat.albedo_color = Color(ghost_mat.albedo_color.lerp(color, 0.35), 0.60)
				ghost_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				node.material_override = ghost_mat
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"merge", "upgrade":
			for size in [Vector3(0.36, 0.015, 0.08), Vector3(0.08, 0.015, 0.36)]:
				var stroke: MeshInstance3D = board.box(board.intent_preview, Vector3(0, 0.06, 0.60), size, color)
				if clear_move:
					stroke.position.y = 0.235
				stroke.material_override = board.material(color, true)
			if intent["kind"] == "upgrade":
				var indicator := Label3D.new()
				indicator.name = "UpgradeIndicator"
				indicator.text = "↑ " + "I".repeat(intent["tier"])
				indicator.font_size = 36
				indicator.pixel_size = 0.012
				indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				indicator.no_depth_test = true
				indicator.modulate = color
				indicator.outline_modulate = Color("253d43")
				indicator.outline_size = 8
				indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				board.intent_preview.add_child(indicator)
				board.update_upgrade_indicator()
		_:
			var arrow := Node3D.new()
			arrow.position.y = 0.235 if clear_move else 0.07
			board.intent_preview.add_child(arrow)
			if path.size() > 1:
				var direction: Vector3 = board.coord_position(path[-1]) - board.coord_position(path[-2])
				arrow.rotation.y = atan2(-direction.x, -direction.z)
			var node: MeshInstance3D = board.piece(arrow, board.intent_arrow_mesh(), Vector3.ZERO, color)
			node.material_override = board.material(color, true, true)

func update_upgrade_indicator() -> void:
	if not is_instance_valid(board.intent_preview) or not board.intent_preview.has_node("UpgradeIndicator"):
		return
	var coord: Vector2i = board.intent_preview.get_meta("hex")
	if not board.unit_actors.has(coord):
		return
	var indicator: Label3D = board.intent_preview.get_node("UpgradeIndicator")
	# Keep screen clearance when a tall/wide world requires a more distant camera.
	var head: Vector3 = board.unit_actors[coord].global_position + Vector3(0, 0.87, 0)
	var up: Vector3 = board.camera.global_basis.y
	var pixels_per_unit: float = absf(board.camera.unproject_position(head + up).y - board.camera.unproject_position(head).y)
	indicator.global_position = head + up * maxf(1.25, 45.0 / maxf(pixels_per_unit, 0.001))
