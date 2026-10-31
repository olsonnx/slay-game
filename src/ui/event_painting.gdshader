shader_type canvas_item;

uniform vec2 rect_size = vec2(424.0, 212.0);
uniform float corner_radius = 8.0;
uniform vec2 crop_focus = vec2(0.5);
varying vec4 vertex_tint;
void vertex() {
	vertex_tint = COLOR;
}
void fragment() {
	// Cover the fixed event frame without stretching or altering the source file.
	float source_aspect = TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x;
	float frame_aspect = rect_size.x / rect_size.y;
	vec2 crop_size = vec2(min(1.0,frame_aspect/source_aspect),min(1.0,source_aspect/frame_aspect));
	vec2 crop_origin = clamp(crop_focus-crop_size*0.5,vec2(0.0),vec2(1.0)-crop_size);
	vec4 source = texture(TEXTURE,crop_origin+UV*crop_size) * vertex_tint;
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 sepia = clamp(luminance * vec3(1.16, 1.0, 0.78), 0.0, 1.0);
	float radius = min(corner_radius, min(rect_size.x, rect_size.y) * 0.5);
	vec2 edge = abs((UV - 0.5) * rect_size) - rect_size * 0.5 + radius;
	float distance_to_edge = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - radius;
	float feather = max(fwidth(distance_to_edge), 0.5);
	float coverage = 1.0 - smoothstep(-feather, feather, distance_to_edge);
	COLOR = vec4(sepia, source.a * coverage);
}
