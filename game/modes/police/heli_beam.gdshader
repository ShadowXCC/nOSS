shader_type spatial;
// A police helicopter's searchlight beam (D251): a cone from the light (y 0) to where it shines
// (y -1), added to what's behind it, fading along its length, soft at its edges and fading out
// near any camera, so a view inside or beside it never whites out.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.96, 0.86);
uniform float strength = 0.16;

varying float along;

void vertex() {
	along = clamp(-VERTEX.y, 0.0, 1.0);
}

void fragment() {
	float near = smoothstep(4.0, 22.0, length(VERTEX));
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	float a = strength * (1.0 - along * 0.8) * near * edge;
	ALBEDO = color * a;
}
