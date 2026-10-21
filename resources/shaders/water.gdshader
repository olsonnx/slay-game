shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
#include "authored_color.gdshaderinc"
// Adapted from MinhCreatorVN's Stylized Water for Godot 4.x (MIT), combining
// kmitt91 and StayAtHomeDev's techniques. See water.LICENSE.md.
// Waves perturb shading, retaining the flat board/picking plane.
uniform bool backdrop_depth = false;
uniform vec4 color : source_color = vec4(0.16, 0.31, 0.34, 1.0);
uniform vec4 deep_water : source_color = vec4(0.10, 0.24, 0.29, 1.0);
uniform vec4 edge_color : source_color = vec4(0.68, 0.85, 0.80, 1.0);
uniform float speed : hint_range(0.0, 0.1) = 0.018;
uniform float noise_scale : hint_range(0.01, 1.0) = 0.025;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.22;
uniform float beer_law_factor : hint_range(0.0, 4.0) = 0.7;
uniform float edge_scale : hint_range(0.01, 1.0) = 0.22;
uniform float refraction_strength : hint_range(0.0, 0.05) = 0.006;
uniform float time_override = -1.0;
uniform sampler2D noise1 : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise2 : repeat_enable, filter_linear_mipmap;
uniform sampler2D normalmap : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
varying vec3 world_pos;

vec3 scene_position(vec2 uv, mat4 inverse_projection) {
    float depth = textureLod(depth_texture, uv, 0.0).r;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
    #endif
    vec4 position = inverse_projection * vec4(ndc, 1.0);
    return position.xyz / position.w;
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    if (backdrop_depth) {
        POSITION.z = mix(CLIP_SPACE_FAR, 1.0, 0.00001) * POSITION.w;
    }
}

void fragment() {
    float clock = time_override >= 0.0 ? time_override : TIME;
    vec2 uv = world_pos.xz * noise_scale;
    vec2 flow = vec2(clock * speed, clock * speed * 0.28);
    float n1 = texture(noise1, uv + flow).r;
    float n2 = texture(noise2, uv * 1.37 - flow * 0.7).r;
    float wave = n1 * 0.6 + n2 * 0.4;
    vec2 slope = (texture(normalmap, uv * 1.8 + flow).rg
        + texture(normalmap, uv * 2.3 - flow * 0.65).rg - 1.0) * normal_strength;
    vec3 normal = normalize(vec3(slope.x, 1.0, slope.y));
    vec3 view = normalize(INV_VIEW_MATRIX[2].xyz);
    float fresnel = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 3.0);
    float bands = smoothstep(0.28, 0.72, wave);
    vec3 water_color = mix(deep_water.rgb, color.rgb, bands * 0.35 + 0.25);
    water_color += authored_to_working(vec3(0.025, 0.045, 0.045)) * fresnel;
    float highlight = pow(max(dot(normal, normalize(view + vec3(-0.35, 0.85, 0.4))), 0.0), 96.0);
    water_color += authored_to_working(vec3(0.07, 0.10, 0.09)) * highlight;
    // Broken crests keep the noise legible as water at the board's small scale.
    float crest = pow(max(sin(world_pos.x * 1.2 + world_pos.z * 1.7
        + wave * 7.0 - clock * 0.5), 0.0), 18.0);
    crest *= smoothstep(0.45, 0.65, n2);
    water_color += authored_to_working(vec3(0.045, 0.065, 0.06)) * crest;
    float foam = 0.0;
    if (!backdrop_depth) {
        vec3 scene = scene_position(SCREEN_UV, INV_PROJECTION_MATRIX);
        float gap = max(0.0, VERTEX.z - scene.z);
        float transmission = exp(-gap * beer_law_factor);
        vec2 offset = slope * refraction_strength * (1.0 - transmission * 0.6);
        vec2 refracted_uv = clamp(SCREEN_UV + offset, vec2(0.001), vec2(0.999));
        // Above-water tiles must not bleed into adjacent refracted water.
        vec3 refracted_scene = scene_position(refracted_uv, INV_PROJECTION_MATRIX);
        vec3 refracted_world = (INV_VIEW_MATRIX * vec4(refracted_scene, 1.0)).xyz;
        float safe = step(refracted_world.y, world_pos.y + 0.02);
        vec3 behind = textureLod(screen_texture, refracted_uv, 0.0).rgb;
        water_color = mix(water_color, behind * color.rgb, transmission * safe * 0.34);
        float foam_edge = edge_scale * (0.65 + wave * 0.7);
        foam = 1.0 - smoothstep(foam_edge * 0.25, foam_edge, gap);
        foam *= smoothstep(0.23, 0.5, n1 + n2 * 0.25);
    }
    ALBEDO = mix(water_color, edge_color.rgb, foam * 0.8);
}
