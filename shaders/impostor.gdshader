// A tree far away: its baked picture on a card that turns to face the camera (around the
// vertical), lit by the sun and the sky like the real tree. Also its cheap shadow caster.
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform;

global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
uniform sampler2D picture : source_color, filter_linear_mipmap, repeat_disable;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - origin;
	to_cam.y = 0.0;
	to_cam = length(to_cam) > 1e-4 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 wp = origin + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(to_cam * 0.5 + vec3(0.0, 0.85, 0.0)), 0.0)).xyz);
}

void fragment() {
	vec4 t = texture(picture, UV);
	ALBEDO = t.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	EMISSION = t.rgb * mix(hemi_ground, hemi_sky, 0.8);
}
