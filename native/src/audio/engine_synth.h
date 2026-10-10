#pragma once

// Synthesized engine sound (docs/ART_AUDIO.md §6): seamless loops of an engine at one rpm
// and load, for one emitter. Original sound made from the engine's layout, no recordings:
// a pulse per firing (crank angles from the firing order) through resonant exhaust and intake
// filters, with small cycle-to-cycle variation. Plain C++, no Godot types.

#include <cstdint>
#include <vector>

namespace noss::audio {

enum class Emitter {
	ENGINE,
	EXHAUST,
	INTAKE,
};

struct EngineProfile {
	// Firings: crank angle (0..720) and exhaust bank of each cylinder.
	std::vector<double> fire_deg;
	std::vector<int> bank;
	double pulse_ms = 2.5; // decay of one combustion pulse
	double exhaust_hz[2] = { 120.0, 120.0 }; // pipe resonance per bank
	double exhaust_q = 3.0;
	double exhaust_delay_ms[2] = { 0.0, 0.0 }; // longer path on one bank
	double muffler_hz = 900.0; // low-pass on the exhaust
	double intake_hz = 380.0;
	double intake_q = 2.0;
	double intake_noise = 0.25;
	double mechanical = 0.15; // valvetrain and block noise
	double harshness = 0.3; // brighter pulses
	double jitter = 0.08; // cycle-to-cycle amplitude variation
	// Electric motor instead of combustion.
	bool electric = false;
	double motor_order = 6.0; // whine frequency = rpm / 60 * order
	double inverter_order = 48.0;
};

struct Loop {
	std::vector<int16_t> samples;
	double rpm = 0.0; // exact rpm of the loop (a whole number of cycles fits it)
};

// A loop of about p_length_s at p_rpm. p_load 0..1 (off- to on-throttle).
Loop render_loop(const EngineProfile &p_profile, double p_rpm, double p_load, Emitter p_emitter, int p_rate = 44100,
		double p_length_s = 0.5, uint32_t p_seed = 1);

} // namespace noss::audio
