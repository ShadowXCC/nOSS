// Shared world material (docs/ARCHITECTURE.md §7). Tracks never hard-code their look: the
// style profile drives the global style_* uniforms.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

global uniform vec4 style_tint;
global uniform float style_mip_bias;
global uniform float style_saturation;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform bool world_uv = false; // planar XZ mapping for terrain
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float specular : hint_range(0.0, 1.0) = 0.2;
uniform bool alpha_scissor = false;
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
	ALBEDO = mix(vec3(grey), c, style_saturation);
	ROUGHNESS = roughness;
	SPECULAR = specular;
	if (alpha_scissor) {
		ALPHA = t.a * albedo.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
