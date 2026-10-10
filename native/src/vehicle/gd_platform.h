#pragma once

// Platform and fitted geometry from script Dictionaries (docs/PLATFORMS.md §2, §4.1).
// Shared by VehicleSim and NossConformance.

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include "vehicle/vehicle_model.h"

namespace noss {

// p_platform: a validated platform with defaults merged (PlatformLoader).
vehicle::PlatformSpec parse_platform(const godot::Dictionary &p_platform);

// p_geometry: {ground_y, wheels: [{center: Vector3, radius, visual_radius, axle (1 front, 2 rear),
// side ("L"/"R"/"C")}]}.
// Returns false with r_error set if it can't be used.
bool parse_geometry(const godot::Dictionary &p_geometry, vehicle::Geometry &r_geometry, godot::String &r_error);

} // namespace noss
