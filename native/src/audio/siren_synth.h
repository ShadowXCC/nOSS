#pragma once

// Synthesized sirens and horns (D116, docs/ART_AUDIO.md §7): seamless loops, original sound.
// A siren is a bright tone swept up and down (wail: slowly; yelp: fast); a horn is two detuned
// buzzy tones through a soft formant. Every loop holds whole cycles of everything in it, so it
// repeats without a click. Plain C++, no Godot types.

#include <cstdint>
#include <vector>

namespace noss::audio {

enum class SirenKind {
	WAIL,
	YELP,
};

// One sweep cycle (wail 4 s, yelp 0.32 s x 6), 16-bit mono at p_rate.
std::vector<int16_t> render_siren(SirenKind p_kind, int p_rate = 44100);
// A horn chord of two tones (Hz, rounded so 0.5 s holds whole cycles of each), 0.5 s.
std::vector<int16_t> render_horn(double p_f1, double p_f2, int p_rate = 44100);

} // namespace noss::audio
