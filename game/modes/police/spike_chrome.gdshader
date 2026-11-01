shader_type spatial;
// A spike strip's teeth (D249): cartoon chrome. The view reflected off each face picks one of a
// few hard bands (sky, horizon, a dark line, the ground), lit a little on its own so it reads at
// night too, with a hard-edged highlight from the lights and a rim on the edges.
render_mode cull_back;

uniform vec3 tint : source_color = vec3(0.86, 0.9, 1.0);
// How much of the banded reflection shines on its own (seen in the dark).
uniform float glow = 0.35;

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float y = reflect(-v, n).y;
	vec3 band = y > 0.3 ? vec3(1.0) : y > 0.04 ? vec3(0.55, 0.64, 0.8) : y > -0.12 ? vec3(0.08, 0.09, 0.12) : vec3(0.42, 0.4, 0.36);
	float rim = step(0.6, pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0));
	ALBEDO = tint * band * 0.5;
	ROUGHNESS = 0.25;
	SPECULAR = 0.9;
	EMISSION = tint * (band * glow + rim * 0.6);
}

void light() {
	float d = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += step(0.2, d) * LIGHT_COLOR * ATTENUATION * 0.35;
	vec3 h = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += step(0.92, max(dot(NORMAL, h), 0.0)) * LIGHT_COLOR * ATTENUATION * 1.5;
}
