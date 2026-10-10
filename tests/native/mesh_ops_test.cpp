#include <doctest/doctest.h>

#include <cmath>

#include "mesh/mesh_ops.h"

using namespace noss::mesh;

namespace {

constexpr double PI_D = 3.14159265358979323846;

// UV sphere: (rings + 1) x (segments + 1) vertices.
void sphere(int p_rings, int p_segments, std::vector<float> &r_positions, std::vector<uint32_t> &r_indices) {
	for (int r = 0; r <= p_rings; r++) {
		double phi = PI_D * r / p_rings;
		for (int s = 0; s <= p_segments; s++) {
			double theta = 2.0 * PI_D * s / p_segments;
			r_positions.insert(r_positions.end(), { float(std::sin(phi) * std::cos(theta)), float(std::cos(phi)), float(std::sin(phi) * std::sin(theta)) });
		}
	}
	for (int r = 0; r < p_rings; r++) {
		for (int s = 0; s < p_segments; s++) {
			uint32_t a = uint32_t(r * (p_segments + 1) + s), b = a + uint32_t(p_segments + 1);
			r_indices.insert(r_indices.end(), { a, b, a + 1, a + 1, b, b + 1 });
		}
	}
}

void cube(float p_x, std::vector<float> &r_positions, std::vector<uint32_t> &r_indices) {
	uint32_t base = uint32_t(r_positions.size() / 3);
	for (int i = 0; i < 8; i++) {
		r_positions.insert(r_positions.end(), { p_x + float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1) });
	}
	const uint32_t faces[6][4] = { { 0, 2, 3, 1 }, { 4, 5, 7, 6 }, { 0, 1, 5, 4 }, { 2, 6, 7, 3 }, { 0, 4, 6, 2 }, { 1, 3, 7, 5 } };
	for (const auto &f : faces) {
		r_indices.insert(r_indices.end(), { base + f[0], base + f[1], base + f[2], base + f[0], base + f[2], base + f[3] });
	}
}

} // namespace

TEST_CASE("mesh: simplify keeps the shape at a quarter of the triangles") {
	std::vector<float> positions;
	std::vector<uint32_t> indices;
	sphere(32, 64, positions, indices);
	SimplifyOptions o;
	o.ratio = 0.25f;
	o.max_error = 0.05f;
	float error = 0.0f;
	std::vector<uint32_t> out = simplify(indices, positions, {}, {}, o, &error);
	CHECK(out.size() % 3 == 0);
	CHECK(out.size() < indices.size() / 3);
	CHECK(out.size() > indices.size() / 8);
	CHECK(error <= 0.05f);
	size_t vertices = 0;
	compact(out, positions.size() / 3, vertices);
	CHECK(vertices < positions.size() / 3);
	for (uint32_t i : out) {
		CHECK(i < vertices);
	}
	o.sloppy = true; // the last LOD: coarse, with a looser error
	o.ratio = 0.04f;
	o.max_error = 0.5f;
	CHECK(simplify(indices, positions, {}, {}, o).size() <= indices.size() / 10);
}

TEST_CASE("mesh: separate parts are told apart") {
	std::vector<float> positions;
	std::vector<uint32_t> indices;
	cube(0.0f, positions, indices);
	cube(3.0f, positions, indices);
	int count = 0;
	std::vector<int> labels = components(indices, positions, 1e-4f, count);
	CHECK(count == 2);
	CHECK(labels.front() != labels.back());
	// A seam (duplicate vertices at the same spot) doesn't split a part.
	positions.insert(positions.end(), { 1.0f, 1.0f, 1.0f });
	indices.insert(indices.end(), { 0, 1, uint32_t(positions.size() / 3 - 1) });
	components(indices, positions, 1e-4f, count);
	CHECK(count == 2);
}

TEST_CASE("mesh: principal axes of a disc") {
	std::vector<float> points;
	for (int i = 0; i < 200; i++) {
		double a = 2.0 * PI_D * i / 200.0;
		// A wheel: a disc in the y-z plane, axle along x.
		points.insert(points.end(), { float(0.05 * ((i % 2) * 2 - 1)), float(0.3 * std::cos(a)), float(0.3 * std::sin(a)) });
	}
	Axes a = principal_axes(points);
	CHECK(std::abs(a.axes[2][0]) == doctest::Approx(1.0).epsilon(1e-6));
	CHECK(a.variances[0] == doctest::Approx(a.variances[1]).epsilon(0.01));
	CHECK(a.variances[2] < 0.1 * a.variances[1]);
}
