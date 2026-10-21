shader_type spatial;
render_mode unshaded;
#include "authored_color.gdshaderinc"
// Water can sit behind departing tiles until they leave the frame. Menus use
// this continuously; gameplay enables it only during island departure.
uniform bool backdrop_depth = false;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (backdrop_depth) {
		POSITION.z = mix(CLIP_SPACE_FAR, 1.0, 0.00001) * POSITION.w;
	}
}

void fragment() {
	// Original water palette, broad bands and animated glints.
	float broad = sin(world_pos.x * 0.17 + world_pos.z * 0.12) * 0.5 + 0.5;
	float ripple = sin(world_pos.x * 4.0 + sin(world_pos.z * 1.8 + TIME * 0.25))
		* sin(world_pos.z * 3.0 - TIME * 0.18);
	float glint = pow(max(ripple, 0.0), 14.0) * 0.025;
	ALBEDO = authored_to_working(mix(vec3(0.10, 0.20, 0.25), vec3(0.16, 0.29, 0.32), broad) + glint);
}
