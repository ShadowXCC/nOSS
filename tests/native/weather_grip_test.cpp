#include <doctest/doctest.h>

#include <cmath>
#include <string>

#include "vehicle/maneuvers.h"
#include "vehicle_harness.h"

using namespace noss::test;

namespace {

// The same 10 s GT run as the kart layer's pinned test.
void gt_run(Harness &h) {
	for (int i = 0; i < 1200; i++) {
		double t = i / 120.0;
		h.model.controls.throttle = t < 7.0 ? 1.0 : 0.0;
		h.model.controls.brake = t >= 7.0 ? 0.6 : 0.0;
		h.model.controls.steer = t > 3.0 ? 0.25 * std::sin(1.7 * (t - 3.0)) : 0.0;
		h.step();
	}
}

double metric(const Config &p_config, const std::string &p_name, const std::string &p_metric, const Conditions &p_conditions) {
	ManeuverSpec spec;
	spec.name = p_name;
	spec.conditions = p_conditions;
	ManeuverResult r = run_maneuver(p_config, spec);
	REQUIRE_MESSAGE(r.ok(), p_name << ": " << r.error);
	for (const Metric &m : r.metrics) {
		if (m.name == p_metric) {
			return m.value;
		}
	}
	return std::nan("");
}

} // namespace

TEST_CASE("weather: grip per surface, wet and under snow") {
	CHECK(surface_grip(SURFACE_ASPHALT, {}) == 1.0);
	CHECK(surface_grip(SURFACE_ASPHALT, { 1.0, 0.0 }) == doctest::Approx(0.75));
	CHECK(surface_grip(SURFACE_ASPHALT, { 0.5, 0.0 }) == doctest::Approx(0.875));
	CHECK(surface_grip(SURFACE_PAINT, { 1.0, 0.0 }) == doctest::Approx(0.95 * 0.75));
	CHECK(surface_grip(SURFACE_CURB, { 1.0, 0.0 }) == doctest::Approx(0.90 * 0.75));
	CHECK(surface_grip(SURFACE_GRASS, { 1.0, 0.0 }) == doctest::Approx(0.60)); // loose: no change wet
	CHECK(surface_grip(SURFACE_ASPHALT, { 0.0, 1.0 }) == doctest::Approx(0.45));
	CHECK(surface_grip(SURFACE_ASPHALT, { 1.0, 1.0 }) == doctest::Approx(0.45)); // snow covers the water
	CHECK(surface_grip(SURFACE_GRASS, { 0.0, 1.0 }) == doctest::Approx(0.35));
	CHECK(surface_grip(SURFACE_ICE, { 1.0, 1.0 }) == doctest::Approx(0.12));
	// Out of range is clamped.
	CHECK(surface_grip(SURFACE_ASPHALT, { 2.0, -1.0 }) == doctest::Approx(0.75));
	for (int s = 0; s < SURFACE_COUNT; s++) {
		CHECK(surface_grip(s, {}) == surface_info(s).grip);
	}
}

TEST_CASE("weather: dry conditions set explicitly change nothing") {
	Harness h(make_config(gt_spec(), nsx_geometry()));
	h.model.conditions = { 0.0, 0.0 };
	h.model.assists.stability = true; // the stability limit scales with grip too
	Harness plain(make_config(gt_spec(), nsx_geometry()));
	plain.model.assists.stability = true;
	gt_run(h);
	gt_run(plain);
	CHECK(h.chassis.com.x == plain.chassis.com.x);
	CHECK(h.chassis.com.z == plain.chassis.com.z);
	CHECK(h.forward_speed() == plain.forward_speed());
	CHECK(h.heading() == plain.heading());
}

// ENV-02 / M9 acceptance: rain measurably lowers grip. On the flat harness with the reference GT:
// cornering grip falls by about the wet factor and braking distance grows by about its inverse.
TEST_CASE("weather: rain lowers cornering grip and lengthens braking") {
	Config config = make_config(gt_spec(), nsx_geometry(2.60, 1.60, 0.33));
	double dry_g = metric(config, "skidpad", "lat_g", {});
	double wet_g = metric(config, "skidpad", "lat_g", { 1.0, 0.0 });
	double half_g = metric(config, "skidpad", "lat_g", { 0.5, 0.0 });
	double dry_d = metric(config, "braking", "d_100_0_m", {});
	double wet_d = metric(config, "braking", "d_100_0_m", { 1.0, 0.0 });
	double snow_d = metric(config, "braking", "d_100_0_m", { 0.0, 1.0 });
	MESSAGE("skidpad dry " << dry_g << " g, half wet " << half_g << " g, wet " << wet_g << " g (" << wet_g / dry_g << "x)");
	MESSAGE("braking 100-0 dry " << dry_d << " m, wet " << wet_d << " m (" << wet_d / dry_d << "x), snow " << snow_d << " m");
	CHECK(wet_g / dry_g == doctest::Approx(0.75).epsilon(0.06));
	CHECK(half_g < dry_g);
	CHECK(half_g > wet_g);
	// Aero drag and rolling resistance don't scale with grip, so wet braking is a little under 1/0.75.
	CHECK(wet_d / dry_d > 1.2);
	CHECK(wet_d / dry_d < 1.4);
	CHECK(snow_d > wet_d);
}

TEST_CASE("weather: hotswap keeps the conditions") {
	Harness h(make_config(gt_spec(), nsx_geometry()));
	h.model.conditions = { 0.7, 0.2 };
	VehicleModel other(make_config(gt_spec(), nsx_geometry(2.4, 1.5, 0.32)));
	other.take_state(h.model);
	CHECK(other.conditions.wetness == 0.7);
	CHECK(other.conditions.snow == 0.2);
}
