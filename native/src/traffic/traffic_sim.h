#pragma once

// The lane sim (D108, D109): every traffic car on a highway as a lane follower, stepped 20 times a
// second in integers (mm, mm/s), so every game that starts from the same seed and applies the same
// events at the same ticks has the same traffic, bit for bit.
//
// Cars follow the car ahead with the Intelligent Driver Model, change lanes when it pays (MOBIL,
// a nudge to keep right, never without 1.5 s of signal first), plan exits a while ahead, merge off
// acceleration lanes, and go into the city through portals to come back out of one later, the same
// car. The population never changes. Events from the server (a car turned into a physics car near
// a player and back, a wreck, a closure) apply at the tick they're for; one that arrives late
// rolls the sim back to it and steps forward again. Plain C++, no Godot types.

#include <cstdint>
#include <string>
#include <vector>

#include "traffic/fixed.h"
#include "traffic/lane_graph.h"

namespace noss::traffic {

constexpr int TICK_HZ = 20;
constexpr int LC_TICKS = 60; // a lane change takes 3 s
constexpr int SIGNAL_TICKS = 30; // signal 1.5 s before moving over
constexpr int SIGNAL_GIVE_UP = 140; // and give up after 7 s without room
constexpr int DECIDE_EVERY = 20; // each car thinks about changing lanes once a second
constexpr int RING = 64; // ticks it can roll back (3.2 s)
constexpr int64_t MAX_DECEL = 9000; // mm/s²
constexpr int64_t SAFE_DECEL = 3000; // a lane change may make the new follower brake this hard
constexpr int64_t LOOK_AHEAD = 400000; // mm: cars further ahead don't matter
constexpr int64_t EXIT_DECIDE = 2200000; // mm before an exit a car decides whether to take it
constexpr int64_t ENTRY_CLEAR = 40000; // mm free at a portal's lane start to come out
constexpr int64_t STOP_GAP = 200; // mm: the closest a car ever gets to what's ahead

struct TypeSpec {
	int32_t length_mm = 4500;
	int32_t width_mm = 1800;
	int32_t speed_min_q8 = 230; // desired speed, a share of the limit, ×256
	int32_t speed_max_q8 = 280;
	int32_t accel_mmps2 = 1400;
	int32_t decel_mmps2 = 2200;
	int32_t headway_ms = 1400;
	int32_t gap_mm = 2500;
	int32_t politeness_q8 = 64;
	int lanes_max = 0; // only the outermost lanes_max lanes (0: any)
	int weight = 10; // how common
	int colors = 8;
	bool patrol = false; // police
};

enum Flag : uint8_t {
	ACTIVE = 1, // on a lane
	AWAY = 2, // in the city
	SHADOW = 4, // a physics car near a player drives it; this is where the lane sim has it
	WRECK = 8, // stopped where it crashed
	BRAKING = 16,
};

struct Car {
	uint16_t id = 0;
	uint8_t type = 0;
	uint8_t color = 0;
	uint8_t flags = 0;
	int8_t signal = 0; // indicators: 1 left, -1 right
	int16_t lane = -1;
	int16_t lc_from = -1; // moving over from this lane
	int16_t target = -1; // signalling for this lane
	int16_t exit = -1; // the branch (global index) it'll take
	int16_t decided = -1; // the branch it last decided about
	uint16_t lc = 0; // lane change progress, ticks
	uint16_t signal_ticks = 0;
	int32_t s = 0; // mm along its lane (its front)
	int32_t v = 0; // mm/s
	int32_t factor_q8 = 256; // desired speed, a share of the limit
	int32_t acc = 0; // last acceleration, mm/s²
	uint32_t away_until = 0; // tick it comes back out of the city
	Pcg32 rng;
};

enum EventKind : uint8_t {
	EV_PROMOTE = 1,
	EV_DEMOTE = 2,
	EV_HANDOVER = 3, // owner changes only; no effect here
	EV_WRECK = 4,
	EV_TOW = 5,
	EV_CLOSE = 6,
	EV_OPEN = 7,
	EV_RESHADOW = 8,
};

// One server event; 24 bytes on the wire (D109).
struct Event {
	uint8_t kind = 0;
	uint16_t seq = 0;
	uint32_t tick = 0;
	uint16_t car = 0; // car index (closure id for CLOSE/OPEN)
	uint16_t owner = 0;
	int16_t lane = -1;
	int32_t s = 0; // mm
	int32_t v = 0; // mm/s (CLOSE: the closure's length, mm)
	int16_t lc_from = -1;
	uint8_t lc = 0;
	uint8_t bits = 0;
	uint8_t extra = 0;
};

struct Closure {
	uint16_t id = 0;
	int16_t lane = -1;
	int32_t from = 0;
	int32_t to = 0;
};

struct State {
	uint32_t tick = 0;
	std::vector<Car> cars;
	std::vector<Closure> closures;
};

// Where to draw a car: the middle of its front bumper on the road, and its heading.
struct CarPose {
	double x = 0.0, y = 0.0, z = 0.0;
	double dx = 0.0, dz = 1.0; // heading, unit XZ
};

class TrafficSim {
public:
	LaneGraph graph;
	std::vector<TypeSpec> types;
	State st;
	double exit_share = 0.15;

	bool setup(const GraphInput &p_graph, const std::vector<TypeSpec> &p_types, uint64_t p_seed, int p_count, double p_exit_share, std::string *r_error = nullptr);
	void step();
	void step_to(uint32_t p_tick);
	// Queues events; ones for ticks already stepped roll back and replay. False if one is older
	// than the snapshots kept (the caller needs a full state from the server).
	bool schedule(const std::vector<Event> &p_events);
	uint64_t checksum() const;
	// The checksum after tick `p_tick` was stepped, if still kept.
	bool checksum_at(uint32_t p_tick, uint64_t &r_sum) const;
	std::vector<uint8_t> full_state() const;
	bool load_full_state(const std::vector<uint8_t> &p_bytes);

	CarPose pose(int p_car, double p_alpha) const;
	// The speed car `p_car` wants where it is, mm/s (its lane's limit, its own pace, an exit).
	int64_t desired(int p_car) const { return _desired(st.cars[size_t(p_car)]); }
	int count() const { return int(st.cars.size()); }
	int active() const;
	int away() const;
	// Branches by global index: [lane, index in that lane's branches].
	std::vector<std::pair<int, int>> branch_list;

private:
	struct Occ {
		int64_t s;
		int car;
	};
	std::vector<std::vector<Occ>> _occ;
	std::vector<State> _ring;
	std::vector<uint64_t> _sums;
	std::vector<uint32_t> _sum_ticks;
	std::vector<Event> _events; // sorted (tick, seq); kept while still inside the ring
	std::vector<int> _entries; // lanes cars come out of the city on
	std::vector<int> _first_lane; // per carriageway (0: dir 1, 1: dir -1): lane 0's lane index
	std::vector<double> _exit_p; // per branch: chance a passing car takes it

	void _occupancy();
	void _apply_events(uint32_t p_tick);
	void _apply(const Event &p_e);
	void _record();
	int64_t _accel(const Car &p_c, int p_lane, int64_t p_s, int64_t p_gap, int64_t p_lead_v, bool p_has_lead) const;
	// The obstacle ahead of position s on a lane: gap (mm) and its speed. False: the road is clear.
	bool _ahead(int p_lane, int64_t p_s, int p_self, int64_t &r_gap, int64_t &r_v) const;
	bool _behind(int p_lane, int64_t p_s, int p_self, int64_t p_length, int &r_car, int64_t &r_gap) const;
	int64_t _desired(const Car &p_c) const;
	bool _closed_at(int p_lane, int64_t p_s) const;
	bool _lane_ok(const Car &p_c, int p_lane) const;
	// Whether moving from `p_from` to lane `p_to` is safe now; the new speed's acceleration.
	bool _safe(const Car &p_c, int p_to, int64_t p_s_to, int64_t &r_acc_new, int64_t &r_follower_loss, int64_t p_follower_decel = SAFE_DECEL) const;
	// A car that has just moved over counts in its new lane at once (later cars this tick see it).
	void _occupy(int p_lane, int64_t p_s, int p_car);
	void _think(Car &r_c, int p_index);
	void _plan_exit(Car &r_c);
	// Moves a car on at its new speed, never closer than STOP_GAP to what was ahead (`p_room`, mm).
	void _move(Car &r_c, int64_t p_v_new, int64_t p_room, int64_t p_lead_v);
	void _reenter();
	int64_t _carriageway_s(const Car &p_c) const;
	const TypeSpec &_type(const Car &p_c) const { return types[size_t(p_c.type)]; }
};

} // namespace noss::traffic
