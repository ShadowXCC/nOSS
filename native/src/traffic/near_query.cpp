#include "traffic/near_query.h"

#include <algorithm>
#include <cmath>

namespace noss::traffic {

namespace {

struct P {
	double x, z;
};

void corners(const Box2 &p_b, P r_out[4]) {
	// The driver's left: up x forward = (fz, -fx).
	double lx = p_b.fz, lz = -p_b.fx;
	double ax = p_b.fx * p_b.half_len, az = p_b.fz * p_b.half_len;
	double bx = lx * p_b.half_wid, bz = lz * p_b.half_wid;
	r_out[0] = { p_b.cx + ax + bx, p_b.cz + az + bz };
	r_out[1] = { p_b.cx + ax - bx, p_b.cz + az - bz };
	r_out[2] = { p_b.cx - ax - bx, p_b.cz - az - bz };
	r_out[3] = { p_b.cx - ax + bx, p_b.cz - az + bz };
}

bool separated(const P p_a[4], const P p_b[4], double p_nx, double p_nz) {
	double a0 = 1e30, a1 = -1e30, b0 = 1e30, b1 = -1e30;
	for (int i = 0; i < 4; i++) {
		double pa = p_a[i].x * p_nx + p_a[i].z * p_nz;
		double pb = p_b[i].x * p_nx + p_b[i].z * p_nz;
		a0 = std::min(a0, pa);
		a1 = std::max(a1, pa);
		b0 = std::min(b0, pb);
		b1 = std::max(b1, pb);
	}
	return a1 < b0 || b1 < a0;
}

double point_segment(const P &p_p, const P &p_a, const P &p_b) {
	double sx = p_b.x - p_a.x, sz = p_b.z - p_a.z;
	double len2 = sx * sx + sz * sz;
	double t = len2 > 1e-12 ? std::clamp(((p_p.x - p_a.x) * sx + (p_p.z - p_a.z) * sz) / len2, 0.0, 1.0) : 0.0;
	return std::hypot(p_p.x - (p_a.x + sx * t), p_p.z - (p_a.z + sz * t));
}

} // namespace

double box_gap(const Box2 &p_a, const Box2 &p_b) {
	P a[4], b[4];
	corners(p_a, a);
	corners(p_b, b);
	double axes[4][2] = { { p_a.fx, p_a.fz }, { p_a.fz, -p_a.fx }, { p_b.fx, p_b.fz }, { p_b.fz, -p_b.fx } };
	bool apart = false;
	for (auto &axis : axes) {
		if (separated(a, b, axis[0], axis[1])) {
			apart = true;
			break;
		}
	}
	if (!apart) {
		return 0.0;
	}
	double best = 1e30;
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 4; j++) {
			best = std::min(best, point_segment(a[i], b[j], b[(j + 1) % 4]));
			best = std::min(best, point_segment(b[i], a[j], a[(j + 1) % 4]));
		}
	}
	return best;
}

void box_offset(const Box2 &p_a, const Box2 &p_b, double &r_along, double &r_left) {
	double dx = p_b.cx - p_a.cx, dz = p_b.cz - p_a.cz;
	r_along = dx * p_a.fx + dz * p_a.fz;
	r_left = dx * p_a.fz - dz * p_a.fx;
}

} // namespace noss::traffic
