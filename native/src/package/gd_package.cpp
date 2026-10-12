#include "package/gd_package.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

#include "package/format_check.h"
#include "package/zip_index.h"

using namespace godot;

namespace noss {

void NossPackage::_bind_methods() {
	ClassDB::bind_static_method("NossPackage", D_METHOD("inspect_zip", "bytes", "limits"), &NossPackage::inspect_zip, DEFVAL(Dictionary()));
	ClassDB::bind_static_method("NossPackage", D_METHOD("inspect_glb", "bytes"), &NossPackage::inspect_glb);
	ClassDB::bind_static_method("NossPackage", D_METHOD("image_size", "bytes"), &NossPackage::image_size);
	ClassDB::bind_static_method("NossPackage", D_METHOD("is_safe_path", "path"), &NossPackage::is_safe_path);
}

Dictionary NossPackage::inspect_zip(const PackedByteArray &p_bytes, const Dictionary &p_limits) {
	// Limits can only be lowered from the car ceiling, or the track one (limits.ceiling = "track").
	package::ZipLimits limits = String(p_limits.get("ceiling", "")) == "track" ? package::track_zip_ceiling() : package::ZipLimits();
	auto lower = [&](const char *p_key, auto &r_value) {
		if (p_limits.has(p_key)) {
			int64_t v = p_limits[p_key];
			if (v >= 0 && uint64_t(v) < uint64_t(r_value)) {
				r_value = decltype(+r_value)(v);
			}
		}
	};
	lower("max_zip_bytes", limits.max_zip_bytes);
	lower("max_total_bytes", limits.max_total_bytes);
	lower("max_entries", limits.max_entries);

	package::ZipIndex index = package::read_zip_index(p_bytes.ptr(), size_t(p_bytes.size()), limits);
	Dictionary result;
	result["ok"] = index.ok;
	result["error"] = String(index.error.c_str());
	result["total_size"] = int64_t(index.total_size);
	Array entries;
	for (const package::ZipEntry &entry : index.entries) {
		Dictionary e;
		e["name"] = String::utf8(entry.name.c_str());
		e["size"] = int64_t(entry.size);
		e["compressed"] = int64_t(entry.compressed);
		entries.push_back(e);
	}
	result["entries"] = entries;
	return result;
}

Dictionary NossPackage::inspect_glb(const PackedByteArray &p_bytes) {
	package::GlbInfo info = package::inspect_glb(p_bytes.ptr(), size_t(p_bytes.size()));
	Dictionary result;
	result["ok"] = info.ok;
	result["error"] = String(info.error.c_str());
	result["json"] = info.ok ? String::utf8(reinterpret_cast<const char *>(p_bytes.ptr() + info.json_offset), int64_t(info.json_length)) : String();
	result["bin_offset"] = int64_t(info.bin_offset);
	result["bin_length"] = int64_t(info.bin_length);
	return result;
}

Vector2i NossPackage::image_size(const PackedByteArray &p_bytes) {
	package::ImageInfo info = package::inspect_image(p_bytes.ptr(), size_t(p_bytes.size()));
	return info.ok ? Vector2i(int32_t(info.width), int32_t(info.height)) : Vector2i();
}

bool NossPackage::is_safe_path(const String &p_path) {
	return package::is_safe_entry_name(std::string(p_path.utf8().get_data()));
}

} // namespace noss
