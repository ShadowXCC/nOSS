#include "endless/gd_road_gen.h"

#include <algorithm>
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
	ClassDB::bind_method(D_METHOD("tile_paint", "x0", "z0", "w", "d", "cell", "heights"), &NossRoadGen::tile_paint);
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

namespace {

double smooth(double p_a, double p_b, double p_x) {
	double t = std::clamp((p_x - p_a) / (p_b - p_a), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// Layer weights for one biome at a sample: grass, dirt, sand, gravel, rock, snow.
void biome_paint(int p_biome, double p_h, double p_slope, double p_patch, double p_field, double r_w[6]) {
	for (int i = 0; i < 6; i++) {
		r_w[i] = 0.0;
	}
	double steep = smooth(0.7, 1.0, p_slope);
	switch (p_biome) {
		case BIOME_COAST: {
			double beach = smooth(5.0, 2.0, p_h);
			r_w[0] = (0.85 - 0.15 * p_patch) * (1.0 - beach);
			r_w[1] = (0.15 + 0.15 * p_patch) * (1.0 - beach);
			r_w[2] = beach;
			break;
		}
		case BIOME_FOREST:
			r_w[0] = 0.7 - 0.2 * p_patch;
			r_w[1] = 0.3 + 0.2 * p_patch;
			break;
		case BIOME_FARMLAND: {
			double ploughed = smooth(0.25, 0.4, p_field);
			r_w[0] = 1.0 - ploughed;
			r_w[1] = ploughed;
			break;
		}
		case BIOME_CANYON:
			r_w[2] = 0.55 + 0.25 * p_patch;
			r_w[1] = 0.45 - 0.25 * p_patch;
			steep = smooth(0.35, 0.6, p_slope);
			break;
		case BIOME_ALPINE:
			r_w[0] = 0.8 - 0.1 * p_patch;
			r_w[1] = 0.2 + 0.1 * p_patch;
			r_w[5] = smooth(210.0, 260.0, p_h) * 3.0;
			steep = smooth(0.45, 0.75, p_slope);
			break;
		case BIOME_SNOW:
			r_w[5] = 1.0;
			steep = smooth(0.55, 0.85, p_slope);
			break;
		case BIOME_AUTUMN:
			r_w[0] = 0.55 - 0.2 * p_patch;
			r_w[1] = 0.45 + 0.2 * p_patch;
			break;
		default:
			r_w[0] = 1.0;
	}
	for (int i = 0; i < 6; i++) {
		if (i != 4) {
			r_w[i] *= 1.0 - steep;
		}
	}
	r_w[4] = steep;
}

} // namespace

PackedByteArray NossRoadGen::tile_paint(double p_x0, double p_z0, int64_t p_w, int64_t p_d, double p_cell, const PackedFloat32Array &p_heights) const {
	PackedByteArray out;
	if (p_w <= 1 || p_d <= 1 || p_heights.size() != p_w * p_d) {
		return out;
	}
	out.resize(p_w * p_d * 8);
	uint8_t *o = out.ptrw();
	const float *h = p_heights.ptr();
	const Landscape &land = _gen.landscape();
	uint64_t seed = _gen.seed();
	for (int64_t r = 0; r < p_d; r++) {
		for (int64_t c = 0; c < p_w; c++) {
			double x = p_x0 + c * p_cell, z = p_z0 + r * p_cell;
			int64_t xm = to_mm(x), zm = to_mm(z);
			int64_t i = r * p_w + c;
			double dx = (h[r * p_w + std::min(c + 1, p_w - 1)] - h[r * p_w + std::max<int64_t>(c - 1, 0)]) / (2.0 * p_cell);
			double dz = (h[std::min(r + 1, p_d - 1) * p_w + c] - h[std::max<int64_t>(r - 1, 0) * p_w + c]) / (2.0 * p_cell);
			double slope = std::sqrt(dx * dx + dz * dz);
			double patch = double(value_noise_q16(xm, zm, 45000, seed ^ 0xBA7C4ULL)) / 65536.0;
			double field = double(value_noise_q16(xm, zm, 140000, seed ^ 0xF1E1DULL)) / 65536.0;
			BiomeMix m = land.biome_at(land.axis_mm(xm, zm));
			double wa[6], wb[6], w[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
			biome_paint(m.a, h[i], slope, patch, field, wa);
			biome_paint(m.b, h[i], slope, patch, field, wb);
			double t = m.b != m.a ? double(m.w) / 65536.0 : 0.0;
			double sum = 0.0;
			for (int k = 0; k < 6; k++) {
				w[k] = std::max(0.0, wa[k] + (wb[k] - wa[k]) * t);
				sum += w[k];
			}
			int total = 0;
			int biggest = 0;
			for (int k = 0; k < 8; k++) {
				int v = sum > 0.0 ? int(w[k] / sum * 255.0) : (k == 0 ? 255 : 0);
				o[i * 8 + k] = uint8_t(v);
				total += v;
				if (w[k] > w[biggest]) {
					biggest = k;
				}
			}
			o[i * 8 + biggest] = uint8_t(o[i * 8 + biggest] + (255 - total)); // exactly 255
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
