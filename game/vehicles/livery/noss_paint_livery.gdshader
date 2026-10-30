// A paint slot with livery layers on it (docs/VEHICLE_PACKAGE.md §12): the plain paint shader's
// look, with the layers composited over the paint before the model's detail texture and normal
// map, so they look painted on. Cars without a livery on a slot keep noss_paint.gdshader.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://game/vehicles/noss_paint.gdshaderinc"
#include "res://game/vehicles/livery/livery.gdshaderinc"

void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
	livery_pos = livery_point(VERTEX);
	livery_nrm = livery_dir(NORMAL);
}

void fragment() {
	vec3 color;
	vec4 finish;
	livery_layers(livery_pos, livery_nrm, paint_albedo(NORMAL, VIEW), vec4(metallic, roughness, clearcoat, clearcoat_roughness), color, finish);
	ALBEDO = color * texture(detail, UV).rgb;
	METALLIC = finish.x;
	ROUGHNESS = finish.y;
	CLEARCOAT = finish.z;
	CLEARCOAT_ROUGHNESS = finish.w;
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
	}
}
