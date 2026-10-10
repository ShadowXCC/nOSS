#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace noss {

// Script access to the package checks, e.g. NossPackage.inspect_zip(bytes).
class NossPackage : public godot::Object {
	GDCLASS(NossPackage, godot::Object)

protected:
	static void _bind_methods();

public:
	// {ok, error, total_size, entries: [{name, size, compressed}]}. Optional limits:
	// max_zip_bytes, max_total_bytes, max_entries (servers can only lower them).
	static godot::Dictionary inspect_zip(const godot::PackedByteArray &p_bytes, const godot::Dictionary &p_limits);
	// {ok, error, json (String), bin_offset, bin_length}
	static godot::Dictionary inspect_glb(const godot::PackedByteArray &p_bytes);
	// Width and height of a PNG or JPEG, or (0, 0).
	static godot::Vector2i image_size(const godot::PackedByteArray &p_bytes);
	static bool is_safe_path(const godot::String &p_path);
};

} // namespace noss
