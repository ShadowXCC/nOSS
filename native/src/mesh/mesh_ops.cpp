#include "mesh/mesh_ops.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <numeric>
#include <unordered_map>

#include <meshoptimizer.h>

namespace noss::mesh {

std::vector<uint32_t> simplify(const std::vector<uint32_t> &p_indices, const std::vector<float> &p_positions,
		const std::vector<float> &p_attributes, const std::vector<float> &p_weights, const SimplifyOptions &p_options,
		float *r_error) {
	size_t vertex_count = p_positions.size() / 3;
	size_t target = size_t(std::max(1.0f, std::round(float(p_indices.size() / 3) * p_options.ratio))) * 3;
	std::vector<uint32_t> out(p_indices.size());
	float error = 0.0f;
	size_t count;
	if (p_options.sloppy) {
		float max_error = p_options.max_error;
		if (p_options.absolute_error) {
			// Sloppy only takes a relative error: divide by the mesh's extent.
			float extent = meshopt_simplifyScale(p_positions.data(), vertex_count, sizeof(float) * 3);
			max_error = extent > 0.0f ? max_error / extent : max_error;
		}
		count = meshopt_simplifySloppy(out.data(), p_indices.data(), p_indices.size(), p_positions.data(), vertex_count,
				sizeof(float) * 3, nullptr, target, max_error, &error);
	} else {
		unsigned int options = (p_options.lock_border ? meshopt_SimplifyLockBorder : 0) |
				(p_options.absolute_error ? meshopt_SimplifyErrorAbsolute : 0);
		size_t attribute_count = p_weights.size();
		if (attribute_count > 0 && p_attributes.size() == vertex_count * attribute_count) {
			count = meshopt_simplifyWithAttributes(out.data(), p_indices.data(), p_indices.size(), p_positions.data(),
					vertex_count, sizeof(float) * 3, p_attributes.data(), sizeof(float) * attribute_count, p_weights.data(),
					attribute_count, nullptr, target, p_options.max_error, options, &error);
		} else {
			count = meshopt_simplify(out.data(), p_indices.data(), p_indices.size(), p_positions.data(), vertex_count,
					sizeof(float) * 3, target, p_options.max_error, options, &error);
		}
	}
	out.resize(count);
	if (count > 0) {
		meshopt_optimizeVertexCache(out.data(), out.data(), count, vertex_count);
	}
	if (r_error) {
		*r_error = error;
	}
	return out;
}

std::vector<uint32_t> compact(std::vector<uint32_t> &p_indices, size_t p_vertex_count, size_t &r_vertex_count) {
	std::vector<uint32_t> remap(p_vertex_count);
	r_vertex_count = meshopt_optimizeVertexFetchRemap(remap.data(), p_indices.data(), p_indices.size(), p_vertex_count);
	meshopt_remapIndexBuffer(p_indices.data(), p_indices.data(), p_indices.size(), remap.data());
	return remap;
}

namespace {

struct Cell {
	long long x, y, z;
	bool operator==(const Cell &o) const { return x == o.x && y == o.y && z == o.z; }
};

struct CellHash {
	size_t operator()(const Cell &c) const {
		uint64_t h = 1469598103934665603ull;
		for (long long v : { c.x, c.y, c.z }) {
			h = (h ^ uint64_t(v)) * 1099511628211ull;
		}
		return size_t(h);
	}
};

int find_root(std::vector<int> &p_parent, int p_i) {
	while (p_parent[size_t(p_i)] != p_i) {
		p_parent[size_t(p_i)] = p_parent[size_t(p_parent[size_t(p_i)])];
		p_i = p_parent[size_t(p_i)];
	}
	return p_i;
}

} // namespace

std::vector<int> components(const std::vector<uint32_t> &p_indices, const std::vector<float> &p_positions, float p_weld, int &r_count) {
	size_t vertex_count = p_positions.size() / 3;
	// Weld by position on a p_weld grid.
	std::vector<int> welded(vertex_count);
	std::unordered_map<Cell, int, CellHash> cells;
	double inv = p_weld > 0.0f ? 1.0 / p_weld : 1e6;
	for (size_t v = 0; v < vertex_count; v++) {
		Cell key{ std::llround(p_positions[v * 3] * inv), std::llround(p_positions[v * 3 + 1] * inv), std::llround(p_positions[v * 3 + 2] * inv) };
		auto [it, inserted] = cells.try_emplace(key, int(v));
		welded[v] = it->second;
	}
	std::vector<int> parent(vertex_count);
	std::iota(parent.begin(), parent.end(), 0);
	for (size_t t = 0; t + 2 < p_indices.size(); t += 3) {
		int a = find_root(parent, welded[p_indices[t]]);
		for (int k = 1; k < 3; k++) {
			int b = find_root(parent, welded[p_indices[t + size_t(k)]]);
			if (a != b) {
				parent[size_t(b)] = a;
			}
		}
	}
	std::vector<int> labels(p_indices.size() / 3);
	std::unordered_map<int, int> ids;
	for (size_t t = 0; t < labels.size(); t++) {
		int root = find_root(parent, welded[p_indices[t * 3]]);
		auto [it, inserted] = ids.try_emplace(root, int(ids.size()));
		labels[t] = it->second;
	}
	r_count = int(ids.size());
	return labels;
}

Axes principal_axes(const std::vector<float> &p_points) {
	Axes out;
	size_t n = p_points.size() / 3;
	if (n == 0) {
		return out;
	}
	for (size_t i = 0; i < n; i++) {
		for (int k = 0; k < 3; k++) {
			out.center[k] += p_points[i * 3 + size_t(k)] / double(n);
		}
	}
	double c[3][3] = {};
	for (size_t i = 0; i < n; i++) {
		double d[3];
		for (int k = 0; k < 3; k++) {
			d[k] = p_points[i * 3 + size_t(k)] - out.center[k];
		}
		for (int r = 0; r < 3; r++) {
			for (int s = 0; s < 3; s++) {
				c[r][s] += d[r] * d[s] / double(n);
			}
		}
	}
	// Jacobi rotations on the symmetric covariance.
	double v[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
	for (int sweep = 0; sweep < 50; sweep++) {
		double off = std::abs(c[0][1]) + std::abs(c[0][2]) + std::abs(c[1][2]);
		if (off < 1e-14) {
			break;
		}
		for (int p = 0; p < 2; p++) {
			for (int q = p + 1; q < 3; q++) {
				if (std::abs(c[p][q]) < 1e-18) {
					continue;
				}
				double theta = (c[q][q] - c[p][p]) / (2.0 * c[p][q]);
				double t = (theta >= 0 ? 1.0 : -1.0) / (std::abs(theta) + std::sqrt(theta * theta + 1.0));
				double cs = 1.0 / std::sqrt(t * t + 1.0), sn = t * cs;
				for (int k = 0; k < 3; k++) {
					double ckp = c[k][p], ckq = c[k][q];
					c[k][p] = cs * ckp - sn * ckq;
					c[k][q] = sn * ckp + cs * ckq;
				}
				for (int k = 0; k < 3; k++) {
					double cpk = c[p][k], cqk = c[q][k];
					c[p][k] = cs * cpk - sn * cqk;
					c[q][k] = sn * cpk + cs * cqk;
				}
				for (int k = 0; k < 3; k++) {
					double vkp = v[k][p], vkq = v[k][q];
					v[k][p] = cs * vkp - sn * vkq;
					v[k][q] = sn * vkp + cs * vkq;
				}
			}
		}
	}
	int order[3] = { 0, 1, 2 };
	std::sort(order, order + 3, [&](int a, int b) { return c[a][a] > c[b][b]; });
	for (int i = 0; i < 3; i++) {
		out.variances[i] = c[order[i]][order[i]];
		for (int k = 0; k < 3; k++) {
			out.axes[i][k] = v[k][order[i]];
		}
	}
	return out;
}

} // namespace noss::mesh
