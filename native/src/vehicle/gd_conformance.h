#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>

namespace noss {

// Runs conformance maneuvers (docs/PLATFORMS.md §5) for the headless runner,
// tests/conformance/run_conformance.gd. The jobs run on native threads, off the script.
class NossConformance : public godot::Object {
	GDCLASS(NossConformance, godot::Object)

protected:
	static void _bind_methods();

public:
	// p_jobs: [{platform, geometry, maneuver, options}]. platform and geometry as for
	// VehicleSim.configure(). options (all optional): track (PackedVector2Array of x, z),
	// track_width, track_start_s, plus any ManeuverSpec number by name.
	// Returns one {ok, error, metrics: {name: value or null}} per job, in order.
	// p_threads <= 0 uses every hardware thread.
	static godot::Array run_batch(const godot::Array &p_jobs, int64_t p_threads);
	static godot::PackedStringArray maneuvers();
};

} // namespace noss
