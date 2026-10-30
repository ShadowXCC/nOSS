// The car's glass with livery layers on it (docs/VEHICLE_PACKAGE.md §12), made only while the
// worn livery puts something on the glass: the original glass material's colour, texture and
// finish, with the layers over it as opaque vinyl. Both sides draw (seen from inside, the layers
// show reversed, as stickers would).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://game/vehicles/livery/livery.gdshaderinc"

uniform vec4 glass_color : source_color = vec4(0.1, 0.12, 0.14, 0.4);
uniform sampler2D glass_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float glass_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.05;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);

void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
	livery_pos = livery_point(VERTEX);
	livery_nrm = livery_dir(NORMAL);
}

void fragment() {
	vec4 g = glass_color * texture(glass_texture, UV);
	vec3 color;
	vec4 finish;
	vec4 base_finish = vec4(glass_metallic, glass_roughness, 0.0, 0.0);
	float cover = livery_layers(livery_pos, livery_nrm, g.rgb, base_finish, color, finish);
	// The layers over the glass: what they cover is opaque, the rest as see-through as before.
	float alpha = mix(g.a, 1.0, cover);
	vec3 layers = color - (1.0 - cover) * g.rgb;
	ALBEDO = (layers + (1.0 - cover) * g.a * g.rgb) / max(alpha, 1e-4);
	ALPHA = alpha;
	METALLIC = finish.x;
	ROUGHNESS = finish.y;
	CLEARCOAT = finish.z;
	CLEARCOAT_ROUGHNESS = finish.w;
}
