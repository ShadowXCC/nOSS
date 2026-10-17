// Painted retro sky (docs/ART_AUDIO.md §2): gradient, sun, a cloud layer and a distant
// mountain strip at the horizon. Also feeds car reflections. Day and night (D153): EnvDirector
// sets the colours for the time and weather, where the sun and moon are, and how much of the
// night (stars, the moon) shows through the clouds.
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
// Toward the sun and the moon; the sun's colour and how much of its disc shows (clouds, horizon).
uniform vec3 sun_dir = vec3(0.0, 0.62, 0.79);
uniform vec3 moon_dir = vec3(0.0, -0.62, -0.79);
uniform vec3 sun_color : source_color = vec3(1.0, 0.945, 0.84);
uniform float sun_disc = 1.0;
// Stars and the moon: how much of the night shows.
uniform float night : hint_range(0.0, 1.0) = 0.0;

float star_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, h));

	float clouds = 0.0;
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 0.11 + vec2(TIME * 0.0004, 0.0);
		float n = texture(noise, uv).r * 0.7 + texture(noise, uv * 3.1).r * 0.3;
		clouds = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.22, n) * smoothstep(0.0, 0.12, h);
	}

	if (night > 0.0 && h > 0.0) {
		// Stars: one in a few hundred cells, twinkling a little, fading toward the horizon.
		vec2 cell = floor(d.xz / (h + 1.0) * 420.0);
		float s = star_hash(cell);
		float star = step(0.9965, s) * (0.5 + 0.5 * sin(TIME * (1.0 + s * 3.0) + s * 40.0));
		col += vec3(0.85, 0.9, 1.0) * star * night * smoothstep(0.02, 0.25, h) * (1.0 - clouds);
		// The moon: a disc and a faint glow.
		float m = max(dot(d, normalize(moon_dir)), 0.0);
		col += vec3(0.8, 0.86, 0.95) * night * (smoothstep(0.99955, 0.9997, m) * 1.4 + pow(m, 48.0) * 0.06) * (1.0 - 0.8 * clouds);
	}

	col = mix(col, cloud_color, clouds * 0.9);

	float s = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_color * sun_disc * (pow(s, 900.0) * 6.0 + pow(s, 12.0) * 0.12);

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
