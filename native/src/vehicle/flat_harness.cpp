#include "vehicle/flat_harness.h"

#include <cmath>
#include <vector>

namespace noss::vehicle {

FlatHarness::FlatHarness(const Config &p_config) :
		model(p_config) {
	const Config &c = model.config();
	_com_body = c.com;
	_inv_mass = 1.0 / c.mass;
	_inv_inertia = V3(1.0 / c.inertia.x, 1.0 / c.inertia.y, 1.0 / c.inertia.z);
	place_at(0.0, 0.0, 0.0);
}

void FlatHarness::place(const V3 &p_origin, const M3 &p_basis) {
	chassis.basis = p_basis;
	chassis.origin = p_origin;
	chassis.com = p_origin + p_basis * _com_body;
	chassis.velocity = V3();
	chassis.angular_velocity = V3();
}

void FlatHarness::place_at(double p_x, double p_z, double p_heading) {
	M3 basis = M3::axis_angle(V3(0, 1, 0), p_heading);
	// The wheels' contact plane (hub height minus radius) sits on the ground.
	const Config &c = model.config();
	double contact = 0.0;
	for (const WheelConfig &w : c.wheels) {
		contact += w.geo.hub.y - w.geo.radius;
	}
	contact /= double(std::max<size_t>(c.wheels.size(), 1));
	V3 com_flat = basis * V3(_com_body.x, 0.0, _com_body.z);
	place(V3(p_x - com_flat.x, ground_y - contact, p_z - com_flat.z), basis);
}

double FlatHarness::heading() const {
	return std::atan2(chassis.basis.c2.x, chassis.basis.c2.z);
}

double FlatHarness::slip_angle() const {
	V3 v = chassis.basis.transposed() * chassis.velocity;
	return std::abs(v.z) > 0.5 ? std::atan2(v.x, std::abs(v.z)) : 0.0;
}

void FlatHarness::step() {
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
				contacts[i].tags = tags;
			}
		}
	}
	StepResult f = model.step(chassis, contacts, DT);
	// Semi-implicit Euler.
	chassis.velocity += (f.force * _inv_mass + V3(0, -GRAVITY, 0)) * DT;
	const M3 &R = chassis.basis;
	V3 tau_body = R.transposed() * f.torque;
	V3 w_body = R.transposed() * chassis.angular_velocity;
	w_body += V3(tau_body.x * _inv_inertia.x, tau_body.y * _inv_inertia.y, tau_body.z * _inv_inertia.z) * DT;
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
	chassis.origin = chassis.com - chassis.basis * _com_body;
	time += DT;
}

void FlatHarness::run(double p_seconds) {
	int steps = int(std::lround(p_seconds / DT));
	for (int i = 0; i < steps; i++) {
		step();
	}
}

} // namespace noss::vehicle
