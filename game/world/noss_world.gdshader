// Shared world material (docs/ARCHITECTURE.md §7). Tracks never hard-code their look: the
// style profile drives the global style_* uniforms, and the sky (EnvDirector, D153) the env_*
// ones: wet surfaces darken (roads shine), snow settles on what faces up (dusting the roads),
// lamps light at night, and old lamps flicker unless a player has Reduce flashing (D221).
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

global uniform vec4 style_tint;
global uniform float style_mip_bias;
global uniform float style_saturation;
global uniform float env_wetness;
global uniform float env_snow;
global uniform float env_night;
global uniform float env_flicker;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform bool world_uv = false; // planar XZ mapping for terrain
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float specular : hint_range(0.0, 1.0) = 0.2;
uniform bool alpha_scissor = false;
// Lamps, tunnel lights: glow at this colour (black: none); lamps only at night.
uniform vec3 emission : source_color = vec3(0.0);
uniform bool night_glow = false;
// An old lamp: its glow dips now and then (flicker_at), each lamp in its own time.
uniform bool flicker = false;
// Roads and paved ground shine when wet (1); how much snow settles on it (lamps, signs: 0).
uniform float wet_shine = 0.0;
uniform float snow_settle = 1.0;
// Paved: snow lies as a dusting, specks over drifting patches (snow_noise: red the specks, green
// the patches), rather than a sheet.
uniform float snow_dust = 0.0;
uniform sampler2D snow_noise : repeat_enable, filter_linear_mipmap, hint_default_white;
// 0 under cover (highway tunnels): no rain or snow reaches it.
uniform float weathered = 1.0;
// Low-frequency colour variation in world space, to break up tiling.
uniform float variation = 0.0;
uniform sampler2D variation_noise : repeat_enable, filter_linear_mipmap, hint_default_white;

varying vec3 world_pos;
varying flat float glow;

float hash3(float a, float b, float k) {
	return fract(sin(a * 12.9898 + b * 78.233 + k * 37.719) * 43758.5453);
}

// A flickering lamp's glow at t (WorldMaterials.flicker is its twin): at most one dip a second,
// 60-140 ms long, down to between 0.5 and 0.8.
float flicker_at(float t, float seed) {
	float sec = floor(t);
	if (hash3(sec, seed, 0.0) > 0.4) {
		return 1.0;
	}
	float len = mix(0.06, 0.14, hash3(sec, seed, 1.0));
	float start = hash3(sec, seed, 2.0) * (1.0 - len);
	float x = t - sec;
	return (x < start || x > start + len) ? 1.0 : mix(0.5, 0.8, hash3(sec, seed, 3.0));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	glow = 1.0;
	if (flicker && env_flicker > 0.0) {
		// Each lamp its own time: where it stands (within the floating origin's 1500 m steps, so
		// a shift keeps it) and, merged into one mesh, its own colour alpha.
		vec2 cell = mod(round(MODEL_MATRIX[3].xz), 1500.0) * 0.01;
		float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453) * 100.0 + COLOR.a * 255.0;
		glow = mix(1.0, flicker_at(TIME, seed), env_flicker);
	}
}

void fragment() {
	vec2 uv = world_uv ? world_pos.xz * uv_scale : UV * uv_scale;
	vec4 t = texture(albedo_texture, uv, style_mip_bias);
	vec3 c = t.rgb * albedo.rgb * COLOR.rgb * style_tint.rgb;
	if (variation > 0.0) {
		float v = texture(variation_noise, world_pos.xz * 0.004).r;
		c *= mix(1.0 - variation, 1.0 + variation, v);
	}
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(grey), c, style_saturation);
	float snow = env_snow * weathered;
	float wet = env_wetness * (1.0 - env_snow) * weathered;
	float dusted = 0.0;
	if (wet > 0.0 || snow > 0.0) {
		float up = smoothstep(0.55, 0.85, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
		c *= 1.0 - (0.18 + 0.2 * wet_shine) * wet;
		float cover = snow * snow_settle * up;
		if (snow_dust > 0.0) {
			// Specks a few centimetres across over patches drawn out by the wind; the more falls,
			// the more the gaps fill. A thin frost over it all, the road damp between.
			float specks = texture(snow_noise, world_pos.xz * 0.6).r;
			float patches = texture(snow_noise, world_pos.xz * vec2(0.05, 0.022) + vec2(0.31, 0.67)).g;
			float n = specks * 0.55 + patches * 0.45;
			float lying = smoothstep(1.0 - 0.6 * cover, 1.16 - 0.6 * cover, n);
			dusted = cover * (0.12 + 0.75 * lying) * snow_dust;
			c *= 1.0 - 0.12 * cover * snow_dust;
			c = mix(c, vec3(0.9, 0.92, 0.96), dusted);
		} else {
			c = mix(c, vec3(0.9, 0.92, 0.96), cover * 0.85);
		}
	}
	ALBEDO = c;
	ROUGHNESS = mix(mix(roughness, 0.15, wet * wet_shine), 1.0, dusted);
	SPECULAR = mix(mix(specular, 0.65, wet * wet_shine), 0.1, dusted);
	EMISSION = (night_glow ? emission * smoothstep(0.05, 0.5, env_night) : emission) * glow;
	if (alpha_scissor) {
		ALPHA = t.a * albedo.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
