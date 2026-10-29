#include "core/noss_core.h"

#include <godot_cpp/core/class_db.hpp>

#include "core/version.h"

#if defined(__GLIBC__)
#include <malloc.h>
#endif

namespace noss {

void NossCore::_bind_methods() {
	godot::ClassDB::bind_static_method("NossCore", godot::D_METHOD("version"), &NossCore::version);
	godot::ClassDB::bind_static_method("NossCore", godot::D_METHOD("trim_memory"), &NossCore::trim_memory);
}

godot::String NossCore::version() {
	return godot::String(noss::to_string(core_version).c_str());
}

void NossCore::trim_memory() {
#if defined(__GLIBC__)
	malloc_trim(0);
#endif
}

} // namespace noss
