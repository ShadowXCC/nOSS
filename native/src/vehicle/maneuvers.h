#pragma once

// Standard maneuvers for the conformance runner (docs/PLATFORMS.md §5). Each runs one fitted
// configuration on the flat harness with the scripted driver and returns its metrics. Every
// metric is continuous (crossings are interpolated between ticks), so fits can be compared at
// a tight tolerance.

#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "vehicle/vehicle_model.h"

namespace noss::vehicle {

struct ManeuverSpec {
	std::string name; // see maneuver_names()
	// Lap: the track's closed centreline (x, z), its width and the start line's distance.
	std::vector<std::pair<double, double>> track;
	double track_width = 12.0;
	double track_start_s = 0.0;
	double lap_runup = 300.0; // m driven before the timed lap
	double skidpad_radius = 60.0;
	double slalom_spacing = 18.0;
	int slalom_gates = 10;
	double slalom_max_error = 1.0; // m of path error that ends a slalom speed
	double step_speed = 100.0 / 3.6; // m/s
	double step_lateral_g = 0.4; // steady-state target of the step input
	double top_speed_time = 60.0; // s
	double pace = 0.75; // lap speed as a share of the tires' grip
};

struct Metric {
	std::string name;
	double value; // NaN when not reached (e.g. 0-200 km/h on a slow platform)
};

struct ManeuverResult {
	std::string error;
	std::vector<Metric> metrics;
	bool ok() const { return error.empty(); }
};

const std::vector<std::string> &maneuver_names();
ManeuverResult run_maneuver(const Config &p_config, const ManeuverSpec &p_spec);

// Helpers, public for the tests.
// Time at which p_values first crosses p_level after p_from, linear between samples. NaN if never.
double first_crossing(const std::vector<double> &p_times, const std::vector<double> &p_values, double p_level, size_t p_from = 0);
// Root of p_f in [p_a, p_b] (p_f(a) and p_f(b) of opposite sign) by the Illinois method.
double find_root(const std::function<double(double)> &p_f, double p_a, double p_fa, double p_b, double p_fb, int p_iterations);

} // namespace noss::vehicle
