extends RefCounted
## Shared shader/immutable procedural maps; independent per-surface parameters.
const ShaderSource = preload("res://resources/shaders/water.gdshader")
const OriginalShader = preload("res://resources/shaders/water_original.gdshader")
const NoiseA = preload("res://resources/water/noise_a.tres")
const NoiseB = preload("res://resources/water/noise_b.tres")
const Normal = preload("res://resources/water/normal.tres")

static func material(backdrop := false, stylized := false) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	set_style(result, stylized)
	result.set_shader_parameter("backdrop_depth", backdrop)
	return result

static func set_style(surface: ShaderMaterial, stylized: bool) -> void:
	var shader: Shader = ShaderSource if stylized else OriginalShader
	if surface.shader == shader:
		return
	var backdrop = surface.get_shader_parameter("backdrop_depth") if surface.shader != null else false
	surface.shader = shader
	surface.set_shader_parameter("backdrop_depth", backdrop)
	if stylized:
		surface.set_shader_parameter("noise1", NoiseA)
		surface.set_shader_parameter("noise2", NoiseB)
		surface.set_shader_parameter("normalmap", Normal)
