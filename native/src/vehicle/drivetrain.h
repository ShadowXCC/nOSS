#pragma once

// Engine, gearbox and clutch logic (docs/PHYSICS.md §5). The coupled spin of engine and
// wheels is solved in vehicle_model.cpp; this file holds the parts that don't need it.

#include <utility>
#include <vector>

namespace noss::vehicle {

struct EngineSpec {
	std::vector<std::pair<double, double>> torque_curve; // (rpm, Nm), ascending rpm
	double idle_rpm = 900.0;
	double redline_rpm = 7000.0;
	double limiter_rpm = 7200.0;
	double inertia = 0.15; // kg m^2
	double engine_brake = 50.0; // Nm of friction at the limiter
};

// Wide-open-throttle torque at p_rpm (linear between points, held past the ends).
double engine_torque(const EngineSpec &p_engine, double p_rpm);

// Friction torque (always >= 0) at p_rpm; it grows with speed.
double engine_friction(const EngineSpec &p_engine, double p_rpm);

enum class GearboxType {
	MANUAL_H,
	SEQUENTIAL,
	AUTO,
};

struct GearboxSpec {
	GearboxType type = GearboxType::SEQUENTIAL;
	std::vector<double> ratios; // forward gears, 1st first
	double reverse = 3.0;
	double final_drive = 3.7;
	double shift_time = 0.1; // s without drive per shift
};

// Gear numbers: -1 reverse, 0 neutral, 1..n forward.
struct Gearbox {
	GearboxSpec spec;
	int gear = 0;
	int target = 0; // gear being shifted into
	double shift_timer = 0.0; // > 0 while a shift is in progress
	double engage = 1.0; // clutch re-engagement ramp after a shift, 0..1
	double since_shift = 10.0; // s since the last shift finished

	int top_gear() const { return int(spec.ratios.size()); }
	bool shifting() const { return shift_timer > 0.0; }
	// Overall ratio, engine to wheels; negative in reverse, 0 in neutral.
	double ratio(int p_gear) const;
	double ratio() const { return ratio(gear); }
	// Starts a shift. Returns false if p_gear is invalid or a shift is already running.
	bool request(int p_gear);
	void update(double p_dt);
};

struct AutoShiftInput {
	double rpm = 0.0;
	double throttle = 0.0; // driver throttle, 0..1
	double brake = 0.0;
	double forward_speed = 0.0; // m/s, + forward
	double drive_slip = 0.0; // mean slip ratio of the driven wheels
	double peak_slip = 0.1;
};

// Picks the gear the automatic box wants, or the current one. Includes reverse when the
// driver holds the brake at a standstill.
struct AutoShifter {
	double reverse_hold = 0.0;
	int choose(const Gearbox &p_box, const EngineSpec &p_engine, const AutoShiftInput &p_in, double p_dt);
};

} // namespace noss::vehicle
