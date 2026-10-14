#pragma once

// Distances between cars seen from above (score attack's near misses, D114): each car a box
// (centre, heading, half length and width) in the XZ plane. Plain C++, no Godot types.

namespace noss::traffic {

struct Box2 {
	double cx = 0.0, cz = 0.0;
	double fx = 0.0, fz = 1.0; // heading, unit
	double half_len = 2.25, half_wid = 0.9;
};

// 0 if the boxes touch or overlap, else the shortest distance between them (hull to hull), m.
double box_gap(const Box2 &p_a, const Box2 &p_b);

// Where `p_b` is relative to `p_a`: along a's heading and to a's left (centre to centre), m.
void box_offset(const Box2 &p_a, const Box2 &p_b, double &r_along, double &r_left);

} // namespace noss::traffic
