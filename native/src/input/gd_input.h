#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace noss {

// Script access to wheels, pedals and force feedback, e.g. NossInput.start().
// Device ids are SDL instance ids from devices().
class NossInput : public godot::Object {
	GDCLASS(NossInput, godot::Object)

protected:
	static void _bind_methods();

public:
	static bool start();
	static void stop();
	static bool is_running();
	static godot::String get_error();
	static godot::String sdl_version();
	static void poll();
	// [{id, name, guid, vendor, product, gamepad, wheel, axes, buttons, ffb}]
	static godot::Array devices();
	static double axis(int64_t p_device, int64_t p_axis);
	static bool button(int64_t p_device, int64_t p_button);
	// force: -1..1, + pulls the wheel left. damper: 0..1.
	static void set_ffb(int64_t p_device, double p_force, double p_damper);
	static void set_ffb_options(int64_t p_device, double p_gain, double p_min_force, bool p_invert);
	static void ffb_test(int64_t p_device);
	// Peak requested force (1 = clipping), decaying over about a second.
	static double ffb_peak(int64_t p_device);
};

} // namespace noss
