#pragma once

// 16-bit greyscale PNG for terrain heights (Godot's PNG loader keeps 8 bits): reads and writes
// non-interlaced 16-bit grey images, checking every chunk's CRC and the size before inflating.
// The zlib stream (IDAT) is inflated and deflated by the caller. Plain C++, no Godot types.

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace noss::world::png16 {

struct Image {
	int w = 0;
	int h = 0;
	std::vector<uint16_t> px; // row by row
};

// zlib stream -> exactly p_expected bytes (false if it isn't that).
using Inflate = std::function<bool(const std::vector<uint8_t> &p_in, size_t p_expected, std::vector<uint8_t> &r_out)>;
// Bytes -> zlib stream.
using Deflate = std::function<bool(const std::vector<uint8_t> &p_in, std::vector<uint8_t> &r_out)>;

uint32_t crc32(const uint8_t *p_data, size_t p_len, uint32_t p_crc = 0);
// "" or why the file was refused.
std::string decode(const uint8_t *p_data, size_t p_len, int p_max_side, const Inflate &p_inflate, Image &r_out);
bool encode(const Image &p_image, const Deflate &p_deflate, std::vector<uint8_t> &r_out);
// PNG row filters on 2-byte samples, in place (raw: h rows of 1 + w*2 bytes).
bool unfilter(std::vector<uint8_t> &p_raw, int p_w, int p_h, int p_bpp);

} // namespace noss::world::png16
