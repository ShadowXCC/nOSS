// Painted retro sky (docs/ART_AUDIO.md §2): gradient, sun, a cloud layer and a distant
// mountain strip at the horizon. Also feeds car reflections.
shader_type sky;
render_mode use_debanding;

uniform vec3 top_color : source_color = vec3(0.18, 0.39, 0.71);
uniform vec3 horizon_color : source_color = vec3(0.79, 0.84, 0.89);
uniform vec3 ground_color : source_color = vec3(0.36, 0.42, 0.32);
uniform vec3 cloud_color : source_color = vec3(0.96);
uniform vec3 mountain_color : source_color = vec3(0.5, 0.56, 0.65);
uniform vec3 mountain_far_color : source_color = vec3(0.65, 0.7, 0.77);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform float mountain_height = 0.055;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, h));

	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 0.11 + vec2(TIME * 0.0004, 0.0);
		float n = texture(noise, uv).r * 0.7 + texture(noise, uv * 3.1).r * 0.3;
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.22, n);
		col = mix(col, cloud_color, c * smoothstep(0.0, 0.12, h) * 0.9);
	}

	if (LIGHT0_ENABLED) {
		float s = max(dot(d, LIGHT0_DIRECTION), 0.0);
		col += LIGHT0_COLOR * (pow(s, 900.0) * 6.0 + pow(s, 12.0) * 0.12);
	}

	// Mountains: two silhouettes from the noise, by azimuth (integer repeats wrap cleanly).
	float az = atan(d.x, d.z) / 6.2831853 + 0.5;
	float far_h = mountain_height * (0.35 + 0.9 * texture(noise, vec2(az * 3.0, 0.31)).r);
	float near_h = mountain_height * 0.7 * (0.15 + texture(noise, vec2(az * 9.0, 0.67)).r);
	if (h < far_h) {
		col = mix(mountain_far_color, col, smoothstep(far_h - 0.003, far_h, h));
	}
	if (h < near_h) {
		col = mix(mountain_color, col, smoothstep(near_h - 0.003, near_h, h));
	}
	if (h < 0.0) {
		col = mix(mountain_color, ground_color, smoothstep(0.0, -0.08, h));
	}
	COLOR = col;
}
