#pragma once

// Drives a VehicleModel on a flat plane with a simple rigid-body integrator, so the sim can
// be tested without Godot or Jolt. Only the wheels touch the ground.

#include <vector>

#include "vehicle/vehicle_model.h"

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

// NSX-like fitted geometry: ground at y = -0.1445.
inline Geometry nsx_geometry(double p_wheelbase = 2.551, double p_track = 1.572) {
	Geometry g;
	g.ground_y = -0.1445;
	double zf = 1.3335 - (2.551 - p_wheelbase) / 2.0, zr = zf - p_wheelbase;
	for (int i = 0; i < 4; i++) {
		WheelGeometry w;
		w.side = (i % 2 == 0) ? 1 : -1;
		w.axle = i / 2;
		w.radius = w.axle == 0 ? 0.30 : 0.314;
		w.hub = V3(w.side * p_track / 2.0, g.ground_y + w.radius, w.axle == 0 ? zf : zr);
		g.wheels.push_back(w);
	}
	return g;
}

struct Harness {
	VehicleModel model;
	Chassis chassis;
	V3 com_body;
	V3 inv_inertia;
	double inv_mass;
	double ground_y = 0.0;
	int surface = SURFACE_ASPHALT;
	double time = 0.0;
	static constexpr double DT = 1.0 / 120.0;

	explicit Harness(const Config &p_config) :
			model(p_config) {
		const Config &c = model.config();
		com_body = c.com;
		inv_mass = 1.0 / c.mass;
		inv_inertia = V3(1.0 / c.inertia.x, 1.0 / c.inertia.y, 1.0 / c.inertia.z);
		// Static: the model's ground plane sits on the world ground.
		place(V3(0, ground_y - model.config().com.y + c.cog_height, 0));
	}

	void place(const V3 &p_origin, const M3 &p_basis = M3()) {
		chassis.basis = p_basis;
		chassis.origin = p_origin;
		chassis.com = p_origin + p_basis * com_body;
		chassis.velocity = V3();
		chassis.angular_velocity = V3();
	}

	// Body-frame velocity helpers.
	double forward_speed() const { return dot(chassis.velocity, chassis.basis.c2); }
	double yaw_rate() const { return dot(chassis.angular_velocity, chassis.basis.c1); }
	double lateral_accel() const { return model.acceleration.x; }

	void step() {
		std::vector<Contact> contacts(model.wheels.size());
		for (size_t i = 0; i < contacts.size(); i++) {
			Ray ray = model.wheel_ray(int(i), chassis);
			if (ray.direction.y < -1e-6) {
				double t = (ray.origin.y - ground_y) / -ray.direction.y;
				if (t >= 0.0 && t <= ray.length) {
					contacts[i].hit = true;
					contacts[i].distance = t;
					contacts[i].point = ray.origin + ray.direction * t;
					contacts[i].normal = V3(0, 1, 0);
					contacts[i].surface = surface;
				}
			}
		}
		StepResult f = model.step(chassis, contacts, DT);
		// Semi-implicit Euler.
		chassis.velocity += (f.force * inv_mass + V3(0, -GRAVITY, 0)) * DT;
		const M3 &R = chassis.basis;
		V3 tau_body = R.transposed() * f.torque;
		V3 w_body = R.transposed() * chassis.angular_velocity;
		w_body += V3(tau_body.x * inv_inertia.x, tau_body.y * inv_inertia.y, tau_body.z * inv_inertia.z) * DT;
		chassis.angular_velocity = R * w_body;
		chassis.com += chassis.velocity * DT;
		double w = length(chassis.angular_velocity);
		if (w > 1e-9) {
			chassis.basis = M3::axis_angle(chassis.angular_velocity, w * DT) * chassis.basis;
			// Re-orthonormalize.
			V3 z = normalized(chassis.basis.c2);
			V3 x = normalized(cross(chassis.basis.c1, z));
			chassis.basis = { x, cross(z, x), z };
		}
		chassis.origin = chassis.com - chassis.basis * com_body;
		time += DT;
	}

	void run(double p_seconds) {
		for (double t = 0.0; t < p_seconds; t += DT) {
			step();
		}
	}
};

} // namespace noss::test
