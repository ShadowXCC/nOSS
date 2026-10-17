// Shared world material (docs/ARCHITECTURE.md §7). Tracks never hard-code their look: the
// style profile drives the global style_* uniforms, and the sky (EnvDirector, D153) the env_*
// ones: wet surfaces darken (roads shine), snow settles on what faces up, lamps light at night.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

global uniform vec4 style_tint;
global uniform float style_mip_bias;
global uniform float style_saturation;
global uniform float env_wetness;
global uniform float env_snow;
global uniform float env_night;

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
// Roads and paved ground shine when wet (1); how much snow settles on it (lamps, signs: 0).
uniform float wet_shine = 0.0;
uniform float snow_settle = 1.0;
// Low-frequency colour variation in world space, to break up tiling.
uniform float variation = 0.0;
uniform sampler2D variation_noise : repeat_enable, filter_linear_mipmap, hint_default_white;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	float wet = env_wetness * (1.0 - env_snow);
	if (wet > 0.0 || env_snow > 0.0) {
		float up = smoothstep(0.55, 0.85, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
		c *= 1.0 - (0.18 + 0.2 * wet_shine) * wet;
		c = mix(c, vec3(0.9, 0.92, 0.96), env_snow * snow_settle * up * 0.85);
	}
	ALBEDO = c;
	ROUGHNESS = mix(roughness, 0.15, wet * wet_shine);
	SPECULAR = mix(specular, 0.65, wet * wet_shine);
	EMISSION = night_glow ? emission * smoothstep(0.05, 0.5, env_night) : emission;
	if (alpha_scissor) {
		ALPHA = t.a * albedo.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
