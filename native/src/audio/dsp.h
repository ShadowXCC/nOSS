#pragma once

// Small DSP pieces shared by the synths: deterministic noise, RBJ biquads and slow random
// signals. Plain C++.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace noss::audio::dsp {

constexpr double PI = 3.14159265358979323846;

// Deterministic noise, -1..1.
struct Rng {
	uint32_t state;
	double next() {
		state ^= state << 13;
		state ^= state >> 17;
		state ^= state << 5;
		return double(state) / 4294967295.0 * 2.0 - 1.0;
	}
};

// Two-pole filters (RBJ cookbook). The band-pass has a constant peak gain.
struct Biquad {
	double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
	double x1 = 0, x2 = 0, y1 = 0, y2 = 0;

	static Biquad bandpass(double p_hz, double p_q, double p_rate) {
		Biquad f;
		double w = 2.0 * PI * std::min(p_hz, p_rate * 0.45) / p_rate;
		double alpha = std::sin(w) / (2.0 * std::max(p_q, 0.1));
		double a0 = 1.0 + alpha;
		f.b0 = alpha / a0;
		f.b1 = 0.0;
		f.b2 = -alpha / a0;
		f.a1 = -2.0 * std::cos(w) / a0;
		f.a2 = (1.0 - alpha) / a0;
		return f;
	}
	static Biquad lowpass(double p_hz, double p_rate) {
		Biquad f;
		double w = 2.0 * PI * std::min(p_hz, p_rate * 0.45) / p_rate;
		double alpha = std::sin(w) / (2.0 * 0.707);
		double c = std::cos(w), a0 = 1.0 + alpha;
		f.b0 = (1.0 - c) / 2.0 / a0;
		f.b1 = (1.0 - c) / a0;
		f.b2 = f.b0;
		f.a1 = -2.0 * c / a0;
		f.a2 = (1.0 - alpha) / a0;
		return f;
	}
	static Biquad highpass(double p_hz, double p_rate) {
		Biquad f;
		double w = 2.0 * PI * std::min(p_hz, p_rate * 0.45) / p_rate;
		double alpha = std::sin(w) / (2.0 * 0.707);
		double c = std::cos(w), a0 = 1.0 + alpha;
		f.b0 = (1.0 + c) / 2.0 / a0;
		f.b1 = -(1.0 + c) / a0;
		f.b2 = f.b0;
		f.a1 = -2.0 * c / a0;
		f.a2 = (1.0 - alpha) / a0;
		return f;
	}
	double run(double x) {
		double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
		x2 = x1;
		x1 = x;
		y2 = y1;
		y1 = y;
		return y;
	}
};

// Slow random signal: noise low-passed twice, run twice around the loop so it wraps without a
// seam, then scaled to a peak of 1 around zero.
inline std::vector<double> slow_noise(Rng &p_rng, int p_n, double p_hz, int p_rate) {
	std::vector<double> in(static_cast<size_t>(p_n));
	for (double &x : in) {
		x = p_rng.next();
	}
	Biquad a = Biquad::lowpass(p_hz, p_rate), b = Biquad::lowpass(p_hz, p_rate);
	std::vector<double> out(static_cast<size_t>(p_n));
	for (int pass = 0; pass < 2; pass++) {
		for (int s = 0; s < p_n; s++) {
			double v = b.run(a.run(in[size_t(s)]));
			if (pass == 1) {
				out[size_t(s)] = v;
			}
		}
	}
	double mean = 0.0, peak = 1e-12;
	for (double v : out) {
		mean += v / p_n;
	}
	for (double &v : out) {
		v -= mean;
		peak = std::max(peak, std::abs(v));
	}
	for (double &v : out) {
		v /= peak;
	}
	return out;
}

} // namespace noss::audio::dsp
