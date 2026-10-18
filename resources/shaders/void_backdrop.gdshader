shader_type canvas_item;
render_mode unshaded;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float soft_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 blend = fract(p);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), blend.x), blend.y);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = (UV - vec2(0.5, 0.43)) * vec2(aspect, 1.0);
	float halo = exp(-dot(p * vec2(1.1, 1.6), p * vec2(1.1, 1.6)) * 2.5);
	vec3 backdrop = mix(vec3(0.065, 0.095, 0.12), vec3(0.19, 0.265, 0.275), halo);
	float mist = soft_noise(UV * vec2(4.0 * aspect, 4.0) + vec2(TIME * 0.002, 0.0));
	mist = mist * 0.7 + soft_noise(UV * vec2(9.0 * aspect, 9.0)) * 0.3;
	backdrop += (mist - 0.5) * vec3(0.018, 0.028, 0.025) * halo;
	// A subdued stone-colored glow ties the void to the warm tile edges.
	vec2 glow_pos = p - vec2(-0.3, -0.12);
	float glow = exp(-dot(glow_pos, glow_pos) * 7.0);
	backdrop += vec3(0.028, 0.023, 0.009) * glow;
	// Sparse, soft motes suggest depth without becoming a starfield.
	vec2 grid = UV * vec2(28.0 * aspect, 28.0);
	vec2 cell = floor(grid);
	vec2 center = vec2(hash(cell + vec2(13.0, 7.0)), hash(cell + vec2(3.0, 19.0))) * 0.6 + 0.2;
	vec2 mote_pos = (fract(grid) - center) / (SCREEN_PIXEL_SIZE * vec2(28.0 * aspect, 28.0));
	float mote = exp(-dot(mote_pos, mote_pos) / 2.0) * step(0.985, hash(cell));
	backdrop += vec3(0.09, 0.11, 0.095) * mote;
	COLOR = vec4(backdrop, 1.0);
}
