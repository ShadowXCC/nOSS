#include <doctest/doctest.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>

#include "audio/dsp.h"
#include "audio/weather_synth.h"

using namespace noss::audio;

TEST_CASE("weather sounds: every kind renders, the loops join seamlessly, the same every time") {
	for (const char *name : { "rain", "wind", "thunder", "surf", "crickets", "birds" }) {
		WeatherSound kind = weather_sound(name);
		std::vector<int16_t> a = render_weather(kind), b = render_weather(kind);
		REQUIRE(a.size() > 44100);
		CHECK(a == b);
		double rms = 0.0;
		for (int16_t v : a) {
			rms += double(v) * double(v);
		}
		rms = std::sqrt(rms / double(a.size()));
		CHECK_MESSAGE(rms > 500.0, name);
		if (weather_loops(kind)) {
			// The jump from the last sample back to the first is no bigger than the sound's own
			// steps.
			int worst = 0;
			for (size_t i = 1; i < a.size(); i++) {
				worst = std::max(worst, std::abs(int(a[i]) - int(a[i - 1])));
			}
			CHECK_MESSAGE(std::abs(int(a.front()) - int(a.back())) <= worst, name);
		}
	}
	CHECK(weather_sound("nothing") == WeatherSound::RAIN);
	CHECK_FALSE(weather_loops(WeatherSound::THUNDER));
}

TEST_CASE("weather sounds: rain is a hiss, not pings") {
	std::vector<int16_t> pcm = render_weather(WeatherSound::RAIN);
	std::vector<double> x(pcm.begin(), pcm.end());
	double all = 0.0;
	for (double v : x) {
		all += v * v;
	}
	// Its share of the energy under a cutoff (a 4th-order low-pass).
	auto under = [&](double p_hz) {
		dsp::Biquad a = dsp::Biquad::lowpass(p_hz, 44100), b = dsp::Biquad::lowpass(p_hz, 44100);
		double e = 0.0;
		for (double v : x) {
			double y = b.run(a.run(v));
			e += y * y;
		}
		return e / all;
	};
	double low = under(1000.0), most = under(8000.0);
	MESSAGE("under 1 kHz " << low << ", under 8 kHz " << most);
	CHECK(low < 0.3); // a hiss, not a rumble
	CHECK(most > 0.75); // not a glassy sizzle up top
	// No tones: in each 1024-sample window, the loudest bin from 1 to 6 kHz stands no more than a
	// noise's own spread above the median one (the old rain's pings stood 200 times over).
	const size_t w = 1024;
	std::vector<double> ratios;
	for (size_t at = 0; at + w <= x.size(); at += w / 2) {
		std::vector<double> bins;
		for (double f = 1000.0; f <= 6000.0; f += 44100.0 / w) {
			double k = 2.0 * std::cos(2.0 * dsp::PI * f / 44100.0), s1 = 0.0, s2 = 0.0;
			for (size_t i = 0; i < w; i++) {
				double hann = 0.5 - 0.5 * std::cos(2.0 * dsp::PI * double(i) / double(w - 1));
				double s = x[at + i] * hann + k * s1 - s2;
				s2 = s1;
				s1 = s;
			}
			bins.push_back(s1 * s1 + s2 * s2 - k * s1 * s2);
		}
		std::sort(bins.begin(), bins.end());
		ratios.push_back(bins.back() / std::max(bins[bins.size() / 2], 1e-12));
	}
	std::sort(ratios.begin(), ratios.end());
	double tonal = ratios[ratios.size() * 99 / 100];
	MESSAGE("loudest bin over the median (99th percentile): " << tonal);
	CHECK(tonal < 40.0);
}

#include <chrono>

#include "audio/music_synth.h"

TEST_CASE("music: a seed makes its own loop, the same every time") {
	auto t0 = std::chrono::steady_clock::now();
	std::vector<int16_t> a = render_music(7), b = render_music(7), c = render_music(8);
	double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count() / 3.0;
	MESSAGE("a 64 s loop in " << ms << " ms");
	REQUIRE(a.size() == size_t(44100 * 64));
	CHECK(a == b);
	CHECK(a != c);
	int worst = 0;
	for (size_t i = 1; i < a.size(); i++) {
		worst = std::max(worst, std::abs(int(a[i]) - int(a[i - 1])));
	}
	CHECK(std::abs(int(a.front()) - int(a.back())) <= worst);
}
