shader_type spatial;
// Item boxes (D139): a see-through crate whose colour drifts slowly round the hues (one turn in
// 5 s, never a flash, ACC-04), with a bright frame and an original glyph on each face: a ring
// round a four-pointed star.
render_mode blend_mix, cull_back;

uniform float hue_speed = 0.2;

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	// A BoxMesh lays its faces out 3 by 2 in UV: fold each to -1..1.
	vec2 p = fract(UV * vec2(3.0, 2.0)) * 2.0 - 1.0;
	float edge = step(0.82, max(abs(p.x), abs(p.y)));
	float r = length(p);
	float ring = smoothstep(0.08, 0.0, abs(r - 0.55));
	float star = step(abs(p.x) * abs(p.y) * 6.0 + r * 0.6, 0.35);
	float glyph = max(ring, star);
	vec3 base = hue(TIME * hue_speed + 0.15 * (p.x + p.y));
	ALBEDO = mix(base * 0.55, vec3(1.0), max(edge, glyph));
	EMISSION = base * 0.35 + vec3(1.0) * glyph * 0.4;
	ALPHA = mix(0.6, 1.0, max(edge, glyph));
	ROUGHNESS = 0.3;
}
