#include "vehicle/tire.h"

#include <algorithm>
#include <cmath>

namespace noss::vehicle {

double tire_mu(const TireParams &p_tire, double p_fz) {
	double ratio = p_fz / std::max(p_tire.reference_load, 1.0);
	return p_tire.mu * std::max(0.3, 1.0 - p_tire.load_sensitivity * (ratio - 1.0));
}

double tire_curve(double p_shape, double p_s) {
	// Peak where C * atan(B * s) = pi/2, at s = 1.
	double b = std::tan(1.5707963267948966 / p_shape);
	return std::sin(p_shape * std::atan(b * p_s));
}

TireForce tire_force(const TireParams &p_tire, double p_fz, double p_mu, double p_kappa, double p_tan_alpha) {
	TireForce out;
	if (p_fz <= 0.0) {
		return out;
	}
	double sx = p_kappa / p_tire.peak_slip_ratio;
	double sy = p_tan_alpha / std::tan(p_tire.peak_slip_angle);
	double s = std::sqrt(sx * sx + sy * sy);
	out.combined = s;
	if (s < 1e-9) {
		return out;
	}
	double f = p_mu * p_fz * tire_curve(p_tire.shape, s);
	out.fx = f * sx / s;
	out.fy = -f * sy / s;
	// Pneumatic trail fades past the lateral peak, so the steering goes light at the limit.
	double trail = p_tire.pneumatic_trail * std::max(0.0, 1.0 - std::abs(sy) / 1.3);
	out.mz = -trail * out.fy;
	return out;
}

} // namespace noss::vehicle
