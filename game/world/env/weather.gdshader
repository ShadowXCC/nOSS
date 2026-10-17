// Rain and snow (D153): a box of streaks round the camera, nothing simulated. Each instance has a
// fixed spot in the box (INSTANCE_CUSTOM); the box is a lattice fixed to the world and wrapped
// round the camera, so drops fall past you as you drive instead of moving with you. One box per
// player view (its own render layer).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, world_vertex_coords;

uniform float box = 36.0; // metres across
uniform float fall = 9.0; // m/s
uniform float length_m = 0.55;
uniform float width_m = 0.012;
uniform float sway = 0.0; // snow drifts side to side, metres
uniform vec4 tint : source_color = vec4(0.75, 0.8, 0.88, 0.32);
// The sky's light (night darkens the drops).
uniform float light = 1.0;
// Drops lean back with the wind and with the camera's speed past them.
uniform vec3 drift = vec3(0.0);

void vertex() {
	vec3 seed = INSTANCE_CUSTOM.xyz;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 p = seed * box;
	p.y -= TIME * fall;
	p.xz += vec2(sin(TIME * 0.8 + seed.z * 23.0), cos(TIME * 0.6 + seed.x * 17.0)) * sway;
	vec3 centre = cam + mod(p - cam, vec3(box)) - vec3(box * 0.5);
	vec3 to_cam = cam - centre;
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam + vec3(0.0001)));
	vec3 along = normalize(vec3(0.0, 1.0, 0.0) + drift);
	// The quad: VERTEX.x across (-0.5..0.5), VERTEX.y along (0..1).
	VERTEX = centre + side * VERTEX.x * width_m + along * VERTEX.y * length_m;
	// Fade the edges of the box so drops don't pop in, and those right at the camera.
	vec3 q = abs(mod(p - cam, vec3(box)) - vec3(box * 0.5)) / (box * 0.5);
	COLOR.a = (1.0 - smoothstep(0.75, 1.0, max(q.x, max(q.y, q.z)))) * smoothstep(1.0, 3.0, length(to_cam));
}

void fragment() {
	ALBEDO = tint.rgb * light;
	ALPHA = tint.a * COLOR.a;
}
