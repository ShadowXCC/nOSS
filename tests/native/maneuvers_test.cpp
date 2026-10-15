#include <doctest/doctest.h>

#include <chrono>
#include <cmath>
#include <string>

#include "vehicle/maneuvers.h"
#include "vehicle/path_driver.h"
#include "vehicle_harness.h"

using namespace noss::test;

namespace {

std::vector<std::pair<double, double>> circle(double p_radius, int p_points) {
	std::vector<std::pair<double, double>> points;
	for (int i = 0; i < p_points; i++) {
		double a = 2.0 * PI * i / p_points;
		points.emplace_back(p_radius - p_radius * std::cos(a), p_radius * std::sin(a));
	}
	return points;
}

double metric(const ManeuverResult &p_result, const std::string &p_name) {
	for (const Metric &m : p_result.metrics) {
		if (m.name == p_name) {
			return m.value;
		}
	}
	return std::nan("");
}

} // namespace

TEST_CASE("path: projection, curvature and wrapping") {
	Path ring(circle(60.0, 400), true);
	CHECK(ring.length() == doctest::Approx(2.0 * PI * 60.0).epsilon(1e-3));
	CHECK(ring.curvature_at(100.0) == doctest::Approx(1.0 / 60.0).epsilon(0.01));
	// A point outside the circle (to the right of a left turn) has negative lateral offset.
	Path::Projection p = ring.project(-1.0, 0.0);
	CHECK(p.lateral == doctest::Approx(-1.0).epsilon(0.01));
	CHECK(p.s == doctest::Approx(0.0).epsilon(0.01));
	CHECK(ring.wrap(-1.0) == doctest::Approx(ring.length() - 1.0));

	Path line({ { 0, 0 }, { 0, 50 }, { 0, 100 } }, false);
	Path::Projection q = line.project(2.0, 70.0, 1, 1);
	CHECK(q.s == doctest::Approx(70.0));
	CHECK(q.lateral == doctest::Approx(2.0)); // +X is left of a path heading +Z
	CHECK(q.heading == doctest::Approx(0.0));
	CHECK(line.curvature_at(50.0) == doctest::Approx(0.0));
}

TEST_CASE("maneuvers: crossing and root helpers") {
	std::vector<double> t = { 0, 1, 2, 3 }, v = { 0, 10, 20, 15 };
	CHECK(first_crossing(t, v, 5.0) == doctest::Approx(0.5));
	CHECK(first_crossing(t, v, 17.5) == doctest::Approx(1.75));
	CHECK(std::isnan(first_crossing(t, v, 30.0)));
	int calls = 0;
	auto f = [&](double x) {
		calls++;
		return x * x * x - 2.0;
	};
	double root = find_root(f, 0.0, f(0.0), 2.0, f(2.0), 12);
	CHECK(root == doctest::Approx(std::cbrt(2.0)).epsilon(1e-4));
}

TEST_CASE("maneuvers: every maneuver runs on the reference GT") {
	Config config = make_config(gt_spec(), nsx_geometry(2.60, 1.60, 0.33));
	std::vector<std::pair<double, double>> track = circle(150.0, 1000);
	for (const std::string &name : maneuver_names()) {
		ManeuverSpec spec;
		spec.name = name;
		spec.track = track;
		auto t0 = std::chrono::steady_clock::now();
		ManeuverResult r = run_maneuver(config, spec);
		double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
		std::string line = name + " (" + std::to_string(int(ms)) + " ms):";
		for (const Metric &m : r.metrics) {
			line += " " + m.name + "=" + std::to_string(m.value);
		}
		MESSAGE(line << (r.ok() ? "" : " ERROR " + r.error));
		CHECK_MESSAGE(r.ok(), name);
	}
}

TEST_CASE("maneuvers: results are plausible and deterministic") {
	Config config = make_config(gt_spec(), nsx_geometry(2.60, 1.60, 0.33));
	ManeuverSpec spec;
	spec.name = "launch";
	ManeuverResult a = run_maneuver(config, spec), b = run_maneuver(config, spec);
	CHECK(metric(a, "t_0_100_s") == metric(b, "t_0_100_s"));
	CHECK(metric(a, "t_0_100_s") > 3.0);
	CHECK(metric(a, "t_0_100_s") < 5.0);
	spec.name = "braking";
	double d = metric(run_maneuver(config, spec), "d_100_0_m");
	CHECK(d > 25.0);
	CHECK(d < 40.0);
	spec.name = "skidpad";
	double g = metric(run_maneuver(config, spec), "lat_g");
	CHECK(g > 1.1);
	CHECK(g < 1.6);
}

TEST_CASE("maneuvers: the kart layer's drift and boost") {
	PlatformSpec s = kart_spec();
	ManeuverSpec spec;
	spec.name = "drift";
	CHECK(run_maneuver(make_config(s, kart_geometry()), spec).metrics.empty()); // no layer, nothing to measure
	s.arcade = KartParams();
	ManeuverResult drift = run_maneuver(make_config(s, kart_geometry()), spec);
	REQUIRE_MESSAGE(drift.ok(), drift.error);
	CHECK(metric(drift, "drift_yaw_rad_s") > 0.4);
	CHECK(metric(drift, "drift_kmh") > 45.0);
	spec.name = "boost";
	ManeuverResult boost = run_maneuver(make_config(s, kart_geometry()), spec);
	REQUIRE_MESSAGE(boost.ok(), boost.error);
	CHECK(metric(boost, "boost_kmh") > 112.0);
	CHECK(metric(boost, "boost_kmh") <= 125.2);
	CHECK(metric(boost, "after_boost_kmh") < 106.0);
	// The same at the kart platform's smallest and largest geometry.
	for (auto geo : { kart_geometry(1.10, 1.00), kart_geometry(2.80, 1.70) }) {
		spec.name = "drift";
		ManeuverResult d = run_maneuver(make_config(s, geo), spec);
		CHECK(metric(d, "drift_yaw_rad_s") == doctest::Approx(metric(drift, "drift_yaw_rad_s")).epsilon(0.02));
		CHECK(metric(d, "drift_kmh") == doctest::Approx(metric(drift, "drift_kmh")).epsilon(0.02));
		spec.name = "boost";
		CHECK(metric(run_maneuver(make_config(s, geo), spec), "boost_kmh") == doctest::Approx(metric(boost, "boost_kmh")).epsilon(0.02));
	}
}
