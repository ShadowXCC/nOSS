#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/string.hpp>

namespace noss {

// Script entry point to the native core. Static methods only, e.g. NossCore.version().
class NossCore : public godot::Object {
	GDCLASS(NossCore, godot::Object)

protected:
	static void _bind_methods();

public:
	static godot::String version();
};

} // namespace noss
