extends RefCounted
## Shared screen blur follows the ColorRect's animated dimming alpha.
static func create_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
void fragment() {
	vec4 tint = COLOR;
	vec3 background = textureLod(screen_texture, SCREEN_UV, 2.5 * clamp(tint.a / 0.78, 0.0, 1.0)).rgb;
	COLOR = vec4(mix(background, tint.rgb, tint.a), 1.0);
}
"""
	var result := ShaderMaterial.new()
	result.shader = shader
	return result
