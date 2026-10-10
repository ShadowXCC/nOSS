#include "core/noss_core.h"

#include <godot_cpp/core/class_db.hpp>

#include "core/version.h"

namespace noss {

void NossCore::_bind_methods() {
	godot::ClassDB::bind_static_method("NossCore", godot::D_METHOD("version"), &NossCore::version);
}

godot::String NossCore::version() {
	return godot::String(noss::to_string(core_version).c_str());
}

} // namespace noss
