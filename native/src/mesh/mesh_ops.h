#pragma once

// Mesh operations for LOD generation and model analysis in the Fitting Bay
// (docs/VEHICLE_PACKAGE.md §7). Plain C++ on meshoptimizer, no Godot types.

#include <cstddef>
#include <cstdint>
#include <vector>

namespace noss::mesh {

struct SimplifyOptions {
	float ratio = 0.5f; // target share of the triangles
	float max_error = 0.01f; // absolute (mesh units) if absolute_error, else relative to the mesh's size
	bool absolute_error = true;
	bool sloppy = false; // much coarser, ignores topology (last LOD)
	bool lock_border = true; // keep open edges, so parts that meet don't crack apart
};

// Triangle indices of a simplified mesh using the same vertices. positions: xyz per vertex.
// attributes: attribute_count floats per vertex (normals, UVs), weighed by weights.
std::vector<uint32_t> simplify(const std::vector<uint32_t> &p_indices, const std::vector<float> &p_positions,
		const std::vector<float> &p_attributes, const std::vector<float> &p_weights, const SimplifyOptions &p_options,
		float *r_error = nullptr);

// Drops unused vertices. Rewrites p_indices and returns the remap (old index -> new, or
// UINT32_MAX for dropped ones) plus the new vertex count in r_vertex_count.
std::vector<uint32_t> compact(std::vector<uint32_t> &p_indices, size_t p_vertex_count, size_t &r_vertex_count);

// Connected parts: one label (0..r_count-1) per triangle. Vertices within p_weld of each other
// count as shared, so seams split for normals or UVs don't separate a part.
std::vector<int> components(const std::vector<uint32_t> &p_indices, const std::vector<float> &p_positions, float p_weld, int &r_count);

struct Axes {
	double center[3] = { 0, 0, 0 };
	double axes[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }; // unit vectors, largest variance first
	double variances[3] = { 0, 0, 0 };
};

// Principal axes of a point cloud (xyz triples).
Axes principal_axes(const std::vector<float> &p_points);

} // namespace noss::mesh
