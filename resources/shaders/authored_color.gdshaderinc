// Authored palette values use display/sRGB space; Forward+ shades in linear HDR.
vec3 authored_to_working(vec3 value) {
    if (OUTPUT_IS_SRGB) { return value; }
    return mix(pow((max(value, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), value / 12.92, lessThan(value, vec3(0.04045)));
}
vec3 working_to_authored(vec3 value) {
    if (OUTPUT_IS_SRGB) { return value; }
    return mix(1.055 * pow(max(value, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, value * 12.92, lessThan(value, vec3(0.0031308)));
}
