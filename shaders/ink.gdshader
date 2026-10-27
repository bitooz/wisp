shader_type spatial;
// The little face drawn over Mo's and Bo's (pal.gd): flat dark strokes. Drawn as if a few centimetres nearer
// the camera, along the line of sight (so it stays exactly where it is in the picture), so that brows show
// over the fringe the way they do in a cartoon, and the mouth never sinks into the skin; the back of the head
// still hides it all.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.18, 0.08, 0.06, 1.0);
uniform float pull = 0.01;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz += normalize(-v.xyz) * pull;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = color.rgb;
}
