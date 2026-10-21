// Pixel shading remains in the artwork; this adds bounded environmental light.
#include "authored_color.gdshaderinc"
uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_nearest, repeat_disable;
uniform bool has_normal_map = false;
uniform vec4 normal_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float normal_strength : hint_range(0.0, 1.0) = 0.65;
uniform bool normal_invert_y = false;
uniform vec2 quad_size = vec2(2.56, 1.6);
uniform vec2 pixel_grid = vec2(32.0, 20.0);
uniform bool flip_texture = false;
uniform vec3 shadow_fill = vec3(0.42, 0.49, 0.61);
uniform float sun_gain = 0.42;
uniform float accent_gain = 0.26;
uniform float highlight_softening : hint_range(0.0, 1.0) = 0.65;
void vertex() {
    COLOR.rgb = authored_to_working(COLOR.rgb);
    UV2 = vec2(VERTEX.x / quad_size.x + 0.5, 0.5 - VERTEX.y / quad_size.y);
    vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * scale.x, 0.0), vec4(INV_VIEW_MATRIX[1].xyz * scale.y, 0.0), vec4(INV_VIEW_MATRIX[2].xyz * scale.z, 0.0), MODEL_MATRIX[3]);
}
void fragment() {
    vec2 tex_uv = UV;
    if (flip_texture) { tex_uv.x = 1.0 - tex_uv.x; }
    vec4 pixel = texture(sprite_texture, tex_uv) * COLOR;
    vec3 authored = working_to_authored(pixel.rgb);
    // Roll off pale armour/skin together, preserving hue and pixel detail.
    float peak = max(authored.r, max(authored.g, authored.b));
    float shoulder = 0.55 + 0.45 * (1.0 - exp(-max(peak - 0.55, 0.0) / 0.45));
    authored *= mix(1.0, min(peak, shoulder) / max(peak, 0.0001), highlight_softening);
    pixel.rgb = authored_to_working(authored);
    ALBEDO = pixel.rgb;
    ALPHA = pixel.a;
    #ifndef SPRITE_FADE
    ALPHA_SCISSOR_THRESHOLD = 0.5;
    #endif
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    EMISSION = pixel.rgb * authored_to_working(shadow_fill);
    // Quantize the curved lighting volume to source pixels, never smooth the art.
    vec2 cell = (floor(clamp(UV2, vec2(0.0), vec2(0.9999)) * pixel_grid) + vec2(0.5)) / pixel_grid;
    vec3 rounded = normalize(vec3(0.0, 0.85, 0.0) + INV_VIEW_MATRIX[0].xyz * (cell.x - 0.5) * 0.75 + vec3(0.0, (0.5 - cell.y) * 0.3, 0.0));
    NORMAL = normalize((VIEW_MATRIX * vec4(rounded, 0.0)).xyz);
    if (has_normal_map && normal_strength > 0.0) {
        vec3 mapped = texture(normal_texture, normal_region.xy + tex_uv * normal_region.zw).rgb * 2.0 - 1.0;
        // Live Sprite3D flips its UVs; batch quads use flip_texture instead.
        float mirrored = (dFdx(UV.x) < 0.0) ? -1.0 : 1.0;
        if (flip_texture) { mirrored *= -1.0; }
        mapped.x *= mirrored;
        if (normal_invert_y) { mapped.y *= -1.0; }
        NORMAL = normalize(mix(NORMAL, normalize(mapped), normal_strength));
    }
}
void light() {
    float wrap = clamp((dot(NORMAL, LIGHT) + 0.35) / 1.35, 0.0, 1.0);
    float gain = LIGHT_IS_DIRECTIONAL ? sun_gain : accent_gain;
    DIFFUSE_LIGHT += LIGHT_COLOR / PI * ATTENUATION * wrap * gain;
}
