#include "traffic/gd_traffic.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

#include "traffic/lane_driver.h"
#include "traffic/near_query.h"

using namespace godot;

namespace noss {

namespace {

std::vector<int32_t> ints(const Variant &p_v) {
	std::vector<int32_t> out;
	if (p_v.get_type() == Variant::PACKED_INT32_ARRAY) {
		PackedInt32Array a = p_v;
		out.assign(a.ptr(), a.ptr() + a.size());
	} else if (p_v.get_type() == Variant::ARRAY) {
		Array a = p_v;
		for (int64_t i = 0; i < a.size(); i++) {
			out.push_back(int32_t(int64_t(a[i])));
		}
	}
	return out;
}

template <size_t N>
std::vector<std::array<int, N>> groups(const Variant &p_v) {
	std::vector<int32_t> flat = ints(p_v);
	std::vector<std::array<int, N>> out;
	for (size_t i = 0; i + N <= flat.size(); i += N) {
		std::array<int, N> g;
		for (size_t k = 0; k < N; k++) {
			g[k] = flat[i + k];
		}
		out.push_back(g);
	}
	return out;
}

constexpr int EVENT_SIZE = 24;

void put16(uint8_t *p, uint16_t v) {
	p[0] = uint8_t(v);
	p[1] = uint8_t(v >> 8);
}

void put32(uint8_t *p, uint32_t v) {
	for (int i = 0; i < 4; i++) {
		p[i] = uint8_t(v >> (8 * i));
	}
}

uint16_t get16(const uint8_t *p) {
	return uint16_t(p[0] | (p[1] << 8));
}

uint32_t get32(const uint8_t *p) {
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

traffic::Event decode(const uint8_t *p) {
	traffic::Event e;
	e.kind = p[0];
	e.seq = get16(p + 1);
	e.tick = get32(p + 3);
	e.car = get16(p + 7);
	e.owner = get16(p + 9);
	e.lane = int16_t(get16(p + 11));
	e.s = int32_t(get32(p + 13));
	e.v = int32_t(get16(p + 17)) * 10; // cm/s on the wire (closures: cm)
	e.lc_from = int16_t(get16(p + 19));
	e.lc = p[21];
	e.bits = p[22];
	e.extra = p[23];
	return e;
}

traffic::Box2 box(const Vector3 &p_at, const Vector3 &p_fwd, const Vector2 &p_half) {
	double len = std::hypot(double(p_fwd.x), double(p_fwd.z));
	traffic::Box2 b;
	b.cx = p_at.x;
	b.cz = p_at.z;
	b.fx = len > 1e-9 ? p_fwd.x / len : 0.0;
	b.fz = len > 1e-9 ? p_fwd.z / len : 1.0;
	b.half_len = p_half.x;
	b.half_wid = p_half.y;
	return b;
}

} // namespace

void NossTraffic::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "graph", "types", "seed", "count", "exit_share"), &NossTraffic::setup);
	ClassDB::bind_method(D_METHOD("is_ready"), &NossTraffic::is_ready);
	ClassDB::bind_method(D_METHOD("graph_hash"), &NossTraffic::graph_hash);
	ClassDB::bind_method(D_METHOD("get_tick"), &NossTraffic::get_tick);
	ClassDB::bind_method(D_METHOD("step"), &NossTraffic::step);
	ClassDB::bind_method(D_METHOD("step_to", "tick"), &NossTraffic::step_to);
	ClassDB::bind_method(D_METHOD("get_count"), &NossTraffic::get_count);
	ClassDB::bind_method(D_METHOD("active_count"), &NossTraffic::active_count);
	ClassDB::bind_method(D_METHOD("away_count"), &NossTraffic::away_count);
	ClassDB::bind_method(D_METHOD("schedule", "events"), &NossTraffic::schedule);
	ClassDB::bind_static_method("NossTraffic", D_METHOD("pack_event", "kind", "seq", "tick", "car", "owner", "lane", "s", "v", "lc_from", "lc", "bits", "extra"), &NossTraffic::pack_event);
	ClassDB::bind_static_method("NossTraffic", D_METHOD("unpack_events", "events"), &NossTraffic::unpack_events);
	ClassDB::bind_method(D_METHOD("checksum"), &NossTraffic::checksum);
	ClassDB::bind_method(D_METHOD("has_checksum", "tick"), &NossTraffic::has_checksum);
	ClassDB::bind_method(D_METHOD("checksum_at", "tick"), &NossTraffic::checksum_at);
	ClassDB::bind_method(D_METHOD("full_state"), &NossTraffic::full_state);
	ClassDB::bind_method(D_METHOD("load_full_state", "bytes"), &NossTraffic::load_full_state);
	ClassDB::bind_method(D_METHOD("car", "car"), &NossTraffic::car);
	ClassDB::bind_method(D_METHOD("poses", "alpha"), &NossTraffic::poses);
	ClassDB::bind_method(D_METHOD("cars_near", "at", "radius"), &NossTraffic::cars_near);
	ClassDB::bind_method(D_METHOD("gaps", "center", "forward", "half", "speed", "radius"), &NossTraffic::gaps);
	ClassDB::bind_static_method("NossTraffic", D_METHOD("box_gap", "a", "a_forward", "a_half", "b", "b_forward", "b_half"), &NossTraffic::box_gap);
	ClassDB::bind_method(D_METHOD("locate", "at"), &NossTraffic::locate);
	ClassDB::bind_method(D_METHOD("lane_info", "lane"), &NossTraffic::lane_info);
	ClassDB::bind_method(D_METHOD("lane_point", "lane", "s"), &NossTraffic::lane_point);
	ClassDB::bind_method(D_METHOD("drive", "car", "member", "at", "forward", "speed", "wheelbase", "max_steer", "half", "members"), &NossTraffic::drive);
	ClassDB::bind_method(D_METHOD("desired", "car"), &NossTraffic::desired);
	ClassDB::bind_method(D_METHOD("place", "car", "lane", "s", "v"), &NossTraffic::place);
	BIND_CONSTANT(traffic::TICK_HZ);
}

String NossTraffic::setup(const Dictionary &p_graph, const Array &p_types, int64_t p_seed, int64_t p_count, double p_exit_share) {
	_ready = false;
	traffic::GraphInput in;
	Array lanes = p_graph.get("lanes", Array());
	for (int64_t i = 0; i < lanes.size(); i++) {
		Dictionary d = lanes[i];
		traffic::LaneInput l;
		l.dir = int(int64_t(d.get("dir", 0)));
		l.road = int(int64_t(d.get("road", -1)));
		l.index = int(int64_t(d.get("index", 0)));
		l.closed = bool(d.get("closed", false));
		l.speed_mmps = int32_t(std::llround(double(d.get("speed", 30.0)) * 1000.0));
		PackedVector3Array pts = d.get("points", PackedVector3Array());
		for (int64_t k = 0; k < pts.size(); k++) {
			l.xyz.push_back(pts[k].x);
			l.xyz.push_back(pts[k].y);
			l.xyz.push_back(pts[k].z);
		}
		l.limit_mmps = ints(d.get("limits", PackedInt32Array()));
		in.lanes.push_back(l);
	}
	in.adjacent = groups<2>(p_graph.get("adjacent", PackedInt32Array()));
	in.branches = groups<3>(p_graph.get("branches", PackedInt32Array()));
	in.merges = groups<3>(p_graph.get("merges", PackedInt32Array()));
	in.attaches = groups<5>(p_graph.get("attaches", PackedInt32Array()));
	in.portal_in = groups<2>(p_graph.get("portal_in", PackedInt32Array()));
	in.portal_out = groups<2>(p_graph.get("portal_out", PackedInt32Array()));
	std::vector<traffic::TypeSpec> types;
	for (int64_t i = 0; i < p_types.size(); i++) {
		Dictionary d = p_types[i];
		traffic::TypeSpec t;
		t.length_mm = int32_t(std::llround(double(d.get("length_m", 4.5)) * 1000.0));
		t.width_mm = int32_t(std::llround(double(d.get("width_m", 1.8)) * 1000.0));
		Array factor = d.get("speed_factor", Array());
		if (factor.size() == 2) {
			t.speed_min_q8 = int32_t(std::llround(double(factor[0]) * 256.0));
			t.speed_max_q8 = int32_t(std::llround(double(factor[1]) * 256.0));
		}
		t.accel_mmps2 = int32_t(std::llround(double(d.get("accel", 1.4)) * 1000.0));
		t.decel_mmps2 = int32_t(std::llround(double(d.get("decel", 2.2)) * 1000.0));
		t.headway_ms = int32_t(std::llround(double(d.get("headway_s", 1.4)) * 1000.0));
		t.gap_mm = int32_t(std::llround(double(d.get("min_gap_m", 2.5)) * 1000.0));
		t.politeness_q8 = int32_t(std::llround(double(d.get("politeness", 0.25)) * 256.0));
		t.lanes_max = int(int64_t(d.get("lanes_max", 0)));
		t.weight = int(int64_t(d.get("weight", 10)));
		t.colors = int(int64_t(d.get("colors", 8)));
		t.patrol = bool(d.get("patrol", false));
		types.push_back(t);
	}
	std::string error;
	if (!_sim.setup(in, types, uint64_t(p_seed), int(p_count), p_exit_share, &error)) {
		return String(error.c_str());
	}
	_ready = true;
	return String();
}

void NossTraffic::step_to(int64_t p_tick) {
	if (_ready && p_tick > int64_t(_sim.st.tick)) {
		_sim.step_to(uint32_t(p_tick));
	}
}

bool NossTraffic::schedule(const PackedByteArray &p_events) {
	std::vector<traffic::Event> events;
	const uint8_t *p = p_events.ptr();
	for (int64_t at = 0; at + EVENT_SIZE <= p_events.size(); at += EVENT_SIZE) {
		events.push_back(decode(p + at));
	}
	return _sim.schedule(events);
}

PackedByteArray NossTraffic::pack_event(int64_t p_kind, int64_t p_seq, int64_t p_tick, int64_t p_car, int64_t p_owner, int64_t p_lane, double p_s, double p_v, int64_t p_lc_from, int64_t p_lc, int64_t p_bits, int64_t p_extra) {
	PackedByteArray out;
	out.resize(EVENT_SIZE);
	uint8_t *p = out.ptrw();
	p[0] = uint8_t(p_kind);
	put16(p + 1, uint16_t(p_seq));
	put32(p + 3, uint32_t(p_tick));
	put16(p + 7, uint16_t(p_car));
	put16(p + 9, uint16_t(p_owner));
	put16(p + 11, uint16_t(int16_t(p_lane)));
	put32(p + 13, uint32_t(int32_t(std::llround(p_s * 1000.0))));
	put16(p + 17, uint16_t(std::clamp<int64_t>(std::llround(p_v * 100.0), 0, 65535)));
	put16(p + 19, uint16_t(int16_t(p_lc_from)));
	p[21] = uint8_t(p_lc);
	p[22] = uint8_t(p_bits);
	p[23] = uint8_t(p_extra);
	return out;
}

Array NossTraffic::unpack_events(const PackedByteArray &p_events) {
	Array out;
	const uint8_t *p = p_events.ptr();
	for (int64_t at = 0; at + EVENT_SIZE <= p_events.size(); at += EVENT_SIZE) {
		traffic::Event e = decode(p + at);
		Dictionary d;
		d["kind"] = e.kind;
		d["seq"] = e.seq;
		d["tick"] = int64_t(e.tick);
		d["car"] = e.car;
		d["owner"] = e.owner;
		d["lane"] = e.lane;
		d["s"] = e.s / 1000.0;
		d["v"] = e.v / 1000.0;
		d["lc_from"] = e.lc_from;
		d["lc"] = e.lc;
		d["bits"] = e.bits;
		d["extra"] = e.extra;
		out.append(d);
	}
	return out;
}

bool NossTraffic::has_checksum(int64_t p_tick) const {
	uint64_t sum = 0;
	return p_tick >= 0 && _sim.checksum_at(uint32_t(p_tick), sum);
}

int64_t NossTraffic::checksum_at(int64_t p_tick) const {
	uint64_t sum = 0;
	return p_tick >= 0 && _sim.checksum_at(uint32_t(p_tick), sum) ? int64_t(sum) : 0;
}

PackedByteArray NossTraffic::full_state() const {
	std::vector<uint8_t> s = _sim.full_state();
	PackedByteArray out;
	out.resize(int64_t(s.size()));
	if (!s.empty()) {
		std::memcpy(out.ptrw(), s.data(), s.size());
	}
	return out;
}

bool NossTraffic::load_full_state(const PackedByteArray &p_bytes) {
	return _ready && _sim.load_full_state(std::vector<uint8_t>(p_bytes.ptr(), p_bytes.ptr() + p_bytes.size()));
}

Dictionary NossTraffic::car(int64_t p_car) const {
	Dictionary d;
	if (p_car < 0 || p_car >= _sim.count()) {
		return d;
	}
	const traffic::Car &c = _sim.st.cars[size_t(p_car)];
	d["lane"] = c.lane;
	d["s"] = c.s / 1000.0;
	d["v"] = c.v / 1000.0;
	d["flags"] = c.flags;
	d["type"] = c.type;
	d["color"] = c.color;
	d["signal"] = c.signal;
	d["lc_from"] = c.lc_from;
	d["lc"] = c.lc;
	d["exit"] = c.exit;
	d["away_until"] = int64_t(c.away_until);
	return d;
}

PackedFloat32Array NossTraffic::poses(double p_alpha) const {
	PackedFloat32Array out;
	out.resize(int64_t(_sim.count()) * 8);
	float *w = out.ptrw();
	for (int i = 0; i < _sim.count(); i++) {
		const traffic::Car &c = _sim.st.cars[size_t(i)];
		traffic::CarPose p = _sim.pose(i, p_alpha);
		float *o = w + i * 8;
		o[0] = float(p.x);
		o[1] = float(p.y);
		o[2] = float(p.z);
		o[3] = float(p.dx);
		o[4] = float(p.dz);
		o[5] = float(c.flags);
		o[6] = float(c.signal);
		o[7] = float(c.type);
	}
	return out;
}

PackedInt32Array NossTraffic::cars_near(const Vector3 &p_at, double p_radius) const {
	PackedInt32Array out;
	double r2 = p_radius * p_radius;
	for (int i = 0; i < _sim.count(); i++) {
		const traffic::Car &c = _sim.st.cars[size_t(i)];
		if (!(c.flags & traffic::ACTIVE)) {
			continue;
		}
		traffic::CarPose p = _sim.pose(i, 0.0);
		double dx = p.x - p_at.x, dy = p.y - p_at.y, dz = p.z - p_at.z;
		if (dx * dx + dy * dy + dz * dz <= r2) {
			out.append(i);
		}
	}
	return out;
}

PackedFloat32Array NossTraffic::gaps(const Vector3 &p_center, const Vector3 &p_forward, const Vector2 &p_half, double p_speed, double p_radius) const {
	PackedFloat32Array out;
	traffic::Box2 me = box(p_center, p_forward, p_half);
	double r2 = p_radius * p_radius;
	for (int i = 0; i < _sim.count(); i++) {
		const traffic::Car &c = _sim.st.cars[size_t(i)];
		if (!(c.flags & traffic::ACTIVE) || (c.flags & traffic::SHADOW)) {
			continue;
		}
		traffic::CarPose p = _sim.pose(i, 0.0);
		const traffic::TypeSpec &t = _sim.types[c.type];
		double half_len = t.length_mm / 2000.0;
		// The pose is the front bumper; the box's centre is half a length back.
		traffic::Box2 other{ p.x - p.dx * half_len, p.z - p.dz * half_len, p.dx, p.dz, half_len, t.width_mm / 2000.0 };
		double dx = other.cx - me.cx, dz = other.cz - me.cz;
		if (dx * dx + dz * dz > r2 || std::abs(p.y - p_center.y) > 3.0) {
			continue;
		}
		double along = 0.0, left = 0.0;
		traffic::box_offset(me, other, along, left);
		double v = c.v / 1000.0 * (p.dx * me.fx + p.dz * me.fz);
		out.append(float(i));
		out.append(float(traffic::box_gap(me, other)));
		out.append(float(along));
		out.append(float(left));
		out.append(float(v - p_speed));
	}
	return out;
}

double NossTraffic::box_gap(const Vector3 &p_a, const Vector3 &p_a_fwd, const Vector2 &p_a_half, const Vector3 &p_b, const Vector3 &p_b_fwd, const Vector2 &p_b_half) {
	return traffic::box_gap(box(p_a, p_a_fwd, p_a_half), box(p_b, p_b_fwd, p_b_half));
}

Dictionary NossTraffic::locate(const Vector3 &p_at) const {
	Dictionary d;
	traffic::LanePos p = _ready ? _sim.graph.locate(p_at.x, p_at.y, p_at.z) : traffic::LanePos();
	d["lane"] = p.lane;
	if (p.lane >= 0) {
		d["s"] = p.s / 1000.0;
		d["lateral"] = p.lateral;
	}
	return d;
}

Dictionary NossTraffic::lane_info(int64_t p_lane) const {
	Dictionary d;
	if (p_lane < 0 || p_lane >= int64_t(_sim.graph.lanes.size())) {
		return d;
	}
	const traffic::Lane &l = _sim.graph.lanes[size_t(p_lane)];
	d["dir"] = l.dir;
	d["road"] = l.road;
	d["index"] = l.index;
	d["closed"] = l.closed;
	d["length"] = l.length / 1000.0;
	d["outer"] = l.outer;
	d["inner"] = l.inner;
	d["portal_in"] = l.portal_in;
	d["portal_out"] = l.portal_out;
	return d;
}

PackedFloat32Array NossTraffic::lane_point(int64_t p_lane, double p_s) const {
	PackedFloat32Array out;
	if (p_lane < 0 || p_lane >= int64_t(_sim.graph.lanes.size())) {
		return out;
	}
	double x, y, z, dx, dz;
	_sim.graph.point(int(p_lane), int64_t(std::llround(p_s * 1000.0)), x, y, z, dx, dz);
	out.append(float(x));
	out.append(float(y));
	out.append(float(z));
	out.append(float(dx));
	out.append(float(dz));
	return out;
}

PackedFloat32Array NossTraffic::drive(int64_t p_car, int64_t p_member, const Vector3 &p_at, const Vector3 &p_forward, double p_speed, double p_wheelbase,
		double p_max_steer, const Vector2 &p_half, const PackedFloat32Array &p_members) const {
	std::vector<traffic::Member> members;
	const float *m = p_members.ptr();
	for (int64_t i = 0; i + 9 <= p_members.size(); i += 9) {
		traffic::Member mb;
		mb.id = int(m[i]);
		mb.box = box(Vector3(m[i + 1], 0.0f, m[i + 3]), Vector3(m[i + 4], 0.0f, m[i + 5]), Vector2(m[i + 7], m[i + 8]));
		mb.y = m[i + 2];
		mb.v = m[i + 6];
		members.push_back(mb);
	}
	traffic::DriveIn in;
	in.car = int(p_car);
	in.member = int(p_member);
	in.x = p_at.x;
	in.y = p_at.y;
	in.z = p_at.z;
	double len = std::hypot(double(p_forward.x), double(p_forward.z));
	in.fx = len > 1e-9 ? p_forward.x / len : 0.0;
	in.fz = len > 1e-9 ? p_forward.z / len : 1.0;
	in.speed = p_speed;
	in.wheelbase = p_wheelbase;
	in.max_steer = p_max_steer;
	in.half_len = p_half.x;
	in.half_wid = p_half.y;
	traffic::DriveOut o = _ready ? traffic::drive(_sim, in, members) : traffic::DriveOut();
	PackedFloat32Array out;
	for (double v : { o.steer, o.throttle, o.brake, o.handbrake, double(o.lane), double(o.s) / 1000.0, o.lateral, o.heading_error, o.blocked ? 1.0 : 0.0, double(o.signal), o.gap }) {
		out.append(float(v));
	}
	return out;
}

double NossTraffic::desired(int64_t p_car) const {
	return (p_car >= 0 && p_car < _sim.count()) ? double(_sim.desired(int(p_car))) / 1000.0 : 0.0;
}

void NossTraffic::place(int64_t p_car, int64_t p_lane, double p_s, double p_v) {
	if (p_car < 0 || p_car >= _sim.count() || p_lane < 0 || p_lane >= int64_t(_sim.graph.lanes.size())) {
		return;
	}
	traffic::Car &c = _sim.st.cars[size_t(p_car)];
	c.flags = traffic::ACTIVE;
	c.lane = int16_t(p_lane);
	c.s = int32_t(_sim.graph.wrap(int(p_lane), std::llround(p_s * 1000.0)));
	c.v = int32_t(std::llround(p_v * 1000.0));
	c.lc_from = -1;
	c.lc = 0;
	c.target = -1;
	c.signal = 0;
	c.exit = -1;
}

} // namespace noss
