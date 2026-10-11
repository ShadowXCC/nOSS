#include "doctest/doctest.h"

#include <cmath>

#include "ffb/ffb_mixer.h"

using namespace noss::ffb;

namespace {
// Runs `p_s` seconds at 500 Hz; returns the last output and the largest swing seen.
struct Run {
	float last = 0.0f;
	float min = 1.0f;
	float max = -1.0f;
};
Run run(Mixer &p_m, const Inputs &p_in, const Settings &p_set, float p_s) {
	Run r;
	for (int i = 0; i < int(p_s * 500.0f); i++) {
		r.last = p_m.step(p_in, p_set, 1.0f / 500.0f);
		r.min = std::min(r.min, r.last);
		r.max = std::max(r.max, r.last);
	}
	return r;
}
} // namespace

TEST_CASE("ffb: the rack force scales with the wheel's torque and gain") {
	Settings s;
	s.spring = 0.0f;
	s.friction = 0.0f;
	s.smoothing = 1.0f;
	s.gain = 1.0f;
	s.reference_nm = 9.0f;
	s.max_torque_nm = 18.0f; // a strong wheel: half the output for the reference force
	Inputs in;
	in.rack = 1.0f;
	in.speed = 30.0f;
	Mixer m;
	CHECK(run(m, in, s, 0.1f).last == doctest::Approx(0.5f).epsilon(0.01));
	s.gain = 0.5f;
	CHECK(run(m, in, s, 0.1f).last == doctest::Approx(0.25f).epsilon(0.01));
	s.invert = true;
	CHECK(run(m, in, s, 0.1f).last == doctest::Approx(-0.25f).epsilon(0.01));
}

TEST_CASE("ffb: clipping is measured and clamped") {
	Settings s;
	s.smoothing = 1.0f;
	s.gain = 1.0f;
	s.max_torque_nm = 3.0f;
	Inputs in;
	in.rack = 1.0f; // 9 Nm on a 3 Nm wheel
	in.speed = 30.0f;
	Mixer m;
	Run r = run(m, in, s, 0.2f);
	CHECK(r.last == doctest::Approx(1.0f));
	CHECK(m.peak() > 2.5f);
}

TEST_CASE("ffb: curbs rumble faster with speed; a straight smooth road is calm") {
	Settings s;
	s.spring = 0.0f;
	s.friction = 0.0f;
	s.smoothing = 1.0f;
	Inputs in;
	in.speed = 30.0f;
	Mixer calm;
	Run quiet = run(calm, in, s, 0.5f);
	CHECK(quiet.max - quiet.min < 0.01f);
	in.curb = 1.0f;
	Mixer rumble;
	Run r = run(rumble, in, s, 0.5f);
	CHECK(r.max - r.min > 0.15f);
	// Count zero crossings: more at higher speed.
	auto crossings = [&](float p_speed) {
		Mixer m;
		Inputs c = in;
		c.speed = p_speed;
		float prev = 0.0f;
		int n = 0;
		for (int i = 0; i < 500; i++) {
			float v = m.step(c, s, 1.0f / 500.0f);
			if ((v > 0.0f) != (prev > 0.0f)) {
				n++;
			}
			prev = v;
		}
		return n;
	};
	CHECK(crossings(30.0f) > crossings(10.0f));
}

TEST_CASE("ffb: a collision gives a jolt that dies away") {
	Settings s;
	s.spring = 0.0f;
	s.friction = 0.0f;
	s.smoothing = 1.0f;
	Inputs in;
	in.speed = 20.0f;
	in.jolt = 1.0f;
	Mixer m;
	float first = m.step(in, s, 1.0f / 500.0f);
	CHECK(std::abs(first) > 0.3f);
	in.jolt = 0.0f;
	Run after = run(m, in, s, 0.4f);
	CHECK(std::abs(after.last) < 0.01f);
}

TEST_CASE("ffb: the wheel centres at a standstill but not at speed") {
	Settings s;
	s.friction = 0.0f;
	s.smoothing = 1.0f;
	s.gain = 1.0f;
	Inputs in;
	in.wheel = 0.5f; // turned left
	Mixer m;
	CHECK(run(m, in, s, 0.1f).last < -0.1f); // pulled back right
	in.speed = 20.0f;
	CHECK(std::abs(run(m, in, s, 0.1f).last) < 0.01f);
}

TEST_CASE("ffb: the test plays every effect then stops") {
	Settings s;
	s.smoothing = 1.0f;
	Mixer m;
	m.start_test();
	CHECK(m.testing());
	Run left = run(m, Inputs(), s, 0.3f);
	CHECK(left.last > 0.2f);
	run(m, Inputs(), s, Mixer::TEST_S);
	CHECK_FALSE(m.testing());
}

TEST_CASE("ffb: min force lifts small forces") {
	Settings s;
	s.spring = 0.0f;
	s.friction = 0.0f;
	s.smoothing = 1.0f;
	s.gain = 1.0f;
	s.min_force = 0.1f;
	Inputs in;
	in.rack = 0.05f;
	in.speed = 20.0f;
	Mixer m;
	float v = run(m, in, s, 0.1f).last;
	CHECK(v > 0.1f);
}

TEST_CASE("ffb: the soft lock wins at full strength") {
	Settings s;
	s.smoothing = 1.0f;
	s.gain = 0.3f;
	Inputs in;
	in.rack = 0.5f; // pulling left
	in.speed = 20.0f;
	in.lock = -1.0f; // past the lock to the left: push right
	Mixer m;
	CHECK(run(m, in, s, 0.05f).last == doctest::Approx(-1.0f));
}
