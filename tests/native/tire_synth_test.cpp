#include <doctest/doctest.h>

#include <cmath>
#include <cstdlib>

#include "audio/tire_synth.h"

using namespace noss::audio;

namespace {

TireProfile squeal() {
	TireProfile p;
	p.bands = { { 1050.0, 20.0, 1.0 }, { 1730.0, 15.0, 0.6 }, { 2600.0, 10.0, 0.35 } };
	p.tone = 0.12;
	return p;
}

// Power at p_hz (Goertzel).
double power(const std::vector<int16_t> &p_x, double p_hz, int p_rate = 44100) {
	double w = 2.0 * 3.14159265358979323846 * p_hz / p_rate, c = 2.0 * std::cos(w);
	double s1 = 0.0, s2 = 0.0;
	for (int16_t v : p_x) {
		double s0 = double(v) + c * s1 - s2;
		s2 = s1;
		s1 = s0;
	}
	return s1 * s1 + s2 * s2 - c * s1 * s2;
}

} // namespace

TEST_CASE("tire synth: loops are seamless") {
	std::vector<int16_t> loop = render_tire_loop(squeal(), 44100, 2.0, 3);
	REQUIRE(loop.size() == 88200);
	double steps = 0.0;
	for (size_t i = 1; i < loop.size(); i++) {
		steps = std::max(steps, std::abs(double(loop[i]) - double(loop[i - 1])));
	}
	double wrap = std::abs(double(loop.front()) - double(loop.back()));
	CHECK(wrap <= steps * 1.05);
}

TEST_CASE("tire synth: the energy is in the bands, not below them") {
	std::vector<int16_t> loop = render_tire_loop(squeal(), 44100, 2.0, 3);
	double in_band = power(loop, 1050.0) + power(loop, 1730.0);
	double low = power(loop, 300.0) + power(loop, 120.0);
	double high = power(loop, 6000.0);
	CHECK(in_band > 20.0 * low);
	CHECK(in_band > 20.0 * high);
}

TEST_CASE("tire synth: same seed, same loop; another seed differs") {
	CHECK(render_tire_loop(squeal(), 44100, 0.5, 4) == render_tire_loop(squeal(), 44100, 0.5, 4));
	CHECK(render_tire_loop(squeal(), 44100, 0.5, 4) != render_tire_loop(squeal(), 44100, 0.5, 5));
}
