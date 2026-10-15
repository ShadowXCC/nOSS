shader_type spatial;
// Boost pads (D137): chevrons pointing along the road, scrolling forward. A point changes colour
// 1.5 times a second, never flashing (ACC-04). UV: x across the pad 0..1, y along it in metres.

uniform vec4 base : source_color = vec4(0.10, 0.10, 0.12, 1.0);
uniform vec4 arrow : source_color = vec4(1.0, 0.56, 0.06, 1.0);
uniform float speed = 1.5;

void fragment() {
	float c = fract(UV.y * 0.8 + abs(UV.x - 0.5) * 0.9 - TIME * speed);
	float m = step(0.55, c);
	ALBEDO = mix(base.rgb, arrow.rgb, m);
	EMISSION = arrow.rgb * m * 0.5;
	ROUGHNESS = 0.55;
}
