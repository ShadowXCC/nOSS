#include <doctest/doctest.h>

#include "world/png16.h"

using namespace noss::world;

namespace {

uint32_t adler32(const std::vector<uint8_t> &p) {
	uint32_t a = 1, b = 0;
	for (uint8_t c : p) {
		a = (a + c) % 65521;
		b = (b + a) % 65521;
	}
	return (b << 16) | a;
}

// zlib with stored (uncompressed) blocks: enough to test the PNG framing without zlib here.
bool stored_deflate(const std::vector<uint8_t> &p_in, std::vector<uint8_t> &r_out) {
	r_out = { 0x78, 0x01 };
	size_t at = 0;
	do {
		size_t n = std::min<size_t>(65535, p_in.size() - at);
		r_out.push_back(at + n >= p_in.size() ? 1 : 0);
		r_out.push_back(uint8_t(n));
		r_out.push_back(uint8_t(n >> 8));
		r_out.push_back(uint8_t(~n));
		r_out.push_back(uint8_t(~n >> 8));
		r_out.insert(r_out.end(), p_in.begin() + long(at), p_in.begin() + long(at + n));
		at += n;
	} while (at < p_in.size());
	uint32_t s = adler32(p_in);
	for (int k = 3; k >= 0; k--) {
		r_out.push_back(uint8_t(s >> (k * 8)));
	}
	return true;
}

bool stored_inflate(const std::vector<uint8_t> &p_in, size_t p_expected, std::vector<uint8_t> &r_out) {
	r_out.clear();
	size_t at = 2;
	while (at + 5 <= p_in.size()) {
		bool last = p_in[at] & 1;
		size_t n = p_in[at + 1] | (size_t(p_in[at + 2]) << 8);
		at += 5;
		if (at + n > p_in.size() || r_out.size() + n > p_expected) {
			return false;
		}
		r_out.insert(r_out.end(), p_in.begin() + long(at), p_in.begin() + long(at + n));
		at += n;
		if (last) {
			break;
		}
	}
	return r_out.size() == p_expected;
}

png16::Image ramp(int p_w, int p_h) {
	png16::Image img;
	img.w = p_w;
	img.h = p_h;
	for (int y = 0; y < p_h; y++) {
		for (int x = 0; x < p_w; x++) {
			img.px.push_back(uint16_t((x * 523 + y * 1999 + (x * y) % 97) & 0xffff));
		}
	}
	return img;
}

} // namespace

TEST_CASE("png16: CRC of IEND is the well-known value") {
	const uint8_t iend[4] = { 'I', 'E', 'N', 'D' };
	CHECK(png16::crc32(iend, 4) == 0xAE426082u);
}

TEST_CASE("png16: encode then decode gives the same samples") {
	png16::Image img = ramp(37, 23);
	std::vector<uint8_t> png;
	REQUIRE(png16::encode(img, stored_deflate, png));
	png16::Image back;
	CHECK(png16::decode(png.data(), png.size(), 100, stored_inflate, back) == "");
	CHECK(back.w == 37);
	CHECK(back.h == 23);
	CHECK(back.px == img.px);
}

TEST_CASE("png16: every row filter unfilters") {
	// Filter each row with type (y % 5) by hand, then unfilter.
	int w = 5, h = 5, bpp = 2;
	size_t stride = size_t(w * bpp);
	std::vector<uint8_t> rows(size_t(h) * stride);
	for (size_t i = 0; i < rows.size(); i++) {
		rows[i] = uint8_t(i * 37 + 11);
	}
	std::vector<uint8_t> raw;
	std::vector<uint8_t> prev(stride, 0);
	for (int y = 0; y < h; y++) {
		int f = y % 5;
		raw.push_back(uint8_t(f));
		const uint8_t *row = &rows[size_t(y) * stride];
		for (size_t i = 0; i < stride; i++) {
			int a = i >= size_t(bpp) ? row[i - size_t(bpp)] : 0, b = prev[i], c = i >= size_t(bpp) ? prev[i - size_t(bpp)] : 0;
			int p = a + b - c, pa = std::abs(p - a), pb = std::abs(p - b), pc = std::abs(p - c);
			int pred = f == 0 ? 0 : f == 1 ? a : f == 2 ? b : f == 3 ? (a + b) / 2 : (pa <= pb && pa <= pc ? a : pb <= pc ? b : c);
			raw.push_back(uint8_t(row[i] - pred));
		}
		std::copy(row, row + stride, prev.begin());
	}
	REQUIRE(png16::unfilter(raw, w, h, bpp));
	CHECK(raw == rows);
}

TEST_CASE("png16: refuses too large, wrong depth, bad CRC and cut files") {
	std::vector<uint8_t> png;
	REQUIRE(png16::encode(ramp(64, 64), stored_deflate, png));
	png16::Image out;
	CHECK(png16::decode(png.data(), png.size(), 32, stored_inflate, out) == "Heightmap too large");
	std::vector<uint8_t> bad = png;
	bad[8 + 8 + 8] = 8; // IHDR bit depth
	CHECK(png16::decode(bad.data(), bad.size(), 100, stored_inflate, out) == "PNG checksum wrong");
	std::vector<uint8_t> cut(png.begin(), png.begin() + long(png.size() / 2));
	CHECK(png16::decode(cut.data(), cut.size(), 100, stored_inflate, out) != "");
	const char *text = "not a png at all, just some words here";
	CHECK(png16::decode(reinterpret_cast<const uint8_t *>(text), 38, 100, stored_inflate, out) == "Not a PNG");
}
