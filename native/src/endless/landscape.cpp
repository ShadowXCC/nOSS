#include "endless/landscape.h"

#include <algorithm>
#include <cstdint>

#include "endless/fixed_math.h"

namespace noss::endless {

namespace {

constexpr int64_t BIOME_MIN_MM = 4000000; // a biome lasts 4 to 7 km along the axis
constexpr int64_t BIOME_MAX_MM = 7000000;
// The region's rise and fall, shared by every biome that counts it: two octaves, and a lift so
// most of it is well above the sea.
constexpr int64_t REGION_CELL_MM[2] = { 6000000, 2600000 };
constexpr int64_t REGION_AMP_MM[2] = { 120000, 50000 };
constexpr int64_t REGION_LIFT_MM = 100000;
constexpr int64_t REGION_FLOOR_MM = 40000;
// Small bumps everywhere.
constexpr int64_t DETAIL_CELL_MM = 40000;
constexpr int64_t DETAIL_AMP_MM = 1200;

int64_t lattice_q16(int64_t p_ix, int64_t p_iz, uint64_t p_seed) {
	uint64_t h = mix64(p_seed ^ mix64(uint64_t(p_ix) * 0x9E3779B97F4A7C15ULL ^ uint64_t(p_iz) * 0xC2B2AE3D27D4EB4FULL));
	return int64_t(h >> 47) - 65536; // 17 bits
}

int64_t lerp_q16(int64_t p_a, int64_t p_b, int64_t p_t) {
	return p_a + (p_b - p_a) * p_t / 65536;
}

// Three octaves of value noise (or ridged noise) scaled to p_amp_mm.
int64_t noise_relief_mm(int64_t p_x, int64_t p_z, int64_t p_cell_mm, int64_t p_amp_mm, bool p_ridged, uint64_t p_seed) {
	int64_t sum = 0;
	int64_t cell = p_cell_mm, weight = 4;
	for (int octave = 0; octave < 3; octave++) {
		int64_t n = value_noise_q16(p_x, p_z, cell, p_seed + uint64_t(octave) * 0x51ED27ULL);
		if (p_ridged) {
			n = 65536 - 2 * (n < 0 ? -n : n); // sharp crests, wide valleys
		}
		sum += n * weight;
		cell /= 2;
		weight /= 2;
	}
	return sum * p_amp_mm / (7 * 65536); // weights 4 + 2 + 1
}

} // namespace

int64_t value_noise_q16(int64_t p_x_mm, int64_t p_z_mm, int64_t p_cell_mm, uint64_t p_seed) {
	int64_t ix = floor_div(p_x_mm, p_cell_mm), iz = floor_div(p_z_mm, p_cell_mm);
	int64_t fx = smooth_q16(((p_x_mm - ix * p_cell_mm) << 16) / p_cell_mm);
	int64_t fz = smooth_q16(((p_z_mm - iz * p_cell_mm) << 16) / p_cell_mm);
	int64_t a = lattice_q16(ix, iz, p_seed), b = lattice_q16(ix + 1, iz, p_seed);
	int64_t c = lattice_q16(ix, iz + 1, p_seed), d = lattice_q16(ix + 1, iz + 1, p_seed);
	return lerp_q16(lerp_q16(a, b, fx), lerp_q16(c, d, fx), fz);
}

void Landscape::setup(uint64_t p_seed, int p_start_biome) {
	std::lock_guard<std::mutex> lock(_mutex);
	_seed = p_seed;
	Pcg32 rng(p_seed, 0xA515);
	_axis = int64_t(rng.next()); // any direction
	_ax = sin_q30(_axis);
	_az = cos_q30(_axis);
	Pcg32 biomes(p_seed, 0xB10E);
	_rng_state = biomes.state;
	_rng_inc = biomes.inc;
	_ends.clear();
	_biomes.clear();
	_biomes.push_back(uint8_t(std::clamp(p_start_biome, 0, int(BIOME_COUNT) - 1)));
	_ends.push_back(BIOME_MIN_MM + int64_t(biomes.below(uint32_t(BIOME_MAX_MM - BIOME_MIN_MM))));
	_rng_state = biomes.state;
}

int64_t Landscape::axis_mm(int64_t p_x_mm, int64_t p_z_mm) const {
	return mul_q30(p_x_mm, _ax) + mul_q30(p_z_mm, _az);
}

void Landscape::_extend_to(int64_t p_axis_mm) const {
	Pcg32 rng;
	rng.state = _rng_state;
	rng.inc = _rng_inc;
	while (_ends.back() < p_axis_mm + 2 * BLEND_MM) {
		const BiomeStyle &last = biome_style(_biomes.back());
		int options = 0;
		while (options < 3 && last.next[options] >= 0) {
			options++;
		}
		_biomes.push_back(uint8_t(last.next[rng.below(uint32_t(options))]));
		_ends.push_back(_ends.back() + BIOME_MIN_MM + int64_t(rng.below(uint32_t(BIOME_MAX_MM - BIOME_MIN_MM))));
	}
	_rng_state = rng.state;
}

BiomeMix Landscape::biome_at(int64_t p_axis_mm) const {
	std::lock_guard<std::mutex> lock(_mutex);
	_extend_to(p_axis_mm);
	// The first biome reaches back behind the start.
	size_t k = size_t(std::upper_bound(_ends.begin(), _ends.end(), p_axis_mm) - _ends.begin());
	BiomeMix m;
	m.a = m.b = _biomes[k];
	if (p_axis_mm > _ends[k] - BLEND_MM) { // into the next one
		m.b = _biomes[k + 1];
		m.w = uint16_t(std::min<int64_t>(smooth_q16((p_axis_mm - (_ends[k] - BLEND_MM)) * 65536 / (2 * BLEND_MM)), 65535));
	} else if (k > 0 && p_axis_mm < _ends[k - 1] + BLEND_MM) { // still leaving the last one
		m.a = _biomes[k - 1];
		m.w = uint16_t(std::min<int64_t>(smooth_q16((p_axis_mm - (_ends[k - 1] - BLEND_MM)) * 65536 / (2 * BLEND_MM)), 65535));
	}
	return m;
}

int64_t Landscape::relief_mm(int p_biome, int64_t p_x_mm, int64_t p_z_mm) const {
	const BiomeStyle &s = biome_style(p_biome);
	return noise_relief_mm(p_x_mm, p_z_mm, int64_t(s.relief_cell_m) * 1000, s.relief_mm, s.ridged, _seed ^ (0xB1000ULL + uint64_t(p_biome) * 0x1F1F));
}

void Landscape::broad_at(int64_t p_axis_mm, int64_t &r_base_mm, int64_t &r_regional_pm) const {
	std::lock_guard<std::mutex> lock(_mutex);
	_extend_to(p_axis_mm + BASE_BLEND_MM);
	// Each biome's share: in from its start and out at its end, smoothly over 2 * BASE_BLEND_MM;
	// the shares add up to 1 everywhere.
	int64_t base = 0, regional = 0;
	size_t k = size_t(std::upper_bound(_ends.begin(), _ends.end(), p_axis_mm - BASE_BLEND_MM) - _ends.begin());
	for (; k < _ends.size(); k++) {
		int64_t start = k == 0 ? INT64_MIN / 4 : _ends[k - 1];
		if (start > p_axis_mm + BASE_BLEND_MM) {
			break;
		}
		auto rise = [&](int64_t p_edge) {
			return std::clamp<int64_t>(smooth_q16(std::clamp<int64_t>((p_axis_mm - p_edge + BASE_BLEND_MM) * 65536 / (2 * BASE_BLEND_MM), 0, 65536)), 0, 65536);
		};
		int64_t share = (k == 0 ? 65536 : rise(start)) - rise(_ends[k]);
		const BiomeStyle &s = biome_style(_biomes[k]);
		base += int64_t(s.base_mm) * share;
		regional += int64_t(s.regional_pm) * share;
	}
	r_base_mm = base / 65536;
	r_regional_pm = regional / 65536;
}

int64_t Landscape::ground_mm(int64_t p_x_mm, int64_t p_z_mm) const {
	int64_t axis = axis_mm(p_x_mm, p_z_mm);
	int64_t base, regional_pm;
	broad_at(axis, base, regional_pm);
	int64_t region = REGION_LIFT_MM;
	for (int i = 0; i < 2; i++) {
		region += value_noise_q16(p_x_mm, p_z_mm, REGION_CELL_MM[i], _seed ^ (0x7E610ULL + uint64_t(i))) * REGION_AMP_MM[i] / 65536;
	}
	if (region < REGION_FLOOR_MM) { // low ground flattens out above the sea
		region = REGION_FLOOR_MM - (REGION_FLOOR_MM - region) / 4;
	}
	int64_t h = base + REGION_LIFT_MM + (region - REGION_LIFT_MM) * regional_pm / 1000;
	BiomeMix m = biome_at(axis);
	int64_t relief = relief_mm(m.a, p_x_mm, p_z_mm);
	if (m.b != m.a && m.w > 0) {
		relief += (relief_mm(m.b, p_x_mm, p_z_mm) - relief) * int64_t(m.w) / 65536;
	}
	return h + relief + value_noise_q16(p_x_mm, p_z_mm, DETAIL_CELL_MM, _seed ^ 0xDE7A11ULL) * DETAIL_AMP_MM / 65536;
}

} // namespace noss::endless
