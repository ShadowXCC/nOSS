#include "world/heightfield.h"

#include <algorithm>
#include <cmath>

namespace noss::world {

namespace {

constexpr double CEILING_OVER_M = 0.5;

double smoothstep01(double p_t) {
	double t = std::clamp(p_t, 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// How much of a dab reaches p_r metres from its centre: full inside, easing out over the
// soft outer share.
double brush_weight(double p_r, double p_radius, double p_falloff) {
	if (p_r >= p_radius) {
		return 0.0;
	}
	double hard = p_radius * (1.0 - std::clamp(p_falloff, 0.0, 1.0));
	if (p_r <= hard) {
		return 1.0;
	}
	return 1.0 - smoothstep01((p_r - hard) / std::max(p_radius - hard, 1e-6));
}

uint32_t hash2(int32_t p_x, int32_t p_z, uint32_t p_seed) {
	uint32_t h = uint32_t(p_x) * 374761393u + uint32_t(p_z) * 668265263u + p_seed * 2246822519u;
	h = (h ^ (h >> 13)) * 1274126177u;
	return h ^ (h >> 16);
}

double lattice(int32_t p_x, int32_t p_z, uint32_t p_seed) {
	return double(hash2(p_x, p_z, p_seed) & 0xffff) / 32767.5 - 1.0;
}

} // namespace

Rect Rect::merged(const Rect &p_other) const {
	if (empty()) {
		return p_other;
	}
	if (p_other.empty()) {
		return *this;
	}
	return { std::min(x0, p_other.x0), std::min(z0, p_other.z0), std::max(x1, p_other.x1), std::max(z1, p_other.z1) };
}

Rect Rect::clipped(int p_w, int p_d) const {
	Rect r{ std::max(x0, 0), std::max(z0, 0), std::min(x1, p_w), std::min(z1, p_d) };
	if (r.empty()) {
		return Rect{};
	}
	return r;
}

double value_noise(double p_x, double p_z, uint32_t p_seed) {
	double sum = 0.0, amp = 1.0, norm = 0.0, f = 1.0;
	for (int octave = 0; octave < 3; octave++) {
		double x = p_x * f, z = p_z * f;
		int32_t ix = int32_t(std::floor(x)), iz = int32_t(std::floor(z));
		double fx = smoothstep01(x - ix), fz = smoothstep01(z - iz);
		uint32_t s = p_seed + uint32_t(octave) * 101u;
		double a = lattice(ix, iz, s), b = lattice(ix + 1, iz, s);
		double c = lattice(ix, iz + 1, s), e = lattice(ix + 1, iz + 1, s);
		sum += amp * ((a + (b - a) * fx) * (1.0 - fz) + (c + (e - c) * fx) * fz);
		norm += amp;
		amp *= 0.5;
		f *= 2.0;
	}
	return sum / norm;
}

void Heightfield::create(int p_w, int p_d, double p_ox, double p_oz, double p_cell, float p_height, int p_layer) {
	w = std::max(p_w, 2);
	d = std::max(p_d, 2);
	ox = p_ox;
	oz = p_oz;
	cell = std::max(p_cell, 0.01);
	base.assign(size_t(w) * size_t(d), p_height);
	final_h = base;
	splat.assign(size_t(w) * size_t(d) * LAYERS, 0);
	int layer = std::clamp(p_layer, 0, LAYERS - 1);
	for (size_t i = 0; i < size_t(w) * size_t(d); i++) {
		splat[i * LAYERS + size_t(layer)] = 255;
	}
}

float Heightfield::_at_clamped(const std::vector<float> &p_h, int p_x, int p_z) const {
	int x = std::clamp(p_x, 0, w - 1), z = std::clamp(p_z, 0, d - 1);
	return p_h[size_t(z) * size_t(w) + size_t(x)];
}

double Heightfield::_bilinear(const std::vector<float> &p_h, double p_x, double p_z) const {
	if (!valid()) {
		return 0.0;
	}
	double gx = std::clamp((p_x - ox) / cell, 0.0, double(w - 1));
	double gz = std::clamp((p_z - oz) / cell, 0.0, double(d - 1));
	int ix = std::min(int(gx), w - 2), iz = std::min(int(gz), d - 2);
	double fx = gx - ix, fz = gz - iz;
	double a = _at_clamped(p_h, ix, iz), b = _at_clamped(p_h, ix + 1, iz);
	double c = _at_clamped(p_h, ix, iz + 1), e = _at_clamped(p_h, ix + 1, iz + 1);
	return (a + (b - a) * fx) * (1.0 - fz) + (c + (e - c) * fx) * fz;
}

double Heightfield::height_at(double p_x, double p_z) const {
	return _bilinear(final_h, p_x, p_z);
}

double Heightfield::base_at(double p_x, double p_z) const {
	return _bilinear(base, p_x, p_z);
}

Rect Heightfield::rect_around(double p_x, double p_z, double p_radius) const {
	Rect r{ int(std::floor((p_x - p_radius - ox) / cell)), int(std::floor((p_z - p_radius - oz) / cell)),
		int(std::ceil((p_x + p_radius - ox) / cell)) + 1, int(std::ceil((p_z + p_radius - oz) / cell)) + 1 };
	return r.clipped(w, d);
}

Rect Heightfield::brush(const Brush &p) {
	Rect r = rect_around(p.x, p.z, p.radius);
	if (r.empty()) {
		return r;
	}
	// Smoothing reads the heights from before this dab.
	std::vector<float> before;
	if (p.mode == BrushMode::SMOOTH) {
		before = base;
	}
	for (int z = r.z0; z < r.z1; z++) {
		for (int x = r.x0; x < r.x1; x++) {
			double wx = ox + x * cell, wz = oz + z * cell;
			double k = brush_weight(std::hypot(wx - p.x, wz - p.z), p.radius, p.falloff);
			if (k <= 0.0) {
				continue;
			}
			float &h = base[size_t(z) * size_t(w) + size_t(x)];
			switch (p.mode) {
				case BrushMode::RAISE:
					h += float(p.strength * k);
					break;
				case BrushMode::LOWER:
					h -= float(p.strength * k);
					break;
				case BrushMode::SMOOTH: {
					double sum = 0.0;
					for (int dz = -1; dz <= 1; dz++) {
						for (int dx = -1; dx <= 1; dx++) {
							sum += _at_clamped(before, x + dx, z + dz);
						}
					}
					h += float((sum / 9.0 - h) * std::clamp(p.strength, 0.0, 1.0) * k);
					break;
				}
				case BrushMode::FLATTEN:
					h += float((p.target - h) * std::clamp(p.strength, 0.0, 1.0) * k);
					break;
				case BrushMode::NOISE:
					h += float(p.strength * k * value_noise(wx * p.scale, wz * p.scale, p.seed));
					break;
			}
		}
	}
	return r;
}

Rect Heightfield::paint(int p_layer, double p_x, double p_z, double p_radius, double p_strength, double p_falloff) {
	Rect r = rect_around(p_x, p_z, p_radius);
	int layer = std::clamp(p_layer, 0, LAYERS - 1);
	for (int z = r.z0; z < r.z1; z++) {
		for (int x = r.x0; x < r.x1; x++) {
			double k = brush_weight(std::hypot(ox + x * cell - p_x, oz + z * cell - p_z), p_radius, p_falloff);
			if (k <= 0.0) {
				continue;
			}
			uint8_t *wts = &splat[(size_t(z) * size_t(w) + size_t(x)) * LAYERS];
			// Move toward all of `layer` by strength x weight, keeping the sum at 255.
			double a = std::clamp(p_strength, 0.0, 1.0) * k;
			double vals[LAYERS];
			double sum = 0.0;
			for (int l = 0; l < LAYERS; l++) {
				vals[l] = wts[l] * (1.0 - a) + (l == layer ? 255.0 * a : 0.0);
				sum += vals[l];
			}
			// Round to bytes that still add up to 255 (the remainder goes to the painted layer).
			int total = 0;
			for (int l = 0; l < LAYERS; l++) {
				int v = int(std::floor(vals[l] * 255.0 / std::max(sum, 1e-9)));
				wts[l] = uint8_t(std::clamp(v, 0, 255));
				total += wts[l];
			}
			wts[layer] = uint8_t(std::clamp(int(wts[layer]) + 255 - total, 0, 255));
		}
	}
	return r;
}

Rect Heightfield::conform(const Rect &p_rect, const std::vector<RoadSample> &p_road, double p_falloff_m, double p_depth_m) {
	Rect r = p_rect.clipped(w, d);
	if (r.empty()) {
		return r;
	}
	for (int z = r.z0; z < r.z1; z++) {
		size_t row = size_t(z) * size_t(w);
		std::copy(base.begin() + long(row + size_t(r.x0)), base.begin() + long(row + size_t(r.x1)), final_h.begin() + long(row + size_t(r.x0)));
	}
	size_t n = p_road.size();
	if (n < 2) {
		return r;
	}
	double falloff = std::max(p_falloff_m, 0.01);
	std::vector<float> best_w(size_t(r.width()) * size_t(r.depth()), 0.0f);
	std::vector<float> best_h(best_w.size(), 0.0f);
	std::vector<float> best_d(best_w.size(), 1e30f);
	std::vector<float> ceiling(best_w.size(), 1e30f);
	for (size_t k = 0; k < n; k++) {
		const RoadSample &a = p_road[k];
		const RoadSample &b = p_road[(k + 1) % n];
		if (a.end) {
			continue;
		}
		// A deck (both ends lifted) only keeps the ground below it; where the road leaves the
		// ground, the bed eases off toward the lifted end and the ground stays under the road.
		bool deck = a.lifted && b.lifted;
		bool to_lifted = a.lifted || b.lifted;
		double flat_max = std::max({ a.flat_l, a.flat_r, b.flat_l, b.flat_r });
		double reach = deck ? flat_max : flat_max + falloff;
		Rect box{ int(std::floor((std::min(a.x, b.x) - reach - ox) / cell)), int(std::floor((std::min(a.z, b.z) - reach - oz) / cell)),
			int(std::ceil((std::max(a.x, b.x) + reach - ox) / cell)) + 1, int(std::ceil((std::max(a.z, b.z) + reach - oz) / cell)) + 1 };
		box = Rect{ std::max(box.x0, r.x0), std::max(box.z0, r.z0), std::min(box.x1, r.x1), std::min(box.z1, r.z1) };
		if (box.empty()) {
			continue;
		}
		double sx = b.x - a.x, sz = b.z - a.z;
		double len2 = std::max(sx * sx + sz * sz, 1e-9);
		// The ceiling reaches a little past each end, so the wedges outside a bend are covered too.
		double over = CEILING_OVER_M / std::sqrt(len2);
		for (int z = box.z0; z < box.z1; z++) {
			for (int x = box.x0; x < box.x1; x++) {
				double px = ox + x * cell, pz = oz + z * cell;
				double t_raw = ((px - a.x) * sx + (pz - a.z) * sz) / len2;
				double t = std::clamp(t_raw, 0.0, 1.0);
				double qx = a.x + sx * t, qz = a.z + sz * t;
				double lx = a.lx + (b.lx - a.lx) * t, lz = a.lz + (b.lz - a.lz) * t, ly = a.ly + (b.ly - a.ly) * t;
				double lxz = std::max(std::hypot(lx, lz), 1e-6);
				double lateral = ((px - qx) * lx + (pz - qz) * lz) / lxz;
				double dist = std::hypot(px - qx, pz - qz);
				double flat = lateral >= 0.0 ? a.flat_l + (b.flat_l - a.flat_l) * t : a.flat_r + (b.flat_r - a.flat_r) * t;
				if (dist >= flat + falloff) {
					continue;
				}
				double bed = a.y + (b.y - a.y) * t + lateral * ly / lxz - p_depth_m;
				double apron = lateral >= 0.0 ? a.apron_l + (b.apron_l - a.apron_l) * t : a.apron_r + (b.apron_r - a.apron_r) * t;
				if (apron > 0.0) {
					// Past the road's edge (across the map), on at the apron's slope.
					double edge = lateral >= 0.0 ? (a.edge_l + (b.edge_l - a.edge_l) * t) * lxz : -(a.edge_r + (b.edge_r - a.edge_r) * t) * lxz;
					if (lateral >= 0.0 ? lateral > edge : lateral < edge) {
						double slope = lateral >= 0.0 ? a.slope_l + (b.slope_l - a.slope_l) * t : a.slope_r + (b.slope_r - a.slope_r) * t;
						bed = a.y + (b.y - a.y) * t + edge * ly / lxz + (lateral - edge) * slope - p_depth_m;
					}
				}
				size_t i = size_t(z - r.z0) * size_t(r.width()) + size_t(x - r.x0);
				if (to_lifted && t_raw >= -over && t_raw <= 1.0 + over && dist <= flat) {
					ceiling[i] = std::min(ceiling[i], float(bed - (deck ? LIFTED_CLEAR_M : 0.0)));
				}
				if (deck) {
					continue;
				}
				double weight = dist <= flat ? 1.0 : 1.0 - smoothstep01((dist - flat) / falloff);
				if (to_lifted) {
					weight *= a.lifted ? t : (1.0 - t); // easing off toward the lifted end, none past it
				}
				// The part of the road that holds the cell most wins; among equals, the nearest
				// (across the flat zone many 2 m segments reach a cell, at their own heights).
				if (weight <= 0.0 || weight < best_w[i] || (weight == best_w[i] && dist >= best_d[i])) {
					continue;
				}
				best_w[i] = float(weight);
				best_d[i] = float(dist);
				best_h[i] = float(bed);
			}
		}
	}
	for (int z = r.z0; z < r.z1; z++) {
		for (int x = r.x0; x < r.x1; x++) {
			size_t i = size_t(z - r.z0) * size_t(r.width()) + size_t(x - r.x0);
			size_t at = size_t(z) * size_t(w) + size_t(x);
			float h = best_w[i] > 0.0f ? base[at] + (best_h[i] - base[at]) * best_w[i] : base[at];
			final_h[at] = std::min(h, ceiling[i]);
		}
	}
	return r;
}

bool Heightfield::raycast(const double p_o[3], const double p_dir[3], double p_max_dist, double r_hit[3]) const {
	if (!valid()) {
		return false;
	}
	double len = std::sqrt(p_dir[0] * p_dir[0] + p_dir[1] * p_dir[1] + p_dir[2] * p_dir[2]);
	if (len < 1e-9) {
		return false;
	}
	double dx = p_dir[0] / len, dy = p_dir[1] / len, dz = p_dir[2] / len;
	double x_end = ox + (w - 1) * cell, z_end = oz + (d - 1) * cell;
	auto inside = [&](double x, double z) { return x >= ox && x <= x_end && z >= oz && z <= z_end; };
	auto above = [&](double t) { return p_o[1] + dy * t - height_at(p_o[0] + dx * t, p_o[2] + dz * t); };
	double step = cell * 0.5;
	double t0 = 0.0;
	double f0 = above(0.0);
	for (double t = step; t <= p_max_dist + step; t += step) {
		double t1 = std::min(t, p_max_dist);
		double x = p_o[0] + dx * t1, z = p_o[2] + dz * t1;
		double f1 = above(t1);
		if (f0 > 0.0 && f1 <= 0.0 && inside(x, z)) {
			double lo = t0, hi = t1;
			for (int i = 0; i < 20; i++) {
				double mid = (lo + hi) * 0.5;
				(above(mid) > 0.0 ? lo : hi) = mid;
			}
			r_hit[0] = p_o[0] + dx * hi;
			r_hit[1] = p_o[1] + dy * hi;
			r_hit[2] = p_o[2] + dz * hi;
			return true;
		}
		t0 = t1;
		f0 = f1;
		if (t1 >= p_max_dist) {
			break;
		}
	}
	return false;
}

std::vector<float> Heightfield::get_region(const Rect &p_rect) const {
	Rect r = p_rect.clipped(w, d);
	std::vector<float> out;
	out.reserve(size_t(r.width()) * size_t(r.depth()));
	for (int z = r.z0; z < r.z1; z++) {
		for (int x = r.x0; x < r.x1; x++) {
			out.push_back(base[size_t(z) * size_t(w) + size_t(x)]);
		}
	}
	return out;
}

void Heightfield::set_region(const Rect &p_rect, const std::vector<float> &p_heights) {
	Rect r = p_rect.clipped(w, d);
	if (r.empty() || p_heights.size() != size_t(r.width()) * size_t(r.depth())) {
		return;
	}
	size_t i = 0;
	for (int z = r.z0; z < r.z1; z++) {
		for (int x = r.x0; x < r.x1; x++) {
			base[size_t(z) * size_t(w) + size_t(x)] = p_heights[i++];
		}
	}
}

std::vector<uint8_t> Heightfield::get_splat_region(const Rect &p_rect) const {
	Rect r = p_rect.clipped(w, d);
	std::vector<uint8_t> out;
	out.reserve(size_t(r.width()) * size_t(r.depth()) * LAYERS);
	for (int z = r.z0; z < r.z1; z++) {
		size_t from = (size_t(z) * size_t(w) + size_t(r.x0)) * LAYERS;
		out.insert(out.end(), splat.begin() + long(from), splat.begin() + long(from + size_t(r.width()) * LAYERS));
	}
	return out;
}

void Heightfield::set_splat_region(const Rect &p_rect, const std::vector<uint8_t> &p_weights) {
	Rect r = p_rect.clipped(w, d);
	if (r.empty() || p_weights.size() != size_t(r.width()) * size_t(r.depth()) * LAYERS) {
		return;
	}
	size_t row_bytes = size_t(r.width()) * LAYERS;
	for (int z = r.z0; z < r.z1; z++) {
		std::copy(p_weights.begin() + long(size_t(z - r.z0) * row_bytes), p_weights.begin() + long(size_t(z - r.z0 + 1) * row_bytes),
				splat.begin() + long((size_t(z) * size_t(w) + size_t(r.x0)) * LAYERS));
	}
}

void Heightfield::chunk_r16(int p_cx, int p_cz, int p_chunk, double p_h_min, double p_h_range, std::vector<uint16_t> &r_out) const {
	int side = p_chunk + 3;
	r_out.resize(size_t(side) * size_t(side));
	int x0 = p_cx * p_chunk - 1, z0 = p_cz * p_chunk - 1;
	double scale = 65535.0 / std::max(p_h_range, 1e-6);
	for (int z = 0; z < side; z++) {
		for (int x = 0; x < side; x++) {
			double v = (_at_clamped(final_h, x0 + x, z0 + z) - p_h_min) * scale;
			r_out[size_t(z) * size_t(side) + size_t(x)] = uint16_t(std::clamp(std::lround(v), 0L, 65535L));
		}
	}
}

void Heightfield::chunk_collision(int p_cx, int p_cz, int p_chunk, std::vector<float> &r_out) const {
	int side = p_chunk + 1;
	r_out.resize(size_t(side) * size_t(side));
	for (int z = 0; z < side; z++) {
		for (int x = 0; x < side; x++) {
			r_out[size_t(z) * size_t(side) + size_t(x)] = _at_clamped(final_h, p_cx * p_chunk + x, p_cz * p_chunk + z);
		}
	}
}

void Heightfield::chunk_splat(int p_cx, int p_cz, int p_chunk, int p_image, std::vector<uint8_t> &r_out) const {
	int side = p_chunk + 1;
	r_out.resize(size_t(side) * size_t(side) * 4);
	int first = std::clamp(p_image, 0, LAYERS / 4 - 1) * 4;
	for (int z = 0; z < side; z++) {
		for (int x = 0; x < side; x++) {
			int sx = std::clamp(p_cx * p_chunk + x, 0, w - 1), sz = std::clamp(p_cz * p_chunk + z, 0, d - 1);
			const uint8_t *wts = &splat[(size_t(sz) * size_t(w) + size_t(sx)) * LAYERS];
			for (int c = 0; c < 4; c++) {
				r_out[(size_t(z) * size_t(side) + size_t(x)) * 4 + size_t(c)] = wts[first + c];
			}
		}
	}
}

void Heightfield::chunk_range(int p_cx, int p_cz, int p_chunk, float &r_lo, float &r_hi) const {
	r_lo = 1e30f;
	r_hi = -1e30f;
	for (int z = 0; z <= p_chunk; z++) {
		for (int x = 0; x <= p_chunk; x++) {
			float h = _at_clamped(final_h, p_cx * p_chunk + x, p_cz * p_chunk + z);
			r_lo = std::min(r_lo, h);
			r_hi = std::max(r_hi, h);
		}
	}
}

std::vector<uint8_t> Heightfield::dominant_layers() const {
	std::vector<uint8_t> out(size_t(w) * size_t(d), 0);
	for (size_t i = 0; i < out.size(); i++) {
		const uint8_t *wts = &splat[i * LAYERS];
		int best = 0;
		for (int l = 1; l < LAYERS; l++) {
			if (wts[l] > wts[best]) {
				best = l;
			}
		}
		out[i] = uint8_t(best);
	}
	return out;
}

} // namespace noss::world
