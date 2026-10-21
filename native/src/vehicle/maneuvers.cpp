#include "vehicle/maneuvers.h"

#include <algorithm>
#include <cmath>
#include <limits>

#include "vehicle/flat_harness.h"
#include "vehicle/path_driver.h"

namespace noss::vehicle {

namespace {

constexpr double KMH = 1.0 / 3.6;
constexpr double DT = FlatHarness::DT;
const double NOT_REACHED = std::numeric_limits<double>::quiet_NaN();
constexpr double SETTLE_S = 0.5;
// Speed error under which a hold counts as reached; the gear is frozen from then on.
constexpr double HOLD_TOLERANCE = 0.5 * KMH;

using Points = std::vector<std::pair<double, double>>;

Path straight_path(double p_length) {
	Points points;
	for (double z = -20.0; z <= p_length; z += 4.0) {
		points.emplace_back(0.0, z);
	}
	return Path(points, false);
}

// Lets the car sit down on its springs before it moves.
void settle(FlatHarness &p_h) {
	p_h.model.controls = Controls();
	p_h.run(SETTLE_S);
}

// Linear interpolation of where p_level falls between two samples.
double between(double p_a, double p_b, double p_va, double p_vb, double p_level) {
	return p_vb == p_va ? p_b : p_a + (p_b - p_a) * (p_level - p_va) / (p_vb - p_va);
}

bool diverged(const FlatHarness &p_h) {
	return !std::isfinite(p_h.chassis.com.x) || !std::isfinite(p_h.chassis.velocity.z) || p_h.chassis.basis.c1.y < 0.3;
}

ManeuverResult fail(const std::string &p_error) {
	ManeuverResult r;
	r.error = p_error;
	return r;
}

// Full throttle along a straight: 0-100 and 0-200 km/h times, or the speed after a set time.
ManeuverResult launch(const Config &p_config, const ManeuverSpec &p_spec, bool p_top_speed) {
	FlatHarness h(p_config);
	h.model.conditions = p_spec.conditions;
	h.model.flats = p_spec.flats;
	Path path = straight_path(8000.0);
	PathDriver driver(path, p_config.spec);
	settle(h);
	double t0 = h.time;
	double t100 = NOT_REACHED, t200 = NOT_REACHED;
	double prev_t = 0.0, prev_v = 0.0;
	int steps = int(std::lround((p_top_speed ? p_spec.top_speed_time : 60.0) / DT));
	for (int i = 0; i <= steps; i++) {
		double steer = driver.steer(h);
		double t = h.time - t0, v = h.forward_speed() / KMH;
		if (i > 0) {
			if (std::isnan(t100) && prev_v < 100.0 && v >= 100.0) {
				t100 = between(prev_t, t, prev_v, v, 100.0);
			}
			if (std::isnan(t200) && prev_v < 200.0 && v >= 200.0) {
				t200 = between(prev_t, t, prev_v, v, 200.0);
			}
		}
		if (i == steps || (!p_top_speed && !std::isnan(t200))) {
			break;
		}
		prev_t = t;
		prev_v = v;
		h.model.controls.steer = steer;
		h.model.controls.throttle = 1.0;
		h.model.controls.brake = 0.0;
		h.step();
		if (diverged(h)) {
			return fail("Sim diverged");
		}
	}
	ManeuverResult r;
	if (p_top_speed) {
		r.metrics.push_back({ "v_60s_kmh", h.forward_speed() / KMH });
	} else {
		r.metrics.push_back({ "t_0_100_s", t100 });
		r.metrics.push_back({ "t_0_200_s", t200 });
	}
	return r;
}

// Holds p_target on a straight until it has been steady for p_hold seconds, then freezes the
// gear. Returns false if the speed was never reached.
bool hold_speed(FlatHarness &p_h, PathDriver &p_driver, double p_target, double p_hold, double &r_throttle) {
	double held = 0.0;
	bool frozen = false;
	double start = p_h.time;
	while (held < p_hold) {
		double steer = p_driver.steer(p_h);
		double throttle, brake;
		p_driver.speed(p_h, p_target, throttle, brake);
		if (!frozen && std::abs(p_h.forward_speed() - p_target) < HOLD_TOLERANCE) {
			frozen = true;
			p_h.model.assists.auto_gearbox = false;
		}
		if (frozen) {
			held += DT;
		}
		p_h.model.controls.steer = steer;
		p_h.model.controls.throttle = throttle;
		p_h.model.controls.brake = brake;
		r_throttle = throttle;
		p_h.step();
		if (diverged(p_h) || p_h.time - start > 120.0) {
			return false;
		}
	}
	return true;
}

// Brake speed (100 km/h on most platforms) to 0 with full brake and ABS, from a steady 2 km/h
// above it.
ManeuverResult braking(const Config &p_config, const ManeuverSpec &p_spec) {
	FlatHarness h(p_config);
	h.model.conditions = p_spec.conditions;
	h.model.flats = p_spec.flats;
	Path path = straight_path(8000.0);
	PathDriver driver(path, p_config.spec);
	settle(h);
	const double from = p_spec.brake_speed * KMH;
	double throttle;
	if (!hold_speed(h, driver, from + 2.0 * KMH, 2.0, throttle)) {
		return fail("Can't reach " + std::to_string(int(p_spec.brake_speed)) + " km/h");
	}
	double s100 = NOT_REACHED, s_stop = NOT_REACHED;
	double prev_s = 0.0, prev_v = 0.0;
	double start = h.time;
	for (int i = 0; h.time - start < 30.0; i++) {
		double steer = driver.steer(h);
		double s = driver.progress(), v = h.forward_speed();
		if (i > 0) {
			if (std::isnan(s100) && prev_v >= from && v < from) {
				s100 = between(prev_s, s, prev_v, v, from);
			}
			if (prev_v >= 0.5 && v < 0.5) {
				s_stop = between(prev_s, s, prev_v, v, 0.5);
				break;
			}
		}
		prev_s = s;
		prev_v = v;
		h.model.controls.steer = steer;
		h.model.controls.throttle = 0.0;
		h.model.controls.brake = 1.0;
		h.step();
		if (diverged(h)) {
			return fail("Sim diverged");
		}
	}
	if (std::isnan(s100) || std::isnan(s_stop)) {
		return fail("Didn't stop");
	}
	ManeuverResult r;
	r.metrics.push_back({ "d_" + std::to_string(int(p_spec.brake_speed)) + "_0_m", s_stop - s100 });
	return r;
}

// Constant-radius circle, speed ramping up: the best 2 s of lateral acceleration while the car
// still holds the line.
ManeuverResult skidpad(const Config &p_config, const ManeuverSpec &p_spec) {
	double radius = p_spec.skidpad_radius;
	Points points;
	int n = int(std::ceil(2.0 * PI * radius));
	for (int i = 0; i < n; i++) {
		double a = 2.0 * PI * i / n;
		points.emplace_back(radius - radius * std::cos(a), radius * std::sin(a)); // left turn
	}
	Path path(points, true);
	FlatHarness h(p_config);
	h.model.conditions = p_spec.conditions;
	h.model.flats = p_spec.flats;
	DriverParams params;
	params.lateral_time = 4.0;
	PathDriver driver(path, p_config.spec, params);
	settle(h);
	double t0 = h.time;
	const int window = int(std::lround(2.0 / DT));
	std::vector<double> ring(size_t(window), 0.0);
	int count = 0;
	double sum = 0.0, best = NOT_REACHED;
	while (h.time - t0 < 240.0) {
		double steer = driver.steer(h);
		double t = h.time - t0;
		double target = 5.0 + 0.25 * t;
		double e = driver.projection().lateral, beta = h.slip_angle();
		bool valid = t > 2.0 && std::abs(e) < 0.5 && std::abs(beta) < 8.0 * PI / 180.0;
		if (valid) {
			double ay = std::abs(h.lateral_accel());
			size_t slot = size_t(count % window);
			sum += ay - (count >= window ? ring[slot] : 0.0);
			ring[slot] = ay;
			count++;
			if (count >= window) {
				best = std::isnan(best) ? sum / window : std::max(best, sum / window);
			}
		} else {
			count = 0;
			sum = 0.0;
		}
		if (t > 2.0 && (std::abs(e) > 3.0 || std::abs(beta) > 20.0 * PI / 180.0 || target - h.forward_speed() > 4.0)) {
			break;
		}
		double throttle, brake;
		driver.speed(h, target, throttle, brake);
		h.model.controls.steer = steer;
		h.model.controls.throttle = throttle;
		h.model.controls.brake = brake;
		h.step();
		if (diverged(h)) {
			return fail("Sim diverged");
		}
	}
	if (std::isnan(best)) {
		return fail("Couldn't hold the circle");
	}
	ManeuverResult r;
	r.metrics.push_back({ "lat_g", best / GRAVITY });
	return r;
}

// At a steady speed, a quick steering step to a fixed input: yaw-rate rise time and overshoot.
ManeuverResult step_steer(const Config &p_config, const ManeuverSpec &p_spec) {
	FlatHarness h(p_config);
	h.model.conditions = p_spec.conditions;
	h.model.flats = p_spec.flats;
	Path path = straight_path(8000.0);
	PathDriver driver(path, p_config.spec);
	settle(h);
	double v = p_spec.step_speed;
	double throttle = 0.0;
	if (!hold_speed(h, driver, v, 3.0, throttle)) {
		return fail("Can't reach the step speed");
	}
	// The input that would give the target lateral acceleration on the reference car.
	double curvature = p_spec.step_lateral_g * GRAVITY / (v * v);
	double input = -curvature * p_config.spec.wheelbase_ref / (p_config.spec.max_steer_deg * PI / 180.0);
	std::vector<double> times, yaw;
	double start = h.time;
	while (h.time - start < 3.0) {
		double t = h.time - start;
		times.push_back(t);
		yaw.push_back(h.yaw_rate());
		h.model.controls.steer = input * std::min(t / 0.05, 1.0);
		h.model.controls.throttle = throttle;
		h.model.controls.brake = 0.0;
		h.step();
		if (diverged(h)) {
			return fail("Sim diverged");
		}
	}
	double steady = 0.0;
	int n = 0;
	for (size_t i = 0; i < times.size(); i++) {
		if (times[i] >= 2.0) {
			steady += yaw[i];
			n++;
		}
	}
	steady /= std::max(n, 1);
	if (steady <= 1e-4) {
		return fail("No yaw response");
	}
	double t10 = first_crossing(times, yaw, 0.1 * steady);
	double t90 = first_crossing(times, yaw, 0.9 * steady);
	double peak = *std::max_element(yaw.begin(), yaw.end());
	ManeuverResult r;
	r.metrics.push_back({ "yaw_rise_s", t90 - t10 });
	r.metrics.push_back({ "yaw_peak_ratio", peak / steady });
	return r;
}

// Highest steady speed at which the car follows an 18 m slalom within a set path error.
ManeuverResult slalom(const Config &p_config, const ManeuverSpec &p_spec) {
	const double runup = 400.0, spacing = p_spec.slalom_spacing;
	const double length = spacing * p_spec.slalom_gates;
	const double amplitude = 0.5 * p_config.spec.track_ref + 0.5;
	Points points;
	for (double z = -runup; z < 0.0; z += 2.0) {
		points.emplace_back(0.0, z);
	}
	for (double z = 0.0; z <= length; z += 0.5) {
		// The weave fades in over the first half gate and out over the last.
		double in = std::clamp(z / (0.5 * spacing), 0.0, 1.0), out = std::clamp((length - z) / (0.5 * spacing), 0.0, 1.0);
		double w = std::min(in * in * (3.0 - 2.0 * in), out * out * (3.0 - 2.0 * out));
		points.emplace_back(amplitude * w * std::sin(PI * z / spacing), z);
	}
	for (double z = length + 2.0; z <= length + 200.0; z += 2.0) {
		points.emplace_back(0.0, z);
	}
	Path path(points, false);

	// Worst path error between the first and last gate at p_kmh.
	auto error_at = [&](double p_kmh) -> double {
		FlatHarness h(p_config);
	h.model.conditions = p_spec.conditions;
	h.model.flats = p_spec.flats;
		h.place_at(0.0, -runup, 0.0);
		PathDriver driver(path, p_config.spec);
		settle(h);
		double target = p_kmh * KMH;
		bool frozen = false;
		double worst = 0.0, start = h.time;
		while (h.time - start < 120.0) {
			double steer = driver.steer(h);
			double z = h.chassis.com.z;
			if (z >= 0.5 * spacing && z <= length - 0.5 * spacing) {
				worst = std::max(worst, std::abs(driver.projection().lateral));
			}
			if (z > length) {
				return worst;
			}
			double throttle, brake;
			driver.speed(h, target, throttle, brake);
			if (!frozen && std::abs(h.forward_speed() - target) < HOLD_TOLERANCE) {
				frozen = true;
				h.model.assists.auto_gearbox = false;
			}
			h.model.controls.steer = steer;
			h.model.controls.throttle = throttle;
			h.model.controls.brake = brake;
			h.step();
			if (diverged(h)) {
				return 1e9;
			}
		}
		return 1e9;
	};

	double limit = p_spec.slalom_max_error;
	double v = 30.0, e = error_at(v);
	if (e > limit) {
		return fail("Can't do the slalom at 30 km/h");
	}
	ManeuverResult r;
	double best = NOT_REACHED;
	for (double next = v + 4.0; next <= 250.0; next += 4.0) {
		double e_next = error_at(next);
		if (e_next > limit) {
			best = find_root([&](double p_v) { return error_at(p_v) - limit; }, v, e - limit, next, e_next - limit, 6);
			break;
		}
		v = next;
		e = e_next;
	}
	r.metrics.push_back({ "v_max_kmh", best });
	return r;
}

// A flying lap of the track's centreline at a set share of the tires' grip.
ManeuverResult lap(const Config &p_config, const ManeuverSpec &p_spec) {
	if (p_spec.track.size() < 3) {
		return fail("No track");
	}
	Path path(p_spec.track, true);
	double grip = p_config.spec.tire.mu * surface_grip(SURFACE_ASPHALT, p_spec.conditions) * GRAVITY * p_spec.pace;
	std::vector<double> profile = speed_profile(path, grip, 0.9 * grip, 120.0);
	double x, z, heading;
	path.point_at(p_spec.track_start_s - p_spec.lap_runup, x, z, heading);
	FlatHarness h(p_config);
	h.model.conditions = p_spec.conditions;
	h.model.flats = p_spec.flats;
	h.place_at(x, z, heading);
	PathDriver driver(path, p_config.spec);
	settle(h);
	double limit = 0.5 * p_spec.track_width - 0.5 * p_config.spec.track_ref;
	double begin = p_spec.lap_runup, end = p_spec.lap_runup + path.length();
	double t_begin = NOT_REACHED, t_end = NOT_REACHED;
	double prev_p = 0.0, prev_t = 0.0;
	double start = h.time;
	for (int i = 0; h.time - start < 900.0; i++) {
		double steer = driver.steer(h);
		double p = driver.progress(), t = h.time - start;
		if (i > 0) {
			if (std::isnan(t_begin) && prev_p < begin && p >= begin) {
				t_begin = between(prev_t, t, prev_p, p, begin);
			}
			if (prev_p < end && p >= end) {
				t_end = between(prev_t, t, prev_p, p, end);
				break;
			}
		}
		if (t > 1.0 && std::abs(driver.projection().lateral) > limit) {
			return fail("Off track at " + std::to_string(int(driver.projection().s)) + " m, " + std::to_string(int(h.forward_speed() / KMH)) + " km/h");
		}
		prev_p = p;
		prev_t = t;
		double v = h.forward_speed();
		double target = profile[path.index_at(driver.projection().s + std::max(v, 0.0) * 0.5)];
		double throttle, brake;
		driver.speed(h, target, throttle, brake);
		h.model.controls.steer = steer;
		h.model.controls.throttle = throttle;
		h.model.controls.brake = brake;
		h.step();
		if (diverged(h)) {
			return fail("Sim diverged");
		}
	}
	if (std::isnan(t_end) || std::isnan(t_begin)) {
		return fail("Lap not finished");
	}
	ManeuverResult r;
	r.metrics.push_back({ "lap_s", t_end - t_begin });
	return r;
}

// Kart layer (D130): a held drift from a steady 50 km/h (or half the geared top speed), steering
// half into it at full throttle for 3 s; its yaw rate and speed over the last second. Platforms
// without the layer have no metrics.
ManeuverResult drift(const Config &p_config, const ManeuverSpec &) {
	ManeuverResult r;
	if (!p_config.spec.arcade) {
		return r;
	}
	FlatHarness h(p_config);
	Path path = straight_path(8000.0);
	PathDriver driver(path, p_config.spec);
	settle(h);
	double throttle;
	double entry = std::min(50.0 * KMH, 0.5 * KartLayer::geared_top(p_config));
	if (!hold_speed(h, driver, entry, 1.0, throttle)) {
		return fail("Can't reach the drift's speed");
	}
	h.model.kart->drift = true;
	h.model.controls = Controls();
	h.model.controls.throttle = 1.0;
	h.model.controls.steer = 0.6;
	double yaw = 0.0, speed = 0.0;
	for (int i = 0; i < int(4.0 / DT); i++) {
		if (h.model.kart->drift_dir != 0) {
			h.model.controls.steer = 0.5;
		}
		h.step();
		if (diverged(h)) {
			return fail("Sim diverged");
		}
		if (i >= int(3.0 / DT)) {
			yaw += std::abs(h.yaw_rate()) * DT;
			speed += h.forward_speed() / KMH * DT;
		}
	}
	if (h.model.kart->drift_dir == 0) {
		return fail("No drift");
	}
	r.metrics.push_back({ "drift_yaw_rad_s", yaw });
	r.metrics.push_back({ "drift_kmh", speed });
	return r;
}

// Kart layer: 2 s of boost from the top speed at full throttle; the speed it reaches.
ManeuverResult boost(const Config &p_config, const ManeuverSpec &) {
	ManeuverResult r;
	if (!p_config.spec.arcade) {
		return r;
	}
	FlatHarness h(p_config);
	Path path = straight_path(8000.0);
	PathDriver driver(path, p_config.spec);
	settle(h);
	for (int i = 0; i < int(16.0 / DT); i++) {
		if (i == int(12.0 / DT)) {
			h.model.kart->effect(KART_BOOST, 2.0);
		}
		h.model.controls.steer = driver.steer(h);
		h.model.controls.throttle = 1.0;
		h.step();
		if (diverged(h)) {
			return fail("Sim diverged");
		}
		if (i == int(14.0 / DT)) {
			r.metrics.push_back({ "boost_kmh", h.forward_speed() / KMH });
		}
	}
	r.metrics.push_back({ "after_boost_kmh", h.forward_speed() / KMH });
	return r;
}

} // namespace

const std::vector<std::string> &maneuver_names() {
	static const std::vector<std::string> names = { "launch", "top_speed", "braking", "skidpad", "step_steer", "slalom", "lap", "drift", "boost" };
	return names;
}

ManeuverResult run_maneuver(const Config &p_config, const ManeuverSpec &p_spec) {
	const std::string &n = p_spec.name;
	if (n == "launch") {
		return launch(p_config, p_spec, false);
	}
	if (n == "top_speed") {
		return launch(p_config, p_spec, true);
	}
	if (n == "braking") {
		return braking(p_config, p_spec);
	}
	if (n == "skidpad") {
		return skidpad(p_config, p_spec);
	}
	if (n == "step_steer") {
		return step_steer(p_config, p_spec);
	}
	if (n == "slalom") {
		return slalom(p_config, p_spec);
	}
	if (n == "lap") {
		return lap(p_config, p_spec);
	}
	if (n == "drift") {
		return drift(p_config, p_spec);
	}
	if (n == "boost") {
		return boost(p_config, p_spec);
	}
	return fail("Unknown maneuver: " + n);
}

double first_crossing(const std::vector<double> &p_times, const std::vector<double> &p_values, double p_level, size_t p_from) {
	for (size_t i = std::max<size_t>(p_from, 1); i < p_values.size() && i < p_times.size(); i++) {
		double a = p_values[i - 1] - p_level, b = p_values[i] - p_level;
		if ((a < 0.0 && b >= 0.0) || (a > 0.0 && b <= 0.0)) {
			return between(p_times[i - 1], p_times[i], p_values[i - 1], p_values[i], p_level);
		}
	}
	return NOT_REACHED;
}

double find_root(const std::function<double(double)> &p_f, double p_a, double p_fa, double p_b, double p_fb, int p_iterations) {
	int side = 0;
	double c = p_b;
	for (int i = 0; i < p_iterations; i++) {
		if (p_fb == p_fa) {
			break;
		}
		c = (p_a * p_fb - p_b * p_fa) / (p_fb - p_fa);
		double fc = p_f(c);
		if (fc == 0.0) {
			return c;
		}
		if ((fc > 0.0) == (p_fb > 0.0)) {
			p_b = c;
			p_fb = fc;
			if (side == -1) {
				p_fa /= 2.0;
			}
			side = -1;
		} else {
			p_a = c;
			p_fa = fc;
			if (side == 1) {
				p_fb /= 2.0;
			}
			side = 1;
		}
	}
	return c;
}

} // namespace noss::vehicle
