#pragma once

// Drives a VehicleModel on an infinite flat plane with a simple rigid-body integrator, so the
// sim runs without Godot or Jolt: native unit tests and the conformance runner
// (docs/PLATFORMS.md §5). Only the wheels touch the ground.

#include "vehicle/vehicle_model.h"

namespace noss::vehicle {

class FlatHarness {
public:
	static constexpr double DT = 1.0 / 120.0; // the game's physics tick

	VehicleModel model;
	Chassis chassis;
	double ground_y = 0.0;
	int surface = SURFACE_ASPHALT;
	double time = 0.0;

	explicit FlatHarness(const Config &p_config);

	void place(const V3 &p_origin, const M3 &p_basis = M3());
	// At rest on the ground, CoM above (p_x, p_z), facing p_heading (0 = +Z, + = turned left).
	void place_at(double p_x, double p_z, double p_heading);

	double forward_speed() const { return dot(chassis.velocity, chassis.basis.c2); }
	double yaw_rate() const { return dot(chassis.angular_velocity, chassis.basis.c1); }
	// Body-frame lateral acceleration, + = to the left.
	double lateral_accel() const { return model.acceleration.x; }
	// Heading of the body's +Z (0 = world +Z, + = turned toward +X, i.e. left).
	double heading() const;
	// Body slip angle at the CoM, rad, + = sliding toward the car's left.
	double slip_angle() const;

	void step();
	void run(double p_seconds);

private:
	V3 _com_body;
	V3 _inv_inertia;
	double _inv_mass = 0.0;
};

} // namespace noss::vehicle
