#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "world/heightfield.h"
#include "world/surface_map.h"

namespace noss {

// What the ground is made of under a terrain (surface_map.h); VehicleSim reads it for wheels on
// a body with this as its "noss_surface_map" meta.
class NossSurfaceMap : public godot::RefCounted {
	GDCLASS(NossSurfaceMap, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	world::SurfaceMap map;
	// VehicleSim surface id, or -1 off the map.
	int64_t surface_at(double p_x, double p_z) const { return map.at(p_x, p_z); }
	// Where its first sample is (the floating origin moves it, D155).
	void set_origin(const godot::Vector2 &p_origin) {
		map.ox = p_origin.x;
		map.oz = p_origin.y;
	}
	godot::Vector2 get_origin() const { return godot::Vector2(real_t(map.ox), real_t(map.oz)); }
};

// A track's terrain (heightfield.h) for scripts: shaping, paint, the road's bed, picking, and
// the pieces the renderer and physics need. Rects are in samples.
class NossTerrain : public godot::RefCounted {
	GDCLASS(NossTerrain, godot::RefCounted)

	world::Heightfield _field;

protected:
	static void _bind_methods();

public:
	void create(int64_t p_w, int64_t p_d, const godot::Vector2 &p_origin, double p_cell, double p_height, int64_t p_layer);
	godot::Vector2i get_size() const { return godot::Vector2i(_field.w, _field.d); }
	godot::Vector2 get_origin() const { return godot::Vector2(_field.ox, _field.oz); }
	// Moves the field without changing it (the floating origin, D155).
	void set_origin(const godot::Vector2 &p_origin) {
		_field.ox = p_origin.x;
		_field.oz = p_origin.y;
	}
	double get_cell() const { return _field.cell; }
	double height_at(double p_x, double p_z) const { return _field.height_at(p_x, p_z); }
	double base_at(double p_x, double p_z) const { return _field.base_at(p_x, p_z); }
	// Base heights as a 16-bit grey PNG: h = h_min + value * step. "" or why not.
	godot::String set_base_png(const godot::PackedByteArray &p_png, double p_h_min, double p_step);
	// The base as 16-bit samples (little-endian), quickly; png16_encode() can run on a worker.
	godot::PackedByteArray get_base_u16(double p_h_min, double p_step) const;
	static godot::PackedByteArray png16_encode(const godot::PackedByteArray &p_u16, int64_t p_w, int64_t p_h);
	godot::PackedFloat32Array get_base() const;
	bool set_base(const godot::PackedFloat32Array &p_heights);
	// Paint layers 4·image..4·image+3 as RGBA8 (w x d), as splat_<image>.png stores them.
	godot::PackedByteArray get_splat_rgba(int64_t p_image) const;
	bool set_splat_rgba(int64_t p_image, const godot::PackedByteArray &p_rgba);
	godot::Rect2i brush(int64_t p_mode, const godot::Vector2 &p_at, double p_radius, double p_strength, double p_falloff, double p_target, double p_scale, int64_t p_seed);
	godot::Rect2i paint(int64_t p_layer, const godot::Vector2 &p_at, double p_radius, double p_strength, double p_falloff);
	// p_road: per centreline sample x, y, z, left x, y, z, flat left, flat right, lifted (0/1).
	godot::Rect2i conform(const godot::Rect2i &p_rect, const godot::PackedFloat32Array &p_road, double p_falloff_m, double p_depth_m);
	godot::Rect2i rect_around(const godot::Vector2 &p_at, double p_radius) const;
	// {hit: bool, position: Vector3}
	godot::Dictionary raycast(const godot::Vector3 &p_origin, const godot::Vector3 &p_dir, double p_max_dist) const;
	godot::PackedFloat32Array region_get(const godot::Rect2i &p_rect) const;
	void region_set(const godot::Rect2i &p_rect, const godot::PackedFloat32Array &p_heights);
	godot::PackedByteArray splat_region_get(const godot::Rect2i &p_rect) const;
	void splat_region_set(const godot::Rect2i &p_rect, const godot::PackedByteArray &p_weights);
	godot::PackedByteArray chunk_r16(int64_t p_cx, int64_t p_cz, int64_t p_chunk, double p_h_min, double p_h_range) const;
	godot::PackedFloat32Array chunk_collision(int64_t p_cx, int64_t p_cz, int64_t p_chunk) const;
	godot::PackedByteArray chunk_splat(int64_t p_cx, int64_t p_cz, int64_t p_chunk, int64_t p_image) const;
	godot::Vector2 chunk_range(int64_t p_cx, int64_t p_cz, int64_t p_chunk) const;
	// The heaviest layer per sample as surfaces (p_layer_surfaces[layer]).
	godot::Ref<NossSurfaceMap> surface_map(const godot::PackedByteArray &p_layer_surfaces) const;
};

} // namespace noss
