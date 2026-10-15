#include <doctest/doctest.h>

#include <cmath>
#include <cstdlib>

#include "audio/fx_synth.h"

using namespace noss::audio;

TEST_CASE("fx synth: every item sound is short, loud enough and the same each time") {
	const char *names[] = { "pickup", "roulette", "fire", "hit", "shield", "emp", "boost", "tier", "slick" };
	for (const char *name : names) {
		CAPTURE(name);
		std::vector<int16_t> a = render_fx(fx_kind(name));
		std::vector<int16_t> b = render_fx(fx_kind(name));
		CHECK(a == b);
		CHECK(a.size() > 1000);
		CHECK(a.size() < size_t(44100)); // under a second
		int peak = 0;
		double rms = 0.0;
		for (int16_t s : a) {
			peak = std::max(peak, std::abs(int(s)));
			rms += double(s) * s;
		}
		rms = std::sqrt(rms / a.size());
		CHECK(peak >= 26000); // normalized to 80% of full scale
		CHECK(peak <= 26300);
		CHECK(rms > 1000.0);
	}
	CHECK(fx_kind("nonsense") == FxKind::PICKUP);
	// The hit is low, the roulette tick high: count zero crossings per second.
	auto crossings = [](const std::vector<int16_t> &p_x) {
		int n = 0;
		for (size_t i = 1; i < p_x.size(); i++) {
			n += (p_x[i - 1] < 0) != (p_x[i] < 0) ? 1 : 0;
		}
		return n / (p_x.size() / 44100.0) / 2.0;
	};
	CHECK(crossings(render_fx(FxKind::ROULETTE)) > crossings(render_fx(FxKind::EMP)));
}
