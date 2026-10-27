// The sea round the island: shallow and green-blue near the beach, deep further out,
// waves glinting in the sun, and foam where it laps the shore. The shoreline is the
// same curve the island's height is built from (scripts/island.gd, shore_radius).
shader_type spatial;
render_mode cull_back;

global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
uniform vec4 deep : source_color = vec4(0.18, 0.47, 0.70, 1.0);
uniform vec4 shallow : source_color = vec4(0.42, 0.80, 0.84, 1.0);
uniform vec4 foam : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform float shore = 58.0;

varying vec3 wp;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float shore_radius(float a) {
	return shore * (1.0 + 0.07 * sin(3.0 * a + 0.5) + 0.05 * sin(5.0 * a + 2.0) + 0.03 * sin(9.0 * a));
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	float k = length(wp.xz) / shore_radius(atan(wp.z, wp.x));
	vec3 c = mix(shallow.rgb, deep.rgb, smoothstep(1.0, 1.35, k));
	vec2 g = vec2(cos(wp.x * 0.45 + t * 1.1) + cos(wp.x * 0.9 - wp.z * 0.3 + t * 1.7) * 0.5,
			cos(wp.z * 0.5 - t * 0.9) + cos(wp.z * 1.1 + wp.x * 0.4 - t * 1.4) * 0.5);
	g += (vec2(vnoise(wp.xz * 0.6 + t * 0.4), vnoise(wp.xz * 0.6 - t * 0.35)) - 0.5) * 1.5;
	vec3 wn = normalize(vec3(-g.x * 0.07, 1.0, -g.y * 0.07));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	// Foam: a lapping band at the waterline, breaking up as it goes out
	float lap = 0.02 * sin(t * 1.3 + atan(wp.z, wp.x) * 23.0) + 0.012 * sin(t * 0.7);
	float band = 1.0 - smoothstep(0.0, 0.045, abs(k - 1.03 - lap));
	float f = band * (0.55 + 0.45 * vnoise(wp.xz * 1.8 + t * 0.6));
	c = mix(c, foam.rgb, clamp(f, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = mix(0.08, 0.8, f);
	SPECULAR = 0.6;
	EMISSION = c * mix(hemi_ground, hemi_sky, 0.5 * wn.y + 0.5);
}
