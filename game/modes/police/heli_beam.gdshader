shader_type spatial;
// A police helicopter's searchlight beam (D251): a cone from the light (y 0) to where it shines
// (y -1), added to what's behind it, fading along its length, soft at its edges and fading out
// near any camera, so a view inside or beside it never whites out. A camera inside the cone
// doesn't see it at all (it would cover the sky in a grey veil).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.96, 0.86);
uniform float strength = 0.1;

varying float along;
varying float outside;

void vertex() {
	along = clamp(-VERTEX.y, 0.0, 1.0);
	// The camera in the cone's own space: its radius at depth y is -y (1 at the far end).
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	float ratio = cam.y < 0.0 && cam.y > -1.2 ? length(cam.xz) / max(-cam.y, 1e-3) : 10.0;
	outside = smoothstep(1.0, 1.6, ratio);
}

void fragment() {
	float near = smoothstep(4.0, 22.0, length(VERTEX));
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	float a = strength * (1.0 - along * 0.8) * near * edge * outside;
	ALBEDO = color * a;
}
