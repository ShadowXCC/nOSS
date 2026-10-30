// Livery layers (docs/VEHICLE_PACKAGE.md §12), drawn live by the paint and glass shaders: each
// layer is a box in the model's space, projected onto the body along its normal. Packed by
// LiveryRenderer, 6 vec4 per layer, bottom layer first:
//   0: centre (model space), depth (how far it reaches along the normal)
//   1: right axis / width (signed: flipped), shape code (0-15 drawn here, 100+ an atlas cell)
//   2: up axis / height (signed), flags
//   3: shape params, or the text's rect in the text atlas
//   4: colour (linear), opacity
//   5: colour source (0 own, 1-4 livery_slots), finish, lowest layer a cut reaches, width / height
// Flags: 1 normal reversed, 2 cut, 4 mirrored, 8 readable (its mirror copy isn't reversed), 16 text,
// 32 fit (the picture keeps its shape inside the box, centred).

uniform vec4 livery[600];
uniform int livery_count = 0;
// The car's paint (linear): primary, secondary, tertiary and the contrast colour.
uniform vec4 livery_slots[4];
// The car's middle in model space (normal, offset): mirrored layers show across it.
uniform vec4 livery_mirror = vec4(1.0, 0.0, 0.0, 0.0);
// Shapes: an R8 distance field, 16 x 16 cells. Text: a multi-channel distance field per livery.
uniform sampler2D livery_shapes : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D livery_text : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float livery_shape_range = 16.0;
uniform float livery_text_range = 8.0;
// Model space from this mesh's own (rows of the transform), per mesh instance.
instance uniform vec4 livery_r0 : instance_index(0) = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 livery_r1 : instance_index(1) = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 livery_r2 : instance_index(2) = vec4(0.0, 0.0, 1.0, 0.0);

varying vec3 livery_pos;
varying vec3 livery_nrm;

#include "res://game/vehicles/livery/livery_shapes.gdshaderinc"

// A vertex in model space: vertex() sets livery_pos and livery_nrm from these.
vec3 livery_point(vec3 vertex) {
	vec4 v = vec4(vertex, 1.0);
	return vec3(dot(livery_r0, v), dot(livery_r1, v), dot(livery_r2, v));
}

vec3 livery_dir(vec3 normal) {
	return vec3(dot(livery_r0.xyz, normal), dot(livery_r1.xyz, normal), dot(livery_r2.xyz, normal));
}

// Coverage of the layer's picture at uv: a procedural shape, an atlas shape or its text.
float livery_shape(int i, vec2 uv, vec2 gx, vec2 gy, int flags) {
	vec4 prm = livery[i * 6 + 3];
	float fw = 0.5 * (length(gx) + length(gy)) + 1e-6;
	float edge = livery_aa(max(abs(uv.x), abs(uv.y)) - 0.5, fw);
	int code = int(livery[i * 6 + 1].w + 0.5);
	if ((flags & 16) != 0 || code >= 100) {
		// A distance field: text from the livery's text atlas (multi-channel), shapes from the
		// shared atlas's 16 x 16 cells (one channel). Image rows run down, uv up.
		// An atlas shape's code: 100 + its cell, plus 256 for each further cell it spans across.
		bool text = (flags & 16) != 0;
		int cell = (code - 100) % 256;
		vec4 rect = text ? prm : vec4(float(cell % 16), float(cell / 16), float(1 + (code - 100) / 256), 1.0) / 16.0;
		vec2 size = text ? vec2(textureSize(livery_text, 0)) : vec2(textureSize(livery_shapes, 0));
		if ((flags & 32) != 0) {
			float picture = rect.z * size.x / max(rect.w * size.y, 1e-6);
			float box = livery[i * 6 + 5].w;
			vec2 k = picture > box ? vec2(1.0, picture / box) : vec2(box / picture, 1.0);
			uv *= k;
			gx *= k;
			gy *= k;
			if (abs(uv.x) > 0.5 || abs(uv.y) > 0.5) {
				return 0.0;
			}
		}
		vec2 tuv = rect.xy + vec2(uv.x + 0.5, 0.5 - uv.y) * rect.zw;
		vec2 tx = vec2(gx.x, -gx.y) * rect.zw;
		vec2 ty = vec2(gy.x, -gy.y) * rect.zw;
		float range = text ? livery_text_range : livery_shape_range;
		vec2 unit = vec2(range) / size;
		vec2 dest = 1.0 / max(abs(tx) + abs(ty), vec2(1e-7));
		float px = max(0.5 * dot(unit, dest), 1.0);
		float sd;
		if (text) {
			sd = livery_median(textureGrad(livery_text, tuv, tx, ty).rgb);
		} else {
			sd = textureGrad(livery_shapes, tuv, tx, ty).r;
		}
		return clamp((sd - 0.5) * px + 0.5, 0.0, 1.0) * edge;
	}
	return livery_proc(code, uv, prm, livery[i * 6 + 5].w, gx, gy, fw) * edge;
}

// How much layer i covers point p (model space) on a surface facing nrm; dpx and dpy are p's
// change across one pixel. mirrored: p is the reflection of the point drawn.
float livery_cover(int i, vec3 p, vec3 nrm, vec3 dpx, vec3 dpy, bool mirrored, int flags) {
	vec4 a = livery[i * 6];
	vec4 r = livery[i * 6 + 1];
	vec4 u = livery[i * 6 + 2];
	vec3 d = p - a.xyz;
	vec2 uv = vec2(dot(d, r.xyz), dot(d, u.xyz));
	if (abs(uv.x) > 0.52 || abs(uv.y) > 0.52) {
		return 0.0;
	}
	vec3 n = normalize(cross(r.xyz, u.xyz)) * ((flags & 1) != 0 ? -1.0 : 1.0);
	float h = dot(d, n);
	if (abs(h) > a.w) {
		return 0.0;
	}
	// Facing away from the layer (the far side, inside trim) fades it out, and so does reaching
	// the end of its depth.
	float facing = clamp((dot(nrm, n) - 0.12) * 4.0, 0.0, 1.0);
	if (facing <= 0.0) {
		return 0.0;
	}
	float fade = facing * (1.0 - smoothstep(a.w * 0.7, a.w, abs(h)));
	vec2 gx = vec2(dot(dpx, r.xyz), dot(dpx, u.xyz));
	vec2 gy = vec2(dot(dpy, r.xyz), dot(dpy, u.xyz));
	if (mirrored && (flags & 8) != 0) {
		uv.x = -uv.x;
		gx.x = -gx.x;
		gy.x = -gy.x;
	}
	return fade * livery_shape(i, uv, gx, gy, flags);
}

// metallic, roughness, clearcoat, clearcoat roughness of a layer finish; 0 (paint) is the base's.
vec4 livery_finish(int f, vec4 base) {
	if (f == 1) return vec4(0.0, 0.18, 1.0, 0.03); // gloss
	if (f == 2) return vec4(0.0, 0.5, 0.3, 0.3); // satin
	if (f == 3) return vec4(0.0, 0.8, 0.0, 0.5); // matte
	if (f == 4) return vec4(0.75, 0.32, 1.0, 0.04); // metallic
	if (f == 5) return vec4(1.0, 0.06, 0.0, 0.1); // chrome
	if (f == 6) return vec4(0.45, 0.28, 1.0, 0.03); // pearl
	return base;
}

// The layers over the base (colour, finish), top layer first until it's covered. Returns how
// much the layers cover; color and finish come back with the base under what's uncovered.
// p, nrm: livery_pos and livery_nrm.
float livery_layers(vec3 p, vec3 nrm, vec3 base_color, vec4 base_finish, out vec3 color, out vec4 finish) {
	color = base_color;
	finish = base_finish;
	if (livery_count <= 0) {
		return 0.0;
	}
	nrm = normalize(nrm);
	vec3 dpx = dFdx(p);
	vec3 dpy = dFdy(p);
	vec3 mn = livery_mirror.xyz;
	vec3 mp = p - 2.0 * (dot(p, mn) - livery_mirror.w) * mn;
	vec3 mnrm = nrm - 2.0 * dot(nrm, mn) * mn;
	vec3 mdpx = dpx - 2.0 * dot(dpx, mn) * mn;
	vec3 mdpy = dpy - 2.0 * dot(dpy, mn) * mn;
	vec3 acc = vec3(0.0);
	vec4 acc_finish = vec4(0.0);
	float cover = 0.0;
	// Cut-outs: what's left of the layers under an ungrouped one, and under a group's (from
	// group_lo up).
	float cut_all = 1.0;
	float cut_group = 1.0;
	int group_lo = -1;
	for (int i = min(livery_count, 100) - 1; i >= 0; i--) {
		int flags = int(livery[i * 6 + 2].w + 0.5);
		float a = livery_cover(i, p, nrm, dpx, dpy, false, flags);
		if ((flags & 4) != 0) {
			a = max(a, livery_cover(i, mp, mnrm, mdpx, mdpy, true, flags));
		}
		if (a <= 0.0) {
			continue;
		}
		vec4 c = livery[i * 6 + 4];
		vec4 ex = livery[i * 6 + 5];
		a *= c.a;
		if ((flags & 2) != 0) {
			int lo = int(ex.z + 0.5);
			if (lo == 0) {
				cut_all *= 1.0 - a;
			} else if (lo == group_lo) {
				cut_group *= 1.0 - a;
			} else {
				cut_group = 1.0 - a;
				group_lo = lo;
			}
			continue;
		}
		a *= cut_all * (i >= group_lo ? cut_group : 1.0);
		int source = int(ex.x + 0.5);
		vec3 col = source == 0 ? c.rgb : livery_slots[clamp(source - 1, 0, 3)].rgb;
		float w = (1.0 - cover) * a;
		acc += w * col;
		acc_finish += w * livery_finish(int(ex.y + 0.5), base_finish);
		cover += w;
		if (cover > 0.996) {
			break;
		}
	}
	color = acc + (1.0 - cover) * base_color;
	finish = acc_finish + (1.0 - cover) * base_finish;
	return cover;
}
