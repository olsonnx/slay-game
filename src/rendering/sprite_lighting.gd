extends Node
## Materials are shared across frames; army lighting never rewrites instance buffers.
const Solid = preload("res://resources/shaders/sprite_lighting.gdshader")
const Fading = preload("res://resources/shaders/sprite_lighting_fade.gdshader")
const CACHE_LIMIT := 512
var normal_strength := 0.65
var normal_invert_y := false
var enabled := false
var sprites: Dictionary = {}
var materials: Dictionary = {}

func set_enabled(value: bool) -> void:
	if enabled == value: return
	enabled = value
	for id in sprites.keys():
		var sprite: Sprite3D = sprites[id].get_ref()
		if sprite == null: sprites.erase(id)
		else: sync(sprite)

func sync(sprite: Sprite3D) -> void:
	if not sprites.has(sprite.get_instance_id()):
		if sprites.size()%128 == 0:
			for id in sprites.keys():
				if sprites[id].get_ref() == null: sprites.erase(id)
		sprites[sprite.get_instance_id()] = weakref(sprite)
	if not enabled:
		sprite.material_override = null
		return
	var texture := sprite.texture
	if texture == null: return
	var fading: bool = sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	var size := Vector2(texture.get_width()/float(sprite.hframes), texture.get_height()/float(sprite.vframes))
	var source: Texture2D = texture.atlas if texture is AtlasTexture else texture
	var key := [source.get_rid(),size,sprite.pixel_size,fading]
	if not materials.has(key):
		if materials.size() >= CACHE_LIMIT: materials.erase(materials.keys()[0])
		materials[key] = make_material(source,size,sprite.pixel_size,false,fading)
	materials[key].set_shader_parameter("normal_strength", normal_strength)
	materials[key].set_shader_parameter("normal_invert_y", normal_invert_y)
	if sprite.material_override != materials[key]: sprite.material_override = materials[key]

static func make_material(texture: Texture2D, pixels: Vector2, pixel_size: float, flipped := false, fading := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Fading if fading else Solid
	bind_texture(material, texture)
	material.set_shader_parameter("quad_size",pixels*pixel_size)
	material.set_shader_parameter("pixel_grid",pixels)
	material.set_shader_parameter("flip_texture",flipped)
	return material

static func bind_texture(material: ShaderMaterial, texture: Texture2D) -> void:
	material.set_shader_parameter("sprite_texture", texture)
	var has_normal := texture.has_meta("normal_texture") and texture.has_meta("normal_region")
	material.set_shader_parameter("has_normal_map", has_normal)
	if has_normal:
		var region: Rect2 = texture.get_meta("normal_region")
		material.set_shader_parameter("normal_texture", texture.get_meta("normal_texture"))
		material.set_shader_parameter("normal_region", Vector4(region.position.x, region.position.y, region.size.x, region.size.y))

func set_normal_options(strength: float, invert_y: bool) -> void:
	normal_strength = clampf(strength, 0.0, 1.0)
	normal_invert_y = invert_y
	for material in materials.values():
		material.set_shader_parameter("normal_strength", normal_strength)
		material.set_shader_parameter("normal_invert_y", normal_invert_y)
	var board = get_parent()
	if board.unit_batches != null:
		for material in board.unit_batches.lit_sprite_materials.values():
			material.set_shader_parameter("normal_strength", normal_strength)
			material.set_shader_parameter("normal_invert_y", normal_invert_y)

