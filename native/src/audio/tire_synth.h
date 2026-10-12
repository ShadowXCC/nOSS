#pragma once

// Synthesized tire sounds (docs/ART_AUDIO.md §7): seamless loops of rubber squeal or scrub.
// Noise through a few band-passes at non-harmonic centres, a faint tone that wanders at random
// and a random flutter of the level. Original sound, no recordings. Plain C++, no Godot types.

#include <cstdint>
#include <vector>

namespace noss::audio {

struct TireBand {
	double hz = 1000.0;
	double q = 10.0;
	double gain = 1.0;
};

struct TireProfile {
	std::vector<TireBand> bands;
	double tone = 0.0; // level of a faint tone, relative to the bands
	double tone_hz = 0.0; // 0: the first band's centre
	double drift = 0.03; // how far the tone wanders, a fraction of its frequency
	double drift_hz = 1.5; // how fast it wanders
	double flutter = 0.3; // random level flutter, 0..1
	double flutter_hz = 11.0; // how fast the level flutters
};

// A loop of p_length_s seconds: 16-bit mono samples at p_rate.
std::vector<int16_t> render_tire_loop(const TireProfile &p_profile, int p_rate = 44100, double p_length_s = 2.5,
		uint32_t p_seed = 1);

} // namespace noss::audio
