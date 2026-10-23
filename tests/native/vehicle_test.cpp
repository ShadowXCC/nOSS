#include <doctest/doctest.h>

#include <cmath>
#include <string>

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
	// Yaw uses the reference wheelbase (tire forces act at the reference arms); pitch the fitted one.
	CHECK(c.inertia.y == doctest::Approx(0.95 * 1300 * 0.53 * 0.47 * 2.6 * 2.6));
	CHECK(c.inertia.x == doctest::Approx(0.9 * 0.95 * 1300 * 0.53 * 0.47 * L * L));
	double m_corner = 1300 * 0.47 / 2.0;
	CHECK(c.wheels[0].k == doctest::Approx(m_corner * std::pow(2 * PI * 2.8, 2)));
	CHECK(c.k_arb[0] > 0.0);
	CHECK(c.k_arb[1] > 0.0);
	// Steering is the platform's, whatever the fit.
	Config longer = make_config(gt_spec(), nsx_geometry(2.9));
	CHECK(longer.max_steer == doctest::Approx(c.max_steer));
	CHECK(c.max_steer == doctest::Approx(28.0 * PI / 180.0));
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
		MESSAGE(std::string(use_abs ? "ABS" : "no ABS") << " 100-0: " << distance << " m");
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

TEST_CASE("sim: TCS keeps full throttle in first gear out of a tight corner") {
	for (bool tcs : { true, false }) {
		Harness h = gt();
		h.model.assists.auto_gearbox = false;
		h.model.assists.tcs = tcs;
		h.model.controls.select_gear = 1;
		h.model.controls.throttle = 0.6;
		while (h.forward_speed() < 14.0) {
			h.step();
		}
		h.model.controls.throttle = 0.0;
		h.model.controls.steer = -0.45;
		h.run(1.0); // settle into the corner
		h.model.controls.throttle = 1.0;
		double worst = 0.0;
		for (int i = 0; i < 240; i++) {
			h.step();
			V3 v = h.chassis.basis.transposed() * h.chassis.velocity;
			if (std::abs(v.z) > 1.0) {
				worst = std::max(worst, std::abs(std::atan2(v.x, std::abs(v.z))));
			}
		}
		MESSAGE(std::string(tcs ? "TCS" : "no TCS") << " body slip " << worst * 180.0 / PI << " deg");
		if (tcs) {
			CHECK(worst < 15.0 * PI / 180.0);
		}
	}
}

TEST_CASE("sim: an H-pattern box needs the clutch; an automatic platform shifts itself") {
	PlatformSpec spec = gt_spec();
	spec.gearbox.type = GearboxType::MANUAL_H;
	Harness h(make_config(spec, nsx_geometry()));
	h.model.assists.auto_gearbox = false;
	h.model.assists.auto_clutch = false;
	h.model.controls.clutch = 1.0;
	h.model.controls.select_gear = 1;
	h.run(0.5);
	CHECK(h.model.gearbox.gear == 1);
	// Clutch out: 2nd is refused and grinds; neutral still works.
	h.model.controls.clutch = 0.0;
	h.model.controls.select_gear = 2;
	h.run(0.3);
	CHECK(h.model.gearbox.gear == 1);
	CHECK(h.model.grinds == 1);
	h.model.controls.select_gear = 0;
	h.run(0.3);
	CHECK(h.model.gearbox.gear == 0);
	// With the auto clutch the same change goes through.
	h.model.assists.auto_clutch = true;
	h.model.controls.select_gear = 2;
	h.run(0.3);
	CHECK(h.model.gearbox.gear == 2);

	PlatformSpec auto_spec = gt_spec();
	auto_spec.gearbox.type = GearboxType::AUTO;
	Harness a(make_config(auto_spec, nsx_geometry()));
	a.model.assists.auto_gearbox = false; // the platform is automatic anyway
	a.model.controls.throttle = 1.0;
	a.run(6.0);
	CHECK(a.model.gearbox.gear >= 3);
	int gear = a.model.gearbox.gear;
	a.model.controls.shift = -1; // paddles do nothing on an automatic
	a.step();
	CHECK(a.model.gearbox.target == gear);
}

TEST_CASE("sim: stability control catches trail-braking oversteer") {
	// Hard braking from speed into a corner on a rear-biased balance: the rear runs out of grip
	// and the car turns round. Stability control brakes the outside front and keeps it straighter.
	double worst_by[2] = { 0.0, 0.0 };
	for (bool esc : { false, true }) {
		Harness h = gt();
		h.model.assists.stability = esc;
		h.model.controls.throttle = 1.0;
		while (kmh(h.forward_speed()) < 160.0) {
			h.step();
		}
		h.model.controls.throttle = 0.0;
		h.model.controls.brake = 0.9;
		h.model.controls.steer = 0.18;
		double worst = 0.0;
		bool active = false;
		for (int i = 0; i < 300 && h.forward_speed() > 5.0; i++) {
			h.step();
			worst = std::max(worst, std::abs(h.slip_angle()));
			active = active || h.model.stability_active;
		}
		worst_by[esc ? 1 : 0] = worst;
		MESSAGE(std::string(esc ? "stability" : "no stability") << " peak body slip " << worst * 180.0 / PI << " deg");
		if (esc) {
			CHECK(active);
		}
	}
	CHECK(worst_by[1] < worst_by[0] * 0.7);
	CHECK(worst_by[1] < 12.0 * PI / 180.0);
}

TEST_CASE("sim: stability control stays out of a steady corner") {
	Harness h = gt();
	h.model.assists.stability = true;
	h.model.controls.throttle = 0.5;
	while (kmh(h.forward_speed()) < 80.0) {
		h.step();
	}
	h.model.controls.steer = 0.1;
	h.model.controls.throttle = 0.35;
	h.run(2.0); // settle
	int active = 0;
	for (int i = 0; i < 240; i++) {
		h.step();
		active += h.model.stability_active ? 1 : 0;
	}
	MESSAGE("stability active " << active << " of 240 ticks in a steady corner");
	CHECK(active < 24);
}

namespace {

PlatformSpec awd_spec(CenterType p_center) {
	PlatformSpec s = gt_spec();
	s.axles[0].driven = true;
	s.axle_diff[0] = { DiffType::OPEN, 0, 0, 0 };
	s.center.type = p_center;
	s.center.front_share = 0.4;
	s.center.viscous = 60.0;
	return s;
}

// Mean wheel speed of each axle.
double axle_omega(const Harness &p_h, int p_axle) {
	double sum = 0.0;
	int n = 0;
	for (size_t i = 0; i < p_h.model.wheels.size(); i++) {
		if (p_h.model.config().wheels[i].geo.axle == p_axle) {
			sum += p_h.model.wheels[i].omega;
			n++;
		}
	}
	return sum / std::max(n, 1);
}

// Drive force of each axle, summed over its wheels.
double axle_fx(const Harness &p_h, int p_axle) {
	double sum = 0.0;
	for (size_t i = 0; i < p_h.model.wheels.size(); i++) {
		if (p_h.model.config().wheels[i].geo.axle == p_axle) {
			sum += p_h.model.wheels[i].fx;
		}
	}
	return sum;
}

} // namespace

TEST_CASE("drivetrain: AWD with an open center splits the torque") {
	Harness h(make_config(awd_spec(CenterType::OPEN), nsx_geometry()));
	h.model.assists.auto_gearbox = false;
	h.model.controls.select_gear = 2;
	h.model.controls.throttle = 0.5;
	h.run(3.0);
	double front = axle_fx(h, 0), rear = axle_fx(h, 1);
	MESSAGE("front share of drive force " << front / (front + rear));
	CHECK(front / (front + rear) == doctest::Approx(0.4).epsilon(0.05));
}

TEST_CASE("drivetrain: a locked center holds both axles at one speed") {
	Harness h(make_config(awd_spec(CenterType::LOCKED), nsx_geometry()));
	h.model.controls.throttle = 1.0;
	double worst = 0.0;
	for (int i = 0; i < 480; i++) {
		h.step();
		worst = std::max(worst, std::abs(axle_omega(h, 0) - axle_omega(h, 1)));
	}
	CHECK(worst < 0.05);
	CHECK(h.forward_speed() > 15.0);
}

TEST_CASE("drivetrain: a viscous center sits between open and locked") {
	auto spread = [](CenterType p_type) {
		PlatformSpec s = awd_spec(p_type);
		s.center.front_share = 0.1; // the rear gets most torque, so it spins up first
		Harness h(make_config(s, nsx_geometry()));
		h.model.assists.tcs = false;
		h.model.controls.throttle = 1.0;
		double worst = 0.0;
		for (int i = 0; i < 240; i++) {
			h.step();
			worst = std::max(worst, axle_omega(h, 1) - axle_omega(h, 0));
		}
		return worst;
	};
	double open = spread(CenterType::OPEN), viscous = spread(CenterType::VISCOUS), locked = spread(CenterType::LOCKED);
	MESSAGE("rear minus front spin: open " << open << ", viscous " << viscous << ", locked " << locked);
	CHECK(viscous < open);
	CHECK(locked <= viscous);
}

TEST_CASE("drivetrain: FWD pulls with the front axle") {
	PlatformSpec s = gt_spec();
	s.axles[0].driven = true;
	s.axles[1].driven = false;
	Harness h(make_config(s, nsx_geometry()));
	h.model.controls.throttle = 1.0;
	h.run(3.0);
	CHECK(h.forward_speed() > 10.0); // traction-limited: only 47% of the weight is on the front
	CHECK(axle_fx(h, 0) > 0.0);
	CHECK(std::abs(axle_fx(h, 1)) < 0.1 * axle_fx(h, 0));
}

TEST_CASE("sim: a rigid kart chassis lands from 0.3 m and settles") {
	PlatformSpec s = gt_spec();
	s.mass = 170.0;
	s.wheelbase_ref = 1.05;
	s.track_ref = 1.2;
	s.wheel_radius_ref = 0.14;
	s.rigid = true;
	s.axles[0] = { 7.0, 0.6, 0.8, 0.02, true, false };
	s.axles[1] = { 7.0, 0.6, 0.8, 0.02, false, true };
	s.axle_diff[1] = { DiffType::LOCKED, 0, 0, 0 };
	s.engine.torque_curve = { { 2000, 18 }, { 6000, 24 }, { 11000, 20 } };
	s.engine.idle_rpm = 1800;
	s.engine.redline_rpm = 10500;
	s.engine.limiter_rpm = 11000;
	s.engine.inertia = 0.02;
	s.gearbox.ratios = { 1.0 };
	s.gearbox.final_drive = 6.0;
	Config c = make_config(s, nsx_geometry(1.05, 1.2, 0.14));
	CHECK(c.wheel_inertia == doctest::Approx(0.0085 * 170 * 0.14 * 0.14));
	Harness h(c);
	h.place(h.chassis.origin + V3(0, 0.3, 0));
	h.run(3.0);
	CHECK(std::isfinite(h.chassis.com.y));
	CHECK(length(h.chassis.velocity) < 0.05);
	CHECK(h.chassis.basis.c1.y > 0.999);
	h.model.controls.throttle = 1.0;
	h.run(4.0);
	MESSAGE("kart after 4 s: " << h.forward_speed() * 3.6 << " km/h");
	CHECK(h.forward_speed() > 10.0);
}

TEST_CASE("sim: drafting cuts the drag; a scale of 1 is the sim exactly") {
	Harness plain = gt(), one = gt(), tow = gt();
	one.model.drag_scale = 1.0;
	tow.model.drag_scale = 0.6;
	for (Harness *h : { &plain, &one, &tow }) {
		h->model.controls.throttle = 1.0;
		h->run(12.0); // short of the limiter: drag still holds it back
	}
	CHECK(plain.chassis.com.z == one.chassis.com.z);
	CHECK(plain.forward_speed() == one.forward_speed());
	MESSAGE("12 s: " << kmh(plain.forward_speed()) << " km/h alone, " << kmh(tow.forward_speed()) << " km/h in a tow");
	CHECK(tow.forward_speed() > plain.forward_speed() + 5.0 / 3.6);
}

TEST_CASE("sim: fuel and tire wear: work counted; full power and new tires are the sim exactly") {
	Harness plain = gt(), same = gt();
	same.model.power_scale = 1.0;
	for (WheelState &w : same.model.wheels) {
		w.wear_grip = 1.0;
	}
	for (Harness *h : { &plain, &same }) {
		h->model.controls.throttle = 1.0;
		h->model.controls.steer = -0.15;
		h->run(8.0);
	}
	CHECK(plain.chassis.com.x == same.chassis.com.x);
	CHECK(plain.chassis.com.z == same.chassis.com.z);
	// The engine's work is about the energy the car took on (kinetic, drag, rolling, slip).
	double kinetic = 0.5 * 1300.0 * plain.forward_speed() * plain.forward_speed();
	MESSAGE("engine " << plain.model.engine_work / 1e6 << " MJ, kinetic " << kinetic / 1e6 << " MJ");
	CHECK(plain.model.engine_work > kinetic);
	CHECK(plain.model.engine_work < kinetic * 3.0);
	double slid = 0.0;
	for (const WheelState &w : plain.model.wheels) {
		slid += w.slide_work;
	}
	CHECK(slid > 0.0);
	// Out of fuel: the car only coasts.
	Harness dry = gt();
	dry.model.power_scale = 0.0;
	dry.model.controls.throttle = 1.0;
	dry.run(4.0);
	CHECK(dry.forward_speed() < 0.5);
	// Worn tires: less cornering grip (the same circle at speed holds less load).
	double peak[2] = { 0.0, 0.0 };
	for (int k = 0; k < 2; k++) {
		Harness h = gt();
		for (WheelState &w : h.model.wheels) {
			w.wear_grip = k == 0 ? 1.0 : 0.75;
		}
		h.model.controls.throttle = 1.0;
		while (h.forward_speed() < 30.0) {
			h.step();
		}
		h.model.controls.steer = 0.35;
		for (int i = 0; i < 600; i++) {
			h.model.controls.throttle = std::clamp((30.0 - h.forward_speed()) * 0.3, 0.0, 1.0);
			h.step();
			peak[k] = std::max(peak[k], -h.lateral_accel());
		}
	}
	MESSAGE("lateral " << peak[0] / GRAVITY << " g new, " << peak[1] / GRAVITY << " g worn");
	CHECK(peak[1] < peak[0] * 0.92);
}
