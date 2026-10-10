#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace noss {

// Script access to the mesh operations (mesh_ops.h), e.g. NossMesh.simplify_surface().
class NossMesh : public godot::Object {
	GDCLASS(NossMesh, godot::Object)

protected:
	static void _bind_methods();

public:
	// A Mesh surface array (Mesh.ARRAY_*) simplified to about p_ratio of its triangles, with
	// p_max_error in mesh units. Unused vertices are dropped from every array.
	static godot::Array simplify_surface(const godot::Array &p_arrays, double p_ratio, double p_max_error, bool p_sloppy);
	// The surface with only the triangles whose p_keep entry is non-zero, unused vertices dropped.
	static godot::Array extract_surface(const godot::Array &p_arrays, const godot::PackedByteArray &p_keep);
	// One connected-part label per triangle; vertices within p_weld count as shared.
	static godot::PackedInt32Array components(const godot::PackedInt32Array &p_indices, const godot::PackedVector3Array &p_positions, double p_weld);
	// {center: Vector3, axes: [Vector3 x3, largest variance first], variances: [float x3]}
	static godot::Dictionary principal_axes(const godot::PackedVector3Array &p_points);
};

} // namespace noss
