#pragma once

// The driver of a traffic car turned into a physics car near a player (D110, D120). It keeps to
// its lane-sim shadow's lane, follows its lane changes (holding back while something is beside
// it) with pure pursuit, and sets its speed with the IDM against what is really around it: the
// other physics cars (players, police, other promoted traffic) and lane-sim cars. Native, so a
// couple of dozen of them cost next to nothing each physics tick. Plain C++, no Godot types.

#include <vector>

#include "traffic/near_query.h"
#include "traffic/traffic_sim.h"

namespace noss::traffic {

// A physics car near the one being driven: its box seen from above, its height, its speed along
// its heading (m/s), and an id to skip itself by.
struct Member {
	int id = -1;
	Box2 box;
	double y = 0.0;
	double v = 0.0;
};

struct DriveIn {
	int car = -1; // the lane-sim car this one is
	int member = -1; // its own id among the members
	double x = 0.0, y = 0.0, z = 0.0; // its centre on the ground
	double fx = 0.0, fz = 1.0; // its heading
	double speed = 0.0; // m/s along its heading
	double wheelbase = 2.7;
	double max_steer = 0.55; // rad at the road wheels
	double half_len = 2.25, half_wid = 0.9;
};

struct DriveOut {
	double steer = 0.0; // -1..1, + = right
	double throttle = 0.0;
	double brake = 0.0;
	double handbrake = 0.0;
	int lane = -1; // the lane it's on and where (its front), for handing back to the lane sim
	int64_t s = 0;
	double lateral = 0.0; // m off that lane's line
	double heading_error = 0.0; // rad between it and its lane
	bool blocked = false; // its shadow is moving over but something is beside it
	int signal = 0; // indicators: 1 left, -1 right
	double gap = 1e9; // m to what's ahead
};

DriveOut drive(const TrafficSim &p_sim, const DriveIn &p_in, const std::vector<Member> &p_members);

} // namespace noss::traffic
