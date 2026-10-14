#include "traffic/lane_driver.h"

#include <algorithm>
#include <cmath>

namespace noss::traffic {

namespace {

constexpr double LANE_HALF = 1.8; // m: a car overlapping this far either side of a lane's line is in it

// What occupies `p_lane` near s: [s (m, centre), half length, speed, lateral].
struct Seen {
	double s, half_len, v, lateral, half_wid;
};

} // namespace

namespace {

// Follows `p_lane` (moving over from `p_from` at progress `p_u` while p_from >= 0) at up to `p_v0`
// m/s, minding what's ahead: the shared part of drive() and follow().
DriveOut drive_on(const TrafficSim &p_sim, int p_lane, int p_from, double p_u, LanePos p_here, double p_v0, const TypeSpec &p_spec,
		const DriveIn &p_in, const std::vector<Member> &p_members);

} // namespace

DriveOut drive(const TrafficSim &p_sim, const DriveIn &p_in, const std::vector<Member> &p_members) {
	DriveOut out;
	const LaneGraph &g = p_sim.graph;
	if (p_in.car < 0 || p_in.car >= p_sim.count()) {
		out.brake = 1.0;
		return out;
	}
	const Car &shadow = p_sim.st.cars[size_t(p_in.car)];
	if (!(shadow.flags & ACTIVE) || shadow.lane < 0) {
		out.brake = 1.0;
		return out;
	}
	const TypeSpec &t = p_sim.types[shadow.type];
	// Which lane to follow: the shadow's; while it moves over, from where to where.
	int lane = shadow.lane;
	int from = shadow.lc_from;
	LanePos here = g.project_near(lane, shadow.s - int64_t(t.length_mm / 2), 120000, p_in.x, p_in.z);
	if (here.lane < 0 || here.dist > 12.0) {
		// Too far from the shadow's lane: find any lane under it.
		here = g.locate(p_in.x, p_in.y, p_in.z);
		if (here.lane < 0) {
			out.brake = 1.0;
			return out;
		}
		lane = here.lane;
		from = -1;
	}
	out = drive_on(p_sim, lane, from, std::clamp(double(shadow.lc) / LC_TICKS, 0.0, 1.0), here, double(p_sim.desired(p_in.car)) / 1000.0, t, p_in, p_members);
	out.signal = shadow.signal;
	return out;
}

DriveOut follow(const TrafficSim &p_sim, int p_lane, int64_t p_s_hint, double p_v0, const DriveIn &p_in, const std::vector<Member> &p_members) {
	DriveOut out;
	if (p_lane < 0 || p_lane >= int(p_sim.graph.lanes.size())) {
		out.brake = 1.0;
		return out;
	}
	LanePos here = p_s_hint >= 0 ? p_sim.graph.project_near(p_lane, p_s_hint, 120000, p_in.x, p_in.z) : LanePos();
	if (here.lane < 0 || here.dist > 12.0) {
		LanePos any = p_sim.graph.locate(p_in.x, p_in.y, p_in.z);
		if (any.lane == p_lane) {
			here = any;
		} else if (here.lane < 0) {
			out.brake = 1.0;
			return out;
		}
	}
	TypeSpec spec;
	spec.accel_mmps2 = 2500;
	spec.decel_mmps2 = 3500;
	spec.headway_ms = 1200;
	spec.gap_mm = 3000;
	return drive_on(p_sim, p_lane, -1, 1.0, here, p_v0, spec, p_in, p_members);
}

namespace {

DriveOut drive_on(const TrafficSim &p_sim, int p_lane, int p_from, double p_u, LanePos p_here, double p_v0, const TypeSpec &p_spec,
		const DriveIn &p_in, const std::vector<Member> &p_members) {
	DriveOut out;
	const LaneGraph &g = p_sim.graph;
	const TypeSpec &t = p_spec;
	double v = std::max(p_in.speed, 0.0);
	int lane = p_lane;
	int from = p_from;
	LanePos here = p_here;
	double s = double(here.s) / 1000.0;
	out.lane = lane;
	out.s = here.s + int64_t(p_in.half_len * 1000.0);
	out.lateral = here.lateral;
	// What's in a lane near here: members, then lane-sim cars (not shadows: they're drawn as
	// physics cars, and not itself).
	auto occupants = [&](int p_lane, double p_s, std::vector<Seen> &r_seen) {
		for (const Member &m : p_members) {
			if (m.id == p_in.member || std::abs(m.y - p_in.y) > 3.0) {
				continue;
			}
			double dx = m.box.cx - p_in.x, dz = m.box.cz - p_in.z;
			if (dx * dx + dz * dz > 200.0 * 200.0) {
				continue;
			}
			LanePos at = g.project_near(p_lane, int64_t(p_s * 1000.0), 220000, m.box.cx, m.box.cz);
			if (at.lane < 0 || std::abs(at.lateral) > LANE_HALF + m.box.half_wid * 0.8) {
				continue;
			}
			r_seen.push_back({ double(at.s) / 1000.0, m.box.half_len, m.v, at.lateral, m.box.half_wid });
		}
		for (int i = 0; i < p_sim.count(); i++) {
			const Car &o = p_sim.st.cars[size_t(i)];
			if (i == p_in.car || !(o.flags & ACTIVE) || (o.flags & SHADOW)) {
				continue;
			}
			if (o.lane != p_lane && o.lc_from != p_lane) {
				continue;
			}
			int64_t os = o.lane == p_lane ? o.s : g.map_s(o.lane, o.s, p_lane);
			if (os < 0) {
				continue;
			}
			const TypeSpec &ot = p_sim.types[o.type];
			double centre = (double(os) - ot.length_mm / 2.0) / 1000.0;
			double d = centre - p_s;
			const Lane &l = g.lanes[size_t(p_lane)];
			if (l.closed) {
				double len = double(l.length) / 1000.0;
				d = std::fmod(d + len * 1.5, len) - len * 0.5;
			}
			if (std::abs(d) > 200.0) {
				continue;
			}
			r_seen.push_back({ p_s + d, ot.length_mm / 2000.0, (o.flags & WRECK) ? 0.0 : double(o.v) / 1000.0, 0.0, ot.width_mm / 2000.0 });
		}
	};
	// Moving over while something is beside it in the new lane: hold the old lane.
	double u = 1.0;
	if (from >= 0) {
		u = p_u;
		std::vector<Seen> beside;
		occupants(lane, s, beside);
		for (const Seen &o : beside) {
			if (std::abs(o.s - s) < o.half_len + p_in.half_len + 2.0) {
				out.blocked = true;
			}
		}
		if (out.blocked) {
			int64_t s_from = g.map_s(lane, here.s, from);
			if (s_from >= 0) {
				lane = from;
				s = double(s_from) / 1000.0;
				from = -1;
				u = 1.0;
			}
		}
	}
	// Steering: pure pursuit to a point ahead on the lane (between the lanes while moving over).
	double look = std::clamp(6.0 + 0.45 * v, 8.0, 40.0);
	int64_t ahead_s = int64_t((s + look) * 1000.0);
	double px, py, pz, dx, dz;
	g.point(lane, ahead_s, px, py, pz, dx, dz);
	if (from >= 0) {
		int64_t s_from = g.map_s(lane, ahead_s, from);
		if (s_from >= 0) {
			double qx, qy, qz, ex, ez;
			g.point(from, s_from, qx, qy, qz, ex, ez);
			double ul = std::clamp(u + look / std::max(v, 1.0) * TICK_HZ / LC_TICKS, 0.0, 1.0);
			double w = ul * ul * (3.0 - 2.0 * ul);
			px = qx + (px - qx) * w;
			pz = qz + (pz - qz) * w;
		}
	}
	double hx, hy, hz, hdx, hdz;
	g.point(lane, int64_t(s * 1000.0), hx, hy, hz, hdx, hdz);
	out.heading_error = std::atan2(p_in.fx * hdz - p_in.fz * hdx, p_in.fx * hdx + p_in.fz * hdz);
	double rx = px - p_in.x, rz = pz - p_in.z;
	double along = rx * p_in.fx + rz * p_in.fz;
	double left = rx * p_in.fz - rz * p_in.fx;
	double dist2 = std::max(along * along + left * left, 1.0);
	double kappa = 2.0 * left / dist2;
	out.steer = std::clamp(-std::atan(p_in.wheelbase * kappa) / std::max(p_in.max_steer, 0.05), -1.0, 1.0);
	// Speed: the IDM against what's ahead in the lane.
	std::vector<Seen> seen;
	occupants(lane, s, seen);
	double gap = 1e9, lead_v = 0.0;
	for (const Seen &o : seen) {
		double d = o.s - s;
		if (d <= 0.0) {
			continue;
		}
		double bumper = d - o.half_len - p_in.half_len;
		if (bumper < gap) {
			gap = bumper;
			lead_v = o.v;
		}
	}
	for (const Closure &cl : p_sim.st.closures) {
		if (cl.lane != lane) {
			continue;
		}
		double d = double(cl.from) / 1000.0 - s - p_in.half_len;
		if (d > -p_in.half_len * 2.0 && d < gap) {
			gap = std::max(d, 0.0);
			lead_v = 0.0;
		}
	}
	out.gap = gap;
	double v0 = std::max(p_v0, 1.0);
	double a = t.accel_mmps2 / 1000.0;
	double b = t.decel_mmps2 / 1000.0;
	double r = v / v0;
	double acc = a * (1.0 - r * r * r * r);
	if (gap < 300.0) {
		double s0 = t.gap_mm / 1000.0;
		double s_star = std::max(s0, s0 + v * t.headway_ms / 1000.0 + v * (v - lead_v) / (2.0 * std::sqrt(a * b)));
		double q = s_star / std::max(gap, 0.1);
		acc -= a * q * q;
	}
	acc = std::clamp(acc, -9.0, a);
	if (acc > 0.05) {
		out.throttle = std::clamp(0.15 + acc / std::max(a, 0.1) * 0.85, 0.0, 1.0);
	} else if (acc < -0.4) {
		out.brake = std::clamp(-acc / 8.0, 0.0, 1.0);
	}
	if (gap < 1.5 && v > lead_v) {
		out.brake = 1.0;
		out.throttle = 0.0;
	}
	if (v < 0.6 && out.throttle < 0.05) { // stopped: hold it still (the brake would select reverse)
		out.brake = 0.0;
		out.handbrake = 1.0;
	}
	out.lead_v = lead_v;
	return out;
}

} // namespace

} // namespace noss::traffic
