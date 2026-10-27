// The corner view in one pass: a rounded window with a little sky (or the dark) behind
// what the character's eye sees.
shader_type canvas_item;

uniform vec4 top : source_color = vec4(0.659, 0.839, 1.0, 1.0);
uniform vec4 bottom : source_color = vec4(0.918, 0.961, 1.0, 1.0);
uniform vec2 size = vec2(176.0, 112.0);
uniform float radius = 18.0;

void fragment() {
	vec2 p = UV * size;
	vec2 q = abs(p - size * 0.5) - (size * 0.5 - radius);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float a = clamp(0.5 - d / max(fwidth(d), 1e-4), 0.0, 1.0);
	vec4 world = texture(TEXTURE, UV);
	vec3 bg = mix(top.rgb, bottom.rgb, UV.y);
	COLOR = vec4(world.rgb + bg * (1.0 - world.a), a);
}
