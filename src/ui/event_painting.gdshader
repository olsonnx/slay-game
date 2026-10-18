shader_type canvas_item;

uniform vec2 rect_size = vec2(424.0, 212.0);
uniform float corner_radius = 8.0;
void fragment() {
	// Fragment COLOR already includes the texture and inherited fade modulation.
	vec4 source = COLOR;
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 sepia = clamp(luminance * vec3(1.16, 1.0, 0.78), 0.0, 1.0);
	float radius = min(corner_radius, min(rect_size.x, rect_size.y) * 0.5);
	vec2 edge = abs((UV - 0.5) * rect_size) - rect_size * 0.5 + radius;
	float distance_to_edge = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - radius;
	float feather = max(fwidth(distance_to_edge), 0.5);
	float coverage = 1.0 - smoothstep(-feather, feather, distance_to_edge);
	COLOR = vec4(sepia, source.a * coverage);
}
