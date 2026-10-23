#include <doctest/doctest.h>

#include <cmath>

#include "world/heightfield.h"

using namespace noss::world;

namespace {

Heightfield flat(int p_side = 101) {
	Heightfield f;
	f.create(p_side, p_side, -50.0, -50.0, 1.0, 0.0f, 0);
	return f;
}

double variance(const Heightfield &p_f, const Rect &p_r) {
	double sum = 0.0, sum2 = 0.0;
	int n = 0;
	for (int z = p_r.z0; z < p_r.z1; z++) {
		for (int x = p_r.x0; x < p_r.x1; x++) {
			double h = p_f.base[size_t(z) * size_t(p_f.w) + size_t(x)];
			sum += h;
			sum2 += h * h;
			n++;
		}
	}
	return sum2 / n - (sum / n) * (sum / n);
}

// A straight road along +x at y = p_y through the field.
std::vector<RoadSample> straight(double p_y, double p_bank_ly = 0.0, bool p_lifted = false) {
	std::vector<RoadSample> road;
	for (int i = -60; i <= 60; i += 2) {
		RoadSample s;
		s.x = i;
		s.y = p_y;
		s.z = 0.0;
		s.lx = 0.0;
		s.ly = p_bank_ly;
		s.lz = -1.0; // left of +x, as the game's left = up x forward
		s.flat_l = 8.0;
		s.flat_r = 8.0;
		s.lifted = p_lifted;
		road.push_back(s);
	}
	return road;
}

} // namespace

TEST_CASE("terrain: a raise dab is full inside, soft at the edge, nothing outside") {
	Heightfield f = flat();
	Brush b;
	b.mode = BrushMode::RAISE;
	b.radius = 10.0;
	b.strength = 2.0;
	b.falloff = 0.5;
	Rect r = f.brush(b);
	CHECK_FALSE(r.empty());
	CHECK(f.base_at(0.0, 0.0) == doctest::Approx(2.0));
	CHECK(f.base_at(4.0, 0.0) == doctest::Approx(2.0));
	double edge = f.base_at(8.0, 0.0);
	CHECK(edge > 0.0);
	CHECK(edge < 2.0);
	CHECK(f.base_at(12.0, 0.0) == doctest::Approx(0.0));
	CHECK(r.x0 >= 0);
	CHECK(r.x1 <= f.w);
}

TEST_CASE("terrain: smoothing lowers the variance; flatten reaches its target") {
	Heightfield f = flat();
	Brush n;
	n.mode = BrushMode::NOISE;
	n.radius = 30.0;
	n.strength = 5.0;
	n.scale = 0.2;
	f.brush(n);
	Rect area = f.rect_around(0.0, 0.0, 10.0);
	double before = variance(f, area);
	CHECK(before > 0.01);
	Brush s;
	s.mode = BrushMode::SMOOTH;
	s.radius = 20.0;
	s.strength = 1.0;
	for (int i = 0; i < 5; i++) {
		f.brush(s);
	}
	CHECK(variance(f, area) < before * 0.5);
	Brush fl;
	fl.mode = BrushMode::FLATTEN;
	fl.radius = 20.0;
	fl.strength = 1.0;
	fl.falloff = 0.0;
	fl.target = 3.0;
	f.brush(fl);
	CHECK(f.base_at(0.0, 0.0) == doctest::Approx(3.0));
}

TEST_CASE("terrain: paint keeps the weights at 255") {
	Heightfield f = flat();
	f.paint(3, 0.0, 0.0, 10.0, 0.6, 0.5);
	f.paint(5, 2.0, 0.0, 10.0, 0.4, 0.5);
	for (int z = 40; z < 60; z++) {
		for (int x = 40; x < 60; x++) {
			int sum = 0;
			for (int l = 0; l < LAYERS; l++) {
				sum += f.splat[(size_t(z) * size_t(f.w) + size_t(x)) * LAYERS + size_t(l)];
			}
			CHECK(sum == 255);
		}
	}
	std::vector<uint8_t> top = f.dominant_layers();
	CHECK(top[50 * size_t(f.w) + 50] != 0);
}

TEST_CASE("terrain: conform levels the ground under a road and blends back outside") {
	Heightfield f = flat();
	for (float &h : f.base) {
		h = 5.0f; // ground 5 m up, road at 2 m: cut
	}
	f.final_h = f.base;
	Rect all{ 0, 0, f.w, f.d };
	f.conform(all, straight(2.0), 12.0, 0.05);
	CHECK(f.height_at(0.0, 0.0) == doctest::Approx(1.95).epsilon(0.001));
	CHECK(f.height_at(0.0, 7.0) == doctest::Approx(1.95).epsilon(0.001)); // inside the flat width
	double mid = f.height_at(0.0, 14.0); // in the falloff
	CHECK(mid > 1.95);
	CHECK(mid < 5.0);
	CHECK(f.height_at(0.0, 25.0) == doctest::Approx(5.0)); // past it
	CHECK(f.base_at(0.0, 0.0) == doctest::Approx(5.0)); // the shaped ground is kept
	// Monotonic out through the falloff.
	double prev = f.height_at(0.0, 8.0);
	for (double z = 9.0; z <= 20.0; z += 1.0) {
		double h = f.height_at(0.0, z);
		CHECK(h >= prev - 1e-6);
		prev = h;
	}
}

TEST_CASE("terrain: a banked road tilts its bed; a lifted one leaves the ground alone") {
	Heightfield f = flat();
	Rect all{ 0, 0, f.w, f.d };
	// Left is -z; ly > 0 raises the left side.
	f.conform(all, straight(0.0, 0.1), 12.0, 0.0);
	CHECK(f.height_at(0.0, -5.0) > f.height_at(0.0, 5.0));
	Heightfield g = flat();
	g.conform(all, straight(10.0, 0.0, true), 12.0, 0.0);
	CHECK(g.height_at(0.0, 0.0) == doctest::Approx(0.0));
}

// A straight along +x from x = -60 to 60, every 2 m: lifted where `p_lifted` says, at `p_y(x)`.
template <typename Lifted, typename Height>
std::vector<RoadSample> bridge(Lifted p_lifted, Height p_y) {
	std::vector<RoadSample> road = straight(0.0);
	for (RoadSample &s : road) {
		s.y = p_y(s.x);
		s.flat_l = 4.0;
		s.flat_r = 4.0;
		s.lifted = p_lifted(s.x);
	}
	road.back().end = true;
	return road;
}

// The highest ground across the deck (inside its width) at x, less the deck there.
double over_deck(const Heightfield &p_f, double p_x, double p_deck) {
	double worst = -1e9;
	for (double z = -1.75; z <= 1.75; z += 1.75) {
		worst = std::max(worst, p_f.height_at(p_x, z) - p_deck);
	}
	return worst;
}

TEST_CASE("terrain: no ramp where a falling deck starts") {
	// On the ground at 10 m to x = 0, then a bridge sinking 0.1 m a metre over a valley at 0.
	Heightfield f = flat();
	auto deck = [](double x) { return x <= 0.0 ? 10.0 : 10.0 - 0.1 * x; };
	f.conform(Rect{ 0, 0, f.w, f.d }, bridge([](double x) { return x > 0.0; }, deck), 20.0, 0.05);
	CHECK(f.height_at(-10.0, 0.0) == doctest::Approx(9.95).epsilon(0.001)); // the fill up to it
	for (double x = 2.0; x <= 40.0; x += 1.0) {
		CAPTURE(x);
		CHECK(over_deck(f, x, deck(x)) <= -LIFTED_CLEAR_M + 1e-3);
	}
}

TEST_CASE("terrain: no ramp where a climbing deck ends") {
	// A bridge rising 0.1 m a metre to x = 0, then on the ground at 10 m.
	Heightfield f = flat();
	auto deck = [](double x) { return x >= 0.0 ? 10.0 : 10.0 + 0.1 * x; };
	f.conform(Rect{ 0, 0, f.w, f.d }, bridge([](double x) { return x < 0.0; }, deck), 20.0, 0.05);
	CHECK(f.height_at(10.0, 0.0) == doctest::Approx(9.95).epsilon(0.001));
	for (double x = -40.0; x <= -2.0; x += 1.0) {
		CAPTURE(x);
		CHECK(over_deck(f, x, deck(x)) <= -LIFTED_CLEAR_M + 1e-3);
	}
}

TEST_CASE("terrain: the bed eases toward a lifted end and stops there") {
	// One 10 m step from the ground (x = 0) onto a level deck (x = 10 on), nothing before it: past
	// the deck's first sample nothing fills the valley at 0 m.
	Heightfield f = flat();
	std::vector<RoadSample> road;
	for (double x : { 0.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0 }) {
		RoadSample s;
		s.x = x;
		s.y = 6.0;
		s.lx = 0.0;
		s.lz = -1.0;
		s.flat_l = 4.0;
		s.flat_r = 4.0;
		s.lifted = x > 0.0;
		road.push_back(s);
	}
	road.back().end = true;
	f.conform(Rect{ 0, 0, f.w, f.d }, road, 6.0, 0.05);
	CHECK(f.height_at(2.0, 0.0) > f.height_at(5.0, 0.0));
	CHECK(f.height_at(5.0, 0.0) > f.height_at(8.0, 0.0));
	CHECK(f.height_at(8.0, 0.0) < 5.95);
	CHECK(f.height_at(14.0, 0.0) == doctest::Approx(0.0));
	CHECK(f.height_at(14.0, 1.75) == doctest::Approx(0.0));
}

TEST_CASE("terrain: ground above a deck is cut below it; beside it is left alone") {
	Heightfield f = flat();
	for (float &h : f.base) {
		h = 8.0f; // a hill the bridge runs into
	}
	f.final_h = f.base;
	f.conform(Rect{ 0, 0, f.w, f.d }, straight(6.0, 0.0, true), 12.0, 0.05);
	CHECK(f.height_at(0.0, 0.0) <= 6.0 - 0.05 - LIFTED_CLEAR_M + 1e-3);
	CHECK(f.height_at(0.0, 20.0) == doctest::Approx(8.0));
}

TEST_CASE("terrain: roads in one list break where one ends") {
	Heightfield f = flat();
	for (float &h : f.base) {
		h = 5.0f;
	}
	f.final_h = f.base;
	Rect all{ 0, 0, f.w, f.d };
	// Two straights at z = 0 and z = 50, each ending on a sample marked `end`: nothing joins the end
	// of one to the start of the next (or the last back to the first).
	std::vector<RoadSample> road = straight(2.0);
	road.back().end = true;
	for (RoadSample s : straight(2.0)) {
		s.z = 50.0;
		road.push_back(s);
	}
	road.back().end = true;
	f.conform(all, road, 6.0, 0.0);
	CHECK(f.height_at(0.0, 0.0) == doctest::Approx(2.0).epsilon(0.001));
	CHECK(f.height_at(0.0, 50.0) == doctest::Approx(2.0).epsilon(0.001));
	CHECK(f.height_at(0.0, 25.0) == doctest::Approx(5.0)); // between them: untouched
	// Without the marks the jump from one road to the next is levelled too.
	Heightfield g = flat();
	for (float &h : g.base) {
		h = 5.0f;
	}
	g.final_h = g.base;
	for (RoadSample &s : road) {
		s.end = false;
	}
	g.conform(all, road, 6.0, 0.0);
	CHECK(g.height_at(0.0, 25.0) < 4.0);
}

TEST_CASE("terrain: a ray hits the ground where it is") {
	Heightfield f = flat();
	Brush b;
	b.mode = BrushMode::RAISE;
	b.radius = 20.0;
	b.strength = 4.0;
	b.falloff = 0.0;
	f.brush(b);
	f.final_h = f.base;
	double o[3] = { 0.0, 50.0, 0.0 }, dir[3] = { 0.0, -1.0, 0.0 }, hit[3];
	REQUIRE(f.raycast(o, dir, 100.0, hit));
	CHECK(hit[1] == doctest::Approx(4.0).epsilon(0.01));
	double o2[3] = { -40.0, 10.0, 30.0 }, dir2[3] = { 1.0, -0.2, 0.0 };
	REQUIRE(f.raycast(o2, dir2, 200.0, hit));
	CHECK(hit[1] == doctest::Approx(f.height_at(hit[0], hit[2])).epsilon(0.01));
	double miss[3] = { 0.0, 50.0, 0.0 }, up[3] = { 0.0, 1.0, 0.0 };
	CHECK_FALSE(f.raycast(miss, up, 100.0, hit));
}

TEST_CASE("terrain: chunks share their edges and regions round-trip") {
	Heightfield f;
	f.create(257, 129, 0.0, 0.0, 1.0, 0.0f, 0);
	Brush n;
	n.mode = BrushMode::NOISE;
	n.x = 128.0;
	n.z = 64.0;
	n.radius = 200.0;
	n.strength = 3.0;
	n.scale = 0.05;
	f.brush(n);
	f.final_h = f.base;
	std::vector<float> a, b;
	f.chunk_collision(0, 0, 128, a);
	f.chunk_collision(1, 0, 128, b);
	REQUIRE(a.size() == 129u * 129u);
	for (int z = 0; z <= 128; z++) {
		CHECK(a[size_t(z) * 129 + 128] == b[size_t(z) * 129]);
	}
	float lo, hi;
	f.chunk_range(0, 0, 128, lo, hi);
	CHECK(lo <= hi);
	std::vector<uint16_t> r16;
	f.chunk_r16(0, 0, 128, lo - 1.0, (hi - lo) + 2.0, r16);
	CHECK(r16.size() == 131u * 131u);
	Rect r{ 10, 10, 30, 20 };
	std::vector<float> before = f.get_region(r);
	Brush up;
	up.x = 20.0;
	up.z = 15.0;
	up.radius = 5.0;
	f.brush(up);
	f.set_region(r, before);
	CHECK(f.get_region(r) == before);
}

TEST_CASE("terrain: on a slope the bed follows the road beside it") {
	Heightfield f = flat();
	std::vector<RoadSample> road = straight(0.0);
	for (RoadSample &s : road) {
		s.y = s.x * 0.1; // a 10 % climb
		s.flat_l = 20.0;
		s.flat_r = 20.0;
	}
	Rect all{ 0, 0, f.w, f.d };
	f.conform(all, road, 12.0, 0.0);
	for (double x = -40.0; x <= 40.0; x += 5.0) {
		CHECK(f.height_at(x, 15.0) == doctest::Approx(x * 0.1).epsilon(0.01));
	}
}

TEST_CASE("terrain: paving holds its bed where another road's run-off reaches over it") {
	Heightfield f = flat();
	Rect all{ 0, 0, f.w, f.d };
	// A road at y 0, paved 5 m each side, levelled out to 20; beside it (a road of its own) one at
	// y 1, centred 14 m to the left (-z), paved 9 m each side: its paving starts at the first one's
	// edge. A cell 6 m left of the first is nearer its centreline, on the second's paving.
	std::vector<RoadSample> road = straight(0.0);
	for (RoadSample &s : road) {
		s.flat_l = 20.0;
		s.flat_r = 20.0;
		s.paved_l = 5.0;
		s.paved_r = 5.0;
	}
	road.back().end = true;
	for (RoadSample s : straight(1.0)) {
		s.z = -14.0;
		s.flat_l = 9.0;
		s.flat_r = 9.0;
		s.paved_l = 9.0;
		s.paved_r = 9.0;
		road.push_back(s);
	}
	road.back().end = true;
	f.conform(all, road, 6.0, 0.0);
	CHECK(f.height_at(0.0, -6.0) == doctest::Approx(1.0).epsilon(0.001));
	CHECK(f.height_at(0.0, -3.0) == doctest::Approx(0.0).epsilon(0.001)); // its own paving
	// Without paving widths the nearest still wins, as before.
	for (RoadSample &s : road) {
		s.paved_l = 1e30;
		s.paved_r = 1e30;
	}
	Heightfield g = flat();
	g.conform(all, road, 6.0, 0.0);
	CHECK(g.height_at(0.0, -6.0) == doctest::Approx(0.0).epsilon(0.001));
}

TEST_CASE("terrain: an apron's bed leaves the banking for its own slope; none changes nothing") {
	Heightfield f = flat();
	Rect all{ 0, 0, f.w, f.d };
	// Banked down to the left (ly < 0), 6 m to each edge, levelled 14 m on the left.
	std::vector<RoadSample> road = straight(4.0, -std::sin(0.4));
	for (RoadSample &s : road) {
		s.lx = 0.0;
		s.lz = -std::cos(0.4);
		s.flat_l = 14.0;
	}
	Heightfield plain = flat();
	plain.conform(all, road, 12.0, 0.0);
	// An apron of width 0 is no apron: the same ground, sample for sample.
	std::vector<RoadSample> zero = road;
	for (RoadSample &s : zero) {
		s.edge_l = 6.0;
		s.edge_r = 6.0;
		s.slope_l = 0.3;
	}
	f.conform(all, zero, 12.0, 0.0);
	CHECK(f.final_h == plain.final_h);
	// A level apron past the left edge: flat from the edge out; the banking carries on without.
	std::vector<RoadSample> apron = zero;
	for (RoadSample &s : apron) {
		s.apron_l = 8.0;
		s.slope_l = 0.0;
	}
	Heightfield g = flat();
	g.conform(all, apron, 12.0, 0.0);
	double edge_x = 6.0 * std::cos(0.4); // across the map
	double edge_y = 4.0 - 6.0 * std::sin(0.4);
	double bend = 0.25 * std::tan(0.4); // cut deeper for the bend at the edge (1 m cells)
	CHECK(g.height_at(0.0, -(edge_x + 1.0)) == doctest::Approx(edge_y - bend).epsilon(0.02));
	CHECK(g.height_at(0.0, -(edge_x + 6.0)) == doctest::Approx(edge_y - bend).epsilon(0.02));
	CHECK(plain.height_at(0.0, -(edge_x + 6.0)) < edge_y - 2.0);
	// The right side, with no apron, is as it was.
	CHECK(g.height_at(0.0, 4.0) == doctest::Approx(plain.height_at(0.0, 4.0)));
	// Across the bend, between the grid's samples, the ground never comes up through the road or
	// the apron.
	for (double z = -edge_x - 3.0; z <= -edge_x + 3.0; z += 0.05) {
		double surface = z < -edge_x ? edge_y : 4.0 + z * std::tan(0.4); // left is -z, down to the left
		CHECK(g.height_at(0.0, z) <= surface + 1e-6);
	}
}
