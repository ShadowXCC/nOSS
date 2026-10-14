#include "traffic/lane_graph.h"

#include <algorithm>
#include <cmath>

#include "traffic/fixed.h"

namespace noss::traffic {

namespace {

int64_t mm(double p_m) {
	return int64_t(std::llround(p_m * 1000.0));
}

} // namespace

bool LaneGraph::build(const GraphInput &p_in, std::string *r_error) {
	auto fail = [&](const std::string &p_why) {
		if (r_error) {
			*r_error = p_why;
		}
		return false;
	};
	lanes.clear();
	_cells.clear();
	portal_ins.clear();
	portal_outs.clear();
	lanes.resize(p_in.lanes.size());
	for (size_t li = 0; li < p_in.lanes.size(); li++) {
		const LaneInput &in = p_in.lanes[li];
		Lane &lane = lanes[li];
		lane.dir = in.dir;
		lane.road = in.road;
		lane.index = in.index;
		lane.closed = in.closed;
		size_t n = in.xyz.size() / 3;
		if (n < 2) {
			return fail("Lane " + std::to_string(li) + " has under 2 points");
		}
		for (size_t i = 0; i < n; i++) {
			lane.x.push_back(in.xyz[i * 3]);
			lane.y.push_back(in.xyz[i * 3 + 1]);
			lane.z.push_back(in.xyz[i * 3 + 2]);
		}
		lane.cum.push_back(0);
		size_t segs = lane.closed ? n : n - 1;
		for (size_t i = 0; i < segs; i++) {
			size_t j = (i + 1) % n;
			double dx = lane.x[j] - lane.x[i], dy = lane.y[j] - lane.y[i], dz = lane.z[j] - lane.z[i];
			lane.cum.push_back(lane.cum.back() + std::max<int64_t>(1, mm(std::sqrt(dx * dx + dy * dy + dz * dz))));
		}
		lane.length = lane.cum.back();
		_limits(lane, in);
		for (size_t i = 0; i < segs; i++) {
			size_t j = (i + 1) % n;
			int x0 = int(std::floor((std::min(lane.x[i], lane.x[j]) - 8.0) / CELL_M));
			int x1 = int(std::floor((std::max(lane.x[i], lane.x[j]) + 8.0) / CELL_M));
			int z0 = int(std::floor((std::min(lane.z[i], lane.z[j]) - 8.0) / CELL_M));
			int z1 = int(std::floor((std::max(lane.z[i], lane.z[j]) + 8.0) / CELL_M));
			for (int cz = z0; cz <= z1; cz++) {
				for (int cx = x0; cx <= x1; cx++) {
					_cells[_cell_key(cx, cz)].push_back({ int(li), int(i) });
				}
			}
		}
	}
	int count = int(lanes.size());
	auto valid = [&](int p_l) { return p_l >= 0 && p_l < count; };
	for (const auto &a : p_in.adjacent) {
		if (!valid(a[0]) || !valid(a[1]) || lanes[a[0]].vertices() != lanes[a[1]].vertices()) {
			return fail("Adjacent lanes must have the same vertices");
		}
		lanes[a[0]].inner = a[1];
		lanes[a[1]].outer = a[0];
	}
	for (const auto &b : p_in.branches) {
		if (!valid(b[0]) || !valid(b[2]) || b[1] < 0 || b[1] >= lanes[b[0]].vertices()) {
			return fail("Bad branch");
		}
		lanes[b[0]].branches.push_back({ lanes[b[0]].cum[size_t(b[1])], b[1], b[2] });
	}
	for (Lane &lane : lanes) {
		std::sort(lane.branches.begin(), lane.branches.end(), [](const Branch &a, const Branch &b) { return a.at < b.at; });
	}
	for (const auto &m : p_in.merges) {
		if (!valid(m[0]) || !valid(m[1]) || m[2] < 0 || m[2] >= lanes[m[1]].vertices()) {
			return fail("Bad merge");
		}
		lanes[m[0]].merge_into = m[1];
		lanes[m[0]].merge_vertex = m[2];
	}
	for (const auto &a : p_in.attaches) {
		if (!valid(a[0]) || !valid(a[2]) || a[4] < 2 || a[1] < 0 || a[1] + a[4] > lanes[a[0]].vertices()) {
			return fail("Bad attach");
		}
		lanes[a[0]].attaches.push_back({ a[1], a[2], a[3], a[4] });
	}
	auto portal_list = [&](std::vector<std::vector<int>> &r_list, int p_portal) -> std::vector<int> & {
		if (int(r_list.size()) <= p_portal) {
			r_list.resize(size_t(p_portal + 1));
		}
		return r_list[size_t(p_portal)];
	};
	for (const auto &p : p_in.portal_in) {
		if (!valid(p[0]) || p[1] < 0) {
			return fail("Bad portal");
		}
		lanes[p[0]].portal_in = p[1];
		portal_list(portal_ins, p[1]).push_back(p[0]);
	}
	for (const auto &p : p_in.portal_out) {
		if (!valid(p[0]) || p[1] < 0) {
			return fail("Bad portal");
		}
		lanes[p[0]].portal_out = p[1];
		portal_list(portal_outs, p[1]).push_back(p[0]);
	}
	size_t portals = std::max(portal_ins.size(), portal_outs.size());
	portal_ins.resize(portals);
	portal_outs.resize(portals);
	return true;
}

void LaneGraph::_limits(Lane &r_lane, const LaneInput &p_in) {
	int n = r_lane.vertices();
	r_lane.limit.assign(size_t(n), p_in.speed_mmps);
	for (int i = 0; i < n && i < int(p_in.limit_mmps.size()); i++) {
		r_lane.limit[size_t(i)] = p_in.limit_mmps[size_t(i)];
	}
	// Bends: the circle through each vertex and its neighbours.
	for (int i = 0; i < n; i++) {
		if (!r_lane.closed && (i == 0 || i == n - 1)) {
			continue;
		}
		int a = (i - 1 + n) % n, c = (i + 1) % n;
		double abx = r_lane.x[i] - r_lane.x[a], abz = r_lane.z[i] - r_lane.z[a];
		double bcx = r_lane.x[c] - r_lane.x[i], bcz = r_lane.z[c] - r_lane.z[i];
		double acx = r_lane.x[c] - r_lane.x[a], acz = r_lane.z[c] - r_lane.z[a];
		double cross = std::abs(abx * bcz - abz * bcx);
		double lens = std::sqrt(abx * abx + abz * abz) * std::sqrt(bcx * bcx + bcz * bcz) * std::sqrt(acx * acx + acz * acz);
		if (cross < 1e-9 || lens < 1e-9) {
			continue;
		}
		double radius = lens / (2.0 * cross);
		int64_t v = mm(std::sqrt(LATERAL_ACCEL * radius));
		r_lane.limit[size_t(i)] = int32_t(std::min<int64_t>(r_lane.limit[size_t(i)], std::max<int64_t>(v, 5000)));
	}
	// Slow down in time: each vertex no faster than braking at PLAN_DECEL reaches the next one's.
	int passes = r_lane.closed ? 2 : 1;
	for (int p = 0; p < passes; p++) {
		for (int i = n - 1; i >= 0; i--) {
			int j = i + 1;
			if (j >= n) {
				if (!r_lane.closed) {
					continue;
				}
				j = 0;
			}
			int64_t seg = r_lane.cum[size_t(i) + 1] - r_lane.cum[size_t(i)];
			int64_t next = r_lane.limit[size_t(j)];
			int64_t reach = int64_t(isqrt64(uint64_t(next * next + 2 * PLAN_DECEL_MMPS2 * seg)));
			r_lane.limit[size_t(i)] = int32_t(std::min<int64_t>(r_lane.limit[size_t(i)], reach));
		}
	}
}

uint64_t LaneGraph::hash() const {
	Fnv64 f;
	f.i64(int64_t(lanes.size()));
	for (const Lane &l : lanes) {
		for (int64_t v : { int64_t(l.dir), int64_t(l.road), int64_t(l.index), int64_t(l.closed), int64_t(l.outer), int64_t(l.inner),
					 int64_t(l.merge_into), int64_t(l.merge_vertex), int64_t(l.portal_in), int64_t(l.portal_out) }) {
			f.i64(v);
		}
		for (size_t i = 0; i < l.x.size(); i++) {
			f.i64(mm(l.x[i]));
			f.i64(mm(l.y[i]));
			f.i64(mm(l.z[i]));
		}
		for (int64_t c : l.cum) {
			f.i64(c);
		}
		for (int32_t v : l.limit) {
			f.i64(v);
		}
		for (const Branch &b : l.branches) {
			f.i64(b.at);
			f.i64(b.ramp);
		}
		for (const Attach &a : l.attaches) {
			f.i64(a.ramp_v0);
			f.i64(a.lane);
			f.i64(a.lane_v0);
			f.i64(a.count);
		}
	}
	return f.h;
}

int64_t LaneGraph::wrap(int p_lane, int64_t p_s) const {
	const Lane &l = lanes[size_t(p_lane)];
	if (l.closed) {
		int64_t r = p_s % l.length;
		return r < 0 ? r + l.length : r;
	}
	return std::clamp<int64_t>(p_s, 0, l.length);
}

int LaneGraph::vertex_at(int p_lane, int64_t p_s) const {
	const Lane &l = lanes[size_t(p_lane)];
	int64_t s = wrap(p_lane, p_s);
	auto it = std::upper_bound(l.cum.begin(), l.cum.end(), s);
	int v = int(it - l.cum.begin()) - 1;
	int last = l.closed ? l.vertices() - 1 : l.vertices() - 2;
	return std::clamp(v, 0, last);
}

int32_t LaneGraph::limit_at(int p_lane, int64_t p_s) const {
	const Lane &l = lanes[size_t(p_lane)];
	int v = vertex_at(p_lane, p_s);
	int w = (v + 1) % l.vertices();
	return std::min(l.limit[size_t(v)], l.limit[size_t(w)]);
}

int64_t LaneGraph::map_s(int p_from, int64_t p_s, int p_to) const {
	if (p_from == p_to) {
		return p_s;
	}
	const Lane &a = lanes[size_t(p_from)];
	const Lane &b = lanes[size_t(p_to)];
	int64_t s = wrap(p_from, p_s);
	int v = vertex_at(p_from, s);
	int64_t seg_a = a.cum[size_t(v) + 1] - a.cum[size_t(v)];
	int64_t into = s - a.cum[size_t(v)];
	auto onto = [&](int p_bv) -> int64_t {
		if (p_bv < 0 || p_bv + 1 >= int(b.cum.size())) {
			return -1;
		}
		int64_t seg_b = b.cum[size_t(p_bv) + 1] - b.cum[size_t(p_bv)];
		return b.cum[size_t(p_bv)] + into * seg_b / std::max<int64_t>(seg_a, 1);
	};
	// Lanes of one carriageway share their vertices (adjacent or not).
	if (a.inner == p_to || a.outer == p_to || (a.road < 0 && b.road < 0 && a.dir != 0 && a.dir == b.dir && a.vertices() == b.vertices())) {
		return onto(v);
	}
	for (const Attach &at : a.attaches) {
		if (at.lane == p_to && v >= at.ramp_v0 && v < at.ramp_v0 + at.count - 1) {
			return onto(int((at.lane_v0 + v - at.ramp_v0) % std::max(b.vertices(), 1)));
		}
	}
	for (const Attach &at : b.attaches) {
		if (at.lane != p_from) {
			continue;
		}
		int off = v - at.lane_v0;
		if (a.closed) {
			off = (off % a.vertices() + a.vertices()) % a.vertices();
		}
		if (off >= 0 && off < at.count - 1) {
			return onto(at.ramp_v0 + off);
		}
	}
	return -1;
}

void LaneGraph::point(int p_lane, int64_t p_s, double &r_x, double &r_y, double &r_z, double &r_dx, double &r_dz) const {
	const Lane &l = lanes[size_t(p_lane)];
	int64_t s = wrap(p_lane, p_s);
	int v = vertex_at(p_lane, s);
	int w = (v + 1) % l.vertices();
	double seg = double(l.cum[size_t(v) + 1] - l.cum[size_t(v)]);
	double t = std::clamp(double(s - l.cum[size_t(v)]) / std::max(seg, 1.0), 0.0, 1.0);
	r_x = l.x[size_t(v)] + (l.x[size_t(w)] - l.x[size_t(v)]) * t;
	r_y = l.y[size_t(v)] + (l.y[size_t(w)] - l.y[size_t(v)]) * t;
	r_z = l.z[size_t(v)] + (l.z[size_t(w)] - l.z[size_t(v)]) * t;
	double dx = l.x[size_t(w)] - l.x[size_t(v)], dz = l.z[size_t(w)] - l.z[size_t(v)];
	double len = std::sqrt(dx * dx + dz * dz);
	r_dx = len > 1e-9 ? dx / len : 0.0;
	r_dz = len > 1e-9 ? dz / len : 1.0;
}

LanePos LaneGraph::locate(double p_x, double p_y, double p_z) const {
	LanePos best;
	auto it = _cells.find(_cell_key(int(std::floor(p_x / CELL_M)), int(std::floor(p_z / CELL_M))));
	if (it == _cells.end()) {
		return best;
	}
	double best_score = 1e30;
	for (const auto &[li, v] : it->second) {
		const Lane &l = lanes[size_t(li)];
		int w = (v + 1) % l.vertices();
		double ax = l.x[size_t(v)], az = l.z[size_t(v)];
		double sx = l.x[size_t(w)] - ax, sz = l.z[size_t(w)] - az;
		double len2 = std::max(sx * sx + sz * sz, 1e-9);
		double t = std::clamp(((p_x - ax) * sx + (p_z - az) * sz) / len2, 0.0, 1.0);
		double qx = ax + sx * t, qz = az + sz * t;
		double qy = l.y[size_t(v)] + (l.y[size_t(w)] - l.y[size_t(v)]) * t;
		double dist = std::hypot(p_x - qx, p_z - qz);
		double dy = std::abs(p_y - qy);
		if (dist > 8.0 || dy > 3.0) {
			continue;
		}
		double score = dist + 3.0 * std::max(0.0, dy - 1.0);
		if (score < best_score) {
			best_score = score;
			double len = std::sqrt(len2);
			// The driver's left: up x forward = (fz, 0, -fx).
			double lateral = ((p_x - qx) * (sz / len) - (p_z - qz) * (sx / len));
			int64_t seg = l.cum[size_t(v) + 1] - l.cum[size_t(v)];
			best = { li, l.cum[size_t(v)] + int64_t(std::llround(double(seg) * t)), lateral, dist };
		}
	}
	return best;
}

LanePos LaneGraph::project_near(int p_lane, int64_t p_s_hint, int64_t p_range, double p_x, double p_z) const {
	LanePos best;
	const Lane &l = lanes[size_t(p_lane)];
	int n = l.vertices();
	int segs = l.closed ? n : n - 1;
	int centre = vertex_at(p_lane, p_s_hint);
	int64_t seg_len = std::max<int64_t>(l.length / std::max(segs, 1), 1);
	int reach = int(std::min<int64_t>(p_range / seg_len + 2, segs));
	for (int k = -reach; k <= reach; k++) {
		int v = centre + k;
		if (l.closed) {
			v = ((v % n) + n) % n;
		} else if (v < 0 || v >= segs) {
			continue;
		}
		int w = (v + 1) % n;
		double ax = l.x[size_t(v)], az = l.z[size_t(v)];
		double sx = l.x[size_t(w)] - ax, sz = l.z[size_t(w)] - az;
		double len2 = std::max(sx * sx + sz * sz, 1e-9);
		double t = std::clamp(((p_x - ax) * sx + (p_z - az) * sz) / len2, 0.0, 1.0);
		double qx = ax + sx * t, qz = az + sz * t;
		double dist = std::hypot(p_x - qx, p_z - qz);
		if (dist < best.dist) {
			double len = std::sqrt(len2);
			int64_t seg = l.cum[size_t(v) + 1] - l.cum[size_t(v)];
			best = { p_lane, l.cum[size_t(v)] + int64_t(std::llround(double(seg) * t)), (p_x - qx) * (sz / len) - (p_z - qz) * (sx / len), dist };
		}
	}
	return best;
}

} // namespace noss::traffic
