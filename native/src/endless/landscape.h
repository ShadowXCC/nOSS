#pragma once

// The endless world's ground and biomes (docs/GAMEMODES.md §4, D152): the road runs along a
// main direction (the axis) picked from the seed, never turning more than 75 degrees off it, so
// how far along the axis a point is says which biome it's in. Biomes follow each other every 4 to
// 7 km, blending over 1.5 km (their base heights over 5 km). The ground is integer value noise:
// the region's slow rise and fall (kept above the sea, except on the coast) plus each biome's
// relief, the same on every machine. Plain C++, no Godot types.

#include <cstdint>
#include <mutex>
#include <vector>

#include "endless/biomes.h"

namespace noss::endless {

struct BiomeMix {
	uint8_t a = 0; // the biome left behind (or the only one)
	uint8_t b = 0; // the one coming
	uint16_t w = 0; // Q16 weight of b
	uint8_t dominant() const { return w >= 32768 ? b : a; }
};

// Value noise in Q16 (-65536..65536) at a point (mm) on cells of p_cell_mm.
int64_t value_noise_q16(int64_t p_x_mm, int64_t p_z_mm, int64_t p_cell_mm, uint64_t p_seed);

class Landscape {
public:
	static constexpr int64_t BLEND_MM = 750000; // half the width of a biome blend
	static constexpr int64_t BASE_BLEND_MM = 2500000; // half the width of a base height blend
	static constexpr int64_t SEA_MM = 0; // sea level (coast)

	void setup(uint64_t p_seed, int p_start_biome);
	uint64_t seed() const { return _seed; }
	int64_t axis_heading() const { return _axis; } // binary angle
	// How far along the axis a point is, mm.
	int64_t axis_mm(int64_t p_x_mm, int64_t p_z_mm) const;
	// The biomes at a distance along the axis. Safe from any thread.
	BiomeMix biome_at(int64_t p_axis_mm) const;
	// The natural ground's height at a point, mm. Safe from any thread.
	int64_t ground_mm(int64_t p_x_mm, int64_t p_z_mm) const;
	// One biome's relief at a point (no blending), mm.
	int64_t relief_mm(int p_biome, int64_t p_x_mm, int64_t p_z_mm) const;
	// The broad shape at a distance along the axis: base height (mm) and how much of the region's
	// rise and fall counts (per mille), each blended over BASE_BLEND_MM either side of a change, so
	// the ground never climbs or drops faster than the road can follow.
	void broad_at(int64_t p_axis_mm, int64_t &r_base_mm, int64_t &r_regional_pm) const;

private:
	uint64_t _seed = 1;
	int64_t _axis = 0;
	int64_t _ax = 0, _az = 0; // the axis's direction, Q30
	mutable std::mutex _mutex;
	mutable std::vector<int64_t> _ends; // where each biome ends along the axis, mm
	mutable std::vector<uint8_t> _biomes;
	mutable uint64_t _rng_state = 0, _rng_inc = 0;

	void _extend_to(int64_t p_axis_mm) const;
};

} // namespace noss::endless
