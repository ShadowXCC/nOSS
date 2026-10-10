#include "audio/engine_synth.h"

#include <algorithm>
#include <cmath>

namespace noss::audio {

namespace {

constexpr double PI = 3.14159265358979323846;

// Deterministic noise.
struct Rng {
	uint32_t state;
	double next() {
		state ^= state << 13;
		state ^= state >> 17;
		state ^= state << 5;
		return double(state) / 4294967295.0 * 2.0 - 1.0;
	}
};

// Two-pole band-pass (RBJ cookbook, constant peak gain).
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
	double run(double x) {
		double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
		x2 = x1;
		x1 = x;
		y2 = y1;
		y1 = y;
		return y;
	}
};

} // namespace

Loop render_loop(const EngineProfile &p, double p_rpm, double p_load, Emitter p_emitter, int p_rate, double p_length_s, uint32_t p_seed) {
	Loop out;
	double rpm = std::max(p_rpm, 60.0);
	double load = std::clamp(p_load, 0.0, 1.0);
	// One cycle: two revolutions (a firing order), or one motor revolution.
	double cycle_s = p.electric ? 60.0 / rpm : 120.0 / rpm;
	int cycles = std::max(2, int(std::lround(p_length_s / cycle_s)));
	int n = int(std::lround(cycles * cycle_s * p_rate));
	out.rpm = rpm * (cycles * cycle_s * p_rate) / n; // exact: the loop holds whole cycles
	cycle_s = double(n) / p_rate / cycles;
	Rng rng{ p_seed * 2654435761u + uint32_t(rpm) + (uint32_t(p_emitter) << 20) + (load > 0.5 ? 7u : 0u) };

	// Excitation per bank: a decaying pulse per firing, varying a little from cycle to cycle.
	// It repeats every loop, so running it twice settles the filters into a seamless loop.
	std::vector<double> bank_in[2] = { std::vector<double>(size_t(n), 0.0), std::vector<double>(size_t(n), 0.0) };
	std::vector<double> noise(static_cast<size_t>(n));
	for (double &x : noise) {
		x = rng.next();
	}
	if (!p.electric) {
		double tau = p.pulse_ms * 0.001 * (load > 0.5 ? 1.0 : 1.6);
		double amp = load > 0.5 ? 1.0 : 0.35;
		for (int c = 0; c < cycles; c++) {
			for (size_t k = 0; k < p.fire_deg.size(); k++) {
				double start = (c + p.fire_deg[k] / 720.0) * cycle_s;
				int b = k < p.bank.size() ? std::clamp(p.bank[k], 0, 1) : 0;
				start += p.exhaust_delay_ms[b] * 0.001;
				double a = amp * (1.0 + p.jitter * rng.next());
				int s0 = int(start * p_rate);
				int len = int(tau * 8.0 * p_rate);
				for (int s = 0; s < len; s++) {
					double t = double(s) / p_rate;
					double v = a * std::exp(-t / tau) * (1.0 - std::exp(-t / (tau * 0.08)));
					v += p.harshness * a * std::exp(-t / (tau * 0.25)) * noise[size_t((s0 + s) % n)];
					size_t at = size_t(((s0 + s) % n + n) % n);
					bank_in[b][at] += v;
				}
			}
		}
	}

	auto bp = [&](double hz, double q) { return Biquad::bandpass(hz, q, p_rate); };
	Biquad ex[2] = { bp(p.exhaust_hz[0], p.exhaust_q), bp(p.exhaust_hz[1], p.exhaust_q) };
	Biquad ex_low[2] = { Biquad::lowpass(p.muffler_hz * (load > 0.5 ? 1.0 : 0.7), p_rate), Biquad::lowpass(p.muffler_hz * (load > 0.5 ? 1.0 : 0.7), p_rate) };
	Biquad intake = bp(p.intake_hz * (0.8 + 0.4 * rpm / 7000.0), p.intake_q);
	Biquad intake_noise = bp(p.intake_hz * 2.5, 0.8);
	Biquad body = Biquad::lowpass(220.0, p_rate);
	Biquad tick = bp(3200.0, 1.5);
	double f_motor = rpm / 60.0 * p.motor_order;
	double f_inverter = rpm / 60.0 * p.inverter_order;

	std::vector<double> y(static_cast<size_t>(n), 0.0);
	for (int pass = 0; pass < 2; pass++) {
		for (int s = 0; s < n; s++) {
			double v = 0.0;
			double t = double(s) / p_rate;
			if (p.electric) {
				double ph = 2.0 * PI * f_motor * t;
				double whine = std::sin(ph) + 0.45 * std::sin(2.0 * ph + 0.3) + 0.2 * std::sin(3.0 * ph + 1.1);
				double inverter = std::sin(2.0 * PI * f_inverter * t) * (0.6 + 0.4 * std::sin(ph));
				switch (p_emitter) {
					case Emitter::ENGINE:
						v = whine * (0.25 + 0.5 * load);
						break;
					case Emitter::INTAKE:
						v = inverter * (0.05 + 0.2 * load) + 0.02 * intake_noise.run(noise[size_t(s)]);
						break;
					case Emitter::EXHAUST:
						v = 0.08 * std::sin(2.0 * PI * f_motor * 0.5 * t) * (0.3 + 0.7 * load);
						break;
				}
			} else {
				double e0 = bank_in[0][size_t(s)], e1 = bank_in[1][size_t(s)];
				switch (p_emitter) {
					case Emitter::EXHAUST:
						v = ex_low[0].run(ex[0].run(e0) * 3.0 + e0 * 0.3) + ex_low[1].run(ex[1].run(e1) * 3.0 + e1 * 0.3);
						break;
					case Emitter::INTAKE:
						v = intake.run(e0 + e1) * 1.5 + intake_noise.run(noise[size_t(s)]) * p.intake_noise * (0.2 + 0.8 * load) * rpm / 6000.0;
						break;
					case Emitter::ENGINE:
						v = body.run(e0 + e1) * 1.2 + tick.run(noise[size_t((s * 7) % n)]) * p.mechanical * std::min(rpm / 3000.0, 2.0);
						break;
				}
			}
			if (pass == 1) {
				y[size_t(s)] = v;
			}
		}
	}

	// Normalize to a common level and remove any offset.
	double mean = 0.0, peak = 1e-9;
	for (double v : y) {
		mean += v / n;
	}
	for (double &v : y) {
		v -= mean;
		peak = std::max(peak, std::abs(v));
	}
	out.samples.resize(size_t(n));
	double gain = 0.7 / peak;
	for (int s = 0; s < n; s++) {
		out.samples[size_t(s)] = int16_t(std::clamp(y[size_t(s)] * gain, -1.0, 1.0) * 32000.0);
	}
	return out;
}

} // namespace noss::audio
