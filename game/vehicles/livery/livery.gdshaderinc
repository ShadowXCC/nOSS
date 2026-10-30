// Livery layers (docs/VEHICLE_PACKAGE.md §12), drawn live by the paint and glass shaders: each
// layer is a box in the model's space, projected onto the body along its normal. Packed by
// LiveryRenderer, 6 vec4 per layer, bottom layer first:
//   0: centre (model space), depth (how far it reaches along the normal)
//   1: right axis / width (signed: flipped), shape code (0-15 drawn here, 100+ an atlas cell)
//   2: up axis / height (signed), flags
//   3: shape params, or the text's rect in the text atlas
//   4: colour (linear), opacity
//   5: colour source (0 own, 1-4 livery_slots), finish, lowest layer a cut reaches, width / height
// Flags: 1 normal reversed, 2 cut, 4 mirrored, 8 readable (its mirror copy isn't reversed), 16 text.

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

// A vertex in model space: vertex() sets livery_pos and livery_nrm from these.
vec3 livery_point(vec3 vertex) {
	vec4 v = vec4(vertex, 1.0);
	return vec3(dot(livery_r0, v), dot(livery_r1, v), dot(livery_r2, v));
}

vec3 livery_dir(vec3 normal) {
	return vec3(dot(livery_r0.xyz, normal), dot(livery_r1.xyz, normal), dot(livery_r2.xyz, normal));
}

float livery_aa(float d, float fw) {
	return clamp(0.5 - d / fw, 0.0, 1.0);
}

float livery_outline(float d, float t) {
	return t > 0.0 ? abs(d + t) - t : d;
}

float livery_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float livery_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
	vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
	vec2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
			vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
			vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

float livery_star(vec2 p, float r, float n, float m) {
	float an = 3.141593 / n;
	float en = 3.141593 / m;
	vec2 acs = vec2(cos(an), sin(an));
	vec2 ecs = vec2(cos(en), sin(en));
	float bn = mod(atan(p.x, p.y), 2.0 * an) - an;
	p = length(p) * vec2(cos(bn), abs(sin(bn)));
	p -= r * acs;
	p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
	return length(p) * sign(p.x);
}

// A procedural shape's coverage at uv (-0.5..0.5 across the box). q is uv in units of the box's
// height; fw and fq a pixel's size in uv and in q.
float livery_proc(int code, vec2 uv, vec4 prm, float aspect, vec2 gx, vec2 gy, float fw) {
	vec2 s = vec2(aspect, 1.0);
	vec2 q = uv * s;
	vec2 hb = s * 0.5;
	float fq = 0.5 * (length(gx * s) + length(gy * s)) + 1e-6;
	float m = min(hb.x, hb.y);
	if (code == 0) { // rectangle
		return livery_aa(livery_outline(livery_box(q, hb, prm.x * m), prm.y * m), fq);
	} else if (code == 1 || code == 2) { // ellipse, ring
		float d = (length(q / hb) - 1.0) * m;
		float t = code == 2 ? max(prm.x, 0.02) * m : prm.x * m;
		return livery_aa(livery_outline(d, t), fq);
	} else if (code == 3) { // triangle
		float d = livery_triangle(q, -hb, vec2(hb.x, -hb.y), vec2((prm.x - 0.5) * s.x, hb.y));
		return livery_aa(livery_outline(d, prm.y * m), fq);
	} else if (code == 4) { // diamond
		vec2 a = abs(q) / hb;
		float d = (a.x + a.y - 1.0) * m * 0.7071;
		return livery_aa(livery_outline(d, prm.x * m), fq);
	} else if (code == 5) { // star
		float n = 3.0 + floor(prm.x * 9.0 + 0.5);
		float d = livery_star(uv, 0.5, n, mix(2.0, n, clamp(prm.y, 0.0, 0.95)));
		return livery_aa(d, fw);
	} else if (code == 6) { // arrow, pointing along the width
		float hl = 0.1 + prm.y * 0.6;
		float sh = 0.05 + prm.x * 0.45;
		float hw = (1.0 - hl) * 0.5;
		float d1 = livery_box(uv - vec2(-0.5 + hw, 0.0), vec2(hw, sh * 0.5), 0.0);
		float d2 = livery_triangle(uv, vec2(0.5 - hl, -0.5), vec2(0.5, 0.0), vec2(0.5 - hl, 0.5));
		return livery_aa(min(d1, d2), fw);
	} else if (code == 7) { // chevrons
		float n = 1.0 + floor(prm.x * 7.0 + 0.5);
		float c = fract((uv.x + 0.5) * n) - 0.5;
		float line = 0.2 - abs(uv.y) * 0.8;
		float d = (abs(c - line) * 0.78 - (0.04 + prm.y * 0.18)) / n;
		return livery_aa(d, fw);
	} else if (code == 8 || code == 9) { // stripes, pinstripes
		float n = code == 8 ? 1.0 + floor(prm.x * 11.0 + 0.5) : 1.0 + floor(prm.x * 5.0 + 0.5);
		float c = fract((uv.y + 0.5) * n) - 0.5;
		float d = code == 8 ? abs(c) - (0.05 + prm.y * 0.9) * 0.5 : abs(abs(c) - 0.3) - (0.01 + prm.y * 0.3) * 0.5;
		return livery_aa(d / n, fw);
	} else if (code == 10) { // checker
		float k = (2.0 + floor(prm.x * 14.0 + 0.5)) / aspect;
		vec2 p = q * k + 0.5;
		vec2 w = max(abs(gx * s * k), abs(gy * s * k)) + 1e-4;
		vec2 i = 2.0 * (abs(fract((p - 0.5 * w) * 0.5) - 0.5) - abs(fract((p + 0.5 * w) * 0.5) - 0.5)) / w;
		return 0.5 - 0.5 * i.x * i.y;
	} else if (code == 11) { // fade
		return clamp((0.5 - uv.x) / max(prm.x, 0.02), 0.0, 1.0);
	} else if (code == 12) { // glow
		return clamp((0.5 - length(uv)) / max(prm.x * 0.5, 0.01), 0.0, 1.0);
	} else if (code == 13) { // halftone
		float cs = 1.0 / (3.0 + floor(prm.x * 21.0 + 0.5));
		vec2 c = (floor(q / cs) + 0.5) * cs;
		float r = 0.575 * cs * clamp(0.5 - c.x / s.x, 0.0, 1.0);
		return livery_aa(length(q - c) - r, fq);
	} else if (code == 14) { // speed lines
		float n = 3.0 + floor(prm.x * 13.0 + 0.5);
		float y = (uv.y + 0.5) * n;
		float c = fract(y) - 0.5;
		float h = fract(sin(floor(y) * 12.9898 + 4.1) * 43758.5453);
		float sx = -0.5 + h * 0.6;
		float t = 0.25 * (1.0 - prm.y * clamp((uv.x - sx) / max(0.5 - sx, 0.01), 0.0, 1.0));
		return livery_aa(max((abs(c) - t) / n, sx - uv.x), fw);
	} else if (code == 15) { // slash
		float sh = (prm.x - 0.5) * 0.8;
		float x = uv.x - uv.y * sh;
		float d = max(abs(x) - (0.5 - abs(sh) * 0.5), abs(uv.y) - 0.5);
		return livery_aa(livery_outline(d, prm.y * 0.25), fw);
	}
	return 0.0;
}

float livery_median(vec3 c) {
	return max(min(c.r, c.g), min(max(c.r, c.g), c.b));
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
		bool text = (flags & 16) != 0;
		vec4 rect = text ? prm : vec4(float((code - 100) % 16), float((code - 100) / 16), 1.0, 1.0) / vec4(16.0, 16.0, 16.0, 16.0);
		vec2 tuv = rect.xy + vec2(uv.x + 0.5, 0.5 - uv.y) * rect.zw;
		vec2 tx = vec2(gx.x, -gx.y) * rect.zw;
		vec2 ty = vec2(gy.x, -gy.y) * rect.zw;
		vec2 size = text ? vec2(textureSize(livery_text, 0)) : vec2(textureSize(livery_shapes, 0));
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
