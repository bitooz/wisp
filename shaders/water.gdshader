// The pond: deeper blue in the middle, rings drifting out, the sun glinting on the
// ripples, and a lapping line of foam at the shore.
shader_type spatial;
render_mode cull_back;

global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
uniform vec4 deep : source_color = vec4(0.26, 0.58, 0.79, 1.0);
uniform vec4 shallow : source_color = vec4(0.56, 0.83, 0.93, 1.0);
uniform vec4 foam : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float radius = 1.15;

#include "res://shaders/colour.gdshaderinc"

varying vec2 lp;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	lp = VERTEX.xy / radius;
}

void fragment() {
	float r = length(lp);
	float t = TIME;
	vec3 c = mix(uniform_linear(deep.rgb), uniform_linear(shallow.rgb), smoothstep(0.15, 0.95, r));
	// Ripples: a few drifting wave trains make the surface normal wobble
	vec2 g = vec2(0.0);
	g += vec2(cos(lp.x * 9.0 + t * 1.4), 0.0) * 0.5;
	g += vec2(0.0, cos(lp.y * 11.0 - t * 1.1)) * 0.5;
	g += normalize(lp + 1e-4) * cos(r * 24.0 - t * 2.0) * 0.6;
	g += (vec2(vnoise(lp * 5.0 + t * 0.3), vnoise(lp * 5.0 - t * 0.27)) - 0.5) * 1.2;
	vec3 wn = normalize(vec3(-g.x * 0.08, 1.0, -g.y * 0.08));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn.x, wn.y, wn.z, 0.0)).xyz);
	// Shore: lapping foam just inside the rim
	float a = atan(lp.y, lp.x);
	float edge = r + 0.035 * sin(a * 7.0 + t * 1.3) + 0.03 * sin(a * 13.0 - t * 0.9);
	float f = smoothstep(0.84, 0.97, edge) * (0.65 + 0.35 * vnoise(lp * 9.0 + t * 0.5));
	c = mix(c, uniform_linear(foam.rgb), f);
	ALBEDO = output_colour(c);
	ROUGHNESS = mix(0.12, 0.8, f);
	SPECULAR = 0.6;
	EMISSION = output_colour(c * mix(hemi_ground, hemi_sky, 0.5 * wn.y + 0.5));
}
