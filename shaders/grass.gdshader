// Instanced-by-hand grass: thousands of blades in one mesh, bending in the wind,
// lit like the lawn they grow from (sun from Godot, sky and ground as in lit.gdshaderinc).
shader_type spatial;
render_mode cull_disabled, shadows_disabled;

global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
uniform vec4 base_colour : source_color = vec4(0.33, 0.55, 0.27, 1.0);
uniform vec4 tip_colour : source_color = vec4(0.62, 0.81, 0.47, 1.0);
uniform float bend = 0.9;

#include "res://shaders/colour.gdshaderinc"
#include "res://shaders/wind.gdshaderinc"

varying float tip;

void vertex() {
	tip = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += wind_offset(wp, tip, TIME) * 0.1 * bend;
	// Lit like the ground, not like little cards: every blade faces up
	NORMAL = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	vec3 c = mix(uniform_linear(base_colour.rgb), uniform_linear(tip_colour.rgb), tip) * COLOR.rgb;
	ALBEDO = output_colour(c);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	EMISSION = output_colour(c * hemi_sky * mix(0.75, 1.0, tip));
}
