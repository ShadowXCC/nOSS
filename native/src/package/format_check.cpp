#include "package/format_check.h"

#include <cstring>

namespace noss::package {

namespace {

constexpr uint32_t GLB_MAGIC = 0x46546C67; // "glTF"
constexpr uint32_t CHUNK_JSON = 0x4E4F534A;
constexpr uint32_t CHUNK_BIN = 0x004E4942;

uint32_t le32(const uint8_t *p) {
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

uint32_t be32(const uint8_t *p) {
	return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | uint32_t(p[3]);
}

uint16_t be16(const uint8_t *p) {
	return uint16_t((p[0] << 8) | p[1]);
}

GlbInfo glb_fail(const char *p_error) {
	GlbInfo info;
	info.error = p_error;
	return info;
}

ImageInfo png(const uint8_t *p_data, size_t p_length) {
	static const uint8_t SIG[8] = { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n' };
	ImageInfo info;
	if (p_length < 24 || std::memcmp(p_data, SIG, 8) != 0 || be32(p_data + 8) != 13 || std::memcmp(p_data + 12, "IHDR", 4) != 0) {
		return info;
	}
	info.format = "png";
	info.width = be32(p_data + 16);
	info.height = be32(p_data + 20);
	info.ok = info.width > 0 && info.height > 0;
	return info;
}

ImageInfo jpeg(const uint8_t *p_data, size_t p_length) {
	ImageInfo info;
	if (p_length < 4 || p_data[0] != 0xFF || p_data[1] != 0xD8) {
		return info;
	}
	size_t pos = 2;
	while (pos + 4 <= p_length) {
		if (p_data[pos] != 0xFF) {
			return info;
		}
		uint8_t marker = p_data[pos + 1];
		if (marker == 0xFF) {
			pos++; // fill byte
			continue;
		}
		if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
			pos += 2; // no length
			continue;
		}
		if (marker == 0xD9 || marker == 0xDA) {
			return info; // end of image or start of scan before any frame header
		}
		uint16_t length = be16(p_data + pos + 2);
		if (length < 2 || pos + 2 + length > p_length) {
			return info;
		}
		bool is_sof = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
		if (is_sof) {
			if (length < 7) {
				return info;
			}
			info.format = "jpg";
			info.height = be16(p_data + pos + 5);
			info.width = be16(p_data + pos + 7);
			info.ok = info.width > 0 && info.height > 0;
			return info;
		}
		pos += 2 + length;
	}
	return info;
}

} // namespace

GlbInfo inspect_glb(const uint8_t *p_data, size_t p_length, size_t p_max_json) {
	if (p_length < 20) {
		return glb_fail("not a GLB");
	}
	if (le32(p_data) != GLB_MAGIC) {
		return glb_fail("not a GLB");
	}
	if (le32(p_data + 4) != 2) {
		return glb_fail("not glTF 2.0");
	}
	if (le32(p_data + 8) != p_length) {
		return glb_fail("GLB length mismatch");
	}
	GlbInfo info;
	size_t pos = 12;
	bool first = true;
	while (pos < p_length) {
		if (pos + 8 > p_length) {
			return glb_fail("truncated GLB chunk");
		}
		uint32_t length = le32(p_data + pos);
		uint32_t type = le32(p_data + pos + 4);
		size_t start = pos + 8;
		if (length > p_length - start) {
			return glb_fail("GLB chunk out of bounds");
		}
		if (first) {
			if (type != CHUNK_JSON) {
				return glb_fail("first GLB chunk isn't JSON");
			}
			if (length == 0 || length > p_max_json) {
				return glb_fail("GLB JSON too large");
			}
			info.json_offset = start;
			info.json_length = length;
			first = false;
		} else if (type == CHUNK_BIN) {
			if (info.bin_offset != 0) {
				return glb_fail("more than one BIN chunk");
			}
			info.bin_offset = start;
			info.bin_length = length;
		} else if (type == CHUNK_JSON) {
			return glb_fail("more than one JSON chunk");
		}
		pos = start + length;
	}
	if (first) {
		return glb_fail("GLB has no JSON chunk");
	}
	info.ok = true;
	return info;
}

ImageInfo inspect_image(const uint8_t *p_data, size_t p_length) {
	ImageInfo info = png(p_data, p_length);
	return info.ok ? info : jpeg(p_data, p_length);
}

} // namespace noss::package
