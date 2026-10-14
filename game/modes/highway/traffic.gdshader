// Distant highway traffic (D108): one MultiMesh per vehicle type. Paint takes each instance's
// colour; lights read each instance's custom data: x = bits (1 brake, 2 left indicator, 4 right
// indicator, 8 head lights).
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

global uniform vec4 style_tint;
global uniform float style_saturation;

// 0: paint (the instance's colour); 1: a fixed colour; 2: a light of `light_bit`.
uniform int kind = 1;
uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform int light_bit = 0;
uniform vec3 glow : source_color = vec3(1.0, 0.1, 0.05);
uniform float glow_energy = 3.0;

varying vec4 instance_color;
varying float bits;

void vertex() {
	instance_color = COLOR;
	bits = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec3 c = kind == 0 ? instance_color.rgb : albedo.rgb;
	c *= style_tint.rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(grey), c, style_saturation);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	if (kind == 2) {
		int b = int(bits + 0.5);
		if ((b & light_bit) != 0) {
			EMISSION = glow * glow_energy;
		}
	}
}
