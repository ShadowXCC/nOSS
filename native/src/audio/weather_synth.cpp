#include "audio/weather_synth.h"

#include <algorithm>
#include <cmath>

namespace noss::audio {

namespace {

constexpr double PI = 3.14159265358979323846;

struct Noise {
	uint32_t state;
	explicit Noise(uint32_t p_seed) :
			state(p_seed) {}
	double next() {
		state = state * 1664525u + 1013904223u;
		return double(state >> 8) / double(1u << 23) - 1.0;
	}
	double unit() { return 0.5 * (next() + 1.0); }
};

struct LowPass {
	double y = 0.0;
	double run(double p_x, double p_cutoff, int p_rate) {
		double a = 1.0 - std::exp(-2.0 * PI * p_cutoff / p_rate);
		y += a * (p_x - y);
		return y;
	}
};

// A band-pass as the difference of two low-passes.
struct BandPass {
	LowPass hi, lo;
	double run(double p_x, double p_low, double p_high, int p_rate) { return hi.run(p_x, p_high, p_rate) - lo.run(p_x, p_low, p_rate); }
};

std::vector<int16_t> to_pcm(const std::vector<double> &p_x, double p_level) {
	double peak = 1e-9;
	for (double v : p_x) {
		peak = std::max(peak, std::abs(v));
	}
	std::vector<int16_t> out(p_x.size());
	for (size_t i = 0; i < p_x.size(); i++) {
		out[i] = int16_t(std::lround(std::clamp(p_x[i] / peak * p_level, -1.0, 1.0) * 32767.0));
	}
	return out;
}

// Folds the extra tail past p_n back over the head, so the loop joins without a click.
std::vector<double> seamless(const std::vector<double> &p_x, size_t p_n) {
	std::vector<double> out(p_x.begin(), p_x.begin() + long(p_n));
	size_t fade = p_x.size() - p_n;
	for (size_t i = 0; i < fade; i++) {
		double t = double(i) / double(fade);
		out[i] = p_x[i] * t + p_x[p_n + i] * (1.0 - t);
	}
	return out;
}

} // namespace

WeatherSound weather_sound(const std::string &p_name) {
	static const char *names[] = { "rain", "wind", "thunder", "surf", "crickets", "birds" };
	for (int i = 0; i < 6; i++) {
		if (p_name == names[i]) {
			return WeatherSound(i);
		}
	}
	return WeatherSound::RAIN;
}

bool weather_loops(WeatherSound p_kind) {
	return p_kind != WeatherSound::THUNDER;
}

std::vector<int16_t> render_weather(WeatherSound p_kind, int p_rate) {
	double length = 4.0;
	switch (p_kind) {
		case WeatherSound::RAIN: length = 3.0; break;
		case WeatherSound::WIND: length = 6.0; break;
		case WeatherSound::THUNDER: length = 5.5; break;
		case WeatherSound::SURF: length = 9.0; break;
		case WeatherSound::CRICKETS: length = 4.0; break;
		case WeatherSound::BIRDS: length = 8.0; break;
	}
	size_t n = size_t(std::llround(length * p_rate));
	size_t fade = weather_loops(p_kind) ? size_t(0.4 * p_rate) : 0;
	std::vector<double> x(n + fade, 0.0);
	Noise noise(0x51A7u + uint32_t(p_kind) * 977u);
	switch (p_kind) {
		case WeatherSound::RAIN: {
			BandPass hiss;
			LowPass body;
			double drop = 0.0, drop_phase = 0.0, drop_f = 0.0;
			for (size_t i = 0; i < x.size(); i++) {
				double w = noise.next();
				double v = hiss.run(w, 1800.0, 7000.0, p_rate) * 0.6 + body.run(w, 600.0, p_rate) * 0.5;
				// Close drops: short pings at random pitches.
				if (noise.unit() < 14.0 / p_rate) {
					drop = 1.0;
					drop_f = 1800.0 + 2600.0 * noise.unit();
				}
				drop_phase += 2.0 * PI * drop_f / p_rate;
				v += drop * std::sin(drop_phase) * 0.35;
				drop *= std::exp(-1.0 / (0.012 * p_rate));
				x[i] = v;
			}
			break;
		}
		case WeatherSound::WIND: {
			LowPass a, b, gust;
			for (size_t i = 0; i < x.size(); i++) {
				double t = double(i) / p_rate;
				double g = 0.6 + 0.4 * std::sin(2.0 * PI * t / length) * std::sin(2.0 * PI * 3.0 * t / length + 1.0);
				double level = gust.run(g, 0.5, p_rate);
				double w = noise.next();
				double cutoff = 250.0 + 500.0 * level;
				x[i] = (a.run(w, cutoff, p_rate) - b.run(w, 60.0, p_rate)) * level;
			}
			break;
		}
		case WeatherSound::THUNDER: {
			LowPass rumble1, rumble2, crack;
			for (size_t i = 0; i < x.size(); i++) {
				double t = double(i) / p_rate;
				double w = noise.next();
				double env = (t < 0.05 ? t / 0.05 : std::exp(-(t - 0.05) / 1.6)) * (1.0 + 0.5 * std::sin(2.0 * PI * 1.3 * t) * std::exp(-t / 2.0));
				double low = rumble2.run(rumble1.run(w, 140.0, p_rate), 90.0, p_rate) * 4.0;
				double hi = (w - crack.run(w, 1500.0, p_rate)) * std::exp(-t / 0.08) * 0.6;
				x[i] = low * env + hi;
			}
			break;
		}
		case WeatherSound::SURF: {
			LowPass wash, low;
			for (size_t i = 0; i < x.size(); i++) {
				double t = double(i) / p_rate;
				// Three swells across the loop, each rising and falling back.
				double swell = std::pow(std::max(0.0, std::sin(PI * std::fmod(t * 3.0 / length, 1.0))), 3.0);
				double w = noise.next();
				x[i] = (wash.run(w, 400.0 + 1600.0 * swell, p_rate) - low.run(w, 80.0, p_rate)) * (0.2 + swell);
			}
			break;
		}
		case WeatherSound::CRICKETS: {
			double phase = 0.0;
			for (size_t i = 0; i < x.size(); i++) {
				double t = double(i) / p_rate;
				// Chirps of four pulses, twice a second, with a second cricket answering off-beat.
				double v = 0.0;
				for (int c = 0; c < 2; c++) {
					double ct = std::fmod(t + c * 0.27, 0.5);
					if (ct < 0.12) {
						double pulse = std::sin(PI * std::fmod(ct, 0.03) / 0.03);
						v += pulse * (c == 0 ? 1.0 : 0.6);
					}
				}
				phase += 2.0 * PI * 4300.0 / p_rate;
				x[i] = v * std::sin(phase) + noise.next() * 0.01;
			}
			break;
		}
		case WeatherSound::BIRDS: {
			// A handful of calls at set times: a quick sweep up then down, each its own pitch.
			const double calls[][3] = { { 0.4, 2600, 0.25 }, { 0.8, 3100, 0.18 }, { 2.3, 2200, 0.35 }, { 3.9, 3400, 0.15 }, { 4.15, 3400, 0.15 }, { 5.6, 2800, 0.3 }, { 6.9, 2400, 0.22 } };
			double phase = 0.0;
			for (size_t i = 0; i < x.size(); i++) {
				double t = double(i) / p_rate;
				double v = 0.0, f = 2500.0;
				for (const auto &c : calls) {
					double ct = t - c[0];
					if (ct >= 0.0 && ct < c[2]) {
						double u = ct / c[2];
						f = c[1] * (1.0 + 0.35 * std::sin(PI * u)) * (1.0 + 0.05 * std::sin(2.0 * PI * 30.0 * ct));
						v = std::sin(PI * u);
					}
				}
				phase += 2.0 * PI * f / p_rate;
				x[i] = v * std::sin(phase) + noise.next() * 0.005;
			}
			break;
		}
	}
	if (weather_loops(p_kind)) {
		return to_pcm(seamless(x, n), 0.8);
	}
	return to_pcm(x, 0.9);
}

} // namespace noss::audio
