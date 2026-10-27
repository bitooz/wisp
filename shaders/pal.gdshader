shader_type spatial;
render_mode cull_back;

// Mo, Bo, the island's other people and the kid: lit like lit.gdshader (smooth, matte), their colour from the model's own texture.
// The emissive glow (in the dark) lights the whole figure faintly. The kid's lantern glass shines (where
// the vertex colour's red marks it, times glow; Mo and Bo have no vertex colours and glow 0).
global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float roughness = 0.85;
uniform vec4 emissive : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emissive_energy = 0.0;
uniform float glow = 0.0;
// Someone else in Mo's or Bo's clothes (folk.gd): their clothes and hair turn (hue, radians), lose colour
// (desat) and go lighter or darker (tone); their skin stays skin (skin_mask: where the face, neck, forearms and
// hands are on the texture, tools/skin_mask.gd; there, only hair and clothes, by colour, change)
uniform float hue = 0.0;
uniform float desat = 0.0;
uniform float tone = 1.0;
uniform sampler2D skin_mask : hint_default_black, filter_linear;
// Skin is no more coloured than this (Mo's is pale, Bo's tanned): anything stronger there is clothes
uniform float skin_sat = 0.66;

vec3 recolour(vec3 c, vec2 uv) {
	if (hue == 0.0 && desat == 0.0 && tone == 1.0) {
		return c;
	}
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	vec3 hsv = vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
	float skin = texture(skin_mask, uv).r * smoothstep(0.26, 0.4, hsv.z) * (1.0 - smoothstep(skin_sat, skin_sat + 0.08, hsv.y));
	float k = smoothstep(0.18, 0.3, hsv.y) * smoothstep(0.02, 0.08, hsv.z) * (1.0 - skin);
	hsv.x = fract(hsv.x + hue * k / 6.2831853);
	hsv.y *= 1.0 - desat * k;
	hsv.z = clamp(hsv.z * mix(1.0, tone, k), 0.0, 1.0);
	vec3 rgb = clamp(abs(mod(hsv.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return hsv.z * mix(vec3(1.0), rgb, hsv.y);
}

#include "res://shaders/colour.gdshaderinc"

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 hemi = mix(hemi_ground, hemi_sky, 0.5 * wn.y + 0.5);
	vec3 base = recolour(texture(albedo_tex, UV).rgb, UV);
	ALBEDO = base;
	ROUGHNESS = roughness;
	EMISSION = output_colour(uniform_linear(emissive.rgb) * emissive_energy * 0.5 + uniform_linear(base) * hemi)
		+ base * COLOR.r * glow * 2.0;
}
