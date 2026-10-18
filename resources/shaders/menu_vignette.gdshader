shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float left = 1.0 - smoothstep(0.08, 0.65, UV.x);
	float edge = smoothstep(0.20, 0.62, abs(UV.y - 0.5));
	COLOR = vec4(vec3(0.035, 0.07, 0.085), left * 0.72 + edge * 0.12);
}
