#include "mesh/gd_mesh.h"

#include <cstdint>

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "mesh/mesh_ops.h"

using namespace godot;

namespace noss {

namespace {

constexpr uint32_t DROPPED = UINT32_MAX;

// Copies the kept vertices' elements (p_stride per vertex) to their new places.
template <typename T>
T remap_array(const T &p_source, size_t p_vertex_count, const std::vector<uint32_t> &p_remap, size_t p_new_count) {
	T out;
	size_t stride = p_vertex_count > 0 ? size_t(p_source.size()) / p_vertex_count : 0;
	if (stride == 0 || size_t(p_source.size()) != stride * p_vertex_count) {
		return p_source; // not per-vertex data
	}
	out.resize(int64_t(p_new_count * stride));
	for (size_t v = 0; v < p_vertex_count; v++) {
		if (p_remap[v] == DROPPED) {
			continue;
		}
		for (size_t k = 0; k < stride; k++) {
			out.set(int64_t(p_remap[v] * stride + k), p_source[int64_t(v * stride + k)]);
		}
	}
	return out;
}

std::vector<float> positions_of(const PackedVector3Array &p_points) {
	std::vector<float> out(size_t(p_points.size()) * 3);
	for (int64_t i = 0; i < p_points.size(); i++) {
		out[size_t(i) * 3] = p_points[i].x;
		out[size_t(i) * 3 + 1] = p_points[i].y;
		out[size_t(i) * 3 + 2] = p_points[i].z;
	}
	return out;
}

} // namespace

void NossMesh::_bind_methods() {
	ClassDB::bind_static_method("NossMesh", D_METHOD("simplify_surface", "arrays", "ratio", "max_error", "sloppy"), &NossMesh::simplify_surface);
	ClassDB::bind_static_method("NossMesh", D_METHOD("components", "indices", "positions", "weld"), &NossMesh::components);
	ClassDB::bind_static_method("NossMesh", D_METHOD("principal_axes", "points"), &NossMesh::principal_axes);
}

Array NossMesh::simplify_surface(const Array &p_arrays, double p_ratio, double p_max_error, bool p_sloppy) {
	if (p_arrays.size() < Mesh::ARRAY_MAX || p_arrays[Mesh::ARRAY_VERTEX].get_type() != Variant::PACKED_VECTOR3_ARRAY) {
		return Array();
	}
	PackedVector3Array vertices = p_arrays[Mesh::ARRAY_VERTEX];
	size_t vertex_count = size_t(vertices.size());
	std::vector<float> positions = positions_of(vertices);

	std::vector<uint32_t> indices;
	if (p_arrays[Mesh::ARRAY_INDEX].get_type() == Variant::PACKED_INT32_ARRAY && PackedInt32Array(p_arrays[Mesh::ARRAY_INDEX]).size() > 0) {
		PackedInt32Array source = p_arrays[Mesh::ARRAY_INDEX];
		indices.resize(size_t(source.size()));
		for (int64_t i = 0; i < source.size(); i++) {
			indices[size_t(i)] = uint32_t(source[i]);
		}
	} else {
		indices.resize(vertex_count);
		for (size_t i = 0; i < vertex_count; i++) {
			indices[i] = uint32_t(i);
		}
	}

	// Normals and UVs weigh in, so shading and textures stay put.
	std::vector<float> attributes, weights;
	PackedVector3Array normals = p_arrays[Mesh::ARRAY_NORMAL].get_type() == Variant::PACKED_VECTOR3_ARRAY ? PackedVector3Array(p_arrays[Mesh::ARRAY_NORMAL]) : PackedVector3Array();
	PackedVector2Array uvs = p_arrays[Mesh::ARRAY_TEX_UV].get_type() == Variant::PACKED_VECTOR2_ARRAY ? PackedVector2Array(p_arrays[Mesh::ARRAY_TEX_UV]) : PackedVector2Array();
	bool use_normals = size_t(normals.size()) == vertex_count, use_uvs = size_t(uvs.size()) == vertex_count;
	if (use_normals) {
		weights.insert(weights.end(), { 0.5f, 0.5f, 0.5f });
	}
	if (use_uvs) {
		weights.insert(weights.end(), { 0.5f, 0.5f });
	}
	if (!weights.empty()) {
		attributes.reserve(vertex_count * weights.size());
		for (size_t v = 0; v < vertex_count; v++) {
			if (use_normals) {
				attributes.insert(attributes.end(), { normals[int64_t(v)].x, normals[int64_t(v)].y, normals[int64_t(v)].z });
			}
			if (use_uvs) {
				attributes.insert(attributes.end(), { uvs[int64_t(v)].x, uvs[int64_t(v)].y });
			}
		}
	}

	mesh::SimplifyOptions options;
	options.ratio = float(p_ratio);
	options.max_error = float(p_max_error);
	options.sloppy = p_sloppy;
	std::vector<uint32_t> simplified = mesh::simplify(indices, positions, attributes, weights, options);
	size_t new_count = 0;
	std::vector<uint32_t> remap = mesh::compact(simplified, vertex_count, new_count);

	Array out;
	out.resize(Mesh::ARRAY_MAX);
	for (int a = 0; a < Mesh::ARRAY_MAX; a++) {
		Variant v = p_arrays[a];
		if (a == Mesh::ARRAY_INDEX) {
			PackedInt32Array index;
			index.resize(int64_t(simplified.size()));
			for (size_t i = 0; i < simplified.size(); i++) {
				index.set(int64_t(i), int32_t(simplified[i]));
			}
			out[a] = index;
			continue;
		}
		switch (v.get_type()) {
			case Variant::PACKED_VECTOR3_ARRAY:
				out[a] = remap_array(PackedVector3Array(v), vertex_count, remap, new_count);
				break;
			case Variant::PACKED_VECTOR2_ARRAY:
				out[a] = remap_array(PackedVector2Array(v), vertex_count, remap, new_count);
				break;
			case Variant::PACKED_COLOR_ARRAY:
				out[a] = remap_array(PackedColorArray(v), vertex_count, remap, new_count);
				break;
			case Variant::PACKED_FLOAT32_ARRAY:
				out[a] = remap_array(PackedFloat32Array(v), vertex_count, remap, new_count);
				break;
			case Variant::PACKED_INT32_ARRAY:
				out[a] = remap_array(PackedInt32Array(v), vertex_count, remap, new_count);
				break;
			case Variant::PACKED_BYTE_ARRAY:
				out[a] = remap_array(PackedByteArray(v), vertex_count, remap, new_count);
				break;
			default:
				out[a] = v;
		}
	}
	return out;
}

PackedInt32Array NossMesh::components(const PackedInt32Array &p_indices, const PackedVector3Array &p_positions, double p_weld) {
	std::vector<uint32_t> indices(size_t(p_indices.size()));
	for (int64_t i = 0; i < p_indices.size(); i++) {
		indices[size_t(i)] = uint32_t(p_indices[i]);
	}
	int count = 0;
	std::vector<int> labels = mesh::components(indices, positions_of(p_positions), float(p_weld), count);
	PackedInt32Array out;
	out.resize(int64_t(labels.size()));
	for (size_t i = 0; i < labels.size(); i++) {
		out.set(int64_t(i), labels[i]);
	}
	return out;
}

Dictionary NossMesh::principal_axes(const PackedVector3Array &p_points) {
	mesh::Axes a = mesh::principal_axes(positions_of(p_points));
	Dictionary d;
	d["center"] = Vector3(real_t(a.center[0]), real_t(a.center[1]), real_t(a.center[2]));
	Array axes, variances;
	for (int i = 0; i < 3; i++) {
		axes.push_back(Vector3(real_t(a.axes[i][0]), real_t(a.axes[i][1]), real_t(a.axes[i][2])));
		variances.push_back(a.variances[i]);
	}
	d["axes"] = axes;
	d["variances"] = variances;
	return d;
}

} // namespace noss
