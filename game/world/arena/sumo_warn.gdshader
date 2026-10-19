shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// The band over the floor a sumo platform is about to lose (D182): light thrown on the deck, so
// the concrete still reads through it. The goo's own colour, so the band says what that floor is
// about to become. Two pulses a second, and none at all with reduce flashing (ACC-04), where it
// sits at the dim end instead of flashing.

uniform vec3 tint : source_color = vec3(1.0, 0.45, 0.08);
uniform float calm = 0.0;

void fragment() {
	float pulse = 0.5 + 0.5 * sin(TIME * TAU * 2.0);
	float lit = mix(mix(0.3, 1.0, pulse), 0.45, calm);
	ALBEDO = tint * lit;
	ALPHA = 1.0;
}
