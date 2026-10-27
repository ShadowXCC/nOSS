#include <doctest/doctest.h>

#include <chrono>
#include <cmath>
#include <cstdint>
#include <tuple>
#include <unordered_map>
#include <vector>

#include "endless/road_gen.h"

using namespace noss::endless;

namespace {

constexpr int64_t CONE = 894784853; // 75 degrees
constexpr int64_t PINNED_SEED1 = 4068332388687893009;
constexpr int64_t PINNED_HAUNTED = -7993603731218011089;
constexpr int64_t PINNED_INTO_HAUNTED = -6517383681570269417;
// A Forest start whose second biome is Haunted (D221).
constexpr uint64_t INTO_HAUNTED_SEED = 2;

// Every chunk up to p_km, joined (the shared sample between chunks once).
std::vector<Sample> drive(RoadGen &p_gen, int64_t p_km) {
	std::vector<Sample> out;
	int64_t chunks = p_km * 1000 / (CHUNK * 2) + 1;
	for (int64_t k = 0; k < chunks; k++) {
		std::vector<Sample> c = p_gen.chunk(k);
		REQUIRE(c.size() == size_t(CHUNK + 1));
		if (!out.empty()) {
			REQUIRE(out.back().index == c.front().index);
			CHECK(RoadGen::checksum({ out.back() }) == RoadGen::checksum({ c.front() }));
			out.pop_back();
		}
		out.insert(out.end(), c.begin(), c.end());
	}
	return out;
}

int tightest_radius() {
	int r = 1 << 30;
	for (int b = 0; b < BIOME_COUNT; b++) {
		r = std::min(r, biome_style(b).r_tight[0]);
	}
	return r;
}

int steepest_pm() {
	int g = 0;
	for (int b = 0; b < BIOME_COUNT; b++) {
		g = std::max(g, biome_style(b).max_grade_pm);
	}
	return g;
}

} // namespace

TEST_CASE("endless: integer sin and cos") {
	double worst = 0.0;
	for (int64_t a = -TURN; a <= 2 * TURN; a += 1234567) {
		double rad = double(a) * TURN_TO_RAD;
		worst = std::max(worst, std::abs(double(sin_q30(a)) / double(Q30) - std::sin(rad)));
		worst = std::max(worst, std::abs(double(cos_q30(a)) / double(Q30) - std::cos(rad)));
	}
	MESSAGE("worst error " << worst);
	CHECK(worst < 1e-5);
	CHECK(sin_q30(0) == 0);
	CHECK(cos_q30(0) == Q30);
	CHECK(sin_q30(QUARTER) == Q30);
	CHECK(mul_q30(-3 * Q30, Q30 / 2) == -(3 * Q30 / 2));
	CHECK(floor_div(-7, 2) == -4);
	CHECK(floor_div(7, 2) == 3);
}

TEST_CASE("endless: the same seed makes the same road, other seeds others") {
	RoadGen a, b, c;
	a.setup(1234, BIOME_FOREST);
	b.setup(1234, BIOME_FOREST);
	c.setup(1235, BIOME_FOREST);
	uint64_t ha = 0, hb = 0, hc = 0;
	for (int k = 0; k < 40; k++) {
		ha = RoadGen::checksum(a.chunk(k), ha);
		hb = RoadGen::checksum(b.chunk(k), hb);
		hc = RoadGen::checksum(c.chunk(k), hc);
	}
	CHECK(ha == hb);
	CHECK(ha != hc);
	RoadGen d;
	d.setup(1234, BIOME_ALPINE);
	CHECK(RoadGen::checksum(d.chunk(0)) != RoadGen::checksum(b.chunk(0)));
}

// Pinned: any change to these numbers changes every road made from a seed (and its share code).
// Change them only on purpose, with a new decision.
TEST_CASE("endless: pinned checksums") {
	RoadGen g;
	g.setup(1, BIOME_FOREST);
	uint64_t h = 0xcbf29ce484222325ULL;
	for (int k = 0; k < 50; k++) {
		h = RoadGen::checksum(g.chunk(k), h);
	}
	MESSAGE("seed 1, forest, 12 km: " << int64_t(h));
	CHECK(int64_t(h) == PINNED_SEED1);
	// Haunted (D221): a start there, and a Forest start that goes into it.
	for (auto [seed, start, pinned] : { std::tuple{ uint64_t(1), int(BIOME_HAUNTED), PINNED_HAUNTED }, std::tuple{ INTO_HAUNTED_SEED, int(BIOME_FOREST), PINNED_INTO_HAUNTED } }) {
		RoadGen r;
		r.setup(seed, start);
		uint64_t hr = 0xcbf29ce484222325ULL;
		int haunted = 0; // samples where it's mostly Haunted
		for (int k = 0; k < 50; k++) {
			std::vector<Sample> c = r.chunk(k);
			hr = RoadGen::checksum(c, hr);
			for (const Sample &sm : c) {
				haunted += BiomeMix{ sm.biome, sm.biome2, sm.blend }.dominant() == BIOME_HAUNTED ? 1 : 0;
			}
		}
		MESSAGE("seed " << seed << ", biome " << start << ", 12 km: " << int64_t(hr) << ", " << haunted * 2 << " m of it Haunted");
		CHECK(int64_t(hr) == pinned);
		CHECK(haunted > 500);
	}
}

TEST_CASE("endless: chunks made again from their checkpoints match") {
	RoadGen g;
	g.setup(77, BIOME_COAST);
	std::vector<uint64_t> sums;
	for (int k = 0; k < 60; k++) {
		sums.push_back(RoadGen::checksum(g.chunk(k)));
	}
	for (int k : { 3, 0, 41, 42, 59, 17, 18, 18, 2 }) {
		CHECK(RoadGen::checksum(g.chunk(k)) == sums[size_t(k)]);
	}
	// And on past where it was: the same as a fresh generator going straight there.
	RoadGen fresh;
	fresh.setup(77, BIOME_COAST);
	for (int k = 0; k < 70; k++) {
		uint64_t want = RoadGen::checksum(fresh.chunk(k));
		if (k >= 60) {
			CHECK(RoadGen::checksum(g.chunk(k)) == want);
		}
	}
	// Skipping ahead makes the same chunks as going one at a time.
	RoadGen skip;
	skip.setup(77, BIOME_COAST);
	CHECK(RoadGen::checksum(skip.chunk(65)) == RoadGen::checksum(fresh.chunk(65)));
}

// The road's rules over long drives on many seeds: bends no tighter than the tightest biome's,
// grades within the steepest's, the heading within 75 degrees of the axis, always moving on along
// it (so no two stretches more than 300 m apart along the road come within 60 m), lanes timed.
TEST_CASE("endless: road rules over 20 seeds") {
	const int64_t max_curve = STEP_CURVE / tightest_radius() + 1;
	const int64_t max_grade = STEP_UM * steepest_pm() / 1000;
	int64_t km_total = 0;
	int bridges = 0, barriers = 0;
	double tightest_m = 1e9, steepest = 0.0, widest_deg = 0.0;
	auto t0 = std::chrono::steady_clock::now();
	for (uint64_t seed = 1; seed <= 20; seed++) {
		RoadGen g;
		g.setup(seed * 7919, int(seed % BIOME_COUNT));
		int64_t km = seed <= 2 ? 1000 : 150;
		std::vector<Sample> road = drive(g, km);
		km_total += km;
		int64_t axis_heading = g.landscape().axis_heading();
		std::unordered_map<int64_t, std::vector<size_t>> cells; // 60 m cells
		bool lifted = false;
		for (size_t i = 0; i < road.size(); i++) {
			const Sample &s = road[i];
			int64_t k = s.curve < 0 ? -s.curve : s.curve;
			REQUIRE(k <= max_curve);
			if (k > 0) {
				tightest_m = std::min(tightest_m, double(STEP_CURVE) / double(k));
			}
			REQUIRE(std::llabs(s.grade) <= max_grade);
			steepest = std::max(steepest, std::abs(double(s.grade) / double(STEP_UM)));
			int64_t dev = s.heading - axis_heading;
			REQUIRE(std::llabs(dev) <= CONE);
			widest_deg = std::max(widest_deg, std::abs(double(dev) * 360.0 / double(TURN)));
			REQUIRE(s.v_up > 0);
			REQUIRE(s.v_down > 0);
			REQUIRE(s.y >= 3999000); // above the sea
			if (i > 0) {
				REQUIRE(s.axis - road[i - 1].axis >= 500); // on along the axis every step
				REQUIRE(s.t_up > road[i - 1].t_up);
				REQUIRE(s.t_down > road[i - 1].t_down);
				// 2 m apart, within a few µm
				double dx = double(s.x - road[i - 1].x), dz = double(s.z - road[i - 1].z);
				REQUIRE(std::abs(std::sqrt(dx * dx + dz * dz) - 2e6) < 50.0);
			}
			if ((s.flags & FLAG_LIFTED) && !lifted) {
				bridges++;
			}
			lifted = s.flags & FLAG_LIFTED;
			barriers += (s.flags & (FLAG_BARRIER_L | FLAG_BARRIER_R)) ? 1 : 0;
			if (i % 5 == 0 && seed <= 4) {
				int64_t cx = s.x / 60000000, cz = s.z / 60000000;
				for (int64_t ox = -1; ox <= 1; ox++) {
					for (int64_t oz = -1; oz <= 1; oz++) {
						auto it = cells.find((cx + ox) * 1000003 + (cz + oz));
						if (it == cells.end()) {
							continue;
						}
						for (size_t j : it->second) {
							if (i - j < 150) {
								continue;
							}
							double dx = double(s.x - road[j].x) * 1e-6, dz = double(s.z - road[j].z) * 1e-6;
							REQUIRE(dx * dx + dz * dz >= 60.0 * 60.0);
						}
					}
				}
				cells[cx * 1000003 + cz].push_back(i);
			}
		}
	}
	double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
	MESSAGE(km_total << " km in " << s << " s; tightest " << tightest_m << " m, steepest " << steepest * 100.0
					 << "%, widest " << widest_deg << " deg off the axis, " << bridges << " bridges, " << barriers * 2 / 1000 << " km of guard rail");
	CHECK(bridges > 0);
	CHECK(barriers > 0);
	CHECK(widest_deg > 50.0); // it does wander
	CHECK(tightest_m < 60.0);
}

TEST_CASE("endless: biomes follow each other and blend") {
	Landscape land;
	land.setup(5, BIOME_FARMLAND);
	CHECK(land.biome_at(0).a == BIOME_FARMLAND);
	CHECK(land.biome_at(-50000000).a == BIOME_FARMLAND); // behind the start too
	int changes = 0;
	BiomeMix prev = land.biome_at(0);
	for (int64_t a = 0; a < 100000000; a += 50000) { // 100 km, every 50 m
		BiomeMix m = land.biome_at(a);
		if (m.dominant() != prev.dominant()) {
			changes++;
			CHECK(m.w >= 32000); // a change happens mid-blend
			CHECK(m.w <= 36100);
		}
		prev = m;
	}
	MESSAGE(changes << " biome changes in 100 km");
	CHECK(changes >= 12);
	CHECK(changes <= 26);
	// Ground is continuous across a blend: 1 m apart differ by little.
	for (int64_t a = 0; a < 30000000; a += 7000) {
		int64_t h0 = land.ground_mm(a, 0), h1 = land.ground_mm(a + 1000, 0);
		REQUIRE(std::llabs(h1 - h0) < 3000);
	}
}

// What may follow each biome: Haunted (D221) widened only Forest's and Autumn's choices, so
// roads through the others are unchanged.
TEST_CASE("endless: what follows each biome") {
	const int want[BIOME_COUNT] = { 3, 4, 3, 3, 3, 2, 4, 3 };
	for (int b = 0; b < BIOME_COUNT; b++) {
		int n = 0;
		while (n < NEXT_MAX && biome_style(b).next[n] >= 0) {
			n++;
		}
		CAPTURE(biome_style(b).id);
		CHECK(n == want[b]);
	}
	int seen = 0;
	uint64_t first = 0;
	for (uint64_t seed = 1; seed <= 200; seed++) {
		Landscape land;
		land.setup(seed, int(seed % BIOME_COUNT));
		int prev = land.biome_at(0).a;
		for (int64_t a = 0; a < 120000000; a += 250000) { // 120 km
			int now = land.biome_at(a).a;
			if (now == prev) {
				continue;
			}
			if (now == BIOME_HAUNTED) {
				seen++;
				first = first ? first : seed;
				CHECK((prev == BIOME_FOREST || prev == BIOME_AUTUMN));
			}
			if (prev == BIOME_HAUNTED) {
				CHECK((now == BIOME_FOREST || now == BIOME_AUTUMN || now == BIOME_FARMLAND));
			}
			prev = now;
		}
	}
	MESSAGE(seen << " times into Haunted over 200 seeds, first on seed " << first);
	CHECK(seen > 0);
}

TEST_CASE("endless: a long drive's speed") {
	RoadGen g;
	g.setup(424242, BIOME_ALPINE);
	auto t0 = std::chrono::steady_clock::now();
	for (int k = 0; k < 400; k++) { // ~96 km
		g.chunk(k);
	}
	double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
	MESSAGE("96 km in " << ms << " ms (" << ms / 400.0 << " ms a chunk)");
	CHECK(ms / 400.0 < 5.0);
	CHECK(g.checkpoints() == 401);
}
