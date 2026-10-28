extends Node3D
## Procedural scenery and shared faction-colored unit sprites.

const Catalog = preload("res://src/game/game_catalog.gd")
const SceneryMaterials = preload("res://src/rendering/scenery_materials.gd")
var COLORS: Array = Catalog.TERRAIN_COLORS.duplicate()
const NEUTRAL := Color("a0aa83")
var material_cache: Dictionary = {}
const MATERIAL_CACHE_LIMIT := 1024
var mesh_cache: Dictionary = {}
var icon_cache: Dictionary = {}
# Color-keyed textures survive scene changes and are prepared at application boot.
static var shared_unit_sprites = preload("res://src/rendering/unit_sprite_library.gd").new()
var unit_sprites = shared_unit_sprites
var sprite_cache: Dictionary = {}
var image_cache: Dictionary = {}
static var hover_outline_cache: Dictionary = {}
var outline_cache: Dictionary = hover_outline_cache
var shadow_texture: Texture2D
var sprite_lighting
var lighting_materials: Dictionary = {}
var lighting_registrations := 0
var internal_border_visibility := 0.0
var plastic_tiles := true

func set_plastic_tiles(value: bool) -> bool:
	if plastic_tiles == value: return false
	plastic_tiles = value
	for key in mesh_cache.keys():
		if str(key).begins_with("kingdom_cap:") or str(key).begins_with("tile_base:"):
			mesh_cache.erase(key)
	return true

func set_internal_border_visibility(value: float) -> bool:
	if is_equal_approx(internal_border_visibility, value):
		return false
	internal_border_visibility = value
	# Both live and decorative islands retain one visibility's mesh variants.
	for key in mesh_cache.keys():
		if str(key).begins_with("kingdom_cap:"):
			mesh_cache.erase(key)
	return true

func material(color: Color, unshaded := false, double_sided := false) -> StandardMaterial3D:
	var key := str(color) + str(unshaded) + str(double_sided)
	if material_cache.has(key):
		return material_cache[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.92
	result.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
	if unshaded:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return cache_material(key, result)

func cache_material(key: String, value: StandardMaterial3D) -> StandardMaterial3D:
	# All variants share one budget. Live meshes keep their resource references
	# when an old cache entry is evicted; their appearance is never mutated.
	if not material_cache.has(key):
		while material_cache.size() >= MATERIAL_CACHE_LIMIT:
			material_cache.erase(material_cache.keys()[0])
	material_cache[key] = value
	return value

func tile_material(color: Color, rubber := false) -> StandardMaterial3D:
	if not plastic_tiles: return material(color)
	var key := "tile:%s:%s" % [color, rubber]
	if material_cache.has(key):
		return material_cache[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = 0.0
	result.roughness = 0.78 if rubber else 0.32
	result.metallic_specular = 0.28 if rubber else 0.55
	return cache_material(key, result)

func scenery_material(color: Color, kind: String) -> StandardMaterial3D:
	var key := "scenery:%s:%s" % [kind, color]
	if material_cache.has(key): return material_cache[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	SceneryMaterials.apply(result, kind)
	return cache_material(key, result)

func cylinder_mesh(top: float, bottom: float, height: float, sides := 8) -> CylinderMesh:
	var key := "cylinder:%s:%s:%s:%s" % [top, bottom, height, sides]
	if mesh_cache.has(key):
		return mesh_cache[key]
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	# Straight cylinder/cone sides need no redundant intermediate height ring.
	mesh.rings = 0
	mesh_cache[key] = mesh
	return mesh

func piece(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material(color)
	parent.add_child(node)
	return node

func intent_arrow_mesh() -> ArrayMesh:
	if mesh_cache.has("intent_arrow"):
		return mesh_cache["intent_arrow"]
	var shape := PackedVector2Array([Vector2(-0.08, 0.32), Vector2(0.08, 0.32), Vector2(0.08, -0.04), Vector2(0.26, -0.04), Vector2(0, -0.34), Vector2(-0.26, -0.04), Vector2(-0.08, -0.04)])
	var triangles := Geometry2D.triangulate_polygon(shape)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_normal(Vector3.UP)
	for index in triangles:
		builder.add_vertex(Vector3(shape[index].x, 0, shape[index].y))
	var mesh := builder.commit()
	mesh_cache["intent_arrow"] = mesh
	return mesh

func event_relief_mesh() -> ArrayMesh:
	if mesh_cache.has("event_relief"):
		return mesh_cache["event_relief"]
	var points := PackedVector2Array([
		Vector2(-0.28, -0.30), Vector2(-0.25, -0.46), Vector2(-0.08, -0.55),
		Vector2(0.14, -0.54), Vector2(0.30, -0.41), Vector2(0.32, -0.22),
		Vector2(0.24, -0.09), Vector2(0.04, 0.02), Vector2(0.00, 0.17)])
	var result := ArrayMesh.new()
	# Keep the original geometry, but merge it into two shared material surfaces.
	for layer in [[0.033, 0.044, 0.21, 0.115, Color("74654b")], [0.064, 0.050, 0.15, 0.085, Color("f0d49a")]]:
		var height: float = layer[0]
		var depth: float = layer[1]
		var width: float = layer[2]
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(material(layer[4]))
		for index in range(points.size() - 1):
			var delta := points[index + 1] - points[index]
			var midpoint := (points[index + 1] + points[index]) * 0.5
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(delta.length(), depth, width)
			var transform := Transform3D(Basis(Vector3.UP, -atan2(delta.y, delta.x)), Vector3(midpoint.x, height, midpoint.y))
			builder.append_from(box_mesh, 0, transform)
		for point in points:
			builder.append_from(cylinder_mesh(width / 2, width / 2, depth, 8), 0, Transform3D(Basis.IDENTITY, Vector3(point.x, height, point.y)))
		var radius: float = layer[3]
		builder.append_from(cylinder_mesh(radius, radius, depth, 8), 0, Transform3D(Basis.IDENTITY, Vector3(0, height, 0.42)))
		builder.commit(result)
	mesh_cache["event_relief"] = result
	return result

func box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var key := "box:%s" % size
	var mesh: BoxMesh = mesh_cache.get(key)
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size
		mesh_cache[key] = mesh
	return piece(parent, mesh, at, color)

func cylinder(parent: Node3D, at: Vector3, top: float, bottom: float, height: float, color: Color, sides := 8) -> MeshInstance3D:
	return piece(parent, cylinder_mesh(top, bottom, height, sides), at, color)

func roof_mesh(width: float, depth: float, height: float) -> ArrayMesh:
	var key := "roof:%s:%s:%s" % [width, depth, height]
	if mesh_cache.has(key):
		return mesh_cache[key]
	var a := Vector3(-width / 2, 0, -depth / 2)
	var b := Vector3(width / 2, 0, -depth / 2)
	var c := Vector3(0, height, -depth / 2)
	var d := Vector3(-width / 2, 0, depth / 2)
	var e := Vector3(width / 2, 0, depth / 2)
	var f := Vector3(0, height, depth / 2)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [a, b, c, d, f, e, a, c, f, a, f, d, b, e, f, b, f, c]:
		builder.add_vertex(vertex)
	builder.generate_normals()
	var mesh := builder.commit()
	mesh_cache[key] = mesh
	return mesh

func add_mana_source(tile: Node3D) -> void:
	var source := Node3D.new()
	source.name = "ManaSource"
	source.position = Vector3(0.48, 0, -0.38)
	tile.add_child(source)
	cylinder(source, Vector3(0, 0.04, 0), 0.25, 0.28, 0.08, Color("575778"), 6)
	for index in range(3):
		var at := Vector3((index - 1) * 0.14, 0.16, 0.07 if index != 1 else -0.03)
		var height := 0.46 if index == 1 else 0.30
		var crystal := cylinder(source, at + Vector3(0, height * 0.5, 0), 0, 0.105, height, Color("a5dcf5"), 4)
		crystal.material_override = material(Color("a5dcf5"), true)


func add_tree(parent: Node3D, offset: Vector3) -> void:
	# Shared grouping preserves identical menu/game geometry and lets the
	# value filter hide foliage without removing other province landmarks.
	var tree := Node3D.new()
	tree.name = "Tree"
	parent.add_child(tree)
	shadow(tree, offset, 0.85)
	var trunk := cylinder(tree, offset + Vector3(0, 0.3, 0), 0.075, 0.11, 0.6, Color("72563e"), 6)
	trunk.material_override = scenery_material(Color("72563e"), "bark")
	for index in range(3):
		var radius := 0.48 - index * 0.11
		var color := Color("416447").lightened(index * 0.05)
		var foliage := cylinder(tree, offset + Vector3(0, 0.52 + index * 0.32, 0), 0.02, radius, 0.62, color, 7)
		foliage.material_override = scenery_material(color, "foliage")

func add_mountain(parent: Node3D, coord: Vector2i) -> void:
	var rotation := float(posmod(coord.x * 7 + coord.y * 13, 6)) * PI / 3
	var range_root := Node3D.new()
	range_root.rotation.y = rotation
	parent.add_child(range_root)
	var peak := cylinder(range_root, Vector3(-0.13, 0.82, 0), 0, 0.76, 1.64, Color("777c79"), 5)
	peak.material_override = scenery_material(Color("777c79"), "rock")
	# Sit just above the rock cone instead of burying the cap inside it.
	var snow := cylinder(range_root, Vector3(-0.13, 1.45, 0), 0, 0.20, 0.42, Color("dedfd4"), 5)
	snow.material_override = scenery_material(Color("dedfd4"), "snow")
	var ridge := cylinder(range_root, Vector3(0.41, 0.53, 0.27), 0, 0.43, 1.06, Color("92948a"), 5)
	ridge.material_override = scenery_material(Color("92948a"), "rock")

func add_grave(parent: Node3D, offset: Vector3) -> void:
	shadow(parent, offset, 0.6)
	box(parent, offset + Vector3(0, 0.06, 0), Vector3(0.46, 0.1, 0.30), Color("888c82"))
	box(parent, offset + Vector3(0, 0.26, 0), Vector3(0.29, 0.38, 0.12), Color("c3c5b5"))
	box(parent, offset + Vector3(0, 0.29, 0.065), Vector3(0.034, 0.19, 0.012), Color("6b786c"))
	box(parent, offset + Vector3(0, 0.32, 0.065), Vector3(0.14, 0.034, 0.012), Color("6b786c"))

func add_house(parent: Node3D, offset: Vector3) -> void:
	shadow(parent, offset, 1.2)
	box(parent, offset + Vector3(0, 0.08, 0), Vector3(0.86, 0.13, 0.72), Color("a09a82"))
	box(parent, offset + Vector3(0, 0.37, 0), Vector3(0.68, 0.55, 0.57), Color("e2cfaa"))
	var roof := piece(parent, roof_mesh(0.88, 0.78, 0.34), offset + Vector3(0, 0.64, 0), Color("88584b"))
	roof.material_override = material(Color("88584b"), false, true)
	for x in [-0.29, 0.29]:
		box(parent, offset + Vector3(x, 0.36, 0.29), Vector3(0.05, 0.55, 0.035), Color("795d48"))
	box(parent, offset + Vector3(0.05, 0.26, 0.296), Vector3(0.17, 0.35, 0.035), Color("73503e"))
	register_lighting_material(box(parent, offset + Vector3(-0.17, 0.44, 0.30), Vector3(0.13, 0.15, 0.035), Color("f5d090")).material_override,"window")
	box(parent, offset + Vector3(0.25, 0.88, -0.14), Vector3(0.13, 0.36, 0.14), Color("b3a08a"))
	register_lighting_material(box(parent, offset + Vector3(0.35, 0.44, -0.05), Vector3(0.025, 0.15, 0.14), Color("f5d090")).material_override,"window")

func add_bridge(parent: Node3D) -> MeshInstance3D:
	var surface := cylinder(parent, Vector3(0, -0.04, 0), 0.97, 0.97, 0.075, Color("88613e"), 6)
	for index in range(7):
		var z := (index - 3) * 0.25
		var half_width := minf(0.84, sqrt(3.0) * (0.96 - absf(z)))
		box(parent, Vector3(0, 0.016, z), Vector3(half_width * 2, 0.075, 0.225), Color("b18a59").darkened(float(index % 3) * 0.055))
	for x in [-0.52, 0.52]:
		box(parent, Vector3(x, -0.12, 0), Vector3(0.13, 0.15, 1.34), Color("735035"))
		for z in [-0.52, 0.52]:
			box(parent, Vector3(x, -0.28, z), Vector3(0.15, 0.55, 0.15), Color("624632"))
	return surface

func add_tower(parent: Node3D, offset: Vector3, flag_color: Color) -> void:
	shadow(parent, offset, 1.0)
	box(parent, offset + Vector3(0, 0.07, 0), Vector3(0.66, 0.13, 0.66), Color("999681"))
	box(parent, offset + Vector3(0, 0.54, 0), Vector3(0.46, 0.85, 0.46), Color("d3cbb2"))
	box(parent, offset + Vector3(0, 0.93, 0), Vector3(0.62, 0.12, 0.62), Color("b1ac98"))
	for x in [-0.22, 0.22]:
		for z in [-0.22, 0.22]:
			box(parent, offset + Vector3(x, 1.06, z), Vector3(0.15, 0.21, 0.15), Color("e0d8bd"))
	for height in [0.40, 0.64]:
		box(parent, offset + Vector3(0, height, 0.236), Vector3(0.06, 0.15, 0.014), Color("5b655d"))
		box(parent, offset + Vector3(0.236, height, 0), Vector3(0.014, 0.15, 0.06), Color("5b655d"))
	add_flag(parent, offset + Vector3(0, 1.06, 0), flag_color)

func add_capital(parent: Node3D, offset: Vector3, flag_color: Color) -> void:
	var castle := Node3D.new()
	castle.name = "CapitalCastle"
	castle.position = offset
	castle.scale = Vector3.ONE * (0.78 if offset != Vector3.ZERO else 1.0)
	parent.add_child(castle)
	shadow(castle, Vector3.ZERO, 1.65)
	box(castle, Vector3(0, 0.07, 0), Vector3(1.25, 0.14, 1.10), Color("9e9c8a"))
	box(castle, Vector3(0, 0.52, -0.10), Vector3(0.66, 0.90, 0.61), Color("e5dabd"))
	piece(castle, roof_mesh(0.80, 0.75, 0.36), Vector3(0, 1.10, -0.10), Color("4b6667"))
	for x in [-0.48, 0.48]:
		for z in [-0.38, 0.38]:
			cylinder(castle, Vector3(x, 0.53, z), 0.16, 0.19, 0.98, Color("d2c9b0"), 8)
			cylinder(castle, Vector3(x, 1.10, z), 0, 0.23, 0.32, Color("526b69"), 8)
		box(castle, Vector3(x, 0.27, 0), Vector3(0.12, 0.42, 0.80), Color("c5bea7"))
	box(castle, Vector3(0, 0.24, 0.41), Vector3(0.80, 0.35, 0.12), Color("c5bea7"))
	box(castle, Vector3(0, 0.20, 0.48), Vector3(0.23, 0.30, 0.045), Color("76604c"))
	for x in [-0.20, 0.20]:
		register_lighting_material(box(castle, Vector3(x, 0.72, 0.21), Vector3(0.10, 0.20, 0.025), Color("f9d892")).material_override, "window")
	for x in [-0.43, 0.43]: add_flag(castle, Vector3(x, 0.85, 0.39), flag_color)
	add_flag(castle, Vector3(0, 1.28, -0.10), flag_color)

func add_city(parent: Node3D, offset: Vector3) -> void:
	var town := Node3D.new()
	town.name = "City"
	town.position = offset
	town.scale = Vector3.ONE * (0.76 if offset != Vector3.ZERO else 0.94)
	parent.add_child(town)
	shadow(town, Vector3.ZERO, 1.15)
	# A small town hall and two cottages leave a readable central square.
	for data in [[Vector3(0, 0, -0.20), Vector3(0.48, 0.55, 0.40)], [Vector3(-0.38, 0, 0.25), Vector3(0.32, 0.32, 0.32)], [Vector3(0.38, 0, 0.25), Vector3(0.32, 0.32, 0.32)]]:
		var at: Vector3 = data[0]
		var size: Vector3 = data[1]
		box(town, at + Vector3(0, size.y * 0.5, 0), size, Color("e2cfaa"))
		piece(town, roof_mesh(size.x + 0.10, size.z + 0.10, 0.22), at + Vector3(0, size.y, 0), Color("88584b"))
		register_lighting_material(box(town, at + Vector3(0, size.y * 0.55, size.z * 0.5 + 0.01), Vector3(0.09, 0.12, 0.015), Color("f5d090")).material_override, "window")
	box(town, Vector3(0, 0.70, -0.20), Vector3(0.16, 0.30, 0.16), Color("d2c9b0"))
	piece(town, roof_mesh(0.24, 0.24, 0.16), Vector3(0, 0.86, -0.20), Color("88584b"))

func add_road_preview(parent: Node3D) -> void:
	box(parent, Vector3(0, 0.025, 0), Vector3(1.7, 0.025, 0.30), Color("8d826a"))

func add_treasure(parent: Node3D) -> void:
	var chest := Node3D.new()
	chest.name = "TreasureChest"
	parent.add_child(chest)
	shadow(chest, Vector3.ZERO, 0.95)
	box(chest, Vector3(0, 0.22, 0), Vector3(0.70, 0.40, 0.48), Color("825535"))
	box(chest, Vector3(0, 0.47, 0), Vector3(0.74, 0.13, 0.52), Color("ad7946"))
	for x in [-0.24, 0.24]:
		box(chest, Vector3(x, 0.27, 0.25), Vector3(0.07, 0.43, 0.035), Color("edc66e"))
		box(chest, Vector3(x, 0.54, 0), Vector3(0.07, 0.025, 0.53), Color("edc66e"))
	box(chest, Vector3(0, 0.36, 0.275), Vector3(0.13, 0.14, 0.055), Color("ffda7c"))

func add_flag(parent: Node3D, offset: Vector3, color: Color) -> void:
	cylinder(parent, offset + Vector3(0, 0.20, 0), 0.012, 0.012, 0.4, Color("634f3e"), 4)
	box(parent, offset + Vector3(0.13, 0.31, 0), Vector3(0.25, 0.14, 0.016), color.lightened(0.20))

func make_shadow() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for x in range(32):
		for y in range(32):
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			image.set_pixel(x, y, Color(0.08, 0.12, 0.09, maxf(0, 1.0 - d) * 0.35))
	return ImageTexture.create_from_image(image)

func shadow(parent: Node3D, offset: Vector3, size: float) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = offset + Vector3(0, 0.02, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = shadow_texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	register_lighting_material(mat,"contact")
	parent.add_child(node)

func soldier_texture(tier: int, owner: int) -> Texture2D:
	var key := Vector2i(tier, owner)
	if sprite_cache.has(key):
		return sprite_cache[key]
	var frame: Dictionary = unit_sprites.frame(tier,COLORS[owner])
	var image: Image = frame.image
	var texture: Texture2D = frame.texture
	sprite_cache[key] = texture
	image_cache[key] = image
	return texture

func unit_icon_texture(tier: int, owner: int) -> Texture2D:
	return unit_sprites.portrait(tier,COLORS[owner])

func soldier_hover_outline(tier: int, owner: int, frame_index := 0) -> Texture2D:
	var key := "%d:%s:%d" % [tier, COLORS[owner].to_html(), frame_index]
	if outline_cache.has(key):
		return outline_cache[key]
	soldier_texture(tier, owner)
	var source: Image = unit_sprites.frame(tier,COLORS[owner],"idle",frame_index).image
	var texture := pixel_hover_outline(source)
	outline_cache[key] = texture
	return texture

static func pixel_hover_outline(source: Image) -> Texture2D:
	var outline := Image.create(source.get_width() + 4, source.get_height() + 4, false, Image.FORMAT_RGBA8)
	for x in range(outline.get_width()):
		for y in range(outline.get_height()):
			var sx := x - 2
			var sy := y - 2
			if sx >= 0 and sy >= 0 and sx < source.get_width() and sy < source.get_height() and source.get_pixel(sx, sy).a > 0.1:
				continue
			var edge := false
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					if dx * dx + dy * dy > 4:
						continue
					var nx := sx + dx
					var ny := sy + dy
					if nx >= 0 and ny >= 0 and nx < source.get_width() and ny < source.get_height() and source.get_pixel(nx, ny).a > 0.1:
						edge = true
			if edge:
				outline.set_pixel(x, y, Color("ffe6ab"))
	return ImageTexture.create_from_image(outline)

func building_icon(kind: String) -> Texture2D:
	if icon_cache.has(kind):
		return icon_cache[kind]
	var image := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	var stone := Color("ded4b8")
	var dark := Color("646e65")
	if kind == "bridge":
		image.fill_rect(Rect2i(4, 9, 32, 25), Color("6d4b32"))
		for row in range(5):
			image.fill_rect(Rect2i(6, 10 + row * 5, 28, 4), Color("b78d57"))
		for x in [6, 30]:
			image.fill_rect(Rect2i(x, 7, 4, 29), Color("835f3e"))
	elif kind == "city":
		image.fill_rect(Rect2i(14, 13, 12, 21), stone)
		image.fill_rect(Rect2i(17, 5, 6, 9), Color("b6a98c"))
		for x in [2, 28]:
			image.fill_rect(Rect2i(x, 25, 10, 11), stone)
			for y in range(19, 26):
				var width := (y - 18) * 2
				image.fill_rect(Rect2i(x + 5 - width / 2, y, width, 1), Color("a56e55"))
		image.fill_rect(Rect2i(18, 25, 5, 9), dark)
	elif kind == "road":
		image.fill_rect(Rect2i(3, 17, 34, 7), Color("9a8b71"))
		for x in range(4, 38, 6): image.fill_rect(Rect2i(x, 18, 3, 5), Color("cabfa2"))
	elif kind == "tower":
		image.fill_rect(Rect2i(9, 10, 22, 26), dark)
		image.fill_rect(Rect2i(11, 12, 18, 22), stone)
		image.fill_rect(Rect2i(7, 10, 26, 7), Color("b3b4a1"))
		for x in [7, 17, 27]:
			image.fill_rect(Rect2i(x, 5, 6, 10), stone)
		image.fill_rect(Rect2i(17, 22, 5, 8), dark)
	else:
		image.fill_rect(Rect2i(7, 20, 26, 16), stone)
		for y in range(9, 23):
			var width := (y - 8) * 2
			image.fill_rect(Rect2i(20 - width / 2, y, width, 1), Color("a56e55"))
		image.fill_rect(Rect2i(18, 25, 6, 11), Color("75624a"))
		image.fill_rect(Rect2i(10, 25, 5, 5), Color("f1ce89"))
		image.fill_rect(Rect2i(29, 8, 5, 12), Color("b6a98c"))
	var texture := ImageTexture.create_from_image(image)
	icon_cache[kind] = texture
	return texture

func ring_mesh() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_normal(Vector3.UP)
	for index in range(6):
		var angle_a := deg_to_rad(60.0 * index - 30.0)
		var angle_b := deg_to_rad(60.0 * (index + 1) - 30.0)
		var a := Vector3(cos(angle_a), 0, sin(angle_a)) * 0.98
		var b := Vector3(cos(angle_b), 0, sin(angle_b)) * 0.98
		var c := a * 0.94
		var d := b * 0.94
		for vertex in [a, c, b, b, c, d]:
			builder.add_vertex(vertex)
	return builder.commit()


func register_lighting_material(value: StandardMaterial3D, role: String) -> void:
	value.set_meta("lighting_role",role)
	if not lighting_materials.has(value.get_instance_id()):
		lighting_registrations += 1
		if lighting_registrations%128 == 0:
			for id in lighting_materials.keys():
				if lighting_materials[id].get_ref() == null: lighting_materials.erase(id)
	lighting_materials[value.get_instance_id()] = weakref(value)
	var preferences = Engine.get_main_loop().root.get_node("Video")
	preload("res://src/rendering/lighting_style.gd").apply_material(value,preferences.atmospheric_lighting,shadow_texture)

func refresh_lighting_materials(rich: bool) -> void:
	for id in lighting_materials.keys():
		var value: StandardMaterial3D = lighting_materials[id].get_ref()
		if value == null: lighting_materials.erase(id)
		else: preload("res://src/rendering/lighting_style.gd").apply_material(value,rich,shadow_texture)

func add_event_landmark(parent: Node3D, flag_color: Color, offset: Vector3, source: String) -> void:
	if source not in ["builders_guild", "barracks", "scout_lodge", "watchtower"]:
		add_monument(parent, flag_color, offset)
		return
	var model := Node3D.new()
	model.name = "Landmark"
	model.position = offset
	parent.add_child(model)
	if source == "watchtower":
		add_tower(model, Vector3.ZERO, flag_color)
		cylinder(model, Vector3(0, 1.18, 0), 0.12, 0.16, 0.18, Color("eac97d"), 6)
		return
	add_house(model, Vector3.ZERO)
	match source:
		"builders_guild":
			box(model, Vector3(-0.38, 0.57, 0), Vector3(0.07, 1.0, 0.07), Color("92704b"))
			box(model, Vector3(-0.14, 1.04, 0), Vector3(0.55, 0.07, 0.07), Color("92704b"))
			box(model, Vector3(0.12, 0.70, 0), Vector3(0.04, 0.64, 0.04), Color("c3b28e"))
		"barracks":
			for x in [-0.32, 0.32]:
				cylinder(model, Vector3(x, 0.34, 0.40), 0.025, 0.025, 0.56, Color("66543c"), 5)
				box(model, Vector3(x, 0.43, 0.42), Vector3(0.20, 0.25, 0.045), flag_color)
		"scout_lodge":
			piece(model, roof_mesh(0.91, 0.81, 0.36), Vector3(0, 0.64, 0), Color("526d52"))
			for index in range(3):
				cylinder(model, Vector3(-0.34 + index * 0.14, 0.15, 0.40), 0.065, 0.065, 0.33, Color("96764b"), 6).rotation.z = PI / 2

func add_monument(parent: Node3D, flag_color: Color, offset := Vector3.ZERO) -> void:
	var model := Node3D.new()
	model.name = "Landmark"
	model.position = offset
	parent.add_child(model)
	# One shared placeholder for all encounter and cleared-lair sites.
	shadow(model, Vector3.ZERO, 1.0)
	box(model, Vector3(0,0.08,0), Vector3(0.76,0.14,0.76), Color("999681"))
	box(model, Vector3(0,0.22,0), Vector3(0.54,0.16,0.54), Color("d3cbb2"))
	cylinder(model, Vector3(0,0.62,0),0.16,0.23,0.68,Color("dfd9c6"),6)
	cylinder(model, Vector3(0,1.02,0),0.0,0.26,0.24,Color("b5a276"),6)
	box(model, Vector3(0.22,0.71,0),Vector3(0.24,0.18,0.025),flag_color)
