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
	ClassDB::bind_static_method("NossInput", D_METHOD("set_ffb_inputs", "device", "inputs"), &NossInput::set_ffb_inputs);
	ClassDB::bind_static_method("NossInput", D_METHOD("set_ffb_settings", "device", "settings"), &NossInput::set_ffb_settings);
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

namespace {
float num(const Dictionary &p_d, const char *p_key, float p_default) {
	Variant v = p_d.get(p_key, p_default);
	return (v.get_type() == Variant::FLOAT || v.get_type() == Variant::INT) ? float(double(v)) : p_default;
}
} // namespace

// What the car is doing this tick (keys as ffb::Inputs; missing ones are 0).
void NossInput::set_ffb_inputs(int64_t p_device, const Dictionary &p_inputs) {
	if (input::Device *d = device(p_device)) {
		std::lock_guard<std::mutex> lock(d->state->lock);
		ffb::Inputs &in = d->state->inputs;
		in.rack = num(p_inputs, "rack", 0.0f);
		in.speed = num(p_inputs, "speed", 0.0f);
		in.curb = num(p_inputs, "curb", 0.0f);
		in.road = num(p_inputs, "road", 0.0f);
		in.slip = num(p_inputs, "slip", 0.0f);
		in.rpm_ratio = num(p_inputs, "rpm_ratio", 0.0f);
		in.jolt = num(p_inputs, "jolt", 0.0f);
		in.wheel = num(p_inputs, "wheel", 0.0f);
		in.lock = num(p_inputs, "lock", 0.0f);
	}
}

// The player's settings (keys as ffb::Settings; missing ones keep their value).
void NossInput::set_ffb_settings(int64_t p_device, const Dictionary &p_settings) {
	if (input::Device *d = device(p_device)) {
		std::lock_guard<std::mutex> lock(d->state->lock);
		ffb::Settings &s = d->state->settings;
		s.gain = num(p_settings, "gain", s.gain);
		s.max_torque_nm = num(p_settings, "max_torque_nm", s.max_torque_nm);
		s.reference_nm = num(p_settings, "reference_nm", s.reference_nm);
		s.road = num(p_settings, "road", s.road);
		s.curb = num(p_settings, "curb", s.curb);
		s.slip = num(p_settings, "slip", s.slip);
		s.jolt = num(p_settings, "jolt", s.jolt);
		s.engine = num(p_settings, "engine", s.engine);
		s.spring = num(p_settings, "spring", s.spring);
		s.damper = num(p_settings, "damper", s.damper);
		s.friction = num(p_settings, "friction", s.friction);
		s.min_force = num(p_settings, "min_force", s.min_force);
		s.smoothing = num(p_settings, "smoothing", s.smoothing);
		s.invert = bool(p_settings.get("invert", s.invert));
	}
}

void NossInput::ffb_test(int64_t p_device) {
	if (input::Device *d = device(p_device)) {
		std::lock_guard<std::mutex> lock(d->state->lock);
		d->state->mixer.start_test();
	}
}

double NossInput::ffb_peak(int64_t p_device) {
	input::Device *d = device(p_device);
	return d ? double(d->state->peak.load()) : 0.0;
}

} // namespace noss
