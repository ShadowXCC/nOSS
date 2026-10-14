#include <doctest/doctest.h>

#include <cmath>
#include <cstdlib>

#include "audio/siren_synth.h"

using namespace noss::audio;

namespace {

// Zero crossings per second over samples [from, from + n): about twice the frequency.
double crossing_hz(const std::vector<int16_t> &p_s, size_t p_from, size_t p_n, int p_rate) {
	int crossings = 0;
	for (size_t i = p_from + 1; i < p_from + p_n && i < p_s.size(); i++) {
		if ((p_s[i - 1] < 0) != (p_s[i] < 0)) {
			crossings++;
		}
	}
	return crossings / 2.0 / (double(p_n) / p_rate);
}

} // namespace

TEST_CASE("siren: loops are seamless and sweep where they should") {
	for (SirenKind kind : { SirenKind::WAIL, SirenKind::YELP }) {
		std::vector<int16_t> s = render_siren(kind);
		REQUIRE(s.size() > 1000);
		// The end flows into the start: the jump there is no bigger than a step inside the loop.
		int biggest = 0;
		for (size_t i = 1; i < s.size(); i++) {
			biggest = std::max(biggest, std::abs(s[i] - s[i - 1]));
		}
		CHECK(std::abs(s.front() - s.back()) <= biggest);
	}
	// The wail starts low (580 Hz) and peaks half way through (1420 Hz).
	std::vector<int16_t> wail = render_siren(SirenKind::WAIL);
	double low = crossing_hz(wail, 0, 2205, 44100);
	double high = crossing_hz(wail, wail.size() / 2 - 1100, 2205, 44100);
	CHECK(low == doctest::Approx(580.0).epsilon(0.15));
	CHECK(high == doctest::Approx(1420.0).epsilon(0.15));
}

TEST_CASE("siren: the horn is two tones that loop") {
	std::vector<int16_t> h = render_horn(420.0, 500.0);
	CHECK(h.size() == 22050);
	int biggest = 0;
	for (size_t i = 1; i < h.size(); i++) {
		biggest = std::max(biggest, std::abs(h[i] - h[i - 1]));
	}
	CHECK(std::abs(h.front() - h.back()) <= biggest);
}
