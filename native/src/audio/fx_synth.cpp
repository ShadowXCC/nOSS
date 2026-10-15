#include "audio/fx_synth.h"

#include <algorithm>
#include <cmath>

namespace noss::audio {

namespace {

constexpr double PI = 3.14159265358979323846;

// Seeded white noise in -1..1 (the same every render).
struct Noise {
	uint32_t state = 0x9e3779b9u;
	double next() {
		state = state * 1664525u + 1013904223u;
		return double(state >> 8) / double(1u << 23) - 1.0;
	}
};

// One-pole low-pass, coefficient from a cutoff in Hz.
struct LowPass {
	double y = 0.0;
	double run(double p_x, double p_cutoff, int p_rate) {
		double a = 1.0 - std::exp(-2.0 * PI * p_cutoff / p_rate);
		y += a * (p_x - y);
		return y;
	}
};

double envelope(double p_t, double p_attack, double p_decay) {
	return p_t < p_attack ? p_t / p_attack : std::exp(-(p_t - p_attack) / p_decay);
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

FxKind fx_kind(const std::string &p_name) {
	static const char *names[] = { "pickup", "roulette", "fire", "hit", "shield", "emp", "boost", "tier", "slick" };
	for (int i = 0; i < 9; i++) {
		if (p_name == names[i]) {
			return FxKind(i);
		}
	}
	return FxKind::PICKUP;
}

std::vector<int16_t> render_fx(FxKind p_kind, int p_rate) {
	double length = 0.3;
	switch (p_kind) {
		case FxKind::PICKUP: length = 0.24; break;
		case FxKind::ROULETTE: length = 0.04; break;
		case FxKind::FIRE: length = 0.3; break;
		case FxKind::HIT: length = 0.4; break;
		case FxKind::SHIELD: length = 0.55; break;
		case FxKind::EMP: length = 0.7; break;
		case FxKind::BOOST: length = 0.5; break;
		case FxKind::TIER: length = 0.12; break;
		case FxKind::SLICK: length = 0.22; break;
	}
	size_t n = size_t(std::llround(length * p_rate));
	std::vector<double> x(n);
	Noise noise;
	LowPass lp, lp2;
	double phase = 0.0, phase2 = 0.0;
	for (size_t i = 0; i < n; i++) {
		double t = double(i) / p_rate;
		double u = t / length;
		double v = 0.0;
		switch (p_kind) {
			case FxKind::PICKUP: {
				// Three notes a fifth and an octave apart, 80 ms each.
				static const double notes[] = { 660.0, 990.0, 1320.0 };
				int k = std::min(int(t / 0.08), 2);
				double local = t - k * 0.08;
				phase += notes[k] / p_rate;
				v = (std::sin(2.0 * PI * phase) + 0.3 * std::sin(6.0 * PI * phase)) * envelope(local, 0.004, 0.05);
				break;
			}
			case FxKind::ROULETTE:
				phase += 1800.0 / p_rate;
				v = std::sin(2.0 * PI * phase) * envelope(t, 0.001, 0.008);
				break;
			case FxKind::FIRE: {
				double f = 2400.0 * (1.0 - u) + 300.0;
				v = lp.run(noise.next(), f, p_rate) * 2.5 * envelope(t, 0.01, 0.1);
				phase += (140.0 - 80.0 * u) / p_rate;
				v += 0.6 * std::sin(2.0 * PI * phase) * envelope(t, 0.002, 0.05);
				break;
			}
			case FxKind::HIT:
				phase += (95.0 - 40.0 * u) / p_rate;
				v = std::sin(2.0 * PI * phase) * envelope(t, 0.002, 0.12);
				v += 0.7 * lp.run(noise.next(), 1800.0, p_rate) * 3.0 * envelope(t, 0.001, 0.05);
				break;
			case FxKind::SHIELD: {
				double f = 520.0 + 260.0 * u;
				phase += f / p_rate;
				phase2 += f * 1.5 / p_rate;
				double shimmer = 0.75 + 0.25 * std::sin(2.0 * PI * 9.0 * t);
				v = (std::sin(2.0 * PI * phase) + 0.6 * std::sin(2.0 * PI * phase2)) * shimmer * envelope(t, 0.03, 0.25);
				break;
			}
			case FxKind::EMP: {
				double f = 60.0 + 340.0 * std::exp(-t / 0.12);
				phase += f / p_rate;
				double s = std::sin(2.0 * PI * phase);
				v = std::tanh(2.5 * s) * envelope(t, 0.005, 0.25);
				v += 0.3 * lp2.run(noise.next(), 400.0, p_rate) * envelope(t, 0.005, 0.1);
				break;
			}
			case FxKind::BOOST: {
				double f = 300.0 + 2600.0 * u;
				v = lp.run(noise.next(), f, p_rate) * 3.0 * std::sin(PI * std::min(u * 1.4, 1.0));
				break;
			}
			case FxKind::TIER:
				phase += (1500.0 + 900.0 * u) / p_rate;
				v = std::sin(2.0 * PI * phase) * envelope(t, 0.003, 0.04);
				break;
			case FxKind::SLICK:
				v = lp.run(noise.next(), 700.0 - 500.0 * u, p_rate) * 3.0 * envelope(t, 0.004, 0.07);
				phase += 70.0 / p_rate;
				v += 0.4 * std::sin(2.0 * PI * phase) * envelope(t, 0.002, 0.05);
				break;
		}
		x[i] = v;
	}
	return to_pcm(x);
}

} // namespace noss::audio
