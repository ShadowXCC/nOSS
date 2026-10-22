// Tire tracks (TireTracks, D197): strips laid behind the wheels in fallen snow and off the road.
// Each fades over the second half of its life (UV2.x: when it was laid); tracks in fallen snow
// (UV2.y 1) also go as it melts, and dirt darkens in the wet. UV: across (0..1), along (m).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_schlick_ggx;

global uniform vec4 style_tint;
global uniform float style_saturation;
global uniform float env_wetness;
global uniform float env_snow;

uniform float now = 0.0;
uniform float life_snow = 60.0;
uniform float life_ground = 45.0;

varying float fade;

void vertex() {
	float age = now - UV2.x;
	fade = 1.0 - smoothstep(0.5, 1.0, age / (UV2.y > 0.5 ? life_snow : life_ground));
	if (UV2.y > 0.5) {
		fade *= smoothstep(0.1, 0.35, env_snow);
	}
	// Drawn a hair nearer the camera than where it lies, so the ground never shows through.
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * vec4(view * 0.999, 1.0);
}

void fragment() {
	// Soft edges, and a tread pressed in: chevrons along the strip.
	float edge = smoothstep(0.0, 0.2, UV.x) * smoothstep(1.0, 0.8, UV.x);
	float tread = 0.82 + 0.18 * step(0.5, fract(UV.y * 5.0 + abs(UV.x - 0.5) * 1.2));
	vec3 c = COLOR.rgb * style_tint.rgb;
	if (UV2.y < 0.5) {
		c *= 1.0 - 0.3 * env_wetness;
	}
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(grey), c, style_saturation);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	ALPHA = COLOR.a * edge * tread * fade;
}
