shader_type spatial;
// A spike strip's glint (D249): a cartoon four-pointed star on a quad that faces the camera. It's
// at least `min_screen` of the view's height tall wherever it's seen from (at least `base_size`
// metres), so a strip far up the road still catches the eye. `pop` (0..1) and `twist` are set by
// the strip as the star pops; `strength` dims it.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.97, 0.82);
uniform float base_size = 0.35;
uniform float min_screen = 0.025;
uniform float pop = 1.0;
uniform float twist = 0.0;
uniform float strength = 1.0;

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(center);
	// The view's height in metres at that distance: 2 d tan(fov / 2).
	float view_h = 2.0 * dist / PROJECTION_MATRIX[1][1];
	float size = max(base_size, view_h * min_screen) * pop;
	float c = cos(twist);
	float s = sin(twist);
	vec2 corner = vec2(c * VERTEX.x - s * VERTEX.y, s * VERTEX.x + c * VERTEX.y) * size;
	// A little toward the camera, so the road doesn't cut it in half.
	center -= normalize(center) * min(dist * 0.5, 0.6 + size * 0.3);
	VERTEX = center + vec3(corner, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	// Two thin arms (a long point each way) and a round core, cut hard: a cartoon star.
	float arms = max(1.0 - (abs(p.x) * 7.0 + abs(p.y)), 1.0 - (abs(p.y) * 7.0 + abs(p.x)));
	float core = 1.0 - r * 3.2;
	float shape = max(arms, core);
	float a = smoothstep(0.0, 0.08, shape);
	vec3 col = mix(color, vec3(1.0), smoothstep(0.3, 0.7, shape));
	ALBEDO = col * a * strength;
	ALPHA = a;
}
