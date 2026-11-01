#include "core/noss_core.h"

#include <godot_cpp/core/class_db.hpp>

#include "core/gpu_memory.h"
#include "core/version.h"

#if defined(__GLIBC__)
#include <malloc.h>
#endif

namespace noss {

void NossCore::_bind_methods() {
	godot::ClassDB::bind_static_method("NossCore", godot::D_METHOD("version"), &NossCore::version);
	godot::ClassDB::bind_static_method("NossCore", godot::D_METHOD("trim_memory"), &NossCore::trim_memory);
	godot::ClassDB::bind_static_method("NossCore", godot::D_METHOD("video_memory_total", "adapter"), &NossCore::video_memory_total);
}

godot::String NossCore::version() {
	return godot::String(noss::to_string(core_version).c_str());
}

void NossCore::trim_memory() {
#if defined(__GLIBC__)
	malloc_trim(0);
#endif
}

int64_t NossCore::video_memory_total(const godot::String &p_adapter) {
	static int64_t total = -1;
	if (total < 0) {
		total = static_cast<int64_t>(gpu_memory_bytes(p_adapter.utf8().get_data()));
	}
	return total;
}

} // namespace noss
