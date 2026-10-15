#include <doctest/doctest.h>

#include <cmath>

#include "vehicle_harness.h"

using namespace noss::test;

namespace {

// 10 s of a GT on the flat harness: a launch, then a weave, then braking.
void gt_run(Harness &h) {
	for (int i = 0; i < 1200; i++) {
		double t = i / 120.0;
		h.model.controls.throttle = t < 7.0 ? 1.0 : 0.0;
		h.model.controls.brake = t >= 7.0 ? 0.6 : 0.0;
		h.model.controls.steer = t > 3.0 ? 0.25 * std::sin(1.7 * (t - 3.0)) : 0.0;
		h.step();
	}
}

Harness kart(double p_wheelbase = 1.25, double p_track = 1.15, const KartParams &p_params = KartParams()) {
	PlatformSpec s = kart_spec();
	s.arcade = p_params;
	return Harness(make_config(s, kart_geometry(p_wheelbase, p_track)));
}

KartLayer &layer(Harness &h) {
	return *h.model.kart;
}

// Drives straight at about p_speed (m/s) for p_seconds.
void cruise(Harness &h, double p_speed, double p_seconds) {
	for (int i = 0; i < int(p_seconds * 120.0); i++) {
		double e = p_speed - h.forward_speed();
		h.model.controls.throttle = clampd(e * 0.5, 0.0, 1.0);
		h.model.controls.brake = clampd(-e * 0.3, 0.0, 1.0);
		h.model.controls.steer = 0.0;
		h.step();
	}
}

// Holds drift with p_steer at full throttle until the drift locks (it hops first). Returns the
// ticks it took, or -1.
int start_drift(Harness &h, double p_steer) {
	layer(h).drift = true;
	h.model.controls.steer = p_steer;
	h.model.controls.throttle = 1.0;
	h.model.controls.brake = 0.0;
	for (int i = 0; i < 120; i++) {
		h.step();
		if (layer(h).drift_dir != 0) {
			return i;
		}
	}
	return -1;
}

void run(Harness &h, double p_seconds) {
	h.run(p_seconds);
}

} // namespace

TEST_CASE("kart layer: without a layer the sim runs exactly as before") {
	Harness h(make_config(gt_spec(), nsx_geometry()));
	CHECK_FALSE(h.model.kart.has_value());
	gt_run(h);
	// Measured before the layer existed.
	CHECK(h.chassis.com.x == doctest::Approx(-78.987516550305).epsilon(1e-9));
	CHECK(h.chassis.com.y == doctest::Approx(0.440362103414).epsilon(1e-9));
	CHECK(h.chassis.com.z == doctest::Approx(157.321370357827).epsilon(1e-9));
	CHECK(h.forward_speed() == doctest::Approx(4.743619712594).epsilon(1e-9));
	CHECK(h.heading() == doctest::Approx(-2.158523876275).epsilon(1e-9));
}

TEST_CASE("kart layer: a drift charges its tiers and a release boosts") {
	Harness h = kart();
	cruise(h, 14.0, 6.0);
	REQUIRE(start_drift(h, 0.6) >= 0);
	CHECK(layer(h).drift_dir == 1);
	run(h, 0.55);
	CHECK(layer(h).tier() == 0);
	run(h, 0.1);
	CHECK(layer(h).tier() == 1);
	run(h, 0.6);
	CHECK(layer(h).tier() == 2);
	run(h, 0.8);
	CHECK(layer(h).tier() == 3);
	CHECK((layer(h).flags() & (KART_FLAG_DRIFT_RIGHT | (3 << KART_FLAG_TIER_SHIFT))) == (KART_FLAG_DRIFT_RIGHT | (3 << KART_FLAG_TIER_SHIFT)));
	layer(h).drift = false;
	h.step();
	CHECK(layer(h).drift_dir == 0);
	CHECK(layer(h).boost == doctest::Approx(1.4).epsilon(0.01));
	CHECK((layer(h).flags() & KART_FLAG_BOOST) != 0);

	// A short drift gives nothing.
	REQUIRE(start_drift(h, -0.6) >= 0);
	CHECK(layer(h).drift_dir == -1);
	run(h, 0.3);
	double boost = layer(h).boost;
	layer(h).drift = false;
	h.step();
	CHECK(layer(h).boost < boost);
}

TEST_CASE("kart layer: a drift keeps its speed and turns its way, whatever the steering") {
	for (double steer : { 1.0, 0.0, -1.0 }) {
		Harness h = kart();
		cruise(h, 14.0, 6.0);
		double v0 = h.forward_speed();
		double heading0 = h.heading();
		REQUIRE(start_drift(h, 0.6) >= 0);
		h.model.controls.steer = steer;
		run(h, 2.5);
		CAPTURE(steer);
		CHECK(layer(h).drift_dir == 1); // locked: steering the other way only widens it
		CHECK(h.yaw_rate() < -0.3);
		CHECK(h.forward_speed() > 0.95 * v0);
		CHECK(h.heading() - heading0 < -0.7);
	}
	// Into the drift turns tighter than against it.
	double yaw[2];
	for (int i = 0; i < 2; i++) {
		Harness h = kart();
		cruise(h, 14.0, 6.0);
		start_drift(h, 0.6);
		h.model.controls.steer = i == 0 ? 1.0 : -1.0;
		run(h, 1.0);
		yaw[i] = h.yaw_rate();
	}
	CHECK(yaw[0] < yaw[1] - 0.3);
}

TEST_CASE("kart layer: a drift turns the same at the smallest and largest wheelbase") {
	double yaw[3], speed[3];
	const double geometry[3][2] = { { 1.80, 1.30 }, { 1.10, 1.00 }, { 2.80, 1.70 } };
	for (int i = 0; i < 3; i++) {
		Harness h = kart(geometry[i][0], geometry[i][1]);
		cruise(h, 14.0, 6.0);
		start_drift(h, 0.6);
		h.model.controls.steer = 0.5;
		run(h, 2.0);
		yaw[i] = h.yaw_rate();
		speed[i] = h.forward_speed();
	}
	for (int i = 1; i < 3; i++) {
		CAPTURE(i);
		CHECK(yaw[i] == doctest::Approx(yaw[0]).epsilon(0.02));
		CHECK(speed[i] == doctest::Approx(speed[0]).epsilon(0.02));
	}
}

TEST_CASE("kart layer: a boost goes past the top speed but never past its cap") {
	Harness h = kart();
	double top = KartLayer::geared_top(h.model.config());
	CHECK(top * 3.6 == doctest::Approx(100.0).epsilon(0.01));
	h.model.controls.throttle = 1.0;
	run(h, 12.0);
	CHECK(h.forward_speed() < top);
	layer(h).effect(KART_BOOST, 8.0);
	double fastest = 0.0;
	for (int i = 0; i < 8 * 120; i++) {
		h.step();
		fastest = std::max(fastest, h.forward_speed());
	}
	CHECK(fastest > 1.2 * top);
	CHECK(fastest <= 1.25 * top + 0.05);
	CHECK(layer(h).boost == 0.0);
	run(h, 4.0);
	CHECK(h.forward_speed() < 1.05 * top);
}

TEST_CASE("kart layer: a boost pad boosts and a spin-out or power cut stops boosts") {
	Harness h = kart();
	cruise(h, 15.0, 4.0);
	h.tags = TAG_BOOST;
	h.step();
	h.tags = 0;
	CHECK(layer(h).boost == doctest::Approx(0.8).epsilon(0.02));
	CHECK(layer(h).boosts == 1);

	layer(h).effect(KART_SPIN, 1.2, 1.0);
	CHECK(layer(h).boost == 0.0);
	double turned = 0.0;
	for (int i = 0; i < 144; i++) {
		h.step();
		turned += h.yaw_rate() / 120.0;
	}
	CHECK(layer(h).spin == 0.0);
	CHECK(turned > 2.0 * PI);
	layer(h).effect(KART_BOOST, 1.0); // nothing while slowed or spun
	CHECK(layer(h).boost == doctest::Approx(1.0));

	cruise(h, 15.0, 3.0);
	layer(h).effect(KART_SLOW, 2.0, 0.0);
	CHECK(layer(h).boost == 0.0);
	h.model.controls.throttle = 1.0;
	double v0 = h.forward_speed();
	run(h, 1.9);
	CHECK(h.forward_speed() < v0 - 0.5);
	CHECK((layer(h).flags() & KART_FLAG_SLOWED) != 0);
	run(h, 1.0);
	CHECK(h.forward_speed() > v0 - 0.5);
}

TEST_CASE("kart layer: air control pitches the kart only off the ground") {
	Harness h = kart();
	h.model.controls.throttle = 1.0;
	run(h, 1.0);
	CHECK(std::abs(h.chassis.basis.c2.y) < 0.02);

	Harness air = kart();
	air.place(V3(0, 30, 0));
	air.model.controls.throttle = 1.0;
	run(air, 0.6);
	CHECK((layer(air).flags() & KART_FLAG_AIRBORNE) != 0);
	CHECK(air.chassis.basis.c2.y < -0.1); // nose down
	// Off the pedals it levels out.
	air.model.controls.throttle = 0.0;
	run(air, 2.0);
	CHECK(air.chassis.basis.c1.y > 0.98);
}

TEST_CASE("kart layer: a kart upside down rights itself after 1.5 s") {
	Harness h = kart();
	h.place(V3(0, 60, 0), M3::axis_angle(V3(0, 0, 1), PI));
	run(h, 1.4);
	CHECK(h.chassis.basis.c1.y < -0.9);
	CHECK(layer(h).righting == 0.0);
	run(h, 0.2);
	CHECK(layer(h).righting > 0.0);
	run(h, 1.0);
	CHECK(h.chassis.basis.c1.y > 0.9);
}

TEST_CASE("kart layer: a trick off a jump boosts on an upright landing") {
	Harness h = kart();
	cruise(h, 15.0, 3.0);
	h.tags = TAG_JUMP;
	h.step();
	h.tags = 0;
	h.chassis.velocity += V3(0, 4.0, 0); // off the lip
	run(h, 0.15);
	REQUIRE((layer(h).flags() & KART_FLAG_AIRBORNE) != 0);
	layer(h).drift = true;
	h.step();
	layer(h).drift = false;
	CHECK(layer(h).trick);
	run(h, 1.5);
	CHECK_FALSE(layer(h).trick);
	CHECK(layer(h).tricks == 1);
	CHECK(layer(h).boosts == 1);

	// Without a jump, a short hop is no trick.
	Harness hop = kart();
	cruise(hop, 15.0, 3.0);
	hop.chassis.velocity += V3(0, 2.0, 0);
	run(hop, 0.1);
	layer(hop).drift = true;
	hop.step();
	CHECK_FALSE(layer(hop).trick);
}

TEST_CASE("kart layer: stick gravity pulls into tagged surfaces above its speed") {
	PlatformSpec s = kart_spec();
	s.arcade = KartParams();
	Config config = make_config(s, kart_geometry());
	Chassis ch;
	ch.velocity = V3(0, 10.0, 0); // up a wall
	Controls controls;
	std::vector<Contact> contacts(4);
	for (Contact &c : contacts) {
		c.hit = true;
		c.normal = V3(1, 0, 0);
		c.tags = TAG_STICK;
	}
	const V3 g(0, -GRAVITY, 0);
	KartLayer k(*s.arcade);
	KartMods m = k.begin(config, ch, contacts, controls, g, 3000.0, 1.0 / 120.0);
	CHECK(m.force.x == doctest::Approx(-config.mass * GRAVITY));
	CHECK(m.force.y == doctest::Approx(config.mass * GRAVITY));
	CHECK((k.stick > 0.0));
	// Held a moment after leaving it, then gone.
	std::vector<Contact> none(4);
	m = k.begin(config, ch, none, controls, g, 3000.0, 0.1);
	CHECK(m.force.x < 0.0);
	m = k.begin(config, ch, none, controls, g, 3000.0, 0.2);
	CHECK(m.force.x == 0.0);
	// Too slow, or not tagged: nothing.
	ch.velocity = V3(0, 4.0, 0);
	KartLayer slow(*s.arcade);
	CHECK(slow.begin(config, ch, contacts, controls, g, 3000.0, 1.0 / 120.0).force.x == 0.0);
	for (Contact &c : contacts) {
		c.tags = 0;
	}
	ch.velocity = V3(0, 10.0, 0);
	KartLayer plain(*s.arcade);
	CHECK(plain.begin(config, ch, contacts, controls, g, 3000.0, 1.0 / 120.0).force.x == 0.0);
}

TEST_CASE("kart layer: a reset ends drifts and boosts, and hotswap keeps the state") {
	Harness h = kart();
	cruise(h, 14.0, 5.0);
	start_drift(h, 0.6);
	layer(h).effect(KART_BOOST, 2.0);
	run(h, 0.3);
	CHECK(layer(h).drift_dir == 1);
	VehicleModel other(h.model.config());
	other.take_state(h.model);
	CHECK(other.kart->drift_dir == 1);
	CHECK(other.kart->boost > 1.0);
	h.model.reset();
	CHECK(layer(h).drift_dir == 0);
	CHECK(layer(h).boost == 0.0);
	h.model.set_kart(nullptr);
	CHECK_FALSE(h.model.kart.has_value());
	KartParams p;
	p.grip = 1.1;
	h.model.set_kart(&p);
	CHECK(layer(h).params.grip == doctest::Approx(1.1));
}
