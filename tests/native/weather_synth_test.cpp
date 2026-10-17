#include <doctest/doctest.h>

#include <cmath>
#include <cstdlib>

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
