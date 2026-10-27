// The whole screen behind the HUD in one pass: the mock's CSS backdrop (day, dusk, night, the
// dungeon's dark) with the world's see-through picture laid over it (premultiplied).
shader_type canvas_item;

uniform float dusk = 0.0;
uniform float cave = 0.0;
uniform float night = 0.0;

vec3 hex(int c) {
	return vec3(float((c >> 16) & 255), float((c >> 8) & 255), float(c & 255)) / 255.0;
}

vec3 grad3(vec3 a, vec3 b, vec3 c, float y) {
	return y < 0.5 ? mix(a, b, y * 2.0) : mix(b, c, (y - 0.5) * 2.0);
}

void fragment() {
	vec3 day = grad3(hex(0x9FD2FF), hex(0xD4ECFF), hex(0xFFF0DC), UV.y);
	vec3 eve = grad3(hex(0x232659), hex(0x5B4B8A), hex(0xE99A7C), UV.y);
	vec2 d = (UV - vec2(0.5, 0.2)) / vec2(1.2, 1.0);
	vec3 dark = mix(hex(0x15141D), hex(0x09090E), clamp(length(d) / 0.7, 0.0, 1.0));
	vec3 nite = grad3(hex(0x050816), hex(0x0B1230), hex(0x1A2142), UV.y);
	vec3 sky = mix(mix(mix(day, eve, dusk), nite, night), dark, cave);
	vec4 world = texture(TEXTURE, UV);
	COLOR = vec4(world.rgb + sky * (1.0 - world.a), 1.0);
}
