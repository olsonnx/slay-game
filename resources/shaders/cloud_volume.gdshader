// Adapted from thepathgame's CC0 Volumetric Raymarched (animated) Clouds v2.
// Orthographic rays, bounded sampling and lighting adapted for Slay & Reign.
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler3D cloud_noise_texture : repeat_enable, filter_linear;
uniform sampler3D detail_noise_texture : repeat_enable, filter_linear;
uniform vec3 ray_origin;
uniform vec3 ray_right;
uniform vec3 ray_up;
uniform vec3 ray_direction;
uniform vec2 view_span;
uniform float cloud_time = 0.0;
uniform vec2 clearing_center;
uniform vec2 ground_origin;
uniform vec2 ground_right;
uniform vec2 ground_down;
uniform vec3 clearing_planes[12];
uniform float clearing_feather = 12.0;

float sample_cloud(vec3 position, float openness) {
	// Less than half a tile per second: perceptible drift without distracting motion.
	vec3 drift = vec3(cloud_time * 0.45, 0.0, cloud_time * 0.18);
	float main_cloud = texture(cloud_noise_texture, (position + drift) * 0.018).r;
	float detail = texture(detail_noise_texture, (position - drift * 0.4) * 0.07).r;
	float height = (position.y - 7.0) / 11.0;
	float profile = smoothstep(0.0, 0.22, height) * (1.0 - smoothstep(0.65, 1.0, height));
	// Thin the actual volume toward the clearing, including its lighting samples.
	// The edge inherits the same billows as the rest of the clouds.
	return max(0.0, mix(main_cloud, detail, 0.18) - mix(1.0, 0.51, openness)) * 6.0 * profile;
}

void fragment() {
	vec2 ground = ground_origin + ground_right * UV.x + ground_down * UV.y;
	float shore_distance = -100000.0;
	for (int i = 0; i < 12; i++) {
		shore_distance = max(shore_distance, dot(ground - clearing_center, clearing_planes[i].xy) - clearing_planes[i].z);
	}
	float openness = smoothstep(0.0, clearing_feather, shore_distance);
	vec3 origin = ray_origin + ray_right * (UV.x - 0.5) * view_span.x + ray_up * (0.5 - UV.y) * view_span.y;
	// Start behind the orthographic view so a wide frame never clips the cloud slab.
	origin -= ray_direction * max(50.0, view_span.y);
	float near_t = (18.0 - origin.y) / ray_direction.y;
	float far_t = (7.0 - origin.y) / ray_direction.y;
	near_t = max(0.0, near_t);
	vec3 color = vec3(0.0);
	float opacity = 0.0;
	if (far_t > near_t && openness > 0.001) {
		float stride = (far_t - near_t) / 24.0;
		for (int i = 0; i < 24; i++) {
			vec3 position = origin + ray_direction * (near_t + (float(i) + 0.5) * stride);
			float density = sample_cloud(position, openness);
			float shade = sample_cloud(position + vec3(-1.5, 2.0, 1.0), openness);
			float alpha = 1.0 - exp(-density * stride * 0.33);
			vec3 lighting = mix(vec3(0.40, 0.53, 0.55), vec3(0.91, 0.91, 0.84), exp(-shade * 2.5));
			color += (1.0 - opacity) * alpha * lighting;
			opacity += (1.0 - opacity) * alpha;
			if (opacity > 0.97) { break; }
		}
	}
	COLOR = vec4(color / max(opacity, 0.001), opacity * 0.72);
}
