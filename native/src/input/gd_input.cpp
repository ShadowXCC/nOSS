#include "input/gd_input.h"

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include "input/devices.h"

using namespace godot;
using noss::input::device_manager;

namespace noss {

namespace {

// Folder of the running game binary, where a bundled SDL3 library sits in exports.
std::string library_dir() {
	String exe = OS::get_singleton()->get_executable_path().get_base_dir();
	return std::string(exe.utf8().get_data());
}

input::Device *device(int64_t p_id) {
	return device_manager().find(uint32_t(p_id));
}

} // namespace

void NossInput::_bind_methods() {
	ClassDB::bind_static_method("NossInput", D_METHOD("start"), &NossInput::start);
	ClassDB::bind_static_method("NossInput", D_METHOD("stop"), &NossInput::stop);
	ClassDB::bind_static_method("NossInput", D_METHOD("is_running"), &NossInput::is_running);
	ClassDB::bind_static_method("NossInput", D_METHOD("get_error"), &NossInput::get_error);
	ClassDB::bind_static_method("NossInput", D_METHOD("sdl_version"), &NossInput::sdl_version);
	ClassDB::bind_static_method("NossInput", D_METHOD("poll"), &NossInput::poll);
	ClassDB::bind_static_method("NossInput", D_METHOD("devices"), &NossInput::devices);
	ClassDB::bind_static_method("NossInput", D_METHOD("axis", "device", "axis"), &NossInput::axis);
	ClassDB::bind_static_method("NossInput", D_METHOD("button", "device", "button"), &NossInput::button);
	ClassDB::bind_static_method("NossInput", D_METHOD("set_ffb", "device", "force", "damper"), &NossInput::set_ffb);
	ClassDB::bind_static_method("NossInput", D_METHOD("set_ffb_options", "device", "gain", "min_force", "invert"), &NossInput::set_ffb_options);
	ClassDB::bind_static_method("NossInput", D_METHOD("ffb_test", "device"), &NossInput::ffb_test);
	ClassDB::bind_static_method("NossInput", D_METHOD("ffb_peak", "device"), &NossInput::ffb_peak);
}

bool NossInput::start() {
	return device_manager().start(library_dir());
}

void NossInput::stop() {
	device_manager().stop();
}

bool NossInput::is_running() {
	return device_manager().running();
}

String NossInput::get_error() {
	return String(device_manager().error().c_str());
}

String NossInput::sdl_version() {
	return String(device_manager().sdl_version().c_str());
}

void NossInput::poll() {
	device_manager().poll();
}

Array NossInput::devices() {
	Array out;
	for (const auto &d : device_manager().devices()) {
		Dictionary info;
		info["id"] = int64_t(d->id);
		info["name"] = String::utf8(d->name.c_str());
		info["guid"] = String(d->guid.c_str());
		info["vendor"] = int64_t(d->vendor);
		info["product"] = int64_t(d->product);
		info["gamepad"] = d->gamepad;
		info["wheel"] = d->wheel;
		info["axes"] = d->axis_count;
		info["buttons"] = int64_t(d->buttons.size()); // its own, then 4 per hat
		info["hats"] = d->hat_count;
		info["ffb"] = d->ffb;
		out.push_back(info);
	}
	return out;
}

double NossInput::axis(int64_t p_device, int64_t p_axis) {
	input::Device *d = device(p_device);
	return (d && p_axis >= 0 && p_axis < int64_t(d->axes.size())) ? d->axes[size_t(p_axis)] : 0.0;
}

bool NossInput::button(int64_t p_device, int64_t p_button) {
	input::Device *d = device(p_device);
	return d && p_button >= 0 && p_button < int64_t(d->buttons.size()) && d->buttons[size_t(p_button)];
}

void NossInput::set_ffb(int64_t p_device, double p_force, double p_damper) {
	if (input::Device *d = device(p_device)) {
		d->state->target = float(p_force);
		d->state->damper = float(p_damper);
	}
}

void NossInput::set_ffb_options(int64_t p_device, double p_gain, double p_min_force, bool p_invert) {
	if (input::Device *d = device(p_device)) {
		d->state->gain = float(p_gain);
		d->state->min_force = float(p_min_force);
		d->state->invert = p_invert;
	}
}

void NossInput::ffb_test(int64_t p_device) {
	if (input::Device *d = device(p_device)) {
		d->state->test_ticks = 600;
	}
}

double NossInput::ffb_peak(int64_t p_device) {
	input::Device *d = device(p_device);
	return d ? double(d->state->peak.load()) : 0.0;
}

} // namespace noss
