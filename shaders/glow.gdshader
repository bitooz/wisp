// The mock's glow sprite: a soft radial gradient, added on top of what's behind.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/colour.gdshaderinc"

uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity = 1.0;
uniform bool billboard = true;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
				vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
				vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	vec4 mid = vec4(1.0, 240.0 / 255.0, 200.0 / 255.0, 0.55);
	vec4 c = r < 0.25 ? mix(vec4(1.0), mid, r / 0.25) : mix(mid, vec4(1.0, 230.0 / 255.0, 170.0 / 255.0, 0.0), clamp((r - 0.25) / 0.75, 0.0, 1.0));
	// The gradient is linear (three.js reads its canvas texture that way)
	ALBEDO = output_colour(c.rgb * uniform_linear(tint.rgb) * COLOR.rgb);
	ALPHA = c.a * opacity * COLOR.a;
}
