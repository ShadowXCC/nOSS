#include "audio/siren_synth.h"

#include <algorithm>
#include <cmath>

namespace noss::audio {

namespace {

constexpr double PI = 3.14159265358979323846;

// A bright, siren-like wave from a phase (cycles): mostly fundamental, some odd harmonics.
double bright(double p_phase) {
	double a = 2.0 * PI * p_phase;
	return 0.75 * std::sin(a) + 0.2 * std::sin(3.0 * a) + 0.08 * std::sin(5.0 * a);
}

std::vector<int16_t> to_pcm(const std::vector<double> &p_x) {
	double peak = 1e-9;
	for (double v : p_x) {
		peak = std::max(peak, std::abs(v));
	}
	std::vector<int16_t> out(p_x.size());
	for (size_t i = 0; i < p_x.size(); i++) {
		out[i] = int16_t(std::lround(p_x[i] / peak * 0.8 * 32767.0));
	}
	return out;
}

} // namespace

std::vector<int16_t> render_siren(SirenKind p_kind, int p_rate) {
	// Sweep f(t) = mid + depth * shape(t / period); the mid frequency times the loop's length is
	// whole, and the sweep's own term integrates to 0 over a period, so the phase closes.
	double period = p_kind == SirenKind::WAIL ? 4.0 : 0.32;
	int periods = p_kind == SirenKind::WAIL ? 1 : 6;
	double mid = p_kind == SirenKind::WAIL ? 1000.0 : 1100.0;
	double depth = p_kind == SirenKind::WAIL ? 420.0 : 450.0;
	double length = period * periods;
	mid = std::round(mid * length) / length;
	size_t n = size_t(std::llround(length * p_rate));
	std::vector<double> x(n);
	double phase = 0.0;
	for (size_t i = 0; i < n; i++) {
		double t = double(i) / p_rate;
		double u = std::fmod(t / period, 1.0);
		// Wail: a smooth rise and fall; yelp: a quick sawtooth-like rise, a fast return (its
		// zero-mean shape keeps the phase closing).
		double shape = p_kind == SirenKind::WAIL ? -std::cos(2.0 * PI * u) : (u < 0.8 ? (u / 0.8) * 2.0 - 1.0 : 1.0 - (u - 0.8) / 0.2 * 2.0);
		double f = mid + depth * shape;
		x[i] = bright(phase);
		phase += f / p_rate;
	}
	return to_pcm(x);
}

std::vector<int16_t> render_horn(double p_f1, double p_f2, int p_rate) {
	double length = 0.5;
	double f1 = std::round(p_f1 * length) / length;
	double f2 = std::round(p_f2 * length) / length;
	size_t n = size_t(std::llround(length * p_rate));
	std::vector<double> x(n);
	for (size_t i = 0; i < n; i++) {
		double t = double(i) / p_rate;
		double v = 0.0;
		// Buzzy: odd and even harmonics falling off, like a diaphragm horn.
		for (int h = 1; h <= 6; h++) {
			double g = 1.0 / (h * 0.9 + 0.1);
			v += g * (std::sin(2.0 * PI * f1 * h * t) + 0.85 * std::sin(2.0 * PI * f2 * h * t));
		}
		x[i] = v;
	}
	return to_pcm(x);
}

} // namespace noss::audio
