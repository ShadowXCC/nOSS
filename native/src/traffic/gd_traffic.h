#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "traffic/traffic_sim.h"

namespace noss {

// A highway's traffic for scripts (D108-D110): the lane sim (traffic_sim.h), its events and
// sync, where to draw its cars, near-miss gaps, and the driver of the cars turned into physics
// cars near players (lane_driver.h). Distances in metres and speeds in m/s at this boundary;
// the sim itself keeps mm and mm/s.
class NossTraffic : public godot::RefCounted {
	GDCLASS(NossTraffic, godot::RefCounted)

	traffic::TrafficSim _sim;
	bool _ready = false;

protected:
	static void _bind_methods();

public:
	// graph: HighwayLayout.lane_graph(); types: data/traffic/types.json's list. "" or why not.
	godot::String setup(const godot::Dictionary &p_graph, const godot::Array &p_types, int64_t p_seed, int64_t p_count, double p_exit_share);
	bool is_ready() const { return _ready; }
	int64_t graph_hash() const { return int64_t(_sim.graph.hash()); }
	int64_t get_tick() const { return _sim.st.tick; }
	void step() { _sim.step(); }
	void step_to(int64_t p_tick);
	int64_t get_count() const { return _sim.count(); }
	int64_t active_count() const { return _sim.active(); }
	int64_t away_count() const { return _sim.away(); }
	// Events as 24-byte records (pack_event); false: one is too old to replay (resync).
	bool schedule(const godot::PackedByteArray &p_events);
	static godot::PackedByteArray pack_event(int64_t p_kind, int64_t p_seq, int64_t p_tick, int64_t p_car, int64_t p_owner, int64_t p_lane, double p_s, double p_v, int64_t p_lc_from, int64_t p_lc, int64_t p_bits, int64_t p_extra);
	static godot::Array unpack_events(const godot::PackedByteArray &p_events);
	int64_t checksum() const { return int64_t(_sim.checksum()); }
	bool has_checksum(int64_t p_tick) const;
	int64_t checksum_at(int64_t p_tick) const;
	godot::PackedByteArray full_state() const;
	bool load_full_state(const godot::PackedByteArray &p_bytes);
	// {lane, s, v, flags, type, color, signal, lc_from, lc, exit, away_until}
	godot::Dictionary car(int64_t p_car) const;
	// Every car: x, y, z, heading x, heading z, flags, signal, type (8 floats each); `alpha` of the
	// way to the next tick.
	godot::PackedFloat32Array poses(double p_alpha) const;
	godot::PackedInt32Array cars_near(const godot::Vector3 &p_at, double p_radius) const;
	// Lane-sim cars (not shadows) within `p_radius` of a box: id, gap (hull to hull), along and left
	// of the box (centre to centre), their speed along the box's heading minus `p_speed`.
	godot::PackedFloat32Array gaps(const godot::Vector3 &p_center, const godot::Vector3 &p_forward, const godot::Vector2 &p_half, double p_speed, double p_radius) const;
	static double box_gap(const godot::Vector3 &p_a, const godot::Vector3 &p_a_fwd, const godot::Vector2 &p_a_half, const godot::Vector3 &p_b, const godot::Vector3 &p_b_fwd, const godot::Vector2 &p_b_half);
	// {lane, s, lateral} or {lane: -1}
	godot::Dictionary locate(const godot::Vector3 &p_at) const;
	godot::Dictionary lane_info(int64_t p_lane) const;
	godot::PackedFloat32Array lane_point(int64_t p_lane, double p_s) const;
	// Controls for car `p_car` as a physics car: steer, throttle, brake, handbrake, lane, s, lateral,
	// heading error, blocked, signal, gap. members: 9 floats each: id, x, y, z, heading x, heading z,
	// speed, half length, half width.
	godot::PackedFloat32Array drive(int64_t p_car, int64_t p_member, const godot::Vector3 &p_at, const godot::Vector3 &p_forward, double p_speed,
			double p_wheelbase, double p_max_steer, const godot::Vector2 &p_half, const godot::PackedFloat32Array &p_members) const;
	// The speed the car wants where it is, m/s.
	double desired(int64_t p_car) const;
	// Test hook: puts a car on a lane (lab placements; never online).
	void place(int64_t p_car, int64_t p_lane, double p_s, double p_v);
};

} // namespace noss
