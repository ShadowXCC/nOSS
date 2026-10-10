#include <doctest/doctest.h>

#include <cstring>
#include <string>
#include <vector>

#include "package/format_check.h"

using namespace noss::package;

namespace {

void put32(std::vector<uint8_t> &out, uint32_t v) {
	for (int i = 0; i < 4; i++) {
		out.push_back(uint8_t(v >> (8 * i)));
	}
}

std::vector<uint8_t> glb(const std::string &p_json, const std::string &p_bin = "", int p_version = 2) {
	std::vector<uint8_t> out;
	put32(out, 0x46546C67);
	put32(out, uint32_t(p_version));
	put32(out, 0); // patched below
	put32(out, uint32_t(p_json.size()));
	put32(out, 0x4E4F534A);
	out.insert(out.end(), p_json.begin(), p_json.end());
	if (!p_bin.empty()) {
		put32(out, uint32_t(p_bin.size()));
		put32(out, 0x004E4942);
		out.insert(out.end(), p_bin.begin(), p_bin.end());
	}
	uint32_t length = uint32_t(out.size());
	std::memcpy(out.data() + 8, &length, 4);
	return out;
}

} // namespace

TEST_CASE("glb: chunks are found") {
	std::vector<uint8_t> bytes = glb("{\"asset\":{}}", "BINDATA!");
	GlbInfo info = inspect_glb(bytes.data(), bytes.size());
	REQUIRE_MESSAGE(info.ok, info.error);
	CHECK(std::string(reinterpret_cast<const char *>(bytes.data() + info.json_offset), info.json_length) == "{\"asset\":{}}");
	CHECK(info.bin_length == 8);
	CHECK(std::memcmp(bytes.data() + info.bin_offset, "BINDATA!", 8) == 0);

	std::vector<uint8_t> no_bin = glb("{}");
	CHECK(inspect_glb(no_bin.data(), no_bin.size()).ok);
}

TEST_CASE("glb: bad headers are rejected") {
	std::vector<uint8_t> v1 = glb("{}", "", 1);
	CHECK(inspect_glb(v1.data(), v1.size()).error == "not glTF 2.0");

	std::vector<uint8_t> bytes = glb("{}", "abcd");
	bytes[0] = 'X';
	CHECK(inspect_glb(bytes.data(), bytes.size()).error == "not a GLB");

	std::vector<uint8_t> big_chunk = glb("{}");
	big_chunk[12] = 0xFF; // JSON length past the end
	CHECK_FALSE(inspect_glb(big_chunk.data(), big_chunk.size()).ok);

	std::vector<uint8_t> good = glb("{\"a\":1}", "abcd");
	for (size_t cut = 0; cut < good.size(); cut++) {
		CHECK_FALSE(inspect_glb(good.data(), cut).ok); // length mismatch or truncation
	}
	CHECK(inspect_glb(good.data(), good.size(), 3).error == "GLB JSON too large");
}

TEST_CASE("image: png and jpeg sizes") {
	std::vector<uint8_t> png = { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n', 0, 0, 0, 13, 'I', 'H', 'D', 'R',
		0, 0, 0x08, 0x00, 0, 0, 0x04, 0x00, 8, 6, 0, 0, 0 };
	ImageInfo p = inspect_image(png.data(), png.size());
	CHECK(p.ok);
	CHECK(std::string(p.format) == "png");
	CHECK(p.width == 2048);
	CHECK(p.height == 1024);

	// SOI, APP0 (len 16), SOF0 with height 300, width 500.
	std::vector<uint8_t> jpg = { 0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 'J', 'F', 'I', 'F', 0, 1, 1, 0, 0, 1, 0, 1, 0, 0,
		0xFF, 0xC0, 0x00, 0x11, 8, 0x01, 0x2C, 0x01, 0xF4, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1 };
	ImageInfo j = inspect_image(jpg.data(), jpg.size());
	CHECK(j.ok);
	CHECK(std::string(j.format) == "jpg");
	CHECK(j.width == 500);
	CHECK(j.height == 300);

	std::vector<uint8_t> junk(64, 0xAB);
	CHECK_FALSE(inspect_image(junk.data(), junk.size()).ok);
	CHECK_FALSE(inspect_image(png.data(), 10).ok);
}
