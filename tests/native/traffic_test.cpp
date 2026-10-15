#include <doctest/doctest.h>

#include <algorithm>
#include <cmath>
#include <map>
#include <set>

#include "traffic/traffic_sim.h"

using namespace noss::traffic;

namespace {

constexpr double PI = 3.14159265358979323846;
constexpr double R = 500.0; // the ring's centreline radius, m
constexpr int N = 1572; // vertices round it (~2 m apart)

// A ring road like a highway's lane graph: 3 lanes each way (direction 1 round the outside, its
// lane 0 outermost; -1 the other way round the inside), an exit off direction 1's outer lane into
// a portal, and an entry out of a portal that runs beside that lane and joins it.
GraphInput ring(bool p_ramps = true) {
	GraphInput g;
	auto circle = [&](double p_r, int p_dir, int p_index) {
		LaneInput l;
		l.dir = p_dir;
		l.index = p_index;
		l.closed = true;
		l.speed_mmps = 30000;
		for (int v = 0; v < N; v++) {
			double a = 2.0 * PI * v / N * p_dir;
			l.xyz.push_back(float(std::cos(a) * p_r));
			l.xyz.push_back(0.0f);
			l.xyz.push_back(float(std::sin(a) * p_r));
		}
		g.lanes.push_back(l);
	};
	for (int k = 0; k < 3; k++) {
		circle(R + 15.0 - 3.6 * k, 1, k); // lanes 0-2: direction 1, lane 0 outermost
	}
	for (int k = 0; k < 3; k++) {
		circle(R - 15.0 + 3.6 * k, -1, k); // lanes 3-5: direction -1, lane 0 innermost (its outside)
	}
	g.adjacent = { { 0, 1 }, { 1, 2 }, { 3, 4 }, { 4, 5 } };
	if (!p_ramps) {
		return g;
	}
	// The exit: off lane 0 at vertex 100, straight on (tangent) for 300 m into portal 0.
	{
		LaneInput l;
		l.road = 0;
		l.speed_mmps = 19000;
		double a = 2.0 * PI * 100 / N;
		double x0 = std::cos(a) * (R + 15.0), z0 = std::sin(a) * (R + 15.0);
		double tx = -std::sin(a), tz = std::cos(a);
		double ox = std::cos(a), oz = std::sin(a);
		for (int i = 0; i <= 150; i++) {
			double along = i * 2.0;
			double out = 0.0006 * along * along;
			l.xyz.push_back(float(x0 + tx * along + ox * out));
			l.xyz.push_back(0.0f);
			l.xyz.push_back(float(z0 + tz * along + oz * out));
		}
		g.lanes.push_back(l); // lane 6
		g.branches.push_back({ 0, 100, 6 });
		g.portal_in.push_back({ 6, 0 });
	}
	// The entry: from portal 1 for 200 m, then beside lane 0 from vertex 700 for 100 vertices,
	// drifting in onto it, joining at vertex 799.
	{
		LaneInput l;
		l.road = 1;
		l.speed_mmps = 19000;
		double a0 = 2.0 * PI * 700 / N;
		double sx = std::cos(a0) * (R + 15.0 + 4.0), sz = std::sin(a0) * (R + 15.0 + 4.0);
		double tx = -std::sin(a0), tz = std::cos(a0);
		for (int i = 100; i >= 1; i--) {
			l.xyz.push_back(float(sx - tx * i * 2.0 + std::cos(a0) * 0.002 * i * i));
			l.xyz.push_back(0.0f);
			l.xyz.push_back(float(sz - tz * i * 2.0 + std::sin(a0) * 0.002 * i * i));
		}
		for (int v = 700; v < 800; v++) {
			double a = 2.0 * PI * v / N;
			double out = 4.0 * (1.0 - (v - 700) / 99.0);
			l.xyz.push_back(float(std::cos(a) * (R + 15.0 + out)));
			l.xyz.push_back(0.0f);
			l.xyz.push_back(float(std::sin(a) * (R + 15.0 + out)));
		}
		g.lanes.push_back(l); // lane 7
		g.attaches.push_back({ 7, 100, 0, 700, 100 });
		g.merges.push_back({ 7, 0, 799 });
		g.portal_out.push_back({ 7, 1 });
	}
	return g;
}

std::vector<TypeSpec> mix() {
	TypeSpec car;
	car.weight = 70;
	TypeSpec van;
	van.length_mm = 5600;
	van.speed_min_q8 = 220;
	van.speed_max_q8 = 250;
	van.accel_mmps2 = 1100;
	van.weight = 15;
	TypeSpec truck;
	truck.length_mm = 9000;
	truck.width_mm = 2500;
	truck.speed_min_q8 = 200;
	truck.speed_max_q8 = 225;
	truck.accel_mmps2 = 700;
	truck.decel_mmps2 = 1800;
	truck.headway_ms = 1800;
	truck.lanes_max = 2;
	truck.weight = 15;
	return { car, van, truck };
}

TrafficSim make(int p_count, uint64_t p_seed = 7, bool p_ramps = true) {
	TrafficSim sim;
	std::string error;
	bool ok = sim.setup(ring(p_ramps), mix(), p_seed, p_count, 0.3, &error);
	REQUIRE_MESSAGE(ok, error);
	return sim;
}

// Smallest bumper gap between cars wholly in one lane (not moving over), mm; `r_where` says where.
int64_t min_gap(const TrafficSim &p_sim, std::string *r_where = nullptr) {
	int64_t worst = INT64_MAX;
	std::map<int, std::vector<std::pair<int64_t, int>>> by_lane;
	for (const Car &c : p_sim.st.cars) {
		if ((c.flags & ACTIVE) && c.lc_from < 0) {
			by_lane[c.lane].push_back({ c.s, c.id });
		}
	}
	for (auto &[lane, cars] : by_lane) {
		std::sort(cars.begin(), cars.end());
		const Lane &l = p_sim.graph.lanes[size_t(lane)];
		for (size_t i = 0; i < cars.size(); i++) {
			size_t j = i + 1;
			int64_t wrap = 0;
			if (j == cars.size()) {
				if (!l.closed || cars.size() < 2) {
					break;
				}
				j = 0;
				wrap = l.length;
			}
			const Car &lead = p_sim.st.cars[size_t(cars[j].second)];
			int64_t gap = cars[j].first + wrap - p_sim.types[lead.type].length_mm - cars[i].first;
			if (gap < worst && r_where) {
				const Car &back = p_sim.st.cars[size_t(cars[i].second)];
				*r_where = "lane " + std::to_string(lane) + " cars " + std::to_string(back.id) + " (v " + std::to_string(back.v) + ", type " + std::to_string(back.type) +
						") behind " + std::to_string(lead.id) + " (v " + std::to_string(lead.v) + ", flags " + std::to_string(lead.flags) + ") at " + std::to_string(cars[i].first);
			}
			worst = std::min(worst, gap);
		}
	}
	return worst;
}

} // namespace

TEST_CASE("traffic: helpers are exact") {
	CHECK(isqrt64(0) == 0);
	CHECK(isqrt64(15) == 3);
	CHECK(isqrt64(16) == 4);
	CHECK(isqrt64(1000000000000ULL) == 1000000);
	Pcg32 a(42, 54), b(42, 54);
	for (int i = 0; i < 100; i++) {
		CHECK(a.next() == b.next());
	}
	Pcg32 c(1, 1);
	for (int i = 0; i < 1000; i++) {
		int32_t v = c.range(5, 9);
		CHECK(v >= 5);
		CHECK(v <= 9);
	}
}

TEST_CASE("traffic: the lane graph measures, maps and finds lanes") {
	LaneGraph g;
	std::string error;
	REQUIRE(g.build(ring(), &error));
	CHECK(g.lanes.size() == 8);
	// Lane 0's length is the circle's, to the millimetre or so per segment.
	CHECK(double(g.lanes[0].length) == doctest::Approx(2.0 * PI * (R + 15.0) * 1000.0).epsilon(0.001));
	// Adjacent lanes map by vertex: half way round lane 0 is half way round lane 2.
	int64_t half0 = g.lanes[0].length / 2;
	int64_t on2 = g.map_s(0, half0, 2);
	CHECK(double(on2) == doctest::Approx(double(g.lanes[2].length) / 2.0).epsilon(0.001));
	CHECK(std::llabs(g.map_s(2, on2, 0) - half0) < 5);
	// The entry runs beside lane 0 for its last 100 vertices.
	int64_t beside = g.lanes[7].cum[150];
	int64_t on_road = g.map_s(7, beside, 0);
	CHECK(on_road == doctest::Approx(double(g.lanes[0].cum[750])).epsilon(0.01));
	CHECK(g.map_s(7, 1000, 0) == -1); // before it runs beside the road
	// Locating a point a lane width in finds lane 1, and which side.
	double a = 0.3;
	LanePos p = g.locate(std::cos(a) * (R + 15.0 - 3.6), 0.5, std::sin(a) * (R + 15.0 - 3.6));
	CHECK(p.lane == 1);
	CHECK(std::abs(p.lateral) < 0.05);
	LanePos off = g.locate(std::cos(a) * (R + 15.0 - 3.6 - 1.0), 0.5, std::sin(a) * (R + 15.0 - 3.6 - 1.0));
	CHECK(off.lane == 1);
	CHECK(off.lateral < -0.9); // inwards is direction 1's right on this ring
	CHECK(g.locate(0.0, 0.0, 0.0).lane == -1);
	// Speeds: a 515 m bend allows sqrt(2.5 x 515) = 35.9 m/s, so the 30 m/s limit holds; the exit
	// slows to its own limit ahead of time.
	CHECK(g.limit_at(0, 1000) == 30000);
	CHECK(g.lanes[6].limit[0] <= 19000);
	// The same input hashes the same; a moved vertex doesn't.
	LaneGraph h;
	REQUIRE(h.build(ring()));
	CHECK(g.hash() == h.hash());
	GraphInput moved = ring();
	moved.lanes[3].xyz[30] += 0.01f;
	LaneGraph m;
	REQUIRE(m.build(moved));
	CHECK(m.hash() != g.hash());
}

TEST_CASE("traffic: the same seed gives the same traffic") {
	TrafficSim a = make(300);
	TrafficSim b = make(300);
	for (int t = 0; t < 2000; t++) {
		a.step();
		b.step();
	}
	CHECK(a.checksum() == b.checksum());
	TrafficSim c = make(300, 8);
	c.step_to(2000);
	CHECK(c.checksum() != a.checksum());
}

TEST_CASE("traffic: pinned checksum (every platform must step to this)") {
	TrafficSim sim = make(150);
	sim.step_to(10000);
	// If this changes, the lane sim changed: every game must update together (protocol bump).
	CHECK(sim.checksum() == 8343415004528514565ULL);
}

TEST_CASE("traffic: an hour with 400 cars: no overlaps, sane speeds, signals first, trucks keep right") {
	TrafficSim sim = make(400);
	std::map<int, int> signal_since; // car -> ticks its signal has shown
	int changes = 0, exits = 0, returns = 0;
	std::vector<uint8_t> was_away(sim.st.cars.size(), 0);
	int64_t worst_gap = INT64_MAX;
	for (int t = 0; t < 72000; t++) {
		std::vector<int16_t> before(sim.st.cars.size());
		for (size_t i = 0; i < sim.st.cars.size(); i++) {
			before[i] = sim.st.cars[i].lc_from;
			was_away[i] = (sim.st.cars[i].flags & AWAY) ? 1 : 0;
		}
		sim.step();
		REQUIRE(sim.active() + sim.away() == 400);
		for (size_t i = 0; i < sim.st.cars.size(); i++) {
			const Car &c = sim.st.cars[i];
			if (c.lc_from >= 0 && before[i] < 0) {
				changes++;
				CHECK_MESSAGE(signal_since[int(i)] >= SIGNAL_TICKS, "car ", i, " moved over after ", signal_since[int(i)], " ticks of signal");
			}
			signal_since[int(i)] = c.signal != 0 ? signal_since[int(i)] + 1 : 0;
			if ((c.flags & AWAY) && !was_away[i]) {
				exits++;
			}
			if (!(c.flags & AWAY) && was_away[i]) {
				returns++;
			}
			if (c.flags & ACTIVE) {
				CHECK(c.v >= 0);
				CHECK(c.v <= 30000 * sim.types[c.type].speed_max_q8 / 256 + 1500);
				const Lane &l = sim.graph.lanes[size_t(c.lane)];
				if (sim.types[c.type].lanes_max > 0 && l.road < 0 && c.lc_from < 0) {
					CHECK(l.index < sim.types[c.type].lanes_max);
				}
			}
		}
		if (t % 20 == 0) {
			std::string where;
			int64_t g = min_gap(sim, &where);
			if (g < 0 && worst_gap >= 0) {
				MESSAGE("first overlap at tick ", sim.st.tick, ": ", g, " mm, ", where);
			}
			worst_gap = std::min(worst_gap, g);
		}
	}
	CHECK(worst_gap >= 0);
	CHECK(changes > 200);
	// About 30% of direction 1's cars leave per lap; they all come back.
	CHECK(exits > 50);
	CHECK(returns > 30);
	MESSAGE("lane changes ", changes, ", exits ", exits, ", returns ", returns, ", closest ", worst_gap, " mm");
}

TEST_CASE("traffic: the same cars come round again") {
	TrafficSim sim = make(150);
	// Cars passing a point on direction 1's outer lane: who passes in the first lap's worth of
	// time comes past again in the next.
	auto passing = [&](int p_ticks) {
		std::set<int> seen;
		std::vector<int32_t> last(sim.st.cars.size(), -1);
		for (int t = 0; t < p_ticks; t++) {
			sim.step();
			for (const Car &c : sim.st.cars) {
				if ((c.flags & ACTIVE) && sim.graph.lanes[size_t(c.lane)].road < 0 && sim.graph.lanes[size_t(c.lane)].dir == 1) {
					int64_t s0 = sim.graph.map_s(c.lane, c.s, 0);
					if (last[c.id] >= 0 && last[c.id] < 200000 && s0 >= 200000 && s0 < 400000) {
						seen.insert(c.id);
					}
					last[c.id] = int32_t(s0);
				}
			}
		}
		return seen;
	};
	std::set<int> first = passing(20 * 150);
	std::set<int> second = passing(20 * 150);
	int again = 0;
	for (int id : first) {
		again += second.count(id) ? 1 : 0;
	}
	CHECK(first.size() > 20);
	CHECK(double(again) / double(first.size()) > 0.6);
}

TEST_CASE("traffic: late events roll back to the same result") {
	TrafficSim a = make(200);
	TrafficSim b = make(200);
	std::vector<Event> events;
	uint16_t seq = 0;
	for (uint32_t t = 100; t < 1800; t += 37) {
		Event e;
		e.kind = (seq % 3 == 0) ? EV_PROMOTE : (seq % 3 == 1 ? EV_RESHADOW : EV_DEMOTE);
		e.seq = seq++;
		e.tick = t;
		e.car = uint16_t((t * 7) % 200);
		e.lane = int16_t((t / 37) % 3);
		e.s = int32_t((t * 1311) % 3000000);
		e.v = 25000;
		events.push_back(e);
	}
	Event wreck;
	wreck.kind = EV_WRECK;
	wreck.seq = seq++;
	wreck.tick = 900;
	wreck.car = 11;
	wreck.lane = 1;
	wreck.s = 1500000;
	events.push_back(wreck);
	Event tow = wreck;
	tow.kind = EV_TOW;
	tow.seq = seq++;
	tow.tick = 1500;
	events.push_back(tow);
	std::sort(events.begin(), events.end(), [](const Event &x, const Event &y) { return x.tick < y.tick; });
	// A gets each event in time; B gets it 1-40 ticks late.
	size_t next_a = 0, next_b = 0;
	for (uint32_t t = 0; t < 2000; t++) {
		while (next_a < events.size() && events[next_a].tick <= t) {
			REQUIRE(a.schedule({ events[next_a++] }));
		}
		while (next_b < events.size() && events[next_b].tick + 1 + (events[next_b].seq * 13) % 40 <= t) {
			REQUIRE(b.schedule({ events[next_b++] }));
		}
		a.step();
		b.step();
	}
	CHECK(a.checksum() == b.checksum());
	uint64_t sa = 0, sb = 0;
	REQUIRE(a.checksum_at(1990, sa));
	REQUIRE(b.checksum_at(1990, sb));
	CHECK(sa == sb);
	// An event older than the ring can't be replayed.
	Event old;
	old.kind = EV_PROMOTE;
	old.seq = 9999;
	old.tick = 10;
	CHECK_FALSE(b.schedule({ old }));
}

TEST_CASE("traffic: the full state round-trips exactly") {
	TrafficSim a = make(150);
	a.step_to(1234);
	TrafficSim b = make(150);
	REQUIRE(b.load_full_state(a.full_state()));
	CHECK(b.checksum() == a.checksum());
	a.step_to(2000);
	b.step_to(2000);
	CHECK(b.checksum() == a.checksum());
	std::vector<uint8_t> broken = a.full_state();
	broken.pop_back();
	CHECK_FALSE(b.load_full_state(broken));
}

TEST_CASE("traffic: a closure makes cars move over; a wreck stops its lane") {
	TrafficSim sim = make(250, 3, false);
	sim.step_to(400);
	Event close;
	close.kind = EV_CLOSE;
	close.tick = sim.st.tick;
	close.car = 1; // closure id
	close.lane = 2;
	close.s = 1000000;
	close.v = 300000;
	REQUIRE(sim.schedule({ close }));
	sim.step_to(sim.st.tick + 20 * 90);
	// Asked about: ahead, inside, behind, another lane, and from the far side of the loop's seam.
	CHECK(sim.closed_ahead(2, 900000, 200000));
	CHECK(sim.closed_ahead(2, 1100000, 1000));
	CHECK_FALSE(sim.closed_ahead(2, 700000, 200000));
	CHECK_FALSE(sim.closed_ahead(2, 1400000, 200000));
	CHECK_FALSE(sim.closed_ahead(1, 900000, 200000));
	int64_t length = sim.graph.lanes[2].length;
	CHECK(sim.closed_ahead(2, length - 50000, 1100000));
	CHECK_FALSE(sim.closed_ahead(2, length - 50000, 1000000));
	for (const Car &c : sim.st.cars) {
		if ((c.flags & ACTIVE) && c.lane == 2) {
			CHECK_FALSE((c.s > 1000000 && c.s <= 1300000));
		}
	}
	CHECK(min_gap(sim) >= 0);
	Event open;
	open.kind = EV_OPEN;
	open.tick = sim.st.tick;
	open.car = 1;
	REQUIRE(sim.schedule({ open }));
	sim.step();
	CHECK(sim.st.closures.empty());
	// A wreck stands still; nobody drives through it.
	Event wreck;
	wreck.kind = EV_WRECK;
	wreck.tick = sim.st.tick;
	wreck.car = 5;
	wreck.lane = 1;
	wreck.s = 2000000;
	REQUIRE(sim.schedule({ wreck }));
	sim.step_to(sim.st.tick + 20 * 60);
	const Car &w = sim.st.cars[5];
	CHECK((w.flags & WRECK) != 0);
	CHECK(w.s == 2000000);
	CHECK(w.v == 0);
	CHECK(min_gap(sim) >= 0);
	Event tow;
	tow.kind = EV_TOW;
	tow.tick = sim.st.tick;
	tow.car = 5;
	REQUIRE(sim.schedule({ tow }));
	sim.step();
	CHECK((sim.st.cars[5].flags & AWAY) != 0);
}

// --- near misses and the physics driver ------------------------------------------------------

#include "traffic/lane_driver.h"
#include "traffic/near_query.h"
#include "vehicle_harness.h"

TEST_CASE("traffic: box gaps hull to hull") {
	Box2 a{ 0.0, 0.0, 0.0, 1.0, 2.0, 1.0 };
	Box2 b{ 3.0, 0.0, 0.0, 1.0, 2.0, 1.0 }; // side by side, 1 m apart
	CHECK(box_gap(a, b) == doctest::Approx(1.0));
	b.cx = 1.5; // overlapping
	CHECK(box_gap(a, b) == doctest::Approx(0.0));
	b = { 0.0, 7.0, 0.0, 1.0, 2.0, 1.0 }; // nose to tail, 3 m
	CHECK(box_gap(a, b) == doctest::Approx(3.0));
	b = { 3.0, 4.0, 1.0, 0.0, 2.0, 1.0 }; // turned across: level in x, 1 m apart in z
	CHECK(box_gap(a, b) == doctest::Approx(1.0).epsilon(1e-6));
	b = { 4.0, 5.0, 1.0, 0.0, 2.0, 1.0 }; // corner to corner: 1 m and 2 m
	CHECK(box_gap(a, b) == doctest::Approx(std::hypot(1.0, 2.0)).epsilon(1e-6));
	double along = 0.0, left = 0.0;
	box_offset(a, Box2{ 1.0, 5.0, 0.0, 1.0, 2.0, 1.0 }, along, left);
	CHECK(along == doctest::Approx(5.0));
	CHECK(left == doctest::Approx(1.0)); // heading +Z, the driver's left is +X
}

namespace {

// A single carriageway round a 300 m circle: lane 0 outside, lane 1 inside it.
TrafficSim r300() {
	GraphInput g;
	for (int k = 0; k < 2; k++) {
		LaneInput l;
		l.dir = 1;
		l.index = k;
		l.closed = true;
		l.speed_mmps = 30000;
		double r = 300.0 - 3.6 * k;
		for (int v = 0; v < 942; v++) {
			double a = 2.0 * PI * v / 942;
			l.xyz.push_back(float(std::cos(a) * r));
			l.xyz.push_back(0.0f);
			l.xyz.push_back(float(std::sin(a) * r));
		}
		g.lanes.push_back(l);
	}
	g.adjacent = { { 0, 1 } };
	TrafficSim sim;
	REQUIRE(sim.setup(g, { TypeSpec() }, 1, 1, 0.0));
	Car &c = sim.st.cars[0];
	c.flags = ACTIVE | SHADOW;
	c.lane = 0;
	c.s = 10000;
	c.v = 0;
	return sim;
}

// A GT on the harness, driven by the lane driver for `p_seconds`; calls `p_each(time)` per tick.
// `p_pin`: the shadow stays in its lane (no lane changes of its own).
template <typename F>
void drive_for(TrafficSim &r_sim, noss::test::Harness &r_h, double p_seconds, const std::vector<Member> &p_members, F p_each, bool p_pin = false) {
	int ticks = int(p_seconds * 120.0);
	for (int i = 0; i < ticks; i++) {
		DriveIn in;
		in.car = 0;
		const auto &ch = r_h.chassis;
		in.x = ch.origin.x;
		in.y = 0.0;
		in.z = ch.origin.z;
		double fx = ch.basis.c2.x, fz = ch.basis.c2.z;
		double len = std::hypot(fx, fz);
		in.fx = fx / len;
		in.fz = fz / len;
		in.speed = r_h.forward_speed();
		in.wheelbase = 2.6;
		in.max_steer = 28.0 * PI / 180.0;
		DriveOut out = drive(r_sim, in, p_members);
		r_h.model.controls.steer = out.steer;
		r_h.model.controls.throttle = out.throttle;
		r_h.model.controls.brake = out.brake;
		r_h.model.controls.handbrake = out.handbrake;
		r_h.step();
		if (i % 6 == 5) {
			r_sim.step();
			// Keep the shadow alongside (as the owner's reshadows would).
			Car &c = r_sim.st.cars[0];
			c.s = int32_t(out.s);
			c.v = int32_t(std::max(in.speed, 0.0) * 1000.0);
			if (p_pin && c.lc_from < 0) {
				c.target = -1;
				c.signal = 0;
				c.signal_ticks = 0;
			}
		}
		p_each(double(i) / 120.0, out);
	}
}

} // namespace

TEST_CASE("traffic: the lane driver holds its lane round a 300 m bend") {
	TrafficSim sim = r300();
	noss::test::Harness h(noss::vehicle::make_config(noss::test::gt_spec(), noss::test::nsx_geometry()));
	// On lane 0 at s = 10 m: facing along the circle (anticlockwise in x-z: heading +Z at angle 0).
	double a = 10.0 / 300.0;
	h.place_at(std::cos(a) * 300.0, std::sin(a) * 300.0, std::atan2(-std::sin(a), std::cos(a)));
	double worst = 0.0, speed = 0.0;
	drive_for(sim, h, 60.0, {}, [&](double p_t, const DriveOut &p_out) {
		if (p_t > 25.0) {
			worst = std::max(worst, std::abs(p_out.lateral));
		}
		speed = h.forward_speed();
	});
	MESSAGE("lane error ", worst, " m at ", speed, " m/s");
	CHECK(worst < 0.3);
	CHECK(speed > 24.0); // the bend's limit is sqrt(2.5 x 300) = 27.4 m/s
}

TEST_CASE("traffic: the lane driver moves over with its shadow, and not into a car beside it") {
	TrafficSim sim = r300();
	noss::test::Harness h(noss::vehicle::make_config(noss::test::gt_spec(), noss::test::nsx_geometry()));
	double a = 10.0 / 300.0;
	h.place_at(std::cos(a) * 300.0, std::sin(a) * 300.0, std::atan2(-std::sin(a), std::cos(a)));
	drive_for(sim, h, 25.0, {}, [](double, const DriveOut &) {});
	// The shadow moves over to lane 1.
	Car &c = sim.st.cars[0];
	c.lc_from = 0;
	c.lane = 1;
	c.s = int32_t(sim.graph.map_s(0, c.s, 1));
	c.lc = 1;
	c.signal = 1;
	double r_start = std::hypot(h.chassis.origin.x, h.chassis.origin.z);
	double t_done = -1.0;
	drive_for(sim, h, 8.0, {}, [&](double p_t, const DriveOut &) {
		double r = std::hypot(h.chassis.origin.x, h.chassis.origin.z);
		if (t_done < 0.0 && r < 300.0 - 3.6 + 0.3) {
			t_done = p_t;
		}
	}, true);
	MESSAGE("moved over from r = ", r_start, " in ", t_done, " s");
	CHECK(t_done > 1.5);
	CHECK(t_done < 4.5);
	// Back to lane 0 with a car right beside it there: it holds lane 1.
	double ang = std::atan2(h.chassis.origin.z, h.chassis.origin.x);
	Member m;
	m.id = 7;
	m.box = { std::cos(ang) * 300.0, std::sin(ang) * 300.0, -std::sin(ang), std::cos(ang), 6.0, 1.25 }; // a bus (standing still: keep it short)
	m.v = h.forward_speed();
	c.lc_from = 1;
	c.lane = 0;
	c.s = int32_t(sim.graph.map_s(1, c.s, 0));
	c.lc = 1;
	bool blocked = true;
	double max_r = 0.0;
	drive_for(sim, h, 0.25, { m }, [&](double, const DriveOut &p_out) {
		blocked = blocked && p_out.blocked;
		max_r = std::max(max_r, std::hypot(h.chassis.origin.x, h.chassis.origin.z));
	});
	CHECK(blocked);
	CHECK(max_r < 300.0 - 3.6 + 0.5);
}

TEST_CASE("traffic: the lane driver stops behind a stopped car") {
	TrafficSim sim = r300();
	noss::test::Harness h(noss::vehicle::make_config(noss::test::gt_spec(), noss::test::nsx_geometry()));
	double a = 10.0 / 300.0;
	h.place_at(std::cos(a) * 300.0, std::sin(a) * 300.0, std::atan2(-std::sin(a), std::cos(a)));
	drive_for(sim, h, 20.0, {}, [](double, const DriveOut &) {});
	// A stopped car 150 m on round lane 0.
	double here = std::atan2(h.chassis.origin.z, h.chassis.origin.x);
	double there = here + 150.0 / 300.0;
	Member stopped;
	stopped.id = 3;
	stopped.box = { std::cos(there) * 300.0, std::sin(there) * 300.0, -std::sin(there), std::cos(there), 2.25, 0.9 };
	double closest = 1e9;
	drive_for(sim, h, 20.0, { stopped }, [&](double, const DriveOut &) {
		Box2 me{ h.chassis.origin.x, h.chassis.origin.z, h.chassis.basis.c2.x, h.chassis.basis.c2.z, 2.2, 0.9 };
		closest = std::min(closest, box_gap(me, stopped.box));
	});
	MESSAGE("stopped ", closest, " m short, at ", h.forward_speed(), " m/s");
	CHECK(closest > 0.5);
	CHECK(closest < 8.0);
	CHECK(std::abs(h.forward_speed()) < 0.5);
}
