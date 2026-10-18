shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	float top_fade = 1.0 - smoothstep(0.0, 0.20, SCREEN_UV.y);
	float bottom_fade = smoothstep(0.76, 1.0, SCREEN_UV.y);
	float fade = max(top_fade, bottom_fade);
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, 2.2 * fade).rgb;
	vec3 softened = mix(blurred, vec3(0.035, 0.055, 0.065), 0.22);
	COLOR = vec4(softened, fade * 0.8);
}
