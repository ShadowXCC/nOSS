#pragma once

// "Pacejka-lite" tire (docs/PHYSICS.md §4): a simplified Magic Formula on a normalized,
// combined slip vector, so the friction limit is an ellipse.

namespace noss::vehicle {

struct TireParams {
	double mu = 1.4; // peak friction coefficient at the reference load
	double load_sensitivity = 0.08; // mu drops by this fraction per extra reference load
	double reference_load = 3000.0; // N, the static corner load
	double peak_slip_ratio = 0.10;
	double peak_slip_angle = 0.13; // rad
	double shape = 1.5; // Magic Formula C: higher drops off more past the peak
	double pneumatic_trail = 0.03; // m, at small slip angles
};

struct TireForce {
	double fx = 0.0; // along the wheel's forward direction
	double fy = 0.0; // along the wheel's left direction
	double mz = 0.0; // aligning moment about the contact normal (+ = turns the wheel left)
	double combined = 0.0; // normalized slip (1 = at the peak)
};

// Friction coefficient at load p_fz, before the surface grip factor.
double tire_mu(const TireParams &p_tire, double p_fz);

// Normalized Magic Formula curve: 0 at 0, peak 1 at s = 1, falls off past it.
double tire_curve(double p_shape, double p_s);

// Forces for slip ratio kappa and the tangent of the slip angle (+ = the contact patch slides
// left). p_mu includes load sensitivity and surface grip.
TireForce tire_force(const TireParams &p_tire, double p_fz, double p_mu, double p_kappa, double p_tan_alpha);

} // namespace noss::vehicle
