// Paint slot material (docs/VEHICLE_PACKAGE.md §3, §5). The model's base-color texture is a
// multiply/detail layer: white shows pure paint.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform sampler2D detail : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_map = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float clearcoat : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_roughness : hint_range(0.0, 1.0) = 0.05;
// Pearl: tints the paint toward pearl_color at grazing angles.
uniform float pearl : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pearl_color : source_color = vec4(1.0);

void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
}

void fragment() {
	vec3 color = paint_color.rgb;
	if (pearl > 0.0) {
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		color = mix(color, pearl_color.rgb, rim * pearl);
	}
	ALBEDO = color * texture(detail, UV).rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
	}
}
