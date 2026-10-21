#include "traffic/traffic_sim.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace noss::traffic {

namespace {

constexpr int64_t KEEP_RIGHT = 300; // mm/s² nudge towards the outer lanes
constexpr int64_t CHANGE_THRESHOLD = 250; // mm/s² a lane change must gain
constexpr int64_t MUST = 4000; // mm/s²: changes that have to happen (an exit, a closure, a truck)
constexpr int64_t CLOSURE_SEE = 400000; // mm: a closure this close ahead makes cars move over
constexpr int64_t EXIT_GIVE_UP = 150000; // mm before the exit: not in the outer lane by then, carry on
constexpr int64_t EXIT_SIGNAL = 300000; // mm before the exit: signal

int64_t i64(int32_t p_v) {
	return int64_t(p_v);
}

} // namespace

bool TrafficSim::setup(const GraphInput &p_graph, const std::vector<TypeSpec> &p_types, uint64_t p_seed, int p_count, double p_exit_share, std::string *r_error) {
	if (!graph.build(p_graph, r_error)) {
		return false;
	}
	if (p_types.empty()) {
		if (r_error) {
			*r_error = "No traffic types";
		}
		return false;
	}
	types = p_types;
	exit_share = p_exit_share;
	st = State();
	_events.clear();
	_ring.assign(RING, State());
	_sums.assign(RING, 0);
	_sum_ticks.assign(RING, UINT32_MAX);
	_occ.assign(graph.lanes.size(), {});
	branch_list.clear();
	_entries.clear();
	_first_lane.assign(2, -1);
	std::vector<int> main_lanes;
	for (int l = 0; l < int(graph.lanes.size()); l++) {
		const Lane &lane = graph.lanes[size_t(l)];
		for (int b = 0; b < int(lane.branches.size()); b++) {
			branch_list.push_back({ l, b });
		}
		if (lane.portal_out >= 0) {
			_entries.push_back(l);
		}
		if (lane.road < 0 && lane.closed) {
			main_lanes.push_back(l);
			if (lane.index == 0) {
				_first_lane[lane.dir > 0 ? 0 : 1] = l;
			}
		}
	}
	// Each carriageway loses about exit_share of its cars a lap, spread over its exits.
	_exit_p.assign(branch_list.size(), 0.0);
	for (int side = 0; side < 2; side++) {
		int first = _first_lane[size_t(side)];
		if (first < 0) {
			continue;
		}
		int n = int(graph.lanes[size_t(first)].branches.size());
		for (size_t g = 0; g < branch_list.size(); g++) {
			if (branch_list[g].first == first) {
				_exit_p[g] = std::min(0.9, exit_share / std::max(n, 1));
			}
		}
	}
	if (main_lanes.empty()) {
		if (r_error) {
			*r_error = "No main lanes";
		}
		return false;
	}
	// The cars: type, colour and desired speed from each car's own stream; a lane each.
	int total_weight = 0;
	for (const TypeSpec &t : types) {
		total_weight += std::max(t.weight, 0);
	}
	st.cars.resize(size_t(std::max(p_count, 0)));
	for (int i = 0; i < int(st.cars.size()); i++) {
		Car &c = st.cars[size_t(i)];
		c.id = uint16_t(i);
		c.rng.seed(p_seed * 0x9E3779B97F4A7C15ULL + uint64_t(i), uint64_t(i) + 1);
		int pick = int(c.rng.below(uint32_t(std::max(total_weight, 1))));
		for (int t = 0; t < int(types.size()); t++) {
			pick -= std::max(types[size_t(t)].weight, 0);
			if (pick < 0) {
				c.type = uint8_t(t);
				break;
			}
		}
		const TypeSpec &t = types[c.type];
		c.color = uint8_t(c.rng.below(uint32_t(std::max(t.colors, 1))));
		c.factor_q8 = c.rng.range(t.speed_min_q8, t.speed_max_q8);
		std::vector<int> allowed;
		for (int l : main_lanes) {
			if (t.lanes_max <= 0 || graph.lanes[size_t(l)].index < t.lanes_max) {
				allowed.push_back(l);
			}
		}
		if (allowed.empty()) {
			allowed = main_lanes;
		}
		c.lane = int16_t(allowed[c.rng.below(uint32_t(allowed.size()))]);
		c.flags = ACTIVE;
		if (!_entries.empty() && double(c.rng.below(10000)) < exit_share * 0.4 * 10000.0) {
			c.flags = AWAY;
			c.away_until = uint32_t(c.rng.range(0, 60 * TICK_HZ));
			c.lane = -1;
		}
	}
	// Spread each lane's cars evenly round it, a little jitter each; too many for a lane go away.
	for (int l : main_lanes) {
		std::vector<int> on;
		for (int i = 0; i < int(st.cars.size()); i++) {
			if (st.cars[size_t(i)].lane == l) {
				on.push_back(i);
			}
		}
		if (on.empty()) {
			continue;
		}
		int64_t length = graph.lanes[size_t(l)].length;
		int64_t spacing = length / int64_t(on.size());
		for (int k = 0; k < int(on.size()); k++) {
			Car &c = st.cars[size_t(on[size_t(k)])];
			const TypeSpec &t = types[c.type];
			if (spacing < i64(t.length_mm) + i64(t.gap_mm) * 2) {
				c.flags = AWAY;
				c.lane = -1;
				c.away_until = uint32_t(c.rng.range(0, 120 * TICK_HZ));
				continue;
			}
			int64_t jitter = spacing / 4 > 0 ? int64_t(c.rng.below(uint32_t(spacing / 4))) : 0;
			c.s = int32_t(graph.wrap(l, int64_t(k) * spacing + jitter));
			c.v = int32_t(_desired(c) * 9 / 10);
		}
	}
	_record();
	return true;
}

int TrafficSim::active() const {
	int n = 0;
	for (const Car &c : st.cars) {
		n += (c.flags & ACTIVE) ? 1 : 0;
	}
	return n;
}

int TrafficSim::away() const {
	int n = 0;
	for (const Car &c : st.cars) {
		n += (c.flags & AWAY) ? 1 : 0;
	}
	return n;
}

// --- stepping ------------------------------------------------------------------------------

void TrafficSim::step() {
	uint32_t t = st.tick;
	_ring[t % RING] = st;
	_apply_events(t);
	_reenter();
	_occupancy();
	std::vector<int64_t> v_new(st.cars.size(), 0);
	std::vector<int64_t> room(st.cars.size(), LOOK_AHEAD);
	std::vector<int64_t> room_v(st.cars.size(), 0);
	for (size_t i = 0; i < st.cars.size(); i++) {
		const Car &c = st.cars[i];
		if (!(c.flags & ACTIVE) || (c.flags & WRECK)) {
			continue;
		}
		int64_t gap = 0, lead_v = 0;
		bool has = _ahead(c.lane, c.s, int(i), gap, lead_v);
		int64_t acc = _accel(c, c.lane, c.s, gap, lead_v, has);
		if (has) {
			room[i] = gap;
			room_v[i] = lead_v;
		}
		// Moving over: also mind what's ahead in the lane it's leaving, for the first half.
		if (c.lc_from >= 0 && c.lc < LC_TICKS / 2) {
			int64_t s_from = graph.map_s(c.lane, c.s, c.lc_from);
			if (s_from >= 0 && _ahead(c.lc_from, s_from, int(i), gap, lead_v)) {
				acc = std::min(acc, _accel(c, c.lc_from, s_from, gap, lead_v, true));
				if (gap < room[i]) {
					room[i] = gap;
					room_v[i] = lead_v;
				}
			}
		}
		// Taking an exit: mind the cars already on the ramp.
		if (c.exit >= 0) {
			auto [bl, bi] = branch_list[size_t(c.exit)];
			const Branch &b = graph.lanes[size_t(bl)].branches[size_t(bi)];
			if (bl == c.lane && !_occ[size_t(b.ramp)].empty()) {
				int64_t d = b.at - c.s;
				if (d < 0 && graph.lanes[size_t(bl)].closed) {
					d += graph.lanes[size_t(bl)].length;
				}
				const Occ &first = _occ[size_t(b.ramp)].front();
				const Car &o = st.cars[size_t(first.car)];
				int64_t g = d + first.s - types[o.type].length_mm;
				if (d >= 0 && g < LOOK_AHEAD) {
					acc = std::min(acc, _accel(c, c.lane, c.s, g, (o.flags & WRECK) ? 0 : o.v, true));
					if (g < room[i]) {
						room[i] = g;
						room_v[i] = (o.flags & WRECK) ? 0 : o.v;
					}
				}
			}
		}
		v_new[i] = std::max<int64_t>(0, i64(c.v) + acc / TICK_HZ);
	}
	for (size_t i = 0; i < st.cars.size(); i++) {
		Car &c = st.cars[i];
		if ((c.flags & ACTIVE) && !(c.flags & WRECK)) {
			_plan_exit(c);
			_think(c, int(i));
		}
	}
	for (size_t i = 0; i < st.cars.size(); i++) {
		_move(st.cars[i], v_new[i], room[i], room_v[i]);
	}
	st.tick++;
	_record();
}

void TrafficSim::step_to(uint32_t p_tick) {
	while (st.tick < p_tick) {
		step();
	}
}

void TrafficSim::_occupancy() {
	for (auto &o : _occ) {
		o.clear();
	}
	for (size_t i = 0; i < st.cars.size(); i++) {
		const Car &c = st.cars[i];
		if (!(c.flags & ACTIVE) || c.lane < 0) {
			continue;
		}
		_occ[size_t(c.lane)].push_back({ c.s, int(i) });
		if (c.lc_from >= 0 && c.lc < LC_TICKS / 2) {
			int64_t s_from = graph.map_s(c.lane, c.s, c.lc_from);
			if (s_from >= 0) {
				_occ[size_t(c.lc_from)].push_back({ s_from, int(i) });
			}
		}
	}
	for (auto &o : _occ) {
		std::sort(o.begin(), o.end(), [](const Occ &a, const Occ &b) { return a.s < b.s || (a.s == b.s && a.car < b.car); });
	}
}

int64_t TrafficSim::_accel(const Car &p_c, int p_lane, int64_t p_s, int64_t p_gap, int64_t p_lead_v, bool p_has_lead) const {
	const TypeSpec &t = _type(p_c);
	Car at = p_c;
	at.lane = int16_t(p_lane);
	at.s = int32_t(p_s);
	int64_t v = p_c.v;
	int64_t v0 = std::max<int64_t>(_desired(at), 1000);
	int64_t r = (v << 16) / v0;
	int64_t r2 = (r * r) >> 16;
	int64_t r4 = (r2 * r2) >> 16;
	int64_t term = 65536 - r4;
	int64_t a = std::max<int32_t>(t.accel_mmps2, 100);
	if (p_has_lead) {
		int64_t b = std::max<int32_t>(t.decel_mmps2, 100);
		int64_t sqrt_ab = std::max<int64_t>(int64_t(isqrt64(uint64_t(a * b))), 1);
		int64_t dv = v - p_lead_v;
		int64_t s0 = t.gap_mm;
		int64_t s_star = s0 + v * t.headway_ms / 1000 + (v * dv) / (2 * sqrt_ab);
		s_star = std::max(s_star, s0);
		int64_t g = std::max<int64_t>(p_gap, 100);
		int64_t q = std::min<int64_t>((s_star << 16) / g, int64_t(1) << 26);
		term -= (q * q) >> 16;
	}
	int64_t acc = (a * term) >> 16;
	return std::clamp<int64_t>(acc, -MAX_DECEL, a);
}

int64_t TrafficSim::_desired(const Car &p_c) const {
	if (p_c.lane < 0) {
		return 0;
	}
	int64_t lim = graph.limit_at(p_c.lane, p_c.s);
	int64_t v0 = lim * p_c.factor_q8 >> 8;
	const Lane &lane = graph.lanes[size_t(p_c.lane)];
	// On an acceleration lane: up to the speed of the road it joins.
	if (lane.merge_into >= 0) {
		v0 = std::max(v0, i64(graph.lanes[size_t(lane.merge_into)].limit[0]) * 9 / 10);
	}
	if (p_c.exit >= 0) { // slowing for the ramp ahead
		auto [bl, bi] = branch_list[size_t(p_c.exit)];
		const Lane &bl_lane = graph.lanes[size_t(bl)];
		int64_t s0 = p_c.lane == bl ? p_c.s : graph.map_s(p_c.lane, p_c.s, bl);
		if (s0 >= 0) {
			int64_t d = bl_lane.branches[size_t(bi)].at - s0;
			if (bl_lane.closed && d < 0) {
				d += bl_lane.length;
			}
			if (d >= 0 && d < 800000) {
				int64_t ramp_v = graph.lanes[size_t(bl_lane.branches[size_t(bi)].ramp)].limit[0];
				v0 = std::min(v0, int64_t(isqrt64(uint64_t(ramp_v * ramp_v + 2 * PLAN_DECEL_MMPS2 * d))));
			}
		}
	}
	return std::max<int64_t>(v0, 2000);
}

bool TrafficSim::_ahead(int p_lane, int64_t p_s, int p_self, int64_t &r_gap, int64_t &r_v) const {
	const Lane &lane = graph.lanes[size_t(p_lane)];
	const std::vector<Occ> &occ = _occ[size_t(p_lane)];
	r_gap = LOOK_AHEAD;
	r_v = 0;
	bool found = false;
	int self = p_self;
	auto it = std::upper_bound(occ.begin(), occ.end(), p_s, [](int64_t s, const Occ &o) { return s < o.s; });
	// Cars level with this one: the one with the higher index counts as ahead.
	auto start = std::lower_bound(occ.begin(), occ.end(), p_s, [](const Occ &o, int64_t s) { return o.s < s; });
	for (auto j = start; j != it; ++j) {
		if (j->car > self) {
			const Car &o = st.cars[size_t(j->car)];
			r_gap = -i64(types[o.type].length_mm);
			r_v = (o.flags & WRECK) ? 0 : o.v;
			return true;
		}
	}
	size_t n = occ.size();
	for (size_t k = 0; k < n; k++) {
		size_t idx = size_t(it - occ.begin()) + k;
		int64_t wrap = 0;
		if (idx >= n) {
			if (!lane.closed) {
				break;
			}
			idx -= n;
			wrap = lane.length;
		}
		const Occ &e = occ[idx];
		if (e.car == self) {
			continue;
		}
		int64_t d = e.s + wrap - p_s;
		if (d > LOOK_AHEAD || d < 0) {
			break;
		}
		const Car &o = st.cars[size_t(e.car)];
		r_gap = d - types[o.type].length_mm;
		r_v = (o.flags & WRECK) ? 0 : o.v;
		found = true;
		break;
	}
	for (const Closure &cl : st.closures) {
		if (cl.lane != p_lane) {
			continue;
		}
		int64_t d = cl.from - p_s;
		if (lane.closed && d < 0 && p_s > cl.to) {
			d += lane.length;
		}
		if (p_s >= cl.from && p_s <= cl.to) {
			d = 0; // inside it: stop
		}
		if (d >= 0 && d < r_gap) {
			r_gap = d;
			r_v = 0;
			found = true;
		}
	}
	if (!lane.closed && lane.merge_into >= 0) {
		int64_t d = lane.length - p_s;
		if (d < r_gap) {
			r_gap = d;
			r_v = 0;
			found = true;
		}
	}
	return found;
}

bool TrafficSim::_behind(int p_lane, int64_t p_s, int p_self, int64_t p_length, int &r_car, int64_t &r_gap) const {
	const Lane &lane = graph.lanes[size_t(p_lane)];
	const std::vector<Occ> &occ = _occ[size_t(p_lane)];
	size_t n = occ.size();
	auto it = std::lower_bound(occ.begin(), occ.end(), p_s, [](const Occ &o, int64_t s) { return o.s < s; });
	size_t first = size_t(it - occ.begin());
	for (size_t k = 1; k <= n; k++) {
		int64_t idx = int64_t(first) - int64_t(k);
		int64_t wrap = 0;
		if (idx < 0) {
			if (!lane.closed) {
				break;
			}
			idx += int64_t(n);
			wrap = lane.length;
		}
		const Occ &e = occ[size_t(idx)];
		if (e.car == p_self) {
			continue;
		}
		int64_t d = p_s + wrap - e.s;
		if (d > LOOK_AHEAD || d < 0) {
			break;
		}
		r_car = e.car;
		r_gap = d - p_length;
		return true;
	}
	return false;
}

bool TrafficSim::closed_ahead(int p_lane, int64_t p_s, int64_t p_ahead) const {
	if (p_lane < 0 || p_lane >= int(graph.lanes.size())) {
		return false;
	}
	const Lane &l = graph.lanes[size_t(p_lane)];
	for (const Closure &cl : st.closures) {
		if (cl.lane != p_lane || cl.soft) {
			continue;
		}
		int64_t from = cl.from - p_s;
		int64_t to = cl.to - p_s;
		if (l.closed && l.length > 0) {
			// The lap of the loop where its end is just ahead (or where p_s is inside it).
			int64_t k = to >= 0 ? to / l.length : -((-to + l.length - 1) / l.length);
			from -= k * l.length;
			to -= k * l.length;
		}
		if (to >= 0 && from <= p_ahead) {
			return true;
		}
	}
	return false;
}

bool TrafficSim::_closed_at(int p_lane, int64_t p_s) const {
	for (const Closure &cl : st.closures) {
		if (cl.lane == p_lane && p_s >= cl.from - 20000 && p_s <= cl.to) {
			return true;
		}
	}
	return false;
}

bool TrafficSim::_lane_ok(const Car &p_c, int p_lane) const {
	if (p_lane < 0) {
		return false;
	}
	const TypeSpec &t = _type(p_c);
	const Lane &l = graph.lanes[size_t(p_lane)];
	return t.lanes_max <= 0 || l.road >= 0 || l.index < t.lanes_max;
}

void TrafficSim::_occupy(int p_lane, int64_t p_s, int p_car) {
	std::vector<Occ> &occ = _occ[size_t(p_lane)];
	Occ e{ p_s, p_car };
	auto at = std::upper_bound(occ.begin(), occ.end(), e, [](const Occ &a, const Occ &b) { return a.s < b.s || (a.s == b.s && a.car < b.car); });
	occ.insert(at, e);
}

bool TrafficSim::_safe(const Car &p_c, int p_to, int64_t p_s_to, int64_t &r_acc_new, int64_t &r_follower_loss, int64_t p_follower_decel) const {
	const TypeSpec &t = _type(p_c);
	r_follower_loss = 0;
	if (_closed_at(p_to, p_s_to)) {
		return false;
	}
	int self = int(p_c.id);
	int64_t gap = 0, lead_v = 0;
	bool has = _ahead(p_to, p_s_to, self, gap, lead_v);
	if (has && gap < t.gap_mm / 2) {
		return false;
	}
	r_acc_new = _accel(p_c, p_to, p_s_to, gap, lead_v, has);
	int f = -1;
	int64_t f_gap = 0;
	if (_behind(p_to, p_s_to, self, t.length_mm, f, f_gap)) {
		const Car &fc = st.cars[size_t(f)];
		const TypeSpec &ft = _type(fc);
		if (f_gap < ft.gap_mm / 2) {
			return false;
		}
		int64_t acc_f_new = _accel(fc, p_to, fc.lane == p_to ? fc.s : p_s_to - t.length_mm - f_gap, f_gap, p_c.v, true);
		if (acc_f_new < -p_follower_decel) {
			return false;
		}
		int64_t g_old = 0, v_old = 0;
		bool has_old = _ahead(p_to, p_s_to - t.length_mm - f_gap, f, g_old, v_old);
		int64_t acc_f_old = _accel(fc, p_to, p_s_to - t.length_mm - f_gap, g_old, v_old, has_old);
		r_follower_loss = std::max<int64_t>(0, acc_f_old - acc_f_new);
	}
	return true;
}

int64_t TrafficSim::_carriageway_s(const Car &p_c) const {
	const Lane &l = graph.lanes[size_t(p_c.lane)];
	if (l.road >= 0 || l.dir == 0) {
		return -1;
	}
	int first = _first_lane[l.dir > 0 ? 0 : 1];
	return first < 0 ? -1 : graph.map_s(p_c.lane, p_c.s, first);
}

void TrafficSim::_plan_exit(Car &r_c) {
	if (r_c.exit >= 0 || types[r_c.type].patrol) {
		return;
	}
	const Lane &l = graph.lanes[size_t(r_c.lane)];
	if (l.road >= 0) {
		return;
	}
	int first = _first_lane[l.dir > 0 ? 0 : 1];
	if (first < 0) {
		return;
	}
	const Lane &f = graph.lanes[size_t(first)];
	int64_t s0 = _carriageway_s(r_c);
	if (s0 < 0 || f.branches.empty()) {
		return;
	}
	// The next exit ahead on this carriageway.
	int best = -1;
	int64_t best_d = 0;
	for (int b = 0; b < int(f.branches.size()); b++) {
		int64_t d = f.branches[size_t(b)].at - s0;
		if (d < 0) {
			d += f.length;
		}
		if (best < 0 || d < best_d) {
			best = b;
			best_d = d;
		}
	}
	if (best < 0 || best_d > EXIT_DECIDE) {
		return;
	}
	int global = -1;
	for (int g = 0; g < int(branch_list.size()); g++) {
		if (branch_list[size_t(g)].first == first && branch_list[size_t(g)].second == best) {
			global = g;
		}
	}
	if (global < 0 || r_c.decided == global) {
		return;
	}
	r_c.decided = int16_t(global);
	if (double(r_c.rng.below(10000)) < _exit_p[size_t(global)] * 10000.0) {
		r_c.exit = int16_t(global);
	}
}

void TrafficSim::_think(Car &r_c, int p_index) {
	(void)p_index;
	if (r_c.lc_from >= 0) {
		r_c.lc++;
		if (r_c.lc >= LC_TICKS) {
			r_c.lc_from = -1;
			r_c.lc = 0;
			r_c.signal = 0;
		}
		return;
	}
	const Lane &lane = graph.lanes[size_t(r_c.lane)];
	auto start_change = [&](int p_to, int64_t p_s_to, int p_signal) {
		r_c.lc_from = r_c.lane;
		r_c.lane = int16_t(p_to);
		r_c.s = int32_t(p_s_to);
		r_c.lc = 1;
		r_c.target = -1;
		r_c.signal = int8_t(p_signal);
		r_c.signal_ticks = 0;
		_occupy(p_to, p_s_to, int(r_c.id));
	};
	// Stuck (a closure, a wreck, the end of an acceleration lane): the car behind may have to
	// brake harder to let it in.
	int64_t follower_decel = r_c.v < 5000 && r_c.signal_ticks > 5 * TICK_HZ ? MAX_DECEL * 2 / 3 : SAFE_DECEL;
	// Off an acceleration lane: into the road as soon as there's room (signalling left).
	if (lane.merge_into >= 0) {
		int64_t s_main = graph.map_s(r_c.lane, r_c.s, lane.merge_into);
		if (s_main >= 0) {
			if (r_c.signal != 1) { // starts signalling now
				r_c.signal = 1;
				r_c.signal_ticks = 0;
			}
			int64_t acc = 0, loss = 0;
			if (r_c.signal_ticks >= SIGNAL_TICKS && _safe(r_c, lane.merge_into, s_main, acc, loss, follower_decel)) {
				start_change(lane.merge_into, s_main, 1);
			} else {
				r_c.signal_ticks = uint16_t(std::min<int>(r_c.signal_ticks + 1, 60000));
			}
		}
		return;
	}
	// Signalling for a lane: move once the signal has shown long enough and there's room.
	if (r_c.target >= 0) {
		r_c.signal_ticks++;
		if (r_c.signal_ticks >= SIGNAL_TICKS) {
			int64_t s_to = graph.map_s(r_c.lane, r_c.s, r_c.target);
			int64_t acc = 0, loss = 0;
			if (s_to >= 0 && _safe(r_c, r_c.target, s_to, acc, loss, follower_decel)) {
				start_change(r_c.target, s_to, r_c.signal);
			} else if (r_c.signal_ticks > SIGNAL_GIVE_UP && r_c.v > 5000) {
				r_c.target = -1;
				r_c.signal = 0;
				r_c.signal_ticks = 0;
			}
		}
		return;
	}
	// An exit coming up.
	bool must_out = false;
	if (r_c.exit >= 0 && lane.road < 0) {
		auto [bl, bi] = branch_list[size_t(r_c.exit)];
		const Lane &first = graph.lanes[size_t(bl)];
		int64_t s0 = _carriageway_s(r_c);
		int64_t d = s0 >= 0 ? first.branches[size_t(bi)].at - s0 : -1;
		if (d < 0 && first.closed) {
			d += first.length;
		}
		if (lane.index > 0) {
			if (d < EXIT_GIVE_UP) {
				r_c.exit = -1; // too late: carry on
			} else {
				must_out = true;
			}
		} else {
			r_c.signal = int8_t(d >= 0 && d < EXIT_SIGNAL ? -1 : 0);
		}
	}
	const TypeSpec &t = _type(r_c);
	bool truck_out = lane.road < 0 && t.lanes_max > 0 && lane.index >= t.lanes_max;
	int64_t gap = 0, lead_v = 0;
	bool has = _ahead(r_c.lane, r_c.s, int(r_c.id), gap, lead_v);
	bool closure = false;
	for (const Closure &cl : st.closures) {
		int64_t d = cl.from - r_c.s;
		if (cl.lane == r_c.lane && ((d >= -i64(t.length_mm) && d < CLOSURE_SEE) || (r_c.s >= cl.from && r_c.s <= cl.to))) {
			closure = true;
		}
	}
	bool urgent = must_out || truck_out || closure;
	if (!urgent && (int(r_c.id) + int(st.tick)) % DECIDE_EVERY != 0) {
		return;
	}
	if (lane.road >= 0) {
		return; // ramps have one lane
	}
	int64_t acc_cur = _accel(r_c, r_c.lane, r_c.s, gap, lead_v, has);
	int best = -1;
	int64_t best_gain = CHANGE_THRESHOLD;
	for (int side = 0; side < 2; side++) {
		int cand = side == 0 ? lane.outer : lane.inner;
		if (cand < 0 || (side == 1 && (!_lane_ok(r_c, cand) || must_out || truck_out))) {
			continue;
		}
		int64_t s_to = graph.map_s(r_c.lane, r_c.s, cand);
		int64_t acc_new = 0, loss = 0;
		if (s_to < 0 || !_safe(r_c, cand, s_to, acc_new, loss)) {
			continue;
		}
		int64_t gain = acc_new - acc_cur - (i64(t.politeness_q8) * loss >> 8) + (side == 0 ? KEEP_RIGHT : -KEEP_RIGHT);
		if (side == 0 && (must_out || truck_out)) {
			gain += MUST;
		}
		if (closure) {
			gain += MUST;
		}
		if (gain > best_gain) {
			best_gain = gain;
			best = cand;
		}
	}
	if (best >= 0) {
		r_c.target = int16_t(best);
		r_c.signal = int8_t(best == lane.inner ? 1 : -1);
		r_c.signal_ticks = 0;
	}
}

void TrafficSim::_move(Car &r_c, int64_t p_v_new, int64_t p_room, int64_t p_lead_v) {
	if (!(r_c.flags & ACTIVE)) {
		return;
	}
	if (r_c.flags & WRECK) {
		r_c.v = 0;
		r_c.acc = 0;
		return;
	}
	int64_t acc = (p_v_new - r_c.v) * TICK_HZ;
	r_c.acc = int32_t(acc);
	r_c.flags = uint8_t(acc < -1200 ? (r_c.flags | BRAKING) : (r_c.flags & ~BRAKING));
	int64_t old_s = r_c.s;
	int64_t ds = (r_c.v + p_v_new) / (2 * TICK_HZ);
	int64_t can = std::max<int64_t>(0, p_room - STOP_GAP);
	if (ds > can) { // never into what's ahead, whatever the braking it would take
		ds = can;
		p_v_new = std::min(p_v_new, std::max<int64_t>(p_lead_v, 0));
		acc = (p_v_new - r_c.v) * TICK_HZ;
		r_c.acc = int32_t(acc);
	}
	int64_t new_s = old_s + ds;
	r_c.v = int32_t(p_v_new);
	const Lane &lane = graph.lanes[size_t(r_c.lane)];
	auto crossed = [&](int64_t p_from, int64_t p_to, int64_t p_at, const Lane &p_lane) {
		if (p_to < p_lane.length || !p_lane.closed) {
			return p_from < p_at && p_at <= p_to;
		}
		return p_at > p_from || p_at <= p_to - p_lane.length;
	};
	if (r_c.exit >= 0) {
		auto [bl, bi] = branch_list[size_t(r_c.exit)];
		const Branch &b = graph.lanes[size_t(bl)].branches[size_t(bi)];
		if (bl == r_c.lane && crossed(old_s, new_s, b.at, lane)) {
			int64_t over = new_s - b.at;
			if (over < 0) {
				over += lane.length;
			}
			r_c.lane = int16_t(b.ramp);
			r_c.s = int32_t(std::min(over, graph.lanes[size_t(b.ramp)].length));
			r_c.exit = -1;
			r_c.signal = 0;
			r_c.signal_ticks = 0;
			r_c.target = -1;
			r_c.lc_from = -1;
			r_c.lc = 0;
			return;
		}
		if (bl != r_c.lane && lane.road < 0) {
			int64_t s0 = graph.map_s(r_c.lane, old_s, bl);
			int64_t s1 = graph.map_s(r_c.lane, graph.wrap(r_c.lane, new_s), bl);
			if (s0 >= 0 && s1 >= 0 && ((s0 < b.at && b.at <= s1) || (s1 < s0 && (b.at > s0 || b.at <= s1)))) {
				r_c.exit = -1; // missed it
			}
		}
	}
	// Past the exit it decided about: next lap it decides afresh.
	if (r_c.decided >= 0 && r_c.exit < 0 && lane.road < 0) {
		auto [bl, bi] = branch_list[size_t(r_c.decided)];
		const Branch &b = graph.lanes[size_t(bl)].branches[size_t(bi)];
		int64_t s0 = graph.map_s(r_c.lane, old_s, bl);
		int64_t s1 = graph.map_s(r_c.lane, graph.wrap(r_c.lane, new_s), bl);
		if (s0 >= 0 && s1 >= 0 && ((s0 < b.at && b.at <= s1) || (s1 < s0 && (b.at > s0 || b.at <= s1)))) {
			r_c.decided = -1;
		}
	}
	if (lane.closed) {
		r_c.s = int32_t(graph.wrap(r_c.lane, new_s));
		return;
	}
	if (new_s >= lane.length) {
		if (lane.portal_in >= 0) {
			r_c.flags = AWAY;
			r_c.away_until = st.tick + uint32_t(r_c.rng.range(40 * TICK_HZ, 200 * TICK_HZ));
			r_c.lane = -1;
			r_c.lc_from = -1;
			r_c.lc = 0;
			r_c.v = 0;
			r_c.signal = 0;
			r_c.target = -1;
			return;
		}
		r_c.s = int32_t(lane.length - 1);
		r_c.v = 0;
		return;
	}
	r_c.s = int32_t(new_s);
}

void TrafficSim::_reenter() {
	if (_entries.empty()) {
		return;
	}
	for (Car &c : st.cars) {
		if (!(c.flags & AWAY) || c.away_until > st.tick) {
			continue;
		}
		int lane = _entries[c.rng.below(uint32_t(_entries.size()))];
		bool clear = true;
		for (const Car &o : st.cars) {
			if ((o.flags & ACTIVE) && o.lane == lane && o.s < ENTRY_CLEAR) {
				clear = false;
				break;
			}
		}
		if (!clear) {
			c.away_until = st.tick + TICK_HZ;
			continue;
		}
		c.flags = ACTIVE;
		c.lane = int16_t(lane);
		c.s = 0;
		c.v = int32_t(std::min<int64_t>(graph.lanes[size_t(lane)].limit[0], 16000));
		c.exit = -1;
		c.decided = -1;
		c.target = -1;
		c.signal = 0;
		c.signal_ticks = 0;
		c.lc_from = -1;
		c.lc = 0;
	}
}

// --- events, rollback, checksums -------------------------------------------------------------

bool TrafficSim::schedule(const std::vector<Event> &p_events) {
	uint32_t earliest = UINT32_MAX;
	for (const Event &e : p_events) {
		if (e.tick + RING <= st.tick) {
			return false; // too old to replay
		}
		bool known = false;
		for (const Event &k : _events) {
			if (k.tick == e.tick && k.seq == e.seq) {
				known = true;
				break;
			}
		}
		if (known) {
			continue;
		}
		auto at = std::upper_bound(_events.begin(), _events.end(), e, [](const Event &a, const Event &b) {
			return a.tick < b.tick || (a.tick == b.tick && a.seq < b.seq);
		});
		_events.insert(at, e);
		earliest = std::min(earliest, e.tick);
	}
	if (earliest < st.tick) {
		uint32_t now = st.tick;
		const State &snap = _ring[earliest % RING];
		if (snap.tick != earliest) {
			return false;
		}
		st = snap;
		while (st.tick < now) {
			step();
		}
	}
	// Forget events the ring can no longer replay.
	while (!_events.empty() && _events.front().tick + RING < st.tick) {
		_events.erase(_events.begin());
	}
	return true;
}

void TrafficSim::_apply_events(uint32_t p_tick) {
	for (const Event &e : _events) {
		if (e.tick == p_tick) {
			_apply(e);
		} else if (e.tick > p_tick) {
			break;
		}
	}
}

void TrafficSim::_apply(const Event &p_e) {
	if (p_e.kind == EV_CLOSE) {
		st.closures.push_back({ p_e.car, p_e.lane, p_e.s, p_e.s + p_e.v, (p_e.bits & 1) != 0 });
		return;
	}
	if (p_e.kind == EV_OPEN) {
		st.closures.erase(std::remove_if(st.closures.begin(), st.closures.end(), [&](const Closure &c) { return c.id == p_e.car; }), st.closures.end());
		return;
	}
	if (p_e.car >= st.cars.size()) {
		return;
	}
	Car &c = st.cars[p_e.car];
	auto place = [&]() {
		if (p_e.lane >= 0 && p_e.lane < int(graph.lanes.size())) {
			c.lane = p_e.lane;
			c.s = int32_t(graph.wrap(p_e.lane, p_e.s));
			c.v = std::max(p_e.v, 0);
			c.lc_from = (p_e.lc_from >= 0 && p_e.lc_from < int(graph.lanes.size())) ? p_e.lc_from : int16_t(-1);
			c.lc = c.lc_from >= 0 ? p_e.lc : 0;
			c.target = -1;
			c.signal = 0;
			c.signal_ticks = 0;
			c.flags = uint8_t((c.flags | ACTIVE) & ~AWAY);
		}
	};
	switch (p_e.kind) {
		case EV_PROMOTE:
			c.flags |= SHADOW;
			break;
		case EV_DEMOTE:
			place();
			c.flags &= uint8_t(~SHADOW);
			break;
		case EV_RESHADOW:
			place();
			break;
		case EV_WRECK:
			place();
			c.v = 0;
			c.flags |= WRECK;
			break;
		case EV_TOW:
			c.flags = AWAY;
			c.lane = -1;
			c.lc_from = -1;
			c.lc = 0;
			c.v = 0;
			c.exit = -1;
			c.target = -1;
			c.signal = 0;
			c.away_until = p_e.tick + uint32_t(c.rng.range(30 * TICK_HZ, 90 * TICK_HZ));
			break;
		default:
			break;
	}
}

uint64_t TrafficSim::checksum() const {
	Fnv64 f;
	f.i64(st.tick);
	for (const Car &c : st.cars) {
		for (int64_t v : { int64_t(c.flags), int64_t(c.lane), int64_t(c.lc_from), int64_t(c.lc), int64_t(c.s), int64_t(c.v),
					 int64_t(c.signal), int64_t(c.target), int64_t(c.exit), int64_t(c.decided), int64_t(c.away_until), int64_t(c.signal_ticks) }) {
			f.i64(v);
		}
		f.i64(int64_t(c.rng.state));
	}
	for (const Closure &cl : st.closures) {
		f.i64(cl.id);
		f.i64(cl.lane);
		f.i64(cl.from);
		f.i64(cl.to);
		if (cl.soft) {
			f.i64(1);
		}
	}
	return f.h;
}

void TrafficSim::_record() {
	size_t i = st.tick % RING;
	_sums[i] = checksum();
	_sum_ticks[i] = st.tick;
}

bool TrafficSim::checksum_at(uint32_t p_tick, uint64_t &r_sum) const {
	size_t i = p_tick % RING;
	if (_sum_ticks.empty() || _sum_ticks[i] != p_tick) {
		return false;
	}
	r_sum = _sums[i];
	return true;
}

// --- full state ----------------------------------------------------------------------------

namespace {

template <typename T>
void put(std::vector<uint8_t> &r_out, T p_v) {
	uint8_t b[sizeof(T)];
	std::memcpy(b, &p_v, sizeof(T));
	r_out.insert(r_out.end(), b, b + sizeof(T));
}

template <typename T>
bool get(const std::vector<uint8_t> &p_in, size_t &r_at, T &r_v) {
	if (r_at + sizeof(T) > p_in.size()) {
		return false;
	}
	std::memcpy(&r_v, p_in.data() + r_at, sizeof(T));
	r_at += sizeof(T);
	return true;
}

constexpr uint32_t STATE_MAGIC = 0x3146544e; // "NTF1"

} // namespace

std::vector<uint8_t> TrafficSim::full_state() const {
	std::vector<uint8_t> out;
	put(out, STATE_MAGIC);
	put(out, st.tick);
	put(out, uint32_t(st.cars.size()));
	put(out, uint32_t(st.closures.size()));
	for (const Car &c : st.cars) {
		put(out, c.id);
		put(out, c.type);
		put(out, c.color);
		put(out, c.flags);
		put(out, c.signal);
		put(out, c.lane);
		put(out, c.lc_from);
		put(out, c.target);
		put(out, c.exit);
		put(out, c.decided);
		put(out, c.lc);
		put(out, c.signal_ticks);
		put(out, c.s);
		put(out, c.v);
		put(out, c.factor_q8);
		put(out, c.acc);
		put(out, c.away_until);
		put(out, c.rng.state);
		put(out, c.rng.inc);
	}
	for (const Closure &cl : st.closures) {
		put(out, cl.id);
		put(out, cl.lane);
		put(out, cl.from);
		put(out, cl.to);
		put(out, uint8_t(cl.soft ? 1 : 0));
	}
	return out;
}

bool TrafficSim::load_full_state(const std::vector<uint8_t> &p_bytes) {
	size_t at = 0;
	uint32_t magic = 0, cars = 0, closures = 0;
	State s;
	if (!get(p_bytes, at, magic) || magic != STATE_MAGIC || !get(p_bytes, at, s.tick) || !get(p_bytes, at, cars) || !get(p_bytes, at, closures)) {
		return false;
	}
	if (cars != st.cars.size() || closures > 4096) {
		return false;
	}
	s.cars.resize(cars);
	for (Car &c : s.cars) {
		bool ok = get(p_bytes, at, c.id) && get(p_bytes, at, c.type) && get(p_bytes, at, c.color) && get(p_bytes, at, c.flags) && get(p_bytes, at, c.signal) &&
				get(p_bytes, at, c.lane) && get(p_bytes, at, c.lc_from) && get(p_bytes, at, c.target) && get(p_bytes, at, c.exit) && get(p_bytes, at, c.decided) &&
				get(p_bytes, at, c.lc) && get(p_bytes, at, c.signal_ticks) && get(p_bytes, at, c.s) && get(p_bytes, at, c.v) && get(p_bytes, at, c.factor_q8) &&
				get(p_bytes, at, c.acc) && get(p_bytes, at, c.away_until) && get(p_bytes, at, c.rng.state) && get(p_bytes, at, c.rng.inc);
		int lanes = int(graph.lanes.size());
		if (!ok || c.type >= types.size() || c.lane >= lanes || c.lc_from >= lanes || c.target >= lanes || c.exit >= int(branch_list.size()) ||
				c.decided >= int(branch_list.size()) || ((c.flags & ACTIVE) && c.lane < 0)) {
			return false;
		}
	}
	s.closures.resize(closures);
	for (Closure &cl : s.closures) {
		uint8_t soft = 0;
		if (!get(p_bytes, at, cl.id) || !get(p_bytes, at, cl.lane) || !get(p_bytes, at, cl.from) || !get(p_bytes, at, cl.to) || !get(p_bytes, at, soft)) {
			return false;
		}
		cl.soft = soft != 0;
	}
	if (at != p_bytes.size()) {
		return false;
	}
	st = s;
	_ring.assign(RING, State());
	_sum_ticks.assign(RING, UINT32_MAX);
	while (!_events.empty() && _events.front().tick < st.tick) {
		_events.erase(_events.begin());
	}
	_record();
	return true;
}

// --- drawing -------------------------------------------------------------------------------

CarPose TrafficSim::pose(int p_car, double p_alpha) const {
	CarPose out;
	const Car &c = st.cars[size_t(p_car)];
	if (!(c.flags & ACTIVE) || c.lane < 0) {
		return out;
	}
	bool moving = !(c.flags & WRECK);
	int64_t s = c.s + (moving ? int64_t(std::llround(double(c.v) * p_alpha / TICK_HZ)) : 0);
	const Lane &lane = graph.lanes[size_t(c.lane)];
	if (!lane.closed) {
		s = std::min(s, lane.length);
	}
	graph.point(c.lane, s, out.x, out.y, out.z, out.dx, out.dz);
	if (c.lc_from >= 0) {
		int64_t s_from = graph.map_s(c.lane, s, c.lc_from);
		if (s_from >= 0) {
			CarPose from;
			graph.point(c.lc_from, s_from, from.x, from.y, from.z, from.dx, from.dz);
			double u = std::clamp((double(c.lc) + p_alpha) / LC_TICKS, 0.0, 1.0);
			double w = u * u * (3.0 - 2.0 * u);
			double dw = 6.0 * u * (1.0 - u) / LC_TICKS; // per tick
			double ox = out.x - from.x, oz = out.z - from.z;
			out.x = from.x + ox * w;
			out.y = from.y + (out.y - from.y) * w;
			out.z = from.z + oz * w;
			// Heading: along the lane plus the sideways drift.
			double along = std::max(double(c.v) / TICK_HZ / 1000.0, 0.5); // m per tick
			double hx = out.dx + ox * dw / along, hz = out.dz + oz * dw / along;
			double len = std::sqrt(hx * hx + hz * hz);
			out.dx = hx / len;
			out.dz = hz / len;
		}
	}
	return out;
}

} // namespace noss::traffic
