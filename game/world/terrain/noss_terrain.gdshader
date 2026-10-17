// Terrain (docs/TRACK_EDITOR.md §2, D90): a chunk's grid displaced by its height texture, its
// paint layers blended from two splat maps. Like noss_world, the style profile's globals tint it.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

global uniform vec4 style_tint;
global uniform float style_mip_bias;
global uniform float style_saturation;
global uniform float env_wetness;
global uniform float env_snow;

// Heights: (chunk + 3)² with a one-sample apron, 0..1 over h_min .. h_min + h_range.
uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform float h_min = 0.0;
uniform float h_range = 1.0;
// Paint weights: layers 0-3 and 4-7, (chunk + 1)².
uniform sampler2D splat_0 : filter_linear, repeat_disable;
uniform sampler2D splat_1 : filter_linear, repeat_disable;
uniform sampler2DArray layers : source_color, filter_linear_mipmap, repeat_enable;
uniform float layer_tile_m = 4.0;
uniform float chunk_cells = 256.0;
uniform float cell = 1.0;
// This mesh's grid spacing in cells (for normals at its own scale).
uniform float lod_step = 1.0;
uniform float variation = 0.2;
uniform sampler2D variation_noise : repeat_enable, filter_linear_mipmap, hint_default_white;

varying vec3 world_pos;

float height_at(ivec2 s) {
	ivec2 at = clamp(s + ivec2(1), ivec2(0), ivec2(int(chunk_cells) + 2));
	return h_min + texelFetch(height_tex, at, 0).r * h_range;
}

void vertex() {
	// VERTEX.xz: metres within the chunk; UV2.x: 1 on the skirt below the edge.
	ivec2 s = ivec2(round(VERTEX.xz / cell));
	VERTEX.y = height_at(s) - UV2.x * 2.0;
	int st = int(lod_step);
	float hl = height_at(s - ivec2(st, 0));
	float hr = height_at(s + ivec2(st, 0));
	float hd = height_at(s - ivec2(0, st));
	float hu = height_at(s + ivec2(0, st));
	NORMAL = normalize(vec3(hl - hr, 2.0 * float(st) * cell, hd - hu));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	UV = (vec2(s) + 0.5) / (chunk_cells + 1.0);
}

void fragment() {
	vec4 w0 = texture(splat_0, UV);
	vec4 w1 = texture(splat_1, UV);
	float weights[8] = { w0.r, w0.g, w0.b, w0.a, w1.r, w1.g, w1.b, w1.a };
	vec2 uv = world_pos.xz / layer_tile_m;
	vec3 c = vec3(0.0);
	float sum = 0.0;
	for (int i = 0; i < 8; i++) {
		if (weights[i] > 0.004) {
			c += texture(layers, vec3(uv, float(i)), style_mip_bias).rgb * weights[i];
			sum += weights[i];
		}
	}
	c = c / max(sum, 0.001) * style_tint.rgb;
	if (variation > 0.0) {
		float v = texture(variation_noise, world_pos.xz * 0.004).r;
		c *= mix(1.0 - variation, 1.0 + variation, v);
	}
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(grey), c, style_saturation);
	// The sky (D153): darker wet ground, snow lying where it's flat enough.
	float wet = env_wetness * (1.0 - env_snow);
	c *= 1.0 - 0.2 * wet;
	float up = smoothstep(0.6, 0.85, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
	c = mix(c, vec3(0.9, 0.92, 0.96), env_snow * up * 0.9);
	ALBEDO = c;
	ROUGHNESS = 0.95 - 0.35 * wet;
	SPECULAR = 0.1 + 0.15 * wet;
}
