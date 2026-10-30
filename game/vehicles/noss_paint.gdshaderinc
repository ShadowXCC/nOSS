// Paint slot material (docs/VEHICLE_PACKAGE.md §3, §5), shared by the plain paint shader and the
// livery one (noss_paint_livery.gdshader). The model's base-color texture is a multiply/detail
// layer: white shows pure paint.

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

// The slot's colour as seen from `view` (pearl shifts it at grazing angles).
vec3 paint_albedo(vec3 normal, vec3 view) {
	vec3 color = paint_color.rgb;
	if (pearl > 0.0) {
		float rim = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 3.0);
		color = mix(color, pearl_color.rgb, rim * pearl);
	}
	return color;
}
