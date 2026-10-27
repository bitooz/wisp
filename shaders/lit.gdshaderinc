// The mock's MeshStandardMaterial, lit the way three.js lights it: the sun and the
// point lights come from Godot, the sky-and-ground hemisphere light from two globals.
global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform vec4 emissive : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emissive_energy = 0.0;
uniform bool flat_shading = true;
uniform float opacity = 1.0;
// Textured models (KayKit) multiply the colour by their texture
uniform bool use_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// Plants bend in the wind: how much, per unit of height squared
uniform float sway = 0.0;
// Ground: soft patches of a second colour, so a lawn isn't one flat green
uniform float patches = 0.0;
uniform vec4 albedo2 : source_color = vec4(1.0);
// Baked: the colour is the vertex colour (sRGB) times albedo, and how much sky gets in is its alpha, so a whole
// house is one mesh and one draw (houses.gd)
uniform bool use_vcol = false;
// Indoors: how much of the sky's light gets in (1 outdoors)
uniform float sky_seen = 1.0;
// Weight: darker toward the bottom, from base_ao_from up base_ao_h metres above the model's origin (its ground),
// as light is near the floor and in corners
uniform float base_ao = 0.0;
uniform float base_ao_from = 0.0;
uniform float base_ao_h = 0.9;

#include "res://shaders/colour.gdshaderinc"
#include "res://shaders/wind.gdshaderinc"

varying vec3 world_pos;

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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (sway > 0.0) {
		float h = max(world_pos.y - MODEL_MATRIX[3].y, 0.0);
		vec3 off = wind_offset(world_pos, h, TIME) * sway;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
	}
}

void fragment() {
	vec3 n = NORMAL;
#ifdef CUTOUT
	n = FRONT_FACING ? n : -n;
	NORMAL = n;
#endif
	if (flat_shading) {
		// Low-poly facets: the face normal, turned toward the camera
		n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		if (dot(n, VERTEX) > 0.0) {
			n = -n;
		}
		NORMAL = n;
	}
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 hemi = mix(hemi_ground, hemi_sky, 0.5 * wn.y + 0.5);
	vec3 base = albedo.rgb;
	if (use_vcol) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		base *= COLOR.rgb;
#else
		base *= to_linear(COLOR.rgb);
#endif
		hemi *= COLOR.a;
	}
	if (patches > 0.0) {
		float k = vnoise(world_pos.xz * 0.9) * 0.65 + vnoise(world_pos.xz * 2.7) * 0.35;
		base = mix(base, albedo2.rgb, smoothstep(0.35, 0.75, k) * patches);
	}
	float tex_a = 1.0;
	if (use_tex) {
		vec4 tx = texture(albedo_tex, UV);
		base *= tx.rgb;
		tex_a = tx.a;
	}
	if (base_ao > 0.0) {
		base *= mix(1.0 - base_ao, 1.0, smoothstep(base_ao_from, base_ao_from + base_ao_h, world_pos.y - MODEL_MATRIX[3].y));
	}
	hemi *= sky_seen;
	ALBEDO = base;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = output_colour(uniform_linear(emissive.rgb) * emissive_energy + uniform_linear(base) * hemi * (1.0 - metallic));
#ifdef SEE_THROUGH
	ALPHA = opacity;
#endif
#ifdef CUTOUT
	// Leaf cards: cut out by the texture's alpha, lit from whichever side faces you
	ALPHA = tex_a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
}
