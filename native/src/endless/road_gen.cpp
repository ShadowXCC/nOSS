#include "endless/road_gen.h"

#include <algorithm>
#include <limits>

namespace noss::endless {

namespace {

constexpr int64_t CONE = 894784853; // 75 degrees as a binary angle
constexpr int64_t CONE_SOFT = 536870912; // 45 degrees: bends lean back toward the axis past this
// Height follows the mean ground this far ahead (samples), aiming to reach it within REACH.
constexpr int HEIGHT_FROM = 10;
constexpr int HEIGHT_TO = 110;
constexpr int64_t HEIGHT_REACH = 60;
// Bends look this far ahead (mm) to pick their side.
constexpr int64_t PROBE_MM = 150000;
constexpr int64_t SEA_MIN_UM = 4000000; // the road stays this far above the sea
// A bridge starts where the road runs over BRIDGE_ON above the ground for BRIDGE_LOOK samples
// and ends where it's back within BRIDGE_OFF.
constexpr int64_t BRIDGE_ON_UM = 9000000;
constexpr int64_t BRIDGE_OFF_UM = 4000000;
constexpr int BRIDGE_LOOK = 15;
// A guard rail where the ground 9 m out falls this far below the road, and this many samples
// either side of it.
constexpr int64_t DROP_UM = 3000000;
constexpr int BARRIER_REACH = 4;
// Traffic: sideways acceleration in bends, pulling away and braking, mm/s^2.
constexpr int64_t LAT_MM = 1800;
constexpr int64_t ACCEL_MM = 800;
constexpr int64_t BRAKE_MM = 1200;
constexpr int64_t NO_LIMIT = std::numeric_limits<int64_t>::max() / 4;

int64_t clamp64(int64_t p_v, int64_t p_lo, int64_t p_hi) {
	return std::min(std::max(p_v, p_lo), p_hi);
}

const BiomeStyle &style_of(const Sample &p_s) {
	return biome_style(BiomeMix{ p_s.biome, p_s.biome2, p_s.blend }.dominant());
}

} // namespace

void RoadGen::setup(uint64_t p_seed, int p_start_biome) {
	_seed = p_seed;
	_start = std::clamp(p_start_biome, 0, int(BIOME_COUNT) - 1);
	_land.setup(p_seed, _start);
	_path = PathState();
	_path.heading = _land.axis_heading();
	Pcg32 rng(p_seed, 0x40AD);
	_path.rng_state = rng.state;
	_path.rng_inc = rng.inc;
	_height = HeightState();
	_finish = FinishState();
	_finish.v2_up = _finish.v2_down = NO_LIMIT;
	_buf.clear();
	_path_marks.clear();
	_height_marks.clear();
	_checkpoints.clear();
	_window_ready = false;
	_last = Sample();
}

void RoadGen::_restore(int64_t p_k) {
	const Checkpoint &c = _checkpoints[size_t(p_k)];
	_path = c.path;
	_height = c.height;
	_finish = c.finish;
	_buf.clear();
	_path_marks.clear();
	_height_marks.clear();
	_window_ready = false;
}

void RoadGen::_plan() {
	PathState &p = _path;
	Pcg32 rng;
	rng.state = p.rng_state;
	rng.inc = p.rng_inc;
	int64_t xm = floor_div(p.x, 1000), zm = floor_div(p.z, 1000);
	const BiomeStyle &st = biome_style(_land.biome_at(_land.axis_mm(xm, zm)).dominant());
	int64_t k0 = p.curve;
	int64_t dev = p.heading - _land.axis_heading();
	int32_t roll = int32_t(rng.below(1000));
	int64_t kt = 0;
	int32_t hold, ramp;
	if (roll < st.straight) {
		hold = rng.range(st.straight_m[0], st.straight_m[1]) / 2;
		ramp = rng.range(20, 40);
	} else {
		const int32_t *band = roll < st.straight + st.gentle ? st.r_gentle : roll < st.straight + st.gentle + st.medium ? st.r_medium : st.r_tight;
		int32_t radius = rng.range(band[0], band[1]);
		kt = STEP_CURVE / radius;
		int64_t arc = int64_t(rng.range(st.arc_deg[0], st.arc_deg[1])) * TURN / 360;
		hold = int32_t(std::max<int64_t>(arc / kt, 1));
		// Mostly the way the ground stays nearer the level here (along valleys, round hills).
		auto rise = [&](int64_t p_sign) {
			int64_t h = p.heading + p_sign * arc / 2;
			int64_t dh = _land.ground_mm(xm + mul_q30(PROBE_MM, sin_q30(h)), zm + mul_q30(PROBE_MM, cos_q30(h))) - _land.ground_mm(xm, zm);
			return dh < 0 ? -dh : dh;
		};
		bool left = rng.below(100) < 75 ? rise(1) <= rise(-1) : rng.below(2) == 0;
		if ((dev > CONE_SOFT || dev < -CONE_SOFT) && rng.below(100) < 80) {
			left = dev < 0; // lean back toward the axis
		}
		if (!left) {
			kt = -kt;
		}
		ramp = std::clamp(20 + radius / 20, 20, RAMP_MAX);
	}
	// The heading at the end of this piece plus the longest ramp back to straight after it must
	// stay within the cone (so whatever comes next can always straighten up in time).
	auto fits = [&](int64_t p_kt, int32_t p_hold) {
		int64_t d = dev;
		for (int32_t i = 1; i <= ramp; i++) {
			d += k0 + (p_kt - k0) * i / ramp;
		}
		d += p_kt * p_hold + p_kt * (RAMP_MAX + 1) / 2;
		return d <= CONE && d >= -CONE;
	};
	if (!fits(kt, hold)) {
		if (kt != 0 && fits(kt, 0)) {
			int32_t lo = 0, hi = hold;
			while (lo < hi) {
				int32_t mid = (lo + hi + 1) / 2;
				if (fits(kt, mid)) {
					lo = mid;
				} else {
					hi = mid - 1;
				}
			}
			hold = lo;
		} else {
			kt = 0;
			hold = rng.range(st.straight_m[0], st.straight_m[1]) / 2;
		}
	}
	p.k0 = k0;
	p.kt = kt;
	p.n_ramp = ramp;
	p.i_ramp = 0;
	p.n_hold = hold;
	p.i_hold = 0;
	p.rng_state = rng.state;
	p.rng_inc = rng.inc;
}

void RoadGen::_step_path() {
	PathState &p = _path;
	if (p.index % CHUNK == 0) {
		_path_marks.push_back(p); // the state that makes this chunk, for its checkpoint
	}
	if (p.i_ramp >= p.n_ramp && p.i_hold >= p.n_hold) {
		_plan();
	}
	if (p.i_ramp < p.n_ramp) {
		p.i_ramp++;
		p.curve = p.k0 + (p.kt - p.k0) * p.i_ramp / p.n_ramp;
	} else {
		p.i_hold++;
		p.curve = p.kt;
	}
	Sample s;
	s.index = p.index;
	s.x = p.x;
	s.z = p.z;
	s.heading = p.heading;
	s.curve = p.curve;
	int64_t xm = floor_div(p.x, 1000), zm = floor_div(p.z, 1000);
	s.axis = _land.axis_mm(xm, zm);
	BiomeMix mix = _land.biome_at(s.axis);
	s.biome = mix.a;
	s.biome2 = mix.b;
	s.blend = mix.w;
	s.lane_mm = biome_style(mix.dominant()).lane_mm;
	s.ground = _land.ground_mm(xm, zm) * 1000;
	int64_t lx = cos_q30(p.heading), lz = -sin_q30(p.heading); // left, Q30
	s.ground_l = _land.ground_mm(xm + mul_q30(SIDE_MM, lx), zm + mul_q30(SIDE_MM, lz)) * 1000;
	s.ground_r = _land.ground_mm(xm - mul_q30(SIDE_MM, lx), zm - mul_q30(SIDE_MM, lz)) * 1000;
	int64_t k = p.curve < 0 ? -p.curve : p.curve;
	int64_t bank = std::min<int64_t>(600000 * k / STEP_CURVE, 4000); // 600 / R degrees, at most 4
	s.bank_mdeg = int32_t(p.curve < 0 ? -bank : bank);
	s.cap2 = _cap2(s);
	_buf.push_back(s);
	// On along the heading halfway through this step's turn.
	int64_t mid = p.heading + p.curve / 2;
	p.x += mul_q30(STEP_UM, sin_q30(mid));
	p.z += mul_q30(STEP_UM, cos_q30(mid));
	p.heading += p.curve;
	p.index++;
}

void RoadGen::_step_height() {
	HeightState &h = _height;
	if (h.index % CHUNK == 0) {
		_height_marks.push_back(h);
	}
	if (!_window_ready) {
		_window_sum = 0;
		for (int j = HEIGHT_FROM; j <= HEIGHT_TO; j++) {
			_window_sum += _at(h.index + j).ground;
		}
		_window_ready = true;
	}
	int64_t target = std::max(_window_sum / (HEIGHT_TO - HEIGHT_FROM + 1), SEA_MIN_UM);
	Sample &s = _at(h.index);
	const BiomeStyle &st = style_of(s);
	if (!h.started) {
		h.y = target;
		h.grade = 0;
		h.started = true;
	}
	int64_t gmax = STEP_UM * st.max_grade_pm / 1000;
	int64_t want = clamp64((target - h.y) / HEIGHT_REACH, -gmax, gmax);
	int64_t dg = 4000000 / st.crest_m; // (2 m)^2 / R, µm
	h.grade += clamp64(want - h.grade, -dg, dg);
	s.y = h.y;
	s.grade = h.grade;
	h.y += h.grade;
	_window_sum += _at(h.index + HEIGHT_TO + 1).ground - _at(h.index + HEIGHT_FROM).ground;
	h.index++;
}

int64_t RoadGen::_cap2(const Sample &p_s) {
	int64_t design = int64_t(style_of(p_s).design_kmh) * 1000000 / 3600; // mm/s
	int64_t cap = design * design;
	int64_t k = p_s.curve < 0 ? -p_s.curve : p_s.curve;
	if (k > 0) {
		cap = std::min(cap, LAT_MM * 1000 * STEP_CURVE / k); // a_lat * R
	}
	return cap;
}

Sample RoadGen::_finish_one() {
	FinishState &f = _finish;
	if (f.index % CHUNK == 0) {
		int64_t k = f.index / CHUNK;
		PathState path = _path_marks.front();
		_path_marks.pop_front();
		HeightState height = _height_marks.front();
		_height_marks.pop_front();
		if (k == int64_t(_checkpoints.size())) {
			_checkpoints.push_back({ path, height, f });
		}
	}
	Sample s = _buf.front();
	// Traffic speeds. Up (toward higher indices) brakes ahead of slow places and pulls away after
	// them; down drives the other way, so the same places come in the other order.
	int64_t look_up = NO_LIMIT, look_down = NO_LIMIT;
	for (int j = 0; j <= LOOK; j++) {
		int64_t cap = _buf[size_t(j)].cap2;
		look_up = std::min(look_up, cap + 2 * BRAKE_MM * STEP_MM * j);
		look_down = std::min(look_down, cap + 2 * ACCEL_MM * STEP_MM * j);
	}
	f.v2_up = std::min(look_up, f.v2_up + 2 * ACCEL_MM * STEP_MM);
	f.v2_down = std::min(look_down, f.v2_down + 2 * BRAKE_MM * STEP_MM);
	s.v_up = int32_t(isqrt64(uint64_t(f.v2_up)));
	s.v_down = int32_t(isqrt64(uint64_t(f.v2_down)));
	if (f.index > 0) {
		f.t_up += 4000000000LL / std::max<int64_t>(f.prev_up + s.v_up, 1);
		f.t_down += 4000000000LL / std::max<int64_t>(f.prev_down + s.v_down, 1);
	}
	s.t_up = f.t_up;
	s.t_down = f.t_down;
	f.prev_up = s.v_up;
	f.prev_down = s.v_down;
	// Bridges.
	if (!f.bridge) {
		bool all = true;
		for (int j = 0; j <= BRIDGE_LOOK && all; j++) {
			const Sample &q = _buf[size_t(j)];
			all = q.y - q.ground > BRIDGE_ON_UM;
		}
		f.bridge = all;
	} else if (s.y - s.ground < BRIDGE_OFF_UM) {
		f.bridge = false;
	}
	if (f.bridge) {
		s.flags |= FLAG_LIFTED;
	}
	// Guard rails where the ground falls away beside the road, and on bridges.
	bool ahead_l = false, ahead_r = false;
	for (int j = 0; j <= BARRIER_REACH; j++) {
		const Sample &q = _buf[size_t(j)];
		ahead_l = ahead_l || q.y - q.ground_l > DROP_UM;
		ahead_r = ahead_r || q.y - q.ground_r > DROP_UM;
	}
	if (s.y - s.ground_l > DROP_UM) {
		f.drop_l = f.index;
	}
	if (s.y - s.ground_r > DROP_UM) {
		f.drop_r = f.index;
	}
	if (f.bridge || ahead_l || f.index - f.drop_l <= BARRIER_REACH) {
		s.flags |= FLAG_BARRIER_L;
	}
	if (f.bridge || ahead_r || f.index - f.drop_r <= BARRIER_REACH) {
		s.flags |= FLAG_BARRIER_R;
	}
	_buf.pop_front();
	f.index++;
	_last = s;
	return s;
}

std::vector<Sample> RoadGen::chunk(int64_t p_k) {
	std::vector<Sample> out;
	if (p_k < 0) {
		return out;
	}
	int64_t first = p_k * CHUNK;
	if (first < _finish.index - 1) {
		_restore(p_k); // already made: from its checkpoint
	}
	out.reserve(CHUNK + 1);
	if (first == _finish.index - 1) {
		out.push_back(_last);
	}
	while (int64_t(out.size()) < CHUNK + 1) {
		while (_path.index < _finish.index + LOOK + 1) {
			_step_path();
		}
		while (_height.index < _finish.index + BRIDGE_LOOK + 1) {
			_step_height();
		}
		Sample s = _finish_one();
		if (s.index >= first) {
			out.push_back(s);
		}
	}
	return out;
}

uint64_t RoadGen::checksum(const std::vector<Sample> &p_samples, uint64_t p_chain) {
	Fnv64 h;
	h.h = p_chain;
	for (const Sample &s : p_samples) {
		for (int64_t v : { s.index, s.x, s.y, s.z, s.heading, s.curve, s.grade, s.ground, s.ground_l, s.ground_r, s.axis, s.t_up, s.t_down }) {
			h.i64(v);
		}
		for (int64_t v : { int64_t(s.lane_mm), int64_t(s.bank_mdeg), int64_t(s.v_up), int64_t(s.v_down), int64_t(s.biome), int64_t(s.biome2), int64_t(s.blend), int64_t(s.flags) }) {
			h.i64(v);
		}
	}
	return h.h;
}

} // namespace noss::endless
