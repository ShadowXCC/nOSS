// A livery shape in the Fitting Bay's picker: drawn by the same code as on the car.
shader_type canvas_item;

#include "res://game/vehicles/livery/livery_shapes.gdshaderinc"

// The shape's code (LiveryRenderer: 0-15 drawn, 100+ an atlas cell), params and width / height.
uniform int code = 0;
uniform vec4 params = vec4(0.0);
uniform float aspect = 1.0;
uniform sampler2D shapes : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float shape_range = 16.0;

void fragment() {
	// The box fits the rect, kept in shape.
	vec2 rect = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 p = (UV - 0.5) * vec2(1.0, -1.0);
	float rect_aspect = rect.x / rect.y;
	vec2 k = rect_aspect > aspect ? vec2(rect_aspect / aspect, 1.0) : vec2(1.0, aspect / rect_aspect);
	vec2 uv = p * k;
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	float fw = 0.5 * (length(gx) + length(gy)) + 1e-6;
	float a = 0.0;
	if (abs(uv.x) <= 0.52 && abs(uv.y) <= 0.52) {
		if (code >= 100) {
			int cell = (code - 100) % 256;
			vec4 r = vec4(float(cell % 16), float(cell / 16), float(1 + (code - 100) / 256), 1.0) / 16.0;
			vec2 tuv = r.xy + vec2(uv.x + 0.5, 0.5 - uv.y) * r.zw;
			vec2 size = vec2(textureSize(shapes, 0));
			vec2 tx = vec2(gx.x, -gx.y) * r.zw;
			vec2 ty = vec2(gy.x, -gy.y) * r.zw;
			float px = max(0.5 * dot(vec2(shape_range) / size, 1.0 / max(abs(tx) + abs(ty), vec2(1e-7))), 1.0);
			a = clamp((textureGrad(shapes, tuv, tx, ty).r - 0.5) * px + 0.5, 0.0, 1.0);
		} else {
			a = livery_proc(code, uv, params, aspect, gx, gy, fw);
		}
		a *= livery_aa(max(abs(uv.x), abs(uv.y)) - 0.5, fw);
	}
	COLOR = vec4(1.0, 1.0, 1.0, a);
}
