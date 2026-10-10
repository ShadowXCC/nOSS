#pragma once

// Container checks that run before Godot parses a model or image (docs/VEHICLE_PACKAGE.md §9).
// Plain C++, no Godot types.

#include <cstddef>
#include <cstdint>
#include <string>

namespace noss::package {

struct GlbInfo {
	bool ok = false;
	std::string error;
	size_t json_offset = 0;
	size_t json_length = 0;
	size_t bin_offset = 0; // 0 when there is no BIN chunk
	size_t bin_length = 0;
};

// Checks the GLB header and chunk table. The JSON chunk is limited to p_max_json bytes.
GlbInfo inspect_glb(const uint8_t *p_data, size_t p_length, size_t p_max_json = 64u << 20);

struct ImageInfo {
	bool ok = false;
	const char *format = "";
	uint32_t width = 0;
	uint32_t height = 0;
};

// Reads the dimensions of a PNG or JPEG from its header without decoding it.
ImageInfo inspect_image(const uint8_t *p_data, size_t p_length);

} // namespace noss::package
