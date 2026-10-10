#include "package/zip_index.h"

#include <algorithm>
#include <array>
#include <set>
#include <string_view>

namespace noss::package {

namespace {

constexpr uint32_t SIG_EOCD = 0x06054b50;
constexpr uint32_t SIG_CENTRAL = 0x02014b50;
constexpr uint32_t SIG_LOCAL = 0x04034b50;
constexpr size_t EOCD_SIZE = 22;
constexpr size_t CENTRAL_SIZE = 46;
constexpr size_t LOCAL_SIZE = 30;
constexpr size_t MAX_NAME = 200;
constexpr uint16_t FLAG_ENCRYPTED = 0x0001;
constexpr uint16_t FLAG_STRONG_ENCRYPTION = 0x0040;
constexpr uint8_t HOST_UNIX = 3;
constexpr uint32_t UNIX_TYPE_MASK = 0170000;
constexpr uint32_t UNIX_SYMLINK = 0120000;

constexpr std::array<std::string_view, 7> ALLOWED_TYPES = { ".json", ".glb", ".gltf", ".png", ".jpg", ".ogg", ".wav" };

uint16_t u16(const uint8_t *p) {
	return uint16_t(p[0] | (p[1] << 8));
}

uint32_t u32(const uint8_t *p) {
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

ZipIndex fail(std::string p_error) {
	ZipIndex index;
	index.error = std::move(p_error);
	return index;
}

bool segment_ok(std::string_view p_segment) {
	if (p_segment.empty() || p_segment[0] == '.') {
		return false;
	}
	return std::all_of(p_segment.begin(), p_segment.end(), [](char c) {
		return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.';
	});
}

} // namespace

bool is_safe_entry_name(const std::string &p_name, std::string *r_reason) {
	auto reject = [&](const char *p_why) {
		if (r_reason) {
			*r_reason = p_why;
		}
		return false;
	};
	if (p_name.empty() || p_name.size() > MAX_NAME) {
		return reject("bad name length");
	}
	std::string_view rest(p_name);
	while (true) {
		size_t slash = rest.find('/');
		std::string_view segment = rest.substr(0, slash);
		if (!segment_ok(segment) || segment == "..") {
			return reject("bad path segment");
		}
		if (slash == std::string_view::npos) {
			break;
		}
		rest.remove_prefix(slash + 1);
	}
	for (std::string_view type : ALLOWED_TYPES) {
		if (p_name.size() > type.size() && p_name.compare(p_name.size() - type.size(), type.size(), type) == 0) {
			return true;
		}
	}
	return reject("file type not allowed");
}

ZipIndex read_zip_index(const uint8_t *p_data, size_t p_length, const ZipLimits &p_limits) {
	if (p_length > p_limits.max_zip_bytes) {
		return fail("package too large");
	}
	if (p_length < EOCD_SIZE) {
		return fail("not a zip");
	}

	// End of central directory: the last 22 bytes plus an optional comment of up to 64 KB.
	size_t eocd = SIZE_MAX;
	size_t lowest = p_length > EOCD_SIZE + 0xFFFF ? p_length - EOCD_SIZE - 0xFFFF : 0;
	for (size_t i = p_length - EOCD_SIZE + 1; i-- > lowest;) {
		if (u32(p_data + i) == SIG_EOCD && i + EOCD_SIZE + u16(p_data + i + 20) == p_length) {
			eocd = i;
			break;
		}
	}
	if (eocd == SIZE_MAX) {
		return fail("not a zip");
	}
	const uint8_t *e = p_data + eocd;
	uint16_t disk = u16(e + 4), cd_disk = u16(e + 6), disk_entries = u16(e + 8), total_entries = u16(e + 10);
	uint32_t cd_size = u32(e + 12), cd_offset = u32(e + 16);
	if (disk_entries == 0xFFFF || total_entries == 0xFFFF || cd_size == 0xFFFFFFFF || cd_offset == 0xFFFFFFFF) {
		return fail("zip64 not supported");
	}
	if (disk != 0 || cd_disk != 0 || disk_entries != total_entries) {
		return fail("multi-part zip");
	}
	if (total_entries > p_limits.max_entries) {
		return fail("too many files");
	}
	if (uint64_t(cd_offset) + cd_size > eocd) {
		return fail("corrupt zip directory");
	}

	ZipIndex index;
	std::set<std::string> names;
	std::vector<std::pair<uint64_t, uint64_t>> ranges; // [start, end) of each local record
	size_t pos = cd_offset;
	for (uint16_t i = 0; i < total_entries; i++) {
		if (pos + CENTRAL_SIZE > uint64_t(cd_offset) + cd_size || u32(p_data + pos) != SIG_CENTRAL) {
			return fail("corrupt zip directory");
		}
		const uint8_t *c = p_data + pos;
		uint8_t host = c[5];
		uint16_t flags = u16(c + 8), method = u16(c + 10);
		uint32_t crc = u32(c + 16), compressed = u32(c + 20), size = u32(c + 24);
		uint16_t name_len = u16(c + 28), extra_len = u16(c + 30), comment_len = u16(c + 32);
		uint32_t external = u32(c + 38), local = u32(c + 42);
		size_t next = pos + CENTRAL_SIZE + name_len + extra_len + comment_len;
		if (next > uint64_t(cd_offset) + cd_size) {
			return fail("corrupt zip directory");
		}
		std::string name(reinterpret_cast<const char *>(c + CENTRAL_SIZE), name_len);
		pos = next;

		if (compressed == 0xFFFFFFFF || size == 0xFFFFFFFF || local == 0xFFFFFFFF) {
			return fail("zip64 not supported");
		}
		if (flags & (FLAG_ENCRYPTED | FLAG_STRONG_ENCRYPTION)) {
			return fail("encrypted file: " + name);
		}
		if (host == HOST_UNIX && ((external >> 16) & UNIX_TYPE_MASK) == UNIX_SYMLINK) {
			return fail("symlink: " + name);
		}
		if (!name.empty() && name.back() == '/') {
			if (size != 0) {
				return fail("bad directory entry: " + name);
			}
			continue; // directory
		}
		std::string reason;
		if (!is_safe_entry_name(name, &reason)) {
			return fail(reason + ": " + name);
		}
		if (!names.insert(name).second) {
			return fail("duplicate file: " + name);
		}
		if (method != 0 && method != 8) {
			return fail("unsupported compression: " + name);
		}
		if (method == 0 && compressed != size) {
			return fail("corrupt stored file: " + name);
		}
		if (size > p_limits.ratio_min_bytes && double(size) > p_limits.max_ratio * std::max<double>(compressed, 1.0)) {
			return fail("compression ratio too high: " + name);
		}
		index.total_size += size;
		if (index.total_size > p_limits.max_total_bytes) {
			return fail("unpacked size too large");
		}

		if (uint64_t(local) + LOCAL_SIZE > cd_offset || u32(p_data + local) != SIG_LOCAL) {
			return fail("corrupt local header: " + name);
		}
		uint64_t data_offset = uint64_t(local) + LOCAL_SIZE + u16(p_data + local + 26) + u16(p_data + local + 28);
		if (data_offset + compressed > cd_offset) {
			return fail("file data out of bounds: " + name);
		}
		ranges.emplace_back(local, data_offset + compressed);
		index.entries.push_back({ name, method, crc, compressed, size, data_offset });
	}

	// Overlapping records are a zip-bomb trick (one compressed stream counted many times).
	std::sort(ranges.begin(), ranges.end());
	for (size_t i = 1; i < ranges.size(); i++) {
		if (ranges[i].first < ranges[i - 1].second) {
			return fail("overlapping files");
		}
	}
	index.ok = true;
	return index;
}

} // namespace noss::package
