#pragma once

// Reads and checks a zip's central directory before anything is decompressed
// (docs/VEHICLE_PACKAGE.md §9). Plain C++, no Godot types.

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace noss::package {

struct ZipLimits {
	uint64_t max_zip_bytes = 50ull << 20;
	uint64_t max_total_bytes = 150ull << 20;
	uint32_t max_entries = 512;
	// Zip-bomb guard: uncompressed / compressed, checked for entries over ratio_min_bytes.
	double max_ratio = 100.0;
	uint64_t ratio_min_bytes = 1ull << 20;
};

// Tracks (.nosstrack) may be larger than cars (docs/TRACK_EDITOR.md §5): their ceiling.
inline ZipLimits track_zip_ceiling() {
	ZipLimits l;
	l.max_zip_bytes = 100ull << 20;
	l.max_total_bytes = 250ull << 20;
	return l;
}

struct ZipEntry {
	std::string name;
	uint16_t method = 0; // 0 stored, 8 deflate
	uint32_t crc32 = 0;
	uint64_t compressed = 0;
	uint64_t size = 0;
	uint64_t data_offset = 0;
};

struct ZipIndex {
	bool ok = false;
	std::string error;
	std::vector<ZipEntry> entries; // files only; directory entries are skipped
	uint64_t total_size = 0;
};

ZipIndex read_zip_index(const uint8_t *p_data, size_t p_length, const ZipLimits &p_limits = {});

// Relative path with only [A-Za-z0-9_.-] segments, no hidden or '..' segments, and an allowed
// file type (.json .glb .gltf .png .jpg .ogg .wav). Sets r_reason when it returns false.
bool is_safe_entry_name(const std::string &p_name, std::string *r_reason = nullptr);

} // namespace noss::package
