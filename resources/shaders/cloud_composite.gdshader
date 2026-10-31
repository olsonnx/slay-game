shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
uniform sampler2D cloud_texture : filter_linear, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform float visibility = 0.0;
uniform bool water_background = true;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float land_at(vec2 uv, mat4 inverse_projection, mat4 inverse_view) {
	// Match the sampled depth pixel's ray. Unsnapped offset rays can falsely
	// reconstruct a flat ocean above its surface in an orthographic overview.
	vec2 depth_size = vec2(textureSize(scene_depth, 0));
	uv = (floor(clamp(uv, vec2(0.0), vec2(0.999999)) * depth_size) + 0.5) / depth_size;
	float depth = texture(scene_depth, clamp(uv, vec2(0.0), vec2(1.0))).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		if (depth < 0.00001) { return 0.0; }
		vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
	#else
		if (depth < 0.00001) { return 0.0; }
		vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	#endif
	vec4 world = inverse_view * inverse_projection * vec4(ndc, 1.0);
	return water_background ? step(-0.455, world.y / world.w) : 1.0;
}

void fragment() {
	vec4 cloud = texture(cloud_texture, SCREEN_UV);
	if (visibility < 0.001 || cloud.a < 0.002 || land_at(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX) > 0.5) { discard; }
	ALBEDO = cloud.rgb;
	ALPHA = cloud.a * visibility;
}
