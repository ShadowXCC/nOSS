#include "audio/tire_synth.h"

#include "audio/dsp.h"

#include <algorithm>
#include <cmath>

namespace noss::audio {

using dsp::Biquad;
using dsp::PI;
using dsp::Rng;
using dsp::slow_noise;

std::vector<int16_t> render_tire_loop(const TireProfile &p, int p_rate, double p_length_s, uint32_t p_seed) {
	int n = std::max(int(std::lround(p_length_s * p_rate)), 1024);
	Rng rng{ p_seed * 2654435761u + 977u };
	std::vector<double> white(static_cast<size_t>(n));
	for (double &x : white) {
		x = rng.next();
	}
	std::vector<double> drift = slow_noise(rng, n, std::max(p.drift_hz, 0.05), p_rate);
	std::vector<double> flutter = slow_noise(rng, n, std::max(p.flutter_hz, 0.05), p_rate);

	// The bands: band-passed noise, run twice so the filters wrap around the loop.
	std::vector<double> bands(static_cast<size_t>(n), 0.0);
	for (const TireBand &band : p.bands) {
		Biquad f = Biquad::bandpass(band.hz, band.q, p_rate);
		for (int pass = 0; pass < 2; pass++) {
			for (int s = 0; s < n; s++) {
				double v = f.run(white[size_t(s)]);
				if (pass == 1) {
					bands[size_t(s)] += band.gain * v;
				}
			}
		}
	}
	double rms = 1e-12;
	for (double v : bands) {
		rms += v * v / n;
	}
	rms = std::sqrt(rms);

	// The tone wanders with `drift`; its frequency is scaled a hair so a whole number of turns
	// fits the loop, which keeps the wrap seamless.
	double f0 = p.tone_hz > 0.0 ? p.tone_hz : (p.bands.empty() ? 1000.0 : p.bands[0].hz);
	double turns = 0.0;
	for (int s = 0; s < n; s++) {
		turns += f0 * (1.0 + p.drift * drift[size_t(s)]) / p_rate;
	}
	double fit = turns > 0.5 ? std::round(turns) / turns : 1.0;
	double phase = 0.0;

	std::vector<double> y(static_cast<size_t>(n));
	for (int s = 0; s < n; s++) {
		double tone = std::sin(2.0 * PI * phase);
		phase += fit * f0 * (1.0 + p.drift * drift[size_t(s)]) / p_rate;
		phase -= std::floor(phase);
		double v = bands[size_t(s)] / rms + p.tone * 1.41 * tone;
		y[size_t(s)] = v * std::max(0.0, 1.0 + p.flutter * flutter[size_t(s)]);
	}

	double mean = 0.0, peak = 1e-9;
	for (double v : y) {
		mean += v / n;
	}
	for (double &v : y) {
		v -= mean;
		peak = std::max(peak, std::abs(v));
	}
	std::vector<int16_t> out(static_cast<size_t>(n));
	for (int s = 0; s < n; s++) {
		out[size_t(s)] = int16_t(std::clamp(y[size_t(s)] * 0.7 / peak, -1.0, 1.0) * 32000.0);
	}
	return out;
}

} // namespace noss::audio
