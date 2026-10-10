#include <doctest/doctest.h>

#include <cmath>

#include "vehicle_harness.h"

using namespace noss::test;

namespace {

Harness gt() {
	return Harness(make_config(gt_spec(), nsx_geometry()));
}

double kmh(double p_ms) {
	return p_ms * 3.6;
}

} // namespace

TEST_CASE("tire: peak force at the peak slip, ellipse when combined") {
	TireParams t;
	double fz = 3000.0, mu = 1.4;
	CHECK(tire_force(t, fz, mu, t.peak_slip_ratio, 0.0).fx == doctest::Approx(mu * fz).epsilon(1e-6));
	CHECK(tire_force(t, fz, mu, 2.0 * t.peak_slip_ratio, 0.0).fx < mu * fz);
	CHECK(tire_force(t, fz, mu, -t.peak_slip_ratio, 0.0).fx == doctest::Approx(-mu * fz).epsilon(1e-6));
	// Sliding left gives a force to the right, with an aligning moment that straightens.
	TireForce lat = tire_force(t, fz, mu, 0.0, std::tan(t.peak_slip_angle) * 0.5);
	CHECK(lat.fy < 0.0);
	CHECK(lat.mz > 0.0);
	TireForce both = tire_force(t, fz, mu, t.peak_slip_ratio, std::tan(t.peak_slip_angle));
	CHECK(std::hypot(both.fx, both.fy) <= mu * fz * 1.0001);
	CHECK(both.fx < mu * fz * 0.8);
	CHECK(tire_mu(t, t.reference_load * 2.0) < t.mu);
}

TEST_CASE("drivetrain: torque curve and gearbox") {
	EngineSpec e = gt_spec().engine;
	CHECK(engine_torque(e, 6000) == doctest::Approx(560));
	CHECK(engine_torque(e, 5500) == doctest::Approx(550));
	CHECK(engine_torque(e, 500) == doctest::Approx(280));
	CHECK(engine_torque(e, 9000) == doctest::Approx(420));
	Gearbox box;
	box.spec = gt_spec().gearbox;
	CHECK(box.ratio(1) == doctest::Approx(3.10 * 3.70));
	CHECK(box.ratio(-1) < 0.0);
	CHECK(box.ratio(0) == 0.0);
	CHECK(box.request(1));
	box.update(0.01);
	CHECK(box.gear == 1); // out of neutral is instant
	CHECK(box.request(2));
	box.update(0.05);
	CHECK(box.gear == 1);
	box.update(0.05);
	CHECK(box.gear == 2);
	CHECK_FALSE(box.request(9));
}

TEST_CASE("config keeps the platform's invariants") {
	Config c = make_config(gt_spec(), nsx_geometry());
	double L = 2.551;
	CHECK(c.wheelbase == doctest::Approx(L));
	CHECK(c.com.z - c.axle_center[1].z == doctest::Approx(0.47 * L));
	CHECK(c.cog_height == doctest::Approx(0.28 * 1.572));
	double a = L * 0.53, b = L * 0.47;
	CHECK(c.inertia.y == doctest::Approx(0.95 * 1300 * a * b));
	double m_corner = 1300 * 0.47 / 2.0;
	CHECK(c.wheels[0].k == doctest::Approx(m_corner * std::pow(2 * PI * 2.8, 2)));
	CHECK(c.k_arb[0] > 0.0);
	CHECK(c.k_arb[1] > 0.0);
	// Steering scales with wheelbase, so turning circle stays the same.
	Config longer = make_config(gt_spec(), nsx_geometry(2.9));
	CHECK(longer.max_steer / c.max_steer == doctest::Approx(2.9 / L).epsilon(1e-3));
}

TEST_CASE("sim: settles at rest on its static ride height") {
	Harness h = gt();
	h.run(3.0);
	CHECK(length(h.chassis.velocity) < 0.01);
	for (const WheelState &w : h.model.wheels) {
		CHECK(w.contact);
		CHECK(std::abs(w.disp) < 0.005);
	}
	CHECK(h.model.rpm() == doctest::Approx(950).epsilon(0.1));
}

TEST_CASE("sim: launch, gears and top speed are sane") {
	Harness h = gt();
	h.model.controls.throttle = 1.0;
	double t100 = -1.0;
	while (h.time < 20.0) {
		h.step();
		if (t100 < 0.0 && kmh(h.forward_speed()) >= 100.0) {
			t100 = h.time;
		}
		REQUIRE(std::isfinite(h.forward_speed()));
		CHECK(h.model.rpm() < 8200 + 400);
	}
	MESSAGE("0-100 km/h: " << t100 << " s, 20 s speed " << kmh(h.forward_speed()) << " km/h, gear " << h.model.gearbox.gear);
	CHECK(t100 > 2.5);
	CHECK(t100 < 6.0);
	CHECK(h.model.gearbox.gear >= 5);
	CHECK(kmh(h.forward_speed()) > 200.0);
	CHECK(kmh(h.forward_speed()) < 280.0);
	CHECK(std::abs(h.chassis.com.x) < 0.5); // drives straight
}

TEST_CASE("sim: braking from 100 km/h with and without ABS") {
	for (bool use_abs : { true, false }) {
		Harness h = gt();
		h.model.assists.abs = use_abs;
		h.model.controls.throttle = 1.0;
		while (kmh(h.forward_speed()) < 100.0) {
			h.step();
		}
		h.model.controls.throttle = 0.0;
		h.model.controls.brake = 1.0;
		double start = h.chassis.com.z;
		while (h.forward_speed() > 0.1 && h.time < 30.0) {
			h.step();
		}
		double distance = h.chassis.com.z - start;
		MESSAGE((use_abs ? "ABS" : "no ABS") << " 100-0: " << distance << " m");
		CHECK(distance > 22.0);
		CHECK(distance < 45.0);
	}
}

TEST_CASE("sim: steering right turns right and holds a cornering load") {
	Harness h = gt();
	h.model.controls.throttle = 1.0;
	while (h.forward_speed() < 20.0) {
		h.step();
	}
	h.model.controls.steer = 0.25;
	double max_lat = 0.0;
	for (int i = 0; i < 600; i++) {
		// Hold about 20 m/s.
		h.model.controls.throttle = std::clamp((20.0 - h.forward_speed()) * 0.3, 0.0, 1.0);
		h.step();
		max_lat = std::max(max_lat, -h.lateral_accel());
		REQUIRE(std::isfinite(h.yaw_rate()));
	}
	MESSAGE("lateral " << max_lat / GRAVITY << " g, yaw " << h.yaw_rate() << " rad/s");
	CHECK(h.yaw_rate() < -0.2); // right turn: clockwise seen from above
	CHECK(max_lat > 0.6 * GRAVITY);
	CHECK(h.chassis.basis.c1.y > 0.95); // still upright
}

TEST_CASE("sim: auto box reverses when holding the brake at a standstill") {
	Harness h = gt();
	h.run(0.5);
	h.model.controls.brake = 1.0;
	h.run(1.0);
	CHECK(h.model.gearbox.gear == -1);
	h.run(2.0);
	CHECK(h.forward_speed() < -1.0);
	h.model.controls.brake = 0.0;
	h.model.controls.throttle = 1.0;
	h.run(3.0);
	CHECK(h.model.gearbox.gear >= 1);
	CHECK(h.forward_speed() > 1.0);
}

TEST_CASE("sim: rev limiter holds in neutral") {
	Harness h = gt();
	h.model.assists.auto_gearbox = false;
	h.model.controls.throttle = 1.0;
	double peak = 0.0;
	for (int i = 0; i < 240; i++) {
		h.step();
		peak = std::max(peak, h.model.rpm());
	}
	CHECK(peak > 8000);
	CHECK(peak < 8200 + 400);
	CHECK(length(h.chassis.velocity) < 0.05);
}

TEST_CASE("sim: same inputs give the same result") {
	Harness a = gt(), b = gt();
	for (Harness *h : { &a, &b }) {
		h->model.controls.throttle = 0.8;
		h->model.controls.steer = -0.2;
		h->run(4.0);
	}
	CHECK(a.chassis.com.x == b.chassis.com.x);
	CHECK(a.chassis.com.z == b.chassis.com.z);
	CHECK(a.model.rpm() == b.model.rpm());
}
