#pragma once

// Terrain for tracks (docs/TRACK_EDITOR.md §2, D91): a grid of height samples `cell` metres
// apart from (ox, oz). `base` is the ground the player shapes; `final_h` is the ground the game
// uses: base with the road's bed cut and filled in (conform), never saved. Eight paint layers as
// weights per sample (0..255, summing to 255). Plain C++, no Godot types.

#include <cstdint>
#include <vector>

namespace noss::world {

constexpr int LAYERS = 8;

// Samples [x0, x1) x [z0, z1).
struct Rect {
	int x0 = 0, z0 = 0, x1 = 0, z1 = 0;
	bool empty() const { return x1 <= x0 || z1 <= z0; }
	int width() const { return x1 - x0; }
	int depth() const { return z1 - z0; }
	Rect merged(const Rect &p_other) const;
	Rect clipped(int p_w, int p_d) const;
};

enum class BrushMode {
	RAISE,
	LOWER,
	SMOOTH,
	FLATTEN,
	NOISE,
};

// One dab of a brush. strength: metres per dab (raise, lower, noise) or 0..1 of the way there
// (smooth, flatten). falloff: the soft outer share of the radius.
struct Brush {
	BrushMode mode = BrushMode::RAISE;
	double x = 0.0, z = 0.0;
	double radius = 10.0;
	double strength = 0.5;
	double falloff = 0.5;
	double target = 0.0; // flatten to this height
	double scale = 0.02; // noise: features per metre
	uint32_t seed = 1;
};

// The road for conform: its centreline samples (in order, closed), each with its left vector
// (banked) and how far the ground is levelled each side (road, curb and run-off).
struct RoadSample {
	double x = 0.0, y = 0.0, z = 0.0;
	double lx = 1.0, ly = 0.0, lz = 0.0;
	double flat_l = 6.0, flat_r = 6.0;
	bool lifted = false; // on supports: the ground is left alone
};

class Heightfield {
public:
	int w = 0;
	int d = 0;
	double cell = 1.0;
	double ox = 0.0;
	double oz = 0.0;
	std::vector<float> base;
	std::vector<float> final_h;
	std::vector<uint8_t> splat; // LAYERS bytes per sample

	void create(int p_w, int p_d, double p_ox, double p_oz, double p_cell, float p_height, int p_layer);
	bool valid() const { return w > 1 && d > 1; }
	// Bilinear, clamped at the edges.
	double height_at(double p_x, double p_z) const;
	double base_at(double p_x, double p_z) const;
	// Samples within p_radius of a point (clipped to the field).
	Rect rect_around(double p_x, double p_z, double p_radius) const;
	// Changes base; returns the samples changed. Call conform on them afterwards.
	Rect brush(const Brush &p_brush);
	Rect paint(int p_layer, double p_x, double p_z, double p_radius, double p_strength, double p_falloff);
	// final = base inside p_rect, then the road's bed: level with the road (p_depth below it) out
	// to each side's flat width, blending back to base over p_falloff_m. Where two parts of the
	// road reach a sample, the one that holds it most wins, then the nearest.
	Rect conform(const Rect &p_rect, const std::vector<RoadSample> &p_road, double p_falloff_m, double p_depth_m);
	// First hit of a ray with the final ground, inside the field.
	bool raycast(const double p_origin[3], const double p_dir[3], double p_max_dist, double r_hit[3]) const;
	std::vector<float> get_region(const Rect &p_rect) const;
	void set_region(const Rect &p_rect, const std::vector<float> &p_heights);
	std::vector<uint8_t> get_splat_region(const Rect &p_rect) const;
	void set_splat_region(const Rect &p_rect, const std::vector<uint8_t> &p_weights);
	// Chunk p_chunk samples on a side at (cx, cz) (chunk cells; it holds chunk + 1 samples).
	// Heights for the GPU: (chunk + 3)² with a one-sample apron, as 0..65535 over h_min..h_min + h_range.
	void chunk_r16(int p_cx, int p_cz, int p_chunk, double p_h_min, double p_h_range, std::vector<uint16_t> &r_out) const;
	// Heights for a HeightMapShape3D: (chunk + 1)², x fastest.
	void chunk_collision(int p_cx, int p_cz, int p_chunk, std::vector<float> &r_out) const;
	// Paint weights for layers 4·image .. 4·image + 3 as RGBA: (chunk + 1)².
	void chunk_splat(int p_cx, int p_cz, int p_chunk, int p_image, std::vector<uint8_t> &r_out) const;
	void chunk_range(int p_cx, int p_cz, int p_chunk, float &r_lo, float &r_hi) const;
	// The heaviest layer at each sample.
	std::vector<uint8_t> dominant_layers() const;

private:
	double _bilinear(const std::vector<float> &p_h, double p_x, double p_z) const;
	float _at_clamped(const std::vector<float> &p_h, int p_x, int p_z) const;
};

// Smooth value noise, about -1..1.
double value_noise(double p_x, double p_z, uint32_t p_seed);

} // namespace noss::world
