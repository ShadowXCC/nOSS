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
	// Hands memory freed on the heap back to the system (glibc's malloc_trim; nothing elsewhere).
	// glibc keeps each thread's peak otherwise: garage traffic loading and letting go of models on
	// worker threads grew a drive by 2 GB (D233).
	static void trim_memory();
	// The graphics card's memory in bytes (0: unknown), asked once and kept (gpu_memory.h). The
	// garage traffic's Auto video memory limit is a share of it (D247).
	static int64_t video_memory_total(const godot::String &p_adapter);
};

} // namespace noss
