#include "vehicle/drivetrain.h"

#include <algorithm>
#include <cmath>

namespace noss::vehicle {

double engine_torque(const EngineSpec &p_engine, double p_rpm) {
	const auto &c = p_engine.torque_curve;
	if (c.empty()) {
		return 0.0;
	}
	if (p_rpm <= c.front().first) {
		return c.front().second;
	}
	for (size_t i = 1; i < c.size(); i++) {
		if (p_rpm <= c[i].first) {
			double t = (p_rpm - c[i - 1].first) / (c[i].first - c[i - 1].first);
			return c[i - 1].second + (c[i].second - c[i - 1].second) * t;
		}
	}
	return c.back().second;
}

double engine_friction(const EngineSpec &p_engine, double p_rpm) {
	double t = std::max(p_rpm, 0.0) / std::max(p_engine.limiter_rpm, 1.0);
	return p_engine.engine_brake * (0.25 + 0.75 * t);
}

double Gearbox::ratio(int p_gear) const {
	if (p_gear > 0 && p_gear <= top_gear()) {
		return spec.ratios[size_t(p_gear - 1)] * spec.final_drive;
	}
	if (p_gear == -1) {
		return -spec.reverse * spec.final_drive;
	}
	return 0.0;
}

bool Gearbox::request(int p_gear) {
	if (shifting() || p_gear == gear || p_gear < -1 || p_gear > top_gear()) {
		return false;
	}
	target = p_gear;
	// Into or out of neutral is instant; gear to gear takes the platform's shift time.
	shift_timer = (gear == 0 || p_gear == 0) ? 1e-6 : std::max(spec.shift_time, 1e-6);
	return true;
}

void Gearbox::update(double p_dt) {
	since_shift += p_dt;
	if (shift_timer > 0.0) {
		shift_timer -= p_dt;
		engage = 0.0;
		if (shift_timer <= 0.0) {
			shift_timer = 0.0;
			gear = target;
			since_shift = 0.0;
		}
		return;
	}
	engage = std::min(1.0, engage + p_dt / 0.08);
}

int AutoShifter::choose(const Gearbox &p_box, const EngineSpec &p_engine, const AutoShiftInput &p_in, double p_dt) {
	int gear = p_box.gear;
	if (p_box.shifting()) {
		return gear;
	}
	bool stopped = std::abs(p_in.forward_speed) < 0.6;

	// Reverse: hold the brake at a standstill. Throttle goes back to drive.
	if (gear >= 0 && stopped && p_in.brake > 0.3 && p_in.throttle < 0.05) {
		reverse_hold += p_dt;
		if (reverse_hold > 0.35) {
			reverse_hold = 0.0;
			return -1;
		}
	} else {
		reverse_hold = 0.0;
	}
	if (gear == -1) {
		return (p_in.throttle > 0.05 && p_in.forward_speed > -0.6) ? 1 : -1;
	}
	if (gear == 0) {
		return p_in.throttle > 0.02 ? 1 : 0;
	}
	if (p_box.since_shift < 0.35) {
		return gear;
	}

	double idle = p_engine.idle_rpm, red = p_engine.redline_rpm;
	double up_rpm = std::lerp(idle + 0.45 * (red - idle), red * 0.985, std::clamp(p_in.throttle, 0.0, 1.0));
	if (p_in.throttle < 0.1 || p_in.brake > 0.1) {
		up_rpm = red * 0.97; // off throttle, only upshift to save the engine
	}
	bool spinning = p_in.drive_slip > 2.0 * p_in.peak_slip;
	if (gear < p_box.top_gear() && p_in.rpm > up_rpm && !spinning) {
		return gear + 1;
	}
	if (gear > 1) {
		double down_rpm = p_in.rpm * p_box.ratio(gear - 1) / p_box.ratio(gear);
		double down_at = std::lerp(idle * 1.5, red * 0.62, std::clamp(p_in.throttle, 0.0, 1.0));
		if (p_in.brake > 0.2) {
			down_at = std::max(down_at, red * 0.55); // downshift early for engine braking
		}
		if (p_in.rpm < down_at && down_rpm < red * 0.9) {
			return gear - 1;
		}
	}
	return gear;
}

} // namespace noss::vehicle
