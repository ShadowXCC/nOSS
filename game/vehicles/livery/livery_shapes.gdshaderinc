// Livery shapes (docs/VEHICLE_PACKAGE.md §12): the procedural ones as distance fields, shared by
// the paint shaders (livery.gdshaderinc) and the bay's shape picker (livery_icon.gdshader). uv
// runs -0.5..0.5 across a layer's box, up the way it reads.

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
