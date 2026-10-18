shader_type spatial;
// The goo under a sumo arena (D162): lava or acid, by uniform. Two noise octaves drift across
// each other so the surface churns slowly and a point never flashes (ACC-04); `calm` takes the
// motion and the glow down for Reduce flashing. UV is in metres.

uniform vec4 deep : source_color = vec4(0.35, 0.05, 0.02, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.45, 0.07, 1.0);
uniform vec4 crust : source_color = vec4(0.10, 0.07, 0.07, 1.0);
uniform float speed = 0.035;
uniform float emit = 2.2;
uniform float calm = 0.0;

// Value noise: cheap, and enough for a churning surface.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float t = TIME * speed * mix(1.0, 0.35, calm);
	vec2 uv = UV * 0.04;
	// Two octaves drifting apart: the pattern never repeats on the eye.
	float a = noise(uv + vec2(t, t * 0.6));
	float b = noise(uv * 2.3 - vec2(t * 0.8, t * 1.3));
	float heat = clamp(a * 0.65 + b * 0.35, 0.0, 1.0);
	// A wide smoothstep, so the crust fades in rather than snapping on.
	float skin = smoothstep(0.42, 0.72, heat);
	vec3 molten = mix(deep.rgb, glow.rgb, smoothstep(0.30, 0.95, heat));
	ALBEDO = mix(crust.rgb, molten, skin);
	EMISSION = glow.rgb * skin * emit * mix(1.0, 0.45, calm);
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
