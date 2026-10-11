#include "ffb/ffb_mixer.h"

#include <algorithm>
#include <cmath>

namespace noss::ffb {

namespace {
constexpr float TAU = 6.28318530718f;
// Effect sizes at full gain, as a share of full output.
constexpr float ROAD_SIZE = 0.06f;
constexpr float CURB_SIZE = 0.22f;
constexpr float SLIP_SIZE = 0.08f;
constexpr float ENGINE_SIZE = 0.03f;
constexpr float JOLT_SIZE = 0.6f;
constexpr float JOLT_DECAY = 18.0f; // per second
constexpr float CURB_SPACING_M = 1.2f; // one bump per painted block
constexpr float CENTERING_BELOW = 8.0f; // m/s: the spring fades out by this speed
constexpr float PEAK_DECAY = 0.998f; // per step
} // namespace

float Mixer::_rand() {
	_noise = _noise * 1664525u + 1013904223u;
	return float(_noise >> 8) / float(1u << 24) * 2.0f - 1.0f;
}

float Mixer::step(const Inputs &p_in, const Settings &p_set, float p_dt) {
	_time += p_dt;
	float speed = std::abs(p_in.speed);
	float fade_in = std::clamp(speed / 3.0f, 0.0f, 1.0f); // textures need the car rolling
	Inputs in = p_in;

	// Test pattern: steady pulls, then each effect on its own.
	if (_test_time > 0.0f) {
		float t = TEST_S - _test_time;
		_test_time -= p_dt;
		in = Inputs();
		speed = 20.0f;
		fade_in = 1.0f;
		// Half the wheel's torque each way (before the overall gain).
		float half = 0.5f * p_set.max_torque_nm / std::max(p_set.reference_nm, 0.1f);
		if (t < 0.4f) {
			in.rack = half;
		} else if (t < 0.8f) {
			in.rack = -half;
		} else if (t < 1.6f) {
			in.curb = 1.0f;
		} else if (t < 1.7f) {
			in.jolt = 1.0f;
		}
	}

	// The rack force in newton-metres, as a share of what the wheel can do.
	float force = in.rack * p_set.reference_nm / std::max(p_set.max_torque_nm, 0.5f);

	// Road texture: noise, stronger on rough surfaces and with speed.
	force += _rand() * in.road * p_set.road * ROAD_SIZE * fade_in * std::min(speed / 20.0f, 1.0f);
	// Curb rumble: a bump per curb block, so it gets faster with speed.
	float curb_hz = std::clamp(speed / CURB_SPACING_M, 4.0f, 60.0f);
	force += std::sin(_time * TAU * curb_hz) * in.curb * p_set.curb * CURB_SIZE * fade_in;
	// Slip: a light buzz while the front slides.
	force += std::sin(_time * TAU * 31.0f) * in.slip * p_set.slip * SLIP_SIZE * fade_in;
	// Engine: firing pulses of a four-cylinder (two per revolution), off by default.
	float engine_hz = std::clamp(in.rpm_ratio * 8000.0f / 60.0f * 2.0f, 10.0f, 300.0f);
	force += std::sin(_time * TAU * engine_hz) * p_set.engine * ENGINE_SIZE * (in.rpm_ratio > 0.05f ? 1.0f : 0.0f);
	// Collision jolts: a kick that dies away, alternating direction.
	if (in.jolt > 0.05f && in.jolt * JOLT_SIZE > std::abs(_jolt)) {
		_jolt_sign = -_jolt_sign;
		_jolt = _jolt_sign * in.jolt * JOLT_SIZE * p_set.jolt;
	}
	force += _jolt;
	_jolt *= std::exp(-JOLT_DECAY * p_dt);

	// Low-speed centering and damping, so the wheel isn't dead at a standstill.
	float centering = std::clamp(1.0f - speed / CENTERING_BELOW, 0.0f, 1.0f);
	force -= in.wheel * p_set.spring * centering;
	_wheel_speed = p_dt > 0.0f ? (in.wheel - _last_wheel) / p_dt : 0.0f;
	_last_wheel = in.wheel;
	if (!p_set.hardware_damper) {
		force -= std::clamp(_wheel_speed * p_set.damper * 0.1f, -0.5f, 0.5f);
	}
	if (std::abs(_wheel_speed) > 0.01f) {
		force -= std::copysign(p_set.friction, _wheel_speed);
	}

	force *= p_set.gain;
	// The soft lock holds the wheel at the platform's lock at full strength.
	if (std::abs(in.lock) > 0.0f && std::abs(in.lock) >= std::abs(force) * (std::signbit(force) == std::signbit(in.lock) ? 1.0f : 0.0f)) {
		force = in.lock;
	}
	float magnitude = std::abs(force);
	_peak = std::max(magnitude, _peak * PEAK_DECAY);
	if (magnitude > 0.005f) {
		force = std::copysign(p_set.min_force + (1.0f - p_set.min_force) * std::min(magnitude, 1.0f), force);
	}
	force = std::clamp(force, -1.0f, 1.0f);
	_output += (force - _output) * std::clamp(p_set.smoothing, 0.02f, 1.0f);
	return p_set.invert ? -_output : _output;
}

} // namespace noss::ffb
