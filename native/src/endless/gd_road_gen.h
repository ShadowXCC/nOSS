#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "endless/road_gen.h"

namespace noss {

// The endless road for scripts (road_gen.h, D152). Positions are world metres as 64-bit floats
// at this boundary (the floating origin takes them to the scene); everything is made in integers
// inside. chunk() runs on the main thread; ground_heights() and biome_at() are safe from workers.
class NossRoadGen : public godot::RefCounted {
	GDCLASS(NossRoadGen, godot::RefCounted)

	endless::RoadGen _gen;

protected:
	static void _bind_methods();

public:
	void setup(int64_t p_seed, int64_t p_start_biome);
	int64_t get_seed() const { return int64_t(_gen.seed()); }
	int64_t get_start_biome() const { return _gen.start_biome(); }
	// {first, x, y, z, heading (PackedFloat64Array, m and rad), curvature (1/m, + left), grade,
	// bank (deg, + = left edge lower), lane (m), ground, ground_l, ground_r (m), lifted,
	// barrier_l, barrier_r, biome, biome2 (PackedByteArray), blend, speed_up, speed_down (m/s),
	// time_up, time_down (PackedFloat64Array, s), checksum}. CHUNK + 1 samples; {} for k < 0.
	godot::Dictionary chunk(int64_t p_k);
	// Natural ground (m) on a w x d grid from (x0, z0), cell metres apart, row by row in z.
	godot::PackedFloat32Array ground_heights(double p_x0, double p_z0, int64_t p_w, int64_t p_d, double p_cell) const;
	double ground_at(double p_x, double p_z) const;
	// Paint for a tile of ground (TerrainData.LAYERS: grass, dirt, sand, gravel, rock, snow, concrete,
	// asphalt), 8 weights a sample summing to 255, from each sample's biome, height and slope;
	// `p_heights` is the tile's (w x d, row by row in z). For looks only (not part of the road).
	godot::PackedByteArray tile_paint(double p_x0, double p_z0, int64_t p_w, int64_t p_d, double p_cell, const godot::PackedFloat32Array &p_heights) const;
	// (biome, the next one, its weight 0..1) at a world point.
	godot::Vector3 biome_at(double p_x, double p_z) const;
	// The road's main direction (radians, 0 = +Z, + = toward +X).
	double axis_heading() const;
	// Chained checksum of chunks 0 .. p_chunks - 1 from a fresh generator with this seed (the
	// determinism check, --endless-selftest).
	int64_t checksum(int64_t p_chunks) const;
	static godot::PackedStringArray biome_ids();
	static int64_t chunk_samples() { return endless::CHUNK; }
};

} // namespace noss
