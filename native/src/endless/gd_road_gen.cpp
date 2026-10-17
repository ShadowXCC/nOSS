#include "endless/gd_road_gen.h"

#include <cmath>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

using namespace godot;
using namespace noss::endless;

namespace noss {

namespace {

int64_t to_mm(double p_m) {
	return int64_t(std::llround(p_m * 1000.0));
}

} // namespace

void NossRoadGen::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "seed", "start_biome"), &NossRoadGen::setup);
	ClassDB::bind_method(D_METHOD("get_seed"), &NossRoadGen::get_seed);
	ClassDB::bind_method(D_METHOD("get_start_biome"), &NossRoadGen::get_start_biome);
	ClassDB::bind_method(D_METHOD("chunk", "k"), &NossRoadGen::chunk);
	ClassDB::bind_method(D_METHOD("ground_heights", "x0", "z0", "w", "d", "cell"), &NossRoadGen::ground_heights);
	ClassDB::bind_method(D_METHOD("ground_at", "x", "z"), &NossRoadGen::ground_at);
	ClassDB::bind_method(D_METHOD("biome_at", "x", "z"), &NossRoadGen::biome_at);
	ClassDB::bind_method(D_METHOD("axis_heading"), &NossRoadGen::axis_heading);
	ClassDB::bind_method(D_METHOD("checksum", "chunks"), &NossRoadGen::checksum);
	ClassDB::bind_static_method("NossRoadGen", D_METHOD("biome_ids"), &NossRoadGen::biome_ids);
	ClassDB::bind_static_method("NossRoadGen", D_METHOD("chunk_samples"), &NossRoadGen::chunk_samples);
}

void NossRoadGen::setup(int64_t p_seed, int64_t p_start_biome) {
	_gen.setup(uint64_t(p_seed), int(p_start_biome));
}

Dictionary NossRoadGen::chunk(int64_t p_k) {
	Dictionary out;
	std::vector<Sample> samples = _gen.chunk(p_k);
	if (samples.empty()) {
		return out;
	}
	int64_t n = int64_t(samples.size());
	PackedFloat64Array x, y, z, heading, time_up, time_down;
	PackedFloat32Array curvature, grade, bank, lane, ground, ground_l, ground_r, blend, speed_up, speed_down;
	PackedByteArray lifted, barrier_l, barrier_r, biome, biome2;
	for (auto *a : { &x, &y, &z, &heading, &time_up, &time_down }) {
		a->resize(n);
	}
	for (auto *a : { &curvature, &grade, &bank, &lane, &ground, &ground_l, &ground_r, &blend, &speed_up, &speed_down }) {
		a->resize(n);
	}
	for (auto *a : { &lifted, &barrier_l, &barrier_r, &biome, &biome2 }) {
		a->resize(n);
	}
	for (int64_t i = 0; i < n; i++) {
		const Sample &s = samples[size_t(i)];
		x.set(i, double(s.x) * 1e-6);
		y.set(i, double(s.y) * 1e-6);
		z.set(i, double(s.z) * 1e-6);
		heading.set(i, double(s.heading) * TURN_TO_RAD);
		curvature.set(i, float(double(s.curve) * TURN_TO_RAD / 2.0));
		grade.set(i, float(double(s.grade) / double(STEP_UM)));
		bank.set(i, float(s.bank_mdeg) * 0.001f);
		lane.set(i, float(s.lane_mm) * 0.001f);
		ground.set(i, float(double(s.ground) * 1e-6));
		ground_l.set(i, float(double(s.ground_l) * 1e-6));
		ground_r.set(i, float(double(s.ground_r) * 1e-6));
		blend.set(i, float(s.blend) / 65536.0f);
		speed_up.set(i, float(s.v_up) * 0.001f);
		speed_down.set(i, float(s.v_down) * 0.001f);
		time_up.set(i, double(s.t_up) * 1e-6);
		time_down.set(i, double(s.t_down) * 1e-6);
		lifted.set(i, (s.flags & FLAG_LIFTED) ? 1 : 0);
		barrier_l.set(i, (s.flags & FLAG_BARRIER_L) ? 1 : 0);
		barrier_r.set(i, (s.flags & FLAG_BARRIER_R) ? 1 : 0);
		biome.set(i, s.biome);
		biome2.set(i, s.biome2);
	}
	out["first"] = samples[0].index;
	out["x"] = x;
	out["y"] = y;
	out["z"] = z;
	out["heading"] = heading;
	out["curvature"] = curvature;
	out["grade"] = grade;
	out["bank"] = bank;
	out["lane"] = lane;
	out["ground"] = ground;
	out["ground_l"] = ground_l;
	out["ground_r"] = ground_r;
	out["lifted"] = lifted;
	out["barrier_l"] = barrier_l;
	out["barrier_r"] = barrier_r;
	out["biome"] = biome;
	out["biome2"] = biome2;
	out["blend"] = blend;
	out["speed_up"] = speed_up;
	out["speed_down"] = speed_down;
	out["time_up"] = time_up;
	out["time_down"] = time_down;
	out["checksum"] = int64_t(RoadGen::checksum(samples));
	return out;
}

PackedFloat32Array NossRoadGen::ground_heights(double p_x0, double p_z0, int64_t p_w, int64_t p_d, double p_cell) const {
	PackedFloat32Array out;
	if (p_w <= 0 || p_d <= 0 || p_w * p_d > 4096 * 4096) {
		return out;
	}
	out.resize(p_w * p_d);
	float *w = out.ptrw();
	const Landscape &land = _gen.landscape();
	int64_t x0 = to_mm(p_x0), z0 = to_mm(p_z0), cell = std::max<int64_t>(to_mm(p_cell), 1);
	for (int64_t r = 0; r < p_d; r++) {
		for (int64_t c = 0; c < p_w; c++) {
			w[r * p_w + c] = float(double(land.ground_mm(x0 + c * cell, z0 + r * cell)) * 0.001);
		}
	}
	return out;
}

double NossRoadGen::ground_at(double p_x, double p_z) const {
	return double(_gen.landscape().ground_mm(to_mm(p_x), to_mm(p_z))) * 0.001;
}

Vector3 NossRoadGen::biome_at(double p_x, double p_z) const {
	const Landscape &land = _gen.landscape();
	BiomeMix m = land.biome_at(land.axis_mm(to_mm(p_x), to_mm(p_z)));
	return Vector3(real_t(m.a), real_t(m.b), real_t(double(m.w) / 65536.0));
}

double NossRoadGen::axis_heading() const {
	return double(_gen.landscape().axis_heading()) * TURN_TO_RAD;
}

int64_t NossRoadGen::checksum(int64_t p_chunks) const {
	RoadGen fresh;
	fresh.setup(_gen.seed(), _gen.start_biome());
	uint64_t h = 0xcbf29ce484222325ULL;
	for (int64_t k = 0; k < p_chunks; k++) {
		h = RoadGen::checksum(fresh.chunk(k), h);
	}
	return int64_t(h);
}

PackedStringArray NossRoadGen::biome_ids() {
	PackedStringArray out;
	for (int b = 0; b < BIOME_COUNT; b++) {
		out.append(biome_style(b).id);
	}
	return out;
}

} // namespace noss
