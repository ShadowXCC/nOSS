#include "audio/weather_synth.h"

#include "audio/dsp.h"

#include <algorithm>
#include <cmath>

namespace noss::audio {

using dsp::Biquad;

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
		case WeatherSound::RAIN: length = 6.0; break;
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
			// All noise, no tones: a sheet of hiss from countless far drops, the fizz of near ones
			// landing (tiny bursts, mostly faint), a few closer pats and a little body, the sheet
			// and fizz breathing slowly so it never sits still.
			dsp::Rng rng{ 0x9A1B5u };
			std::vector<double> breath = dsp::slow_noise(rng, int(x.size()), 0.3, p_rate);
			std::vector<double> sheet(x.size()), fizz(x.size()), pats(x.size()), body(x.size());
			Biquad sheet_hp = Biquad::highpass(700.0, p_rate), sheet_bp = Biquad::bandpass(2600.0, 0.45, p_rate), sheet_lp = Biquad::lowpass(7500.0, p_rate);
			Biquad fizz_bp = Biquad::bandpass(3600.0, 0.8, p_rate), fizz_lp = Biquad::lowpass(7000.0, p_rate);
			const double pat_hz[3] = { 1100.0, 1600.0, 2300.0 };
			Biquad pat_bp[3] = { Biquad::bandpass(pat_hz[0], 1.2, p_rate), Biquad::bandpass(pat_hz[1], 1.2, p_rate), Biquad::bandpass(pat_hz[2], 1.2, p_rate) };
			Biquad body_lp = Biquad::lowpass(400.0, p_rate), body_lp2 = Biquad::lowpass(400.0, p_rate);
			const double fizz_fall = std::exp(-1.0 / (0.0015 * p_rate)), pat_fall = std::exp(-1.0 / (0.004 * p_rate));
			double fizz_env = 0.0, pat_env[3] = { 0.0, 0.0, 0.0 };
			for (size_t i = 0; i < x.size(); i++) {
				double w = rng.next();
				sheet[i] = sheet_lp.run(sheet_bp.run(sheet_hp.run(w)));
				// About a thousand drops a second, most of them faint.
				if (0.5 * (rng.next() + 1.0) < 1000.0 / p_rate) {
					double u = 0.5 * (rng.next() + 1.0);
					fizz_env += u * u * u;
				}
				fizz[i] = fizz_lp.run(fizz_bp.run(rng.next() * fizz_env));
				fizz_env *= fizz_fall;
				// A score of nearer drops a second, each a soft pat in one of three bands.
				if (0.5 * (rng.next() + 1.0) < 20.0 / p_rate) {
					int k = std::min(int(1.5 * (rng.next() + 1.0)), 2);
					pat_env[k] += 0.4 + 0.6 * 0.5 * (rng.next() + 1.0);
				}
				double pat = 0.0;
				for (int k = 0; k < 3; k++) {
					pat += pat_bp[k].run(rng.next() * pat_env[k]);
					pat_env[k] *= pat_fall;
				}
				pats[i] = pat;
				body[i] = body_lp2.run(body_lp.run(w));
			}
			auto rms = [](const std::vector<double> &p_v) {
				double e = 1e-12;
				for (double v : p_v) {
					e += v * v;
				}
				return std::sqrt(e / double(p_v.size()));
			};
			double rs = rms(sheet), rf = rms(fizz), rp = rms(pats), rb = rms(body);
			for (size_t i = 0; i < x.size(); i++) {
				x[i] = sheet[i] / rs * 1.0 * (1.0 + 0.15 * breath[i]) + fizz[i] / rf * 0.55 * (1.0 + 0.25 * breath[i]) + pats[i] / rp * 0.2 + body[i] / rb * 0.4;
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
