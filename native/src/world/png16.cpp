#include "world/png16.h"

#include <array>
#include <cstdlib>
#include <cstring>

namespace noss::world::png16 {

namespace {

constexpr uint8_t SIGNATURE[8] = { 137, 80, 78, 71, 13, 10, 26, 10 };

uint32_t be32(const uint8_t *p) {
	return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | uint32_t(p[3]);
}

void put32(std::vector<uint8_t> &r_out, uint32_t p_v) {
	r_out.push_back(uint8_t(p_v >> 24));
	r_out.push_back(uint8_t(p_v >> 16));
	r_out.push_back(uint8_t(p_v >> 8));
	r_out.push_back(uint8_t(p_v));
}

void chunk(std::vector<uint8_t> &r_out, const char *p_type, const std::vector<uint8_t> &p_data) {
	put32(r_out, uint32_t(p_data.size()));
	size_t start = r_out.size();
	r_out.insert(r_out.end(), p_type, p_type + 4);
	r_out.insert(r_out.end(), p_data.begin(), p_data.end());
	put32(r_out, crc32(r_out.data() + start, r_out.size() - start));
}

int paeth(int a, int b, int c) {
	int p = a + b - c;
	int pa = std::abs(p - a), pb = std::abs(p - b), pc = std::abs(p - c);
	if (pa <= pb && pa <= pc) {
		return a;
	}
	return pb <= pc ? b : c;
}

} // namespace

uint32_t crc32(const uint8_t *p_data, size_t p_len, uint32_t p_crc) {
	static const std::array<uint32_t, 256> table = [] {
		std::array<uint32_t, 256> t{};
		for (uint32_t n = 0; n < 256; n++) {
			uint32_t c = n;
			for (int k = 0; k < 8; k++) {
				c = (c & 1) ? 0xedb88320u ^ (c >> 1) : c >> 1;
			}
			t[n] = c;
		}
		return t;
	}();
	uint32_t c = p_crc ^ 0xffffffffu;
	for (size_t i = 0; i < p_len; i++) {
		c = table[(c ^ p_data[i]) & 0xff] ^ (c >> 8);
	}
	return c ^ 0xffffffffu;
}

bool unfilter(std::vector<uint8_t> &p_raw, int p_w, int p_h, int p_bpp) {
	size_t stride = size_t(p_w) * size_t(p_bpp);
	if (p_raw.size() != size_t(p_h) * (stride + 1)) {
		return false;
	}
	std::vector<uint8_t> prev(stride, 0);
	std::vector<uint8_t> out(size_t(p_h) * stride);
	for (int y = 0; y < p_h; y++) {
		uint8_t filter = p_raw[size_t(y) * (stride + 1)];
		const uint8_t *in = &p_raw[size_t(y) * (stride + 1) + 1];
		uint8_t *row = &out[size_t(y) * stride];
		for (size_t i = 0; i < stride; i++) {
			int a = i >= size_t(p_bpp) ? row[i - size_t(p_bpp)] : 0;
			int b = prev[i];
			int c = i >= size_t(p_bpp) ? prev[i - size_t(p_bpp)] : 0;
			int v = in[i];
			switch (filter) {
				case 0:
					break;
				case 1:
					v += a;
					break;
				case 2:
					v += b;
					break;
				case 3:
					v += (a + b) / 2;
					break;
				case 4:
					v += paeth(a, b, c);
					break;
				default:
					return false;
			}
			row[i] = uint8_t(v);
		}
		std::memcpy(prev.data(), row, stride);
	}
	p_raw.swap(out);
	return true;
}

std::string decode(const uint8_t *p_data, size_t p_len, int p_max_side, const Inflate &p_inflate, Image &r_out) {
	if (p_len < 8 + 25 || std::memcmp(p_data, SIGNATURE, 8) != 0) {
		return "Not a PNG";
	}
	size_t at = 8;
	bool header = false;
	std::vector<uint8_t> idat;
	int w = 0, h = 0;
	while (at + 12 <= p_len) {
		uint32_t len = be32(p_data + at);
		if (len > p_len - at - 12) {
			return "PNG cut short";
		}
		const uint8_t *type = p_data + at + 4;
		const uint8_t *body = p_data + at + 8;
		if (crc32(type, size_t(len) + 4) != be32(body + len)) {
			return "PNG checksum wrong";
		}
		if (std::memcmp(type, "IHDR", 4) == 0) {
			if (len != 13) {
				return "PNG header wrong";
			}
			w = int(be32(body));
			h = int(be32(body + 4));
			if (w < 1 || h < 1 || w > p_max_side || h > p_max_side) {
				return "Heightmap too large";
			}
			if (body[8] != 16 || body[9] != 0) {
				return "Heightmap must be 16-bit grey";
			}
			if (body[10] != 0 || body[11] != 0 || body[12] != 0) {
				return "Heightmap must not be interlaced";
			}
			header = true;
		} else if (std::memcmp(type, "IDAT", 4) == 0) {
			if (!header) {
				return "PNG header missing";
			}
			idat.insert(idat.end(), body, body + len);
		} else if (std::memcmp(type, "IEND", 4) == 0) {
			break;
		}
		at += size_t(len) + 12;
	}
	if (!header || idat.empty()) {
		return "PNG has no image";
	}
	size_t expected = size_t(h) * (size_t(w) * 2 + 1);
	std::vector<uint8_t> raw;
	if (!p_inflate(idat, expected, raw) || raw.size() != expected) {
		return "PNG data wrong";
	}
	if (!unfilter(raw, w, h, 2)) {
		return "PNG filter wrong";
	}
	r_out.w = w;
	r_out.h = h;
	r_out.px.resize(size_t(w) * size_t(h));
	for (size_t i = 0; i < r_out.px.size(); i++) {
		r_out.px[i] = uint16_t((uint16_t(raw[i * 2]) << 8) | raw[i * 2 + 1]);
	}
	return "";
}

bool encode(const Image &p_image, const Deflate &p_deflate, std::vector<uint8_t> &r_out) {
	if (p_image.w < 1 || p_image.h < 1 || p_image.px.size() != size_t(p_image.w) * size_t(p_image.h)) {
		return false;
	}
	size_t stride = size_t(p_image.w) * 2;
	std::vector<uint8_t> raw(size_t(p_image.h) * (stride + 1));
	std::vector<uint8_t> row(stride), prev(stride, 0), sub(stride), up(stride);
	for (int y = 0; y < p_image.h; y++) {
		for (int x = 0; x < p_image.w; x++) {
			uint16_t v = p_image.px[size_t(y) * size_t(p_image.w) + size_t(x)];
			row[size_t(x) * 2] = uint8_t(v >> 8);
			row[size_t(x) * 2 + 1] = uint8_t(v);
		}
		// Sub or Up, whichever leaves smaller bytes (heights change slowly both ways).
		long cost_sub = 0, cost_up = 0;
		for (size_t i = 0; i < stride; i++) {
			sub[i] = uint8_t(row[i] - (i >= 2 ? row[i - 2] : 0));
			up[i] = uint8_t(row[i] - prev[i]);
			cost_sub += std::abs(int(int8_t(sub[i])));
			cost_up += std::abs(int(int8_t(up[i])));
		}
		bool use_up = y > 0 && cost_up < cost_sub;
		uint8_t *out = &raw[size_t(y) * (stride + 1)];
		out[0] = use_up ? 2 : 1;
		std::memcpy(out + 1, use_up ? up.data() : sub.data(), stride);
		prev.swap(row);
		row.resize(stride);
	}
	std::vector<uint8_t> z;
	if (!p_deflate(raw, z)) {
		return false;
	}
	r_out.assign(SIGNATURE, SIGNATURE + 8);
	std::vector<uint8_t> ihdr;
	put32(ihdr, uint32_t(p_image.w));
	put32(ihdr, uint32_t(p_image.h));
	ihdr.insert(ihdr.end(), { 16, 0, 0, 0, 0 });
	chunk(r_out, "IHDR", ihdr);
	chunk(r_out, "IDAT", z);
	chunk(r_out, "IEND", {});
	return true;
}

} // namespace noss::world::png16
