// Paint slot material (docs/VEHICLE_PACKAGE.md §3, §5): plain paint, for every car without a
// livery on this slot (noss_paint_livery.gdshader draws one).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://game/vehicles/noss_paint.gdshaderinc"

void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
}

void fragment() {
	ALBEDO = paint_albedo(NORMAL, VIEW) * texture(detail, UV).rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
	}
}
