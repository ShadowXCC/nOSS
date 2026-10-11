#pragma once

// Force feedback mixing (docs/PHYSICS.md §11, docs/INPUT.md §6, INP-05): turns what the car is
// doing into one steering force, at the FFB thread's rate (~500 Hz). Plain C++ with no SDL, so
// it's unit-tested. The device layer sends the result as a constant force.

#include <cstdint>

namespace noss::ffb {

// What the car is doing, set by the game each physics tick.
struct Inputs {
	float rack = 0.0f; // steering rack force / the platform's reference, + = pulls the wheel left
	float speed = 0.0f; // m/s
	float curb = 0.0f; // 0..1: share of the front tires on curbs
	float road = 0.0f; // 0..1: how rough the surface under the front is
	float slip = 0.0f; // 0..1: how much the front tires slide
	float rpm_ratio = 0.0f; // engine rpm / limiter
	float jolt = 0.0f; // 0..1: a collision this tick
	float wheel = 0.0f; // wheel position, -1..1 of its rotation (+ = turned left)
	float lock = 0.0f; // soft lock past the platform's lock, -1..1 output, never weakened
};

// The player's settings (Wheel setup).
struct Settings {
	float gain = 0.7f; // overall
	float max_torque_nm = 8.0f; // what the wheel can give at full output
	float reference_nm = 9.0f; // the rack force `rack = 1` stands for
	float road = 0.5f; // effect gains, 0..1
	float curb = 0.6f;
	float slip = 0.3f;
	float jolt = 0.8f;
	float engine = 0.0f; // off by default
	float spring = 0.3f; // low-speed centering
	float damper = 0.12f; // added weight
	float friction = 0.05f;
	float min_force = 0.0f; // lifts small forces past a gear or belt wheel's deadband
	float smoothing = 0.25f; // 0..1 per step toward the target (lower = smoother)
	bool invert = false;
	bool hardware_damper = false; // the device runs its own damper effect: don't add one here
};

class Mixer {
public:
	// One step of `p_dt` seconds: the output level, -1..1 (+ = pull the wheel left).
	float step(const Inputs &p_in, const Settings &p_set, float p_dt);
	// Plays a short pattern of every effect: pull left, right, centre, curb rumble, a jolt.
	void start_test() { _test_time = TEST_S; }
	bool testing() const { return _test_time > 0.0f; }
	// Largest output before clamping, decaying (the clipping meter).
	float peak() const { return _peak; }
	float output() const { return _output; }

	static constexpr float TEST_S = 2.4f;

private:
	float _time = 0.0f;
	float _output = 0.0f;
	float _peak = 0.0f;
	float _jolt = 0.0f;
	float _jolt_sign = 1.0f;
	float _last_wheel = 0.0f;
	float _wheel_speed = 0.0f;
	float _test_time = 0.0f;
	uint32_t _noise = 0x9e3779b9u;

	float _rand(); // -1..1
};

} // namespace noss::ffb
