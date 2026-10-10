#pragma once

// Test fixtures for the vehicle sim: the GT platform and an NSX-like fitted geometry, driven
// by the flat-ground harness.

#include "vehicle/flat_harness.h"

namespace noss::test {

using namespace noss::vehicle;

// Track / GT as in data/platforms/track/gt.platform.json.
inline PlatformSpec gt_spec() {
	PlatformSpec s;
	s.mass = 1300.0;
	s.front_weight = 0.47;
	s.cog_height_over_track = 0.28;
	s.yaw_dynamic_index = 0.95;
	s.wheelbase_ref = 2.60;
	s.track_ref = 1.60;
	s.wheel_radius_ref = 0.33;
	s.drive = Drive::RWD;
	s.engine.torque_curve = { { 1000, 280 }, { 3000, 430 }, { 5000, 540 }, { 6000, 560 }, { 7500, 480 }, { 8200, 420 } };
	s.engine.idle_rpm = 950;
	s.engine.redline_rpm = 8000;
	s.engine.limiter_rpm = 8200;
	s.engine.inertia = 0.14;
	s.engine.engine_brake = 70;
	s.gearbox.type = GearboxType::SEQUENTIAL;
	s.gearbox.ratios = { 3.10, 2.25, 1.75, 1.42, 1.19, 1.02 };
	s.gearbox.reverse = 3.0;
	s.gearbox.final_drive = 3.70;
	s.gearbox.shift_time = 0.07;
	s.diff = DiffType::LSD_CLUTCH;
	s.diff_preload = 80;
	s.diff_power_lock = 0.45;
	s.diff_coast_lock = 0.25;
	s.brake_torque = 6000;
	s.brake_bias_front = 0.62;
	s.axles[0] = { 2.8, 0.55, 0.75, 0.08, true, false };
	s.axles[1] = { 2.6, 0.55, 0.75, 0.09, false, true };
	s.roll_gradient_deg_per_g = 0.9;
	s.roll_front_share = 0.55;
	s.max_steer_deg = 28;
	s.cd_a = 0.80;
	s.cl_a_front = -0.40;
	s.cl_a_rear = -0.60;
	s.tire.mu = 1.40;
	s.tire.load_sensitivity = 0.08;
	s.tire.peak_slip_ratio = 0.10;
	s.tire.peak_slip_angle = 7.5 * PI / 180.0;
	s.relaxation_length = 0.25;
	s.rolling_resistance = 0.012;
	return s;
}

// NSX-like fitted geometry: ground at y = -0.1445. p_radius < 0 keeps the NSX's radii.
inline Geometry nsx_geometry(double p_wheelbase = 2.551, double p_track = 1.572, double p_radius = -1.0) {
	Geometry g;
	g.ground_y = -0.1445;
	double zf = 1.3335 - (2.551 - p_wheelbase) / 2.0, zr = zf - p_wheelbase;
	for (int i = 0; i < 4; i++) {
		WheelGeometry w;
		w.side = (i % 2 == 0) ? 1 : -1;
		w.axle = i / 2;
		w.radius = p_radius > 0.0 ? p_radius : (w.axle == 0 ? 0.30 : 0.314);
		w.hub = V3(w.side * p_track / 2.0, g.ground_y + w.radius, w.axle == 0 ? zf : zr);
		g.wheels.push_back(w);
	}
	return g;
}

using Harness = FlatHarness;

} // namespace noss::test
