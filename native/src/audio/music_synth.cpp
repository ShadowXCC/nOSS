#include "audio/music_synth.h"

#include <algorithm>
#include <cmath>

namespace noss::audio {

namespace {

constexpr double PI = 3.14159265358979323846;

struct Rng {
	uint32_t s;
	explicit Rng(uint32_t p_seed) :
			s(p_seed * 2654435761u + 0x9e3779b9u) {}
	uint32_t next() {
		s ^= s << 13;
		s ^= s >> 17;
		s ^= s << 5;
		return s;
	}
	double unit() { return double(next() & 0xFFFFFF) / double(0x1000000); }
	int below(int p_n) { return int(next() % uint32_t(p_n)); }
};

double midi_hz(double p_note) {
	return 440.0 * std::pow(2.0, (p_note - 69.0) / 12.0);
}

// A soft saw (band-limited enough at these pitches with a gentle filter after).
double saw(double p_phase) {
	return 2.0 * (p_phase - std::floor(p_phase + 0.5));
}

// Progressions in a major key, as scale degrees (0 = I .. 5 = vi).
const int PROGRESSIONS[][MUSIC_CHORDS] = {
	{ 0, 4, 5, 3, 0, 4, 3, 3 }, // I V vi IV ..
	{ 5, 3, 0, 4, 5, 3, 0, 4 }, // vi IV I V
	{ 0, 2, 3, 4, 0, 5, 3, 4 }, // I iii IV V I vi IV V
	{ 3, 0, 4, 5, 3, 0, 4, 4 }, // IV I V vi
	{ 0, 5, 1, 4, 0, 5, 3, 4 }, // I vi ii V
};
const int SCALE[7] = { 0, 2, 4, 5, 7, 9, 11 };

} // namespace

std::vector<int16_t> render_music(uint32_t p_seed, int p_rate) {
	Rng rng(p_seed);
	const double loop_s = MUSIC_CHORDS * MUSIC_CHORD_S;
	const size_t n = size_t(loop_s * p_rate);
	const size_t tail = size_t(4.0 * p_rate); // rendered past the end and folded back over the start
	std::vector<double> x(n + tail, 0.0);
	const int roots[] = { 48, 50, 51, 53, 55, 57 }; // C, D, Eb, F, G, A (octave 3)
	const int root = roots[rng.below(6)];
	const int *prog = PROGRESSIONS[rng.below(5)];
	// Chord notes (MIDI) for each step: a seventh chord from the scale, voiced close.
	std::vector<std::vector<int>> chords;
	for (int c = 0; c < MUSIC_CHORDS; c++) {
		int deg = prog[c];
		std::vector<int> notes;
		for (int k = 0; k < 4; k++) {
			int d = deg + 2 * k;
			notes.push_back(root + SCALE[d % 7] + 12 * (d / 7));
		}
		chords.push_back(notes);
	}
	// Pads: per chord, its notes on two detuned saws, faded in and out across the chord's span.
	for (int c = 0; c <= MUSIC_CHORDS; c++) {
		const std::vector<int> &notes = chords[size_t(c % MUSIC_CHORDS)];
		double start = c * MUSIC_CHORD_S - 2.0;
		size_t i0 = size_t(std::max(0.0, start) * p_rate);
		size_t i1 = std::min(x.size(), size_t((start + MUSIC_CHORD_S + 4.0) * p_rate));
		for (int note : notes) {
			double f = midi_hz(note);
			double pa = rng.unit(), pb = rng.unit();
			double lp = 0.0;
			for (size_t i = i0; i < i1; i++) {
				double t = double(i) / p_rate - start;
				double env = std::min({ t / 2.5, 1.0, (MUSIC_CHORD_S + 4.0 - t) / 3.0 });
				env = std::max(env, 0.0);
				pa += f * 1.0035 / p_rate;
				pb += f * 0.9965 / p_rate;
				double v = 0.5 * (saw(pa) + saw(pb));
				double cutoff = 700.0 + 300.0 * std::sin(2.0 * PI * double(i) / p_rate / 11.0);
				lp += (1.0 - std::exp(-2.0 * PI * cutoff / p_rate)) * (v - lp);
				x[i] += lp * env * 0.09;
			}
		}
		// Bass: the root an octave down, a sine.
		double fb = midi_hz(notes[0] - 12);
		for (size_t i = i0; i < i1; i++) {
			double t = double(i) / p_rate - start;
			double env = std::max(0.0, std::min({ t / 1.5, 1.0, (MUSIC_CHORD_S + 4.0 - t) / 2.5 }));
			x[i] += std::sin(2.0 * PI * fb * t) * env * 0.12;
		}
	}
	// Bells: now and then a note of the chord two octaves up, a sine with a touch of FM, fading.
	double t = 0.5;
	while (t < loop_s) {
		int c = int(t / MUSIC_CHORD_S) % MUSIC_CHORDS;
		const std::vector<int> &notes = chords[size_t(c)];
		double f = midi_hz(notes[size_t(rng.below(4))] + 24);
		double amp = 0.05 + 0.04 * rng.unit();
		size_t i0 = size_t(t * p_rate);
		size_t len = size_t(3.0 * p_rate);
		for (size_t k = 0; k < len && i0 + k < x.size(); k++) {
			double u = double(k) / p_rate;
			double env = std::exp(-u / 0.9) * std::min(1.0, u / 0.005);
			x[i0 + k] += std::sin(2.0 * PI * f * u + 0.6 * std::sin(2.0 * PI * f * 2.0 * u) * env) * env * amp;
		}
		t += 0.6 + 1.6 * rng.unit();
	}
	// Echo.
	size_t delay = size_t(0.43 * p_rate);
	for (size_t i = delay; i < x.size(); i++) {
		x[i] += x[i - delay] * 0.32;
	}
	// The tail over the start, so the loop joins.
	for (size_t i = 0; i < tail; i++) {
		double w = double(i) / double(tail);
		x[i] = x[i] * w + x[n + i] * (1.0 - w);
	}
	x.resize(n);
	double peak = 1e-9;
	for (double v : x) {
		peak = std::max(peak, std::abs(v));
	}
	std::vector<int16_t> out(n);
	for (size_t i = 0; i < n; i++) {
		out[i] = int16_t(std::lround(x[i] / peak * 0.7 * 32767.0));
	}
	return out;
}

} // namespace noss::audio
