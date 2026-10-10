#include <doctest/doctest.h>

#include <cmath>
#include <cstdlib>

#include "audio/engine_synth.h"

using namespace noss::audio;

namespace {

EngineProfile inline_four() {
	EngineProfile p;
	p.fire_deg = { 0, 180, 360, 540 };
	p.bank = { 0, 0, 0, 0 };
	p.exhaust_hz[0] = p.exhaust_hz[1] = 160.0;
	return p;
}

// The lag (in samples) of the strongest autocorrelation between p_min and p_max.
int best_period(const std::vector<int16_t> &p_x, int p_min, int p_max) {
	double best = -1e300;
	int lag = p_min;
	for (int l = p_min; l <= p_max; l++) {
		double sum = 0.0;
		for (size_t i = 0; i + size_t(l) < p_x.size(); i++) {
			sum += double(p_x[i]) * double(p_x[i + size_t(l)]);
		}
		if (sum > best) {
			best = sum;
			lag = l;
		}
	}
	return lag;
}

} // namespace

TEST_CASE("engine synth: loops are seamless") {
	for (Emitter e : { Emitter::ENGINE, Emitter::EXHAUST, Emitter::INTAKE }) {
		Loop loop = render_loop(inline_four(), 3000.0, 1.0, e);
		REQUIRE(loop.samples.size() > 1000);
		// The jump across the wrap is no bigger than the loop's typical sample-to-sample steps.
		double steps = 0.0;
		for (size_t i = 1; i < loop.samples.size(); i++) {
			steps = std::max(steps, std::abs(double(loop.samples[i]) - double(loop.samples[i - 1])));
		}
		double wrap = std::abs(double(loop.samples.front()) - double(loop.samples.back()));
		CHECK(wrap <= steps * 1.05);
	}
}

TEST_CASE("engine synth: the firing frequency is there") {
	// An inline four fires twice per revolution: 100 Hz at 3000 rpm.
	Loop loop = render_loop(inline_four(), 3000.0, 1.0, Emitter::EXHAUST);
	int period = best_period(loop.samples, 300, 600); // 73..147 Hz
	CHECK(44100.0 / period == doctest::Approx(100.0).epsilon(0.03));
	CHECK(loop.rpm == doctest::Approx(3000.0).epsilon(0.01));
}

TEST_CASE("engine synth: an electric motor whines at its order") {
	EngineProfile ev;
	ev.electric = true;
	ev.motor_order = 6.0;
	Loop loop = render_loop(ev, 6000.0, 1.0, Emitter::ENGINE);
	int period = best_period(loop.samples, 50, 120); // the 600 Hz whine: 73.5 samples
	CHECK(44100.0 / period == doctest::Approx(600.0).epsilon(0.03));
}
