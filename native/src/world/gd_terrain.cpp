#include "world/gd_terrain.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <algorithm>
#include <cmath>

#include "world/png16.h"

using namespace godot;

namespace noss {

namespace {

world::Rect to_rect(const Rect2i &p_r) {
	return { p_r.position.x, p_r.position.y, p_r.position.x + p_r.size.x, p_r.position.y + p_r.size.y };
}

Rect2i to_rect2i(const world::Rect &p_r) {
	return p_r.empty() ? Rect2i() : Rect2i(p_r.x0, p_r.z0, p_r.width(), p_r.depth());
}

PackedByteArray bytes(const std::vector<uint8_t> &p_v) {
	PackedByteArray out;
	out.resize(int64_t(p_v.size()));
	if (!p_v.empty()) {
		std::copy(p_v.begin(), p_v.end(), out.ptrw());
	}
	return out;
}

std::vector<uint8_t> vec(const PackedByteArray &p_b) {
	return std::vector<uint8_t>(p_b.ptr(), p_b.ptr() + p_b.size());
}

PackedFloat32Array floats(const std::vector<float> &p_v) {
	PackedFloat32Array out;
	out.resize(int64_t(p_v.size()));
	if (!p_v.empty()) {
		std::copy(p_v.begin(), p_v.end(), out.ptrw());
	}
	return out;
}

} // namespace

void NossSurfaceMap::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_origin", "origin"), &NossSurfaceMap::set_origin);
	ClassDB::bind_method(D_METHOD("get_origin"), &NossSurfaceMap::get_origin);
	ClassDB::bind_method(D_METHOD("surface_at", "x", "z"), &NossSurfaceMap::surface_at);
}

void NossTerrain::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_origin", "origin"), &NossTerrain::set_origin);
	ClassDB::bind_method(D_METHOD("create", "w", "d", "origin", "cell", "height", "layer"), &NossTerrain::create);
	ClassDB::bind_method(D_METHOD("get_size"), &NossTerrain::get_size);
	ClassDB::bind_method(D_METHOD("get_origin"), &NossTerrain::get_origin);
	ClassDB::bind_method(D_METHOD("get_cell"), &NossTerrain::get_cell);
	ClassDB::bind_method(D_METHOD("height_at", "x", "z"), &NossTerrain::height_at);
	ClassDB::bind_method(D_METHOD("base_at", "x", "z"), &NossTerrain::base_at);
	ClassDB::bind_method(D_METHOD("set_base_png", "png", "h_min", "step"), &NossTerrain::set_base_png);
	ClassDB::bind_method(D_METHOD("get_base_u16", "h_min", "step"), &NossTerrain::get_base_u16);
	ClassDB::bind_static_method("NossTerrain", D_METHOD("png16_encode", "u16", "w", "h"), &NossTerrain::png16_encode);
	ClassDB::bind_method(D_METHOD("get_base"), &NossTerrain::get_base);
	ClassDB::bind_method(D_METHOD("set_base", "heights"), &NossTerrain::set_base);
	ClassDB::bind_method(D_METHOD("get_splat_rgba", "image"), &NossTerrain::get_splat_rgba);
	ClassDB::bind_method(D_METHOD("set_splat_rgba", "image", "rgba"), &NossTerrain::set_splat_rgba);
	ClassDB::bind_method(D_METHOD("brush", "mode", "at", "radius", "strength", "falloff", "target", "scale", "seed"), &NossTerrain::brush);
	ClassDB::bind_method(D_METHOD("paint", "layer", "at", "radius", "strength", "falloff"), &NossTerrain::paint);
	ClassDB::bind_method(D_METHOD("conform", "rect", "road", "falloff_m", "depth_m", "aprons"), &NossTerrain::conform, DEFVAL(PackedFloat32Array()));
	ClassDB::bind_method(D_METHOD("rect_around", "at", "radius"), &NossTerrain::rect_around);
	ClassDB::bind_method(D_METHOD("raycast", "origin", "dir", "max_dist"), &NossTerrain::raycast);
	ClassDB::bind_method(D_METHOD("region_get", "rect"), &NossTerrain::region_get);
	ClassDB::bind_method(D_METHOD("region_set", "rect", "heights"), &NossTerrain::region_set);
	ClassDB::bind_method(D_METHOD("splat_region_get", "rect"), &NossTerrain::splat_region_get);
	ClassDB::bind_method(D_METHOD("splat_region_set", "rect", "weights"), &NossTerrain::splat_region_set);
	ClassDB::bind_method(D_METHOD("chunk_r16", "cx", "cz", "chunk", "h_min", "h_range"), &NossTerrain::chunk_r16);
	ClassDB::bind_method(D_METHOD("chunk_collision", "cx", "cz", "chunk"), &NossTerrain::chunk_collision);
	ClassDB::bind_method(D_METHOD("chunk_splat", "cx", "cz", "chunk", "image"), &NossTerrain::chunk_splat);
	ClassDB::bind_method(D_METHOD("chunk_range", "cx", "cz", "chunk"), &NossTerrain::chunk_range);
	ClassDB::bind_method(D_METHOD("surface_map", "layer_surfaces"), &NossTerrain::surface_map);
}

void NossTerrain::create(int64_t p_w, int64_t p_d, const Vector2 &p_origin, double p_cell, double p_height, int64_t p_layer) {
	_field.create(int(std::clamp<int64_t>(p_w, 2, 8193)), int(std::clamp<int64_t>(p_d, 2, 8193)), p_origin.x, p_origin.y, p_cell, float(p_height), int(p_layer));
}

String NossTerrain::set_base_png(const PackedByteArray &p_png, double p_h_min, double p_step) {
	world::png16::Image img;
	auto inflate = [](const std::vector<uint8_t> &p_in, size_t p_expected, std::vector<uint8_t> &r_out) {
		PackedByteArray in = bytes(p_in);
		PackedByteArray out = in.decompress_dynamic(int64_t(p_expected), FileAccess::COMPRESSION_DEFLATE);
		if (size_t(out.size()) != p_expected) {
			return false;
		}
		r_out = vec(out);
		return true;
	};
	std::string err = world::png16::decode(p_png.ptr(), size_t(p_png.size()), std::max(_field.w, _field.d), inflate, img);
	if (!err.empty()) {
		return String(err.c_str());
	}
	if (img.w != _field.w || img.h != _field.d) {
		return "Heightmap size doesn't match";
	}
	for (size_t i = 0; i < img.px.size(); i++) {
		_field.base[i] = float(p_h_min + double(img.px[i]) * p_step);
	}
	_field.final_h = _field.base;
	return "";
}

PackedByteArray NossTerrain::get_base_u16(double p_h_min, double p_step) const {
	PackedByteArray out;
	out.resize(int64_t(_field.base.size() * 2));
	uint8_t *w = out.ptrw();
	for (size_t i = 0; i < _field.base.size(); i++) {
		long v = std::clamp(std::lround((_field.base[i] - p_h_min) / std::max(p_step, 1e-9)), 0L, 65535L);
		w[i * 2] = uint8_t(v & 0xff);
		w[i * 2 + 1] = uint8_t(v >> 8);
	}
	return out;
}

PackedByteArray NossTerrain::png16_encode(const PackedByteArray &p_u16, int64_t p_w, int64_t p_h) {
	world::png16::Image img;
	img.w = int(p_w);
	img.h = int(p_h);
	if (p_w < 1 || p_h < 1 || p_u16.size() != p_w * p_h * 2) {
		return PackedByteArray();
	}
	img.px.resize(size_t(p_w * p_h));
	const uint8_t *r = p_u16.ptr();
	for (size_t i = 0; i < img.px.size(); i++) {
		img.px[i] = uint16_t(r[i * 2] | (uint16_t(r[i * 2 + 1]) << 8));
	}
	auto deflate = [](const std::vector<uint8_t> &p_in, std::vector<uint8_t> &r_out) {
		PackedByteArray z = bytes(p_in).compress(FileAccess::COMPRESSION_DEFLATE);
		r_out = vec(z);
		return !r_out.empty();
	};
	std::vector<uint8_t> png;
	if (!world::png16::encode(img, deflate, png)) {
		return PackedByteArray();
	}
	return bytes(png);
}

PackedFloat32Array NossTerrain::get_base() const {
	return floats(_field.base);
}

bool NossTerrain::set_base(const PackedFloat32Array &p_heights) {
	if (size_t(p_heights.size()) != _field.base.size()) {
		return false;
	}
	std::copy(p_heights.ptr(), p_heights.ptr() + p_heights.size(), _field.base.begin());
	_field.final_h = _field.base;
	return true;
}

PackedByteArray NossTerrain::get_splat_rgba(int64_t p_image) const {
	size_t n = size_t(_field.w) * size_t(_field.d);
	PackedByteArray out;
	out.resize(int64_t(n * 4));
	uint8_t *w = out.ptrw();
	int first = int(std::clamp<int64_t>(p_image, 0, 1)) * 4;
	for (size_t i = 0; i < n; i++) {
		for (int c = 0; c < 4; c++) {
			w[i * 4 + size_t(c)] = _field.splat[i * world::LAYERS + size_t(first + c)];
		}
	}
	return out;
}

bool NossTerrain::set_splat_rgba(int64_t p_image, const PackedByteArray &p_rgba) {
	size_t n = size_t(_field.w) * size_t(_field.d);
	if (size_t(p_rgba.size()) != n * 4) {
		return false;
	}
	int first = int(std::clamp<int64_t>(p_image, 0, 1)) * 4;
	const uint8_t *r = p_rgba.ptr();
	for (size_t i = 0; i < n; i++) {
		for (int c = 0; c < 4; c++) {
			_field.splat[i * world::LAYERS + size_t(first + c)] = r[i * 4 + size_t(c)];
		}
	}
	return true;
}

Rect2i NossTerrain::brush(int64_t p_mode, const Vector2 &p_at, double p_radius, double p_strength, double p_falloff, double p_target, double p_scale, int64_t p_seed) {
	world::Brush b;
	b.mode = world::BrushMode(std::clamp<int64_t>(p_mode, 0, 4));
	b.x = p_at.x;
	b.z = p_at.y;
	b.radius = p_radius;
	b.strength = p_strength;
	b.falloff = p_falloff;
	b.target = p_target;
	b.scale = p_scale;
	b.seed = uint32_t(p_seed);
	return to_rect2i(_field.brush(b));
}

Rect2i NossTerrain::paint(int64_t p_layer, const Vector2 &p_at, double p_radius, double p_strength, double p_falloff) {
	return to_rect2i(_field.paint(int(p_layer), p_at.x, p_at.y, p_radius, p_strength, p_falloff));
}

Rect2i NossTerrain::conform(const Rect2i &p_rect, const PackedFloat32Array &p_road, double p_falloff_m, double p_depth_m, const PackedFloat32Array &p_aprons) {
	std::vector<world::RoadSample> road(size_t(p_road.size() / 9));
	const float *r = p_road.ptr();
	// Aprons, if any: six per sample (edge_l, edge_r, apron_l, apron_r, slope_l, slope_r).
	const float *ap = size_t(p_aprons.size()) == road.size() * 6 ? p_aprons.ptr() : nullptr;
	for (size_t i = 0; i < road.size(); i++) {
		const float *s = r + i * 9;
		int flags = int(s[8] + 0.5f); // 1: lifted, 2: the road ends here
		road[i] = { s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7], (flags & 1) != 0, (flags & 2) != 0 };
		if (ap) {
			const float *a = ap + i * 6;
			road[i].edge_l = a[0];
			road[i].edge_r = a[1];
			road[i].apron_l = a[2];
			road[i].apron_r = a[3];
			road[i].slope_l = a[4];
			road[i].slope_r = a[5];
			road[i].paved_l = a[0] + a[2];
			road[i].paved_r = a[1] + a[3];
		}
	}
	return to_rect2i(_field.conform(to_rect(p_rect), road, p_falloff_m, p_depth_m));
}

Rect2i NossTerrain::rect_around(const Vector2 &p_at, double p_radius) const {
	return to_rect2i(_field.rect_around(p_at.x, p_at.y, p_radius));
}

Dictionary NossTerrain::raycast(const Vector3 &p_origin, const Vector3 &p_dir, double p_max_dist) const {
	double o[3] = { p_origin.x, p_origin.y, p_origin.z };
	double d[3] = { p_dir.x, p_dir.y, p_dir.z };
	double hit[3];
	Dictionary out;
	bool ok = _field.raycast(o, d, p_max_dist, hit);
	out["hit"] = ok;
	out["position"] = ok ? Vector3(hit[0], hit[1], hit[2]) : Vector3();
	return out;
}

PackedFloat32Array NossTerrain::region_get(const Rect2i &p_rect) const {
	return floats(_field.get_region(to_rect(p_rect)));
}

void NossTerrain::region_set(const Rect2i &p_rect, const PackedFloat32Array &p_heights) {
	_field.set_region(to_rect(p_rect), std::vector<float>(p_heights.ptr(), p_heights.ptr() + p_heights.size()));
}

PackedByteArray NossTerrain::splat_region_get(const Rect2i &p_rect) const {
	return bytes(_field.get_splat_region(to_rect(p_rect)));
}

void NossTerrain::splat_region_set(const Rect2i &p_rect, const PackedByteArray &p_weights) {
	_field.set_splat_region(to_rect(p_rect), vec(p_weights));
}

PackedByteArray NossTerrain::chunk_r16(int64_t p_cx, int64_t p_cz, int64_t p_chunk, double p_h_min, double p_h_range) const {
	std::vector<uint16_t> v;
	_field.chunk_r16(int(p_cx), int(p_cz), int(p_chunk), p_h_min, p_h_range, v);
	PackedByteArray out;
	out.resize(int64_t(v.size() * 2));
	uint8_t *w = out.ptrw();
	for (size_t i = 0; i < v.size(); i++) {
		w[i * 2] = uint8_t(v[i] & 0xff);
		w[i * 2 + 1] = uint8_t(v[i] >> 8);
	}
	return out;
}

PackedFloat32Array NossTerrain::chunk_collision(int64_t p_cx, int64_t p_cz, int64_t p_chunk) const {
	std::vector<float> v;
	_field.chunk_collision(int(p_cx), int(p_cz), int(p_chunk), v);
	return floats(v);
}

PackedByteArray NossTerrain::chunk_splat(int64_t p_cx, int64_t p_cz, int64_t p_chunk, int64_t p_image) const {
	std::vector<uint8_t> v;
	_field.chunk_splat(int(p_cx), int(p_cz), int(p_chunk), int(p_image), v);
	return bytes(v);
}

Vector2 NossTerrain::chunk_range(int64_t p_cx, int64_t p_cz, int64_t p_chunk) const {
	float lo, hi;
	_field.chunk_range(int(p_cx), int(p_cz), int(p_chunk), lo, hi);
	return Vector2(lo, hi);
}

Ref<NossSurfaceMap> NossTerrain::surface_map(const PackedByteArray &p_layer_surfaces) const {
	Ref<NossSurfaceMap> m;
	m.instantiate();
	m->map = world::SurfaceMap::from_layers(_field.dominant_layers(), _field.w, _field.d, _field.ox, _field.oz, _field.cell, vec(p_layer_surfaces));
	return m;
}

} // namespace noss
