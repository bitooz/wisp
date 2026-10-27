// The purple closing-in when the shadow is out.
shader_type canvas_item;

uniform float amount = 0.0;

void fragment() {
	vec2 d = (UV - 0.5) / vec2(0.7, 0.8);
	float k = clamp((length(d) - 0.4) / 0.6, 0.0, 1.0);
	COLOR = vec4(36.0 / 255.0, 8.0 / 255.0, 58.0 / 255.0, 0.62 * k * amount);
}
