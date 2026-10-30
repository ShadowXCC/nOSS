#include <doctest/doctest.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>

#include "audio/dsp.h"
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

// Correlation of a loop with itself p_lag samples on (wrapping), 1 = the same.
double correlation(const std::vector<int16_t> &p_x, int p_lag) {
	double sum = 0.0, power = 0.0;
	for (size_t i = 0; i < p_x.size(); i++) {
		sum += double(p_x[i]) * double(p_x[(i + size_t(p_lag)) % p_x.size()]);
		power += double(p_x[i]) * double(p_x[i]);
	}
	return sum / power;
}

// Share of a loop's energy above p_hz.
double energy_above(const std::vector<int16_t> &p_x, double p_hz) {
	dsp::Biquad hp = dsp::Biquad::highpass(p_hz, 44100.0);
	double high = 0.0, all = 0.0;
	for (int pass = 0; pass < 2; pass++) {
		for (int16_t s : p_x) {
			double h = hp.run(double(s));
			if (pass == 1) {
				high += h * h;
				all += double(s) * double(s);
			}
		}
	}
	return high / all;
}

double wrap_jump(const Loop &p_loop) {
	double steps = 0.0;
	for (size_t i = 1; i < p_loop.samples.size(); i++) {
		steps = std::max(steps, std::abs(double(p_loop.samples[i]) - double(p_loop.samples[i - 1])));
	}
	return std::abs(double(p_loop.samples.front()) - double(p_loop.samples.back())) / steps;
}

EngineProfile even(int p_cylinders) {
	EngineProfile p;
	for (int i = 0; i < p_cylinders; i++) {
		p.fire_deg.push_back(720.0 * i / p_cylinders);
		p.bank.push_back(i % 2);
	}
	return p;
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

TEST_CASE("engine synth: a V12 fires six times a revolution") {
	Loop loop = render_loop(even(12), 3000.0, 1.0, Emitter::EXHAUST);
	int period = best_period(loop.samples, 110, 200); // the 300 Hz firing: 147 samples
	CHECK(44100.0 / period == doctest::Approx(300.0).epsilon(0.03));
}

TEST_CASE("engine synth: diesel knock is bright") {
	EngineProfile p = even(6);
	std::fill(p.bank.begin(), p.bank.end(), 0);
	double plain = energy_above(render_loop(p, 1500.0, 1.0, Emitter::ENGINE).samples, 2000.0);
	p.knock = 0.6;
	Loop knocked = render_loop(p, 1500.0, 1.0, Emitter::ENGINE);
	CHECK(energy_above(knocked.samples, 2000.0) > plain * 2.0);
	CHECK(wrap_jump(knocked) <= 1.05);
}

TEST_CASE("engine synth: held pulses keep the firing frequency") {
	// A two-rotor rotary fires like an inline four, with long square pulses.
	EngineProfile p = inline_four();
	p.bank = { 0, 1, 0, 1 };
	p.pulse_hold_deg = 100.0;
	for (Emitter e : { Emitter::ENGINE, Emitter::EXHAUST, Emitter::INTAKE }) {
		Loop loop = render_loop(p, 3000.0, 1.0, e);
		CHECK(wrap_jump(loop) <= 1.05);
	}
	Loop loop = render_loop(p, 3000.0, 1.0, Emitter::EXHAUST);
	CHECK(44100.0 / best_period(loop.samples, 300, 600) == doctest::Approx(100.0).epsilon(0.03));
	// Longer pulses than the plain ones: more of the loop is loud.
	auto loud = [](const Loop &p_loop) {
		int count = 0;
		for (int16_t s : p_loop.samples) {
			count += std::abs(s) > 8000 ? 1 : 0;
		}
		return count;
	};
	CHECK(loud(render_loop(p, 3000.0, 1.0, Emitter::ENGINE)) > loud(render_loop(inline_four(), 3000.0, 1.0, Emitter::ENGINE)));
}

TEST_CASE("engine synth: cylinder spread adds the half order, the same at every rpm") {
	// An even-firing six repeats every firing; uneven cylinders make it repeat only every cycle.
	EngineProfile p = even(6);
	std::fill(p.bank.begin(), p.bank.end(), 0);
	p.jitter = 0.0;
	p.harshness = 0.0;
	auto half_order = [](const EngineProfile &p_profile) {
		Loop loop = render_loop(p_profile, 3000.0, 1.0, Emitter::ENGINE);
		int cycle = int(std::lround(44100.0 * 120.0 / loop.rpm));
		return correlation(loop.samples, cycle) - correlation(loop.samples, cycle / 6);
	};
	double plain = half_order(p);
	p.cyl_spread = 0.15;
	MESSAGE("half order: plain ", plain, ", spread ", half_order(p));
	CHECK(half_order(p) > plain + 0.01);
	// The strengths come from the profile and seed alone, so every rpm point and emitter agrees.
	std::vector<double> gains = cylinder_gains(p, 3);
	REQUIRE(gains.size() == 6);
	CHECK(*std::max_element(gains.begin(), gains.end()) - *std::min_element(gains.begin(), gains.end()) > 0.05);
	for (double g : gains) {
		CHECK(std::abs(g - 1.0) <= 0.15);
	}
	CHECK(gains == cylinder_gains(p, 3));
	p.cyl_spread = 0.0;
	CHECK(cylinder_gains(p, 3) == std::vector<double>(6, 1.0));
}
