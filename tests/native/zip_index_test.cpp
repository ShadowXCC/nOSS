#include <doctest/doctest.h>

#include <cstring>
#include <string>
#include <vector>

#include "package/zip_index.h"

using namespace noss::package;

namespace {

// Writes minimal zips with stored entries, with knobs for the broken cases we must reject.
struct ZipBuilder {
	struct Entry {
		std::string name;
		std::string data;
		uint16_t method = 0;
		uint16_t flags = 0;
		uint32_t external = 0100644u << 16;
		uint32_t declared_size = UINT32_MAX; // override the uncompressed size
		uint32_t local_override = UINT32_MAX;
	};
	std::vector<Entry> entries;

	Entry &add(std::string p_name, std::string p_data = "x") {
		entries.push_back({ std::move(p_name), std::move(p_data) });
		return entries.back();
	}

	static void put16(std::vector<uint8_t> &out, uint16_t v) {
		out.push_back(uint8_t(v));
		out.push_back(uint8_t(v >> 8));
	}
	static void put32(std::vector<uint8_t> &out, uint32_t v) {
		put16(out, uint16_t(v));
		put16(out, uint16_t(v >> 16));
	}

	std::vector<uint8_t> build() const {
		std::vector<uint8_t> out;
		std::vector<uint32_t> offsets;
		for (const Entry &e : entries) {
			offsets.push_back(uint32_t(out.size()));
			put32(out, 0x04034b50);
			put16(out, 20);
			put16(out, e.flags);
			put16(out, e.method);
			put32(out, 0);
			put32(out, 0); // crc (not checked here)
			put32(out, uint32_t(e.data.size()));
			put32(out, e.declared_size != UINT32_MAX ? e.declared_size : uint32_t(e.data.size()));
			put16(out, uint16_t(e.name.size()));
			put16(out, 0);
			out.insert(out.end(), e.name.begin(), e.name.end());
			out.insert(out.end(), e.data.begin(), e.data.end());
		}
		uint32_t cd_offset = uint32_t(out.size());
		for (size_t i = 0; i < entries.size(); i++) {
			const Entry &e = entries[i];
			put32(out, 0x02014b50);
			put16(out, (3 << 8) | 20); // made by Unix
			put16(out, 20);
			put16(out, e.flags);
			put16(out, e.method);
			put32(out, 0);
			put32(out, 0);
			put32(out, uint32_t(e.data.size()));
			put32(out, e.declared_size != UINT32_MAX ? e.declared_size : uint32_t(e.data.size()));
			put16(out, uint16_t(e.name.size()));
			put16(out, 0);
			put16(out, 0);
			put16(out, 0);
			put16(out, 0);
			put32(out, e.external);
			put32(out, e.local_override != UINT32_MAX ? e.local_override : offsets[i]);
			out.insert(out.end(), e.name.begin(), e.name.end());
		}
		uint32_t cd_size = uint32_t(out.size()) - cd_offset;
		put32(out, 0x06054b50);
		put16(out, 0);
		put16(out, 0);
		put16(out, uint16_t(entries.size()));
		put16(out, uint16_t(entries.size()));
		put32(out, cd_size);
		put32(out, cd_offset);
		put16(out, 0);
		return out;
	}
};

ZipIndex index_of(const ZipBuilder &p_builder, const ZipLimits &p_limits = {}) {
	std::vector<uint8_t> bytes = p_builder.build();
	return read_zip_index(bytes.data(), bytes.size(), p_limits);
}

} // namespace

TEST_CASE("zip: a normal package is accepted") {
	ZipBuilder zip;
	zip.add("manifest.json", "{}");
	zip.add("model/body.glb", "glTF");
	zip.add("sound/", "").external = 040755u << 16; // directory entry
	ZipIndex index = index_of(zip);
	REQUIRE_MESSAGE(index.ok, index.error);
	REQUIRE(index.entries.size() == 2);
	CHECK(index.entries[1].name == "model/body.glb");
	CHECK(index.entries[1].size == 4);
	CHECK(index.total_size == 6);
}

TEST_CASE("zip: unsafe names are rejected") {
	for (const char *name : { "../evil.json", "/abs.json", "a//b.json", "model/../x.glb", ".hidden.json", "dir/.x/a.json",
				 "scene.tscn", "script.gd", "lib.so", "a\\b.json", "c:/x.json", "noext" }) {
		ZipBuilder zip;
		zip.add(name);
		CHECK_MESSAGE(!index_of(zip).ok, name);
	}
	CHECK(is_safe_entry_name("model/lod1.glb"));
	CHECK(is_safe_entry_name("sound/ex_on_1000.ogg"));
	CHECK_FALSE(is_safe_entry_name("model/body.GLB"));
}

TEST_CASE("zip: symlinks, encryption, duplicates and odd methods are rejected") {
	ZipBuilder link;
	link.add("a.json").external = 0120777u << 16;
	CHECK(index_of(link).error.find("symlink") == 0);

	ZipBuilder encrypted;
	encrypted.add("a.json").flags = 1;
	CHECK(index_of(encrypted).error.find("encrypted") == 0);

	ZipBuilder dup;
	dup.add("a.json");
	dup.add("a.json");
	CHECK(index_of(dup).error.find("duplicate") == 0);

	ZipBuilder method;
	method.add("a.json").method = 12; // bzip2
	CHECK(index_of(method).error.find("unsupported compression") == 0);
}

TEST_CASE("zip: limits") {
	ZipBuilder many;
	for (int i = 0; i < 10; i++) {
		many.add("f" + std::to_string(i) + ".json");
	}
	ZipLimits limits;
	limits.max_entries = 5;
	CHECK(index_of(many, limits).error == "too many files");

	ZipBuilder big;
	big.add("a.json", std::string(2000, 'a'));
	limits = {};
	limits.max_total_bytes = 1000;
	CHECK(index_of(big, limits).error == "unpacked size too large");
	limits = {};
	limits.max_zip_bytes = 100;
	CHECK(index_of(big, limits).error == "package too large");
}

TEST_CASE("zip: compression bombs are rejected") {
	ZipBuilder bomb;
	auto &e = bomb.add("a.json", std::string(100, 'a'));
	e.method = 8;
	e.declared_size = 200u << 20; // claims 200 MB from 100 bytes
	ZipLimits limits;
	limits.max_total_bytes = 1ull << 40;
	CHECK(index_of(bomb, limits).error.find("compression ratio") == 0);

	ZipBuilder overlap;
	overlap.add("a.json", "aaaa");
	overlap.add("b.json", "bbbb").local_override = 0; // points at a.json's record
	CHECK(!index_of(overlap).ok);
}

TEST_CASE("zip: garbage and truncation") {
	std::vector<uint8_t> junk(100, 0x42);
	CHECK(read_zip_index(junk.data(), junk.size()).error == "not a zip");
	CHECK_FALSE(read_zip_index(junk.data(), 3).ok);

	ZipBuilder zip;
	zip.add("a.json", "hello");
	std::vector<uint8_t> bytes = zip.build();
	for (size_t cut = 1; cut < bytes.size(); cut++) {
		CHECK_FALSE(read_zip_index(bytes.data(), cut).ok);
	}
}
