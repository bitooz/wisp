// The wind: a slow gust rolling across the island and a quicker flutter, bending
// things more the higher they reach above where they stand.
vec3 wind_offset(vec3 wp, float h, float t) {
	float gust = 0.55 + 0.45 * sin(t * 0.6 - (wp.x + wp.z) * 0.3);
	float w = sin(t * 1.9 + wp.x * 0.7 + wp.z * 0.5) * 0.6 + sin(t * 3.3 + wp.z * 1.1 - wp.x * 0.4) * 0.25;
	return vec3(0.85, 0.0, 0.5) * (w + 0.5) * gust * h * h;
}
