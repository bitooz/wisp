// Colour handling differs between renderers. In Mobile (and Forward+) colour uniforms
// arrive linear and ALBEDO, EMISSION and the sky's COLOR are linear. In the Compatibility
// renderer (the fallback when Vulkan is missing) colour uniforms arrive sRGB-encoded and
// those outputs are decoded on the way out (measured with tools/calib.gd).
vec3 to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// A colour uniform, as linear
vec3 uniform_linear(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return to_linear(c);
#else
	return c;
#endif
}

// A linear colour, as the renderer wants it written to ALBEDO, EMISSION or a sky's COLOR
vec3 output_colour(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return to_srgb(c);
#else
	return c;
#endif
}
