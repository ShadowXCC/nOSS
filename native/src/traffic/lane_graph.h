#pragma once

// The lanes traffic drives (D108): polylines in driving order with their lengths in whole
// millimetres, the speed to be at on each vertex, and how lanes connect. A carriageway's lanes
// share vertex numbers (each is the road's samples offset sideways), so a position maps from one
// to the next by vertex. Ramps leave a lane at a vertex (branches), run beside a lane for a while
// (attaches, by vertex too), and join one at their last vertex (merges), or start or end in the
// city (portals). Plain C++, no Godot types.

#include <array>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace noss::traffic {

// Lateral comfort for traffic in bends, and the braking it plans for lower limits ahead.
constexpr double LATERAL_ACCEL = 2.5; // m/s²
constexpr int64_t PLAN_DECEL_MMPS2 = 1500;

struct LaneInput {
	int dir = 0; // carriageway (1 or -1); 0 for ramps
	int road = -1; // -1: the main road; else a ramp's index
	int index = 0; // lane on the carriageway, 0 = outermost
	bool closed = false;
	std::vector<float> xyz; // vertices, 3 floats each
	std::vector<int32_t> limit_mmps; // per vertex (zones); empty: speed_mmps everywhere
	int32_t speed_mmps = 30000;
};

struct GraphInput {
	std::vector<LaneInput> lanes;
	std::vector<std::array<int, 2>> adjacent; // [outer lane, inner lane], same vertex count
	std::vector<std::array<int, 3>> branches; // [lane, vertex, ramp lane]
	std::vector<std::array<int, 3>> merges; // [ramp lane, lane, vertex its last vertex joins]
	std::vector<std::array<int, 5>> attaches; // [ramp lane, ramp vertex, lane, lane vertex, count]
	std::vector<std::array<int, 2>> portal_in; // [lane, portal]: the lane ends in the city
	std::vector<std::array<int, 2>> portal_out; // [lane, portal]: the lane starts there
};

struct Branch {
	int64_t at = 0; // mm along the lane it leaves
	int vertex = 0;
	int ramp = -1;
};

struct Attach {
	int ramp_v0 = 0;
	int lane = -1;
	int lane_v0 = 0;
	int count = 0;
};

struct Lane {
	int dir = 0;
	int road = -1;
	int index = 0;
	bool closed = false;
	std::vector<double> x, y, z;
	// mm from the first vertex to each vertex; closed lanes have one more (the way back round).
	std::vector<int64_t> cum;
	int64_t length = 0;
	// The speed to be at on each vertex, mm/s: the limit, bends, and slowing in time for both.
	std::vector<int32_t> limit;
	int outer = -1;
	int inner = -1;
	std::vector<Branch> branches; // by position
	int merge_into = -1; // a ramp's last vertex joins this lane...
	int merge_vertex = -1; // ...at this vertex
	std::vector<Attach> attaches;
	int portal_in = -1;
	int portal_out = -1;

	int vertices() const { return int(x.size()); }
};

// A spot on a lane.
struct LanePos {
	int lane = -1;
	int64_t s = 0; // mm
	double lateral = 0.0; // m, + = the driver's left
	double dist = 1e30; // m from the asked point
};

class LaneGraph {
public:
	std::vector<Lane> lanes;
	std::vector<std::vector<int>> portal_ins; // per portal, the lanes ending there
	std::vector<std::vector<int>> portal_outs; // per portal, the lanes starting there

	// Builds the graph; false (and why) if the input doesn't fit together.
	bool build(const GraphInput &p_in, std::string *r_error = nullptr);
	// A hash of everything the lane sim reads: equal graphs, equal traffic (D109).
	uint64_t hash() const;

	int64_t wrap(int p_lane, int64_t p_s) const;
	int vertex_at(int p_lane, int64_t p_s) const;
	int32_t limit_at(int p_lane, int64_t p_s) const;
	// Where `p_s` on `p_from` is on lane `p_to` (adjacent, or a ramp attached to it, either way);
	// -1 if they aren't side by side there.
	int64_t map_s(int p_from, int64_t p_s, int p_to) const;
	// A point on a lane, and the lane's direction there (unit, XZ).
	void point(int p_lane, int64_t p_s, double &r_x, double &r_y, double &r_z, double &r_dx, double &r_dz) const;
	// The nearest lane to a world point (within 8 m across, 3 m up or down); lane -1 if none.
	LanePos locate(double p_x, double p_y, double p_z) const;
	// A point projected onto lane `p_lane` near `p_s_hint` (within `p_range` mm of it): its s and
	// lateral (+ = the driver's left).
	LanePos project_near(int p_lane, int64_t p_s_hint, int64_t p_range, double p_x, double p_z) const;

private:
	std::unordered_map<int64_t, std::vector<std::pair<int, int>>> _cells; // cell -> (lane, vertex)
	static constexpr double CELL_M = 16.0;

	void _limits(Lane &r_lane, const LaneInput &p_in);
	static int64_t _cell_key(int p_x, int p_z) { return (int64_t(p_x) << 32) ^ int64_t(uint32_t(p_z)); }
};

} // namespace noss::traffic
