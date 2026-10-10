#include "input/devices.h"

#include <algorithm>
#include <chrono>
#include <cmath>

namespace noss::input {

namespace {

constexpr int FFB_HZ = 500;
constexpr int REFRESH_EVERY = 60; // polls between device list checks
constexpr float SMOOTHING = 0.25f; // per FFB tick, toward the target

} // namespace

DeviceManager &device_manager() {
	static DeviceManager manager;
	return manager;
}

DeviceManager::~DeviceManager() {
	stop();
}

bool DeviceManager::start(const std::string &p_library_dir) {
	if (_running) {
		return true;
	}
	if (!_sdl.load(p_library_dir, _error)) {
		return false;
	}
	// Our SDL only reads non-gamepad devices: no HIDAPI (gamepad drivers), and input keeps
	// flowing without an SDL window.
	_sdl.SetHint(SDL_HINT_JOYSTICK_HIDAPI, "0");
	_sdl.SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
	if (!_sdl.Init(SDL_INIT_JOYSTICK | SDL_INIT_GAMEPAD | SDL_INIT_HAPTIC)) {
		_error = std::string("SDL init failed: ") + _sdl.GetError();
		_sdl.unload();
		return false;
	}
	_running = true;
	_refresh();
	_ffb_run = true;
	_ffb_thread = std::thread(&DeviceManager::_ffb_loop, this);
	return true;
}

void DeviceManager::stop() {
	if (!_running) {
		return;
	}
	_ffb_run = false;
	if (_ffb_thread.joinable()) {
		_ffb_thread.join();
	}
	{
		std::lock_guard<std::mutex> lock(_sdl_mutex);
		for (auto &d : _devices) {
			_close(*d);
		}
		_devices.clear();
		_sdl.Quit();
	}
	_sdl.unload();
	_running = false;
}

std::string DeviceManager::sdl_version() const {
	if (!_sdl.loaded()) {
		return "";
	}
	int v = _sdl.GetVersion();
	return std::to_string(SDL_VERSIONNUM_MAJOR(v)) + "." + std::to_string(SDL_VERSIONNUM_MINOR(v)) + "." + std::to_string(SDL_VERSIONNUM_MICRO(v));
}

Device *DeviceManager::find(uint32_t p_id) {
	for (auto &d : _devices) {
		if (d->id == p_id) {
			return d.get();
		}
	}
	return nullptr;
}

void DeviceManager::poll() {
	if (!_running) {
		return;
	}
	std::lock_guard<std::mutex> lock(_sdl_mutex);
	_sdl.UpdateJoysticks();
	if (++_poll_count >= REFRESH_EVERY) {
		_poll_count = 0;
		_refresh();
	}
	for (auto &d : _devices) {
		if (!d->joystick) {
			continue;
		}
		for (int i = 0; i < d->axis_count; i++) {
			d->axes[size_t(i)] = std::max(-1.0f, float(_sdl.GetJoystickAxis(d->joystick, i)) / 32767.0f);
		}
		for (int i = 0; i < d->button_count; i++) {
			d->buttons[size_t(i)] = _sdl.GetJoystickButton(d->joystick, i) ? 1 : 0;
		}
	}
}

void DeviceManager::_refresh() {
	int count = 0;
	SDL_JoystickID *ids = _sdl.GetJoysticks(&count);
	std::vector<uint32_t> present(ids, ids + std::max(count, 0));
	if (ids) {
		_sdl.free(ids);
	}
	for (auto it = _devices.begin(); it != _devices.end();) {
		if (std::find(present.begin(), present.end(), (*it)->id) == present.end()) {
			_close(**it);
			it = _devices.erase(it);
		} else {
			++it;
		}
	}
	for (uint32_t id : present) {
		if (!find(id)) {
			_open(id);
		}
	}
}

void DeviceManager::_open(uint32_t p_id) {
	auto d = std::make_unique<Device>();
	d->id = p_id;
	const char *name = _sdl.GetJoystickNameForID(p_id);
	d->name = name ? name : "Unknown device";
	char guid[33] = {};
	_sdl.GUIDToString(_sdl.GetJoystickGUIDForID(p_id), guid, sizeof(guid));
	d->guid = guid;
	d->vendor = _sdl.GetJoystickVendorForID(p_id);
	d->product = _sdl.GetJoystickProductForID(p_id);
	d->gamepad = _sdl.IsGamepad(p_id);
	d->wheel = _sdl.GetJoystickTypeForID(p_id) == SDL_JOYSTICK_TYPE_WHEEL;
	if (!d->gamepad || d->wheel) {
		d->joystick = _sdl.OpenJoystick(p_id);
		if (d->joystick) {
			d->axis_count = std::max(_sdl.GetNumJoystickAxes(d->joystick), 0);
			d->button_count = std::max(_sdl.GetNumJoystickButtons(d->joystick), 0);
			d->axes.assign(size_t(d->axis_count), 0.0f);
			d->buttons.assign(size_t(d->button_count), 0);
			_setup_haptics(*d);
		}
	}
	_devices.push_back(std::move(d));
}

void DeviceManager::_setup_haptics(Device &r_device) {
	if (!_sdl.IsJoystickHaptic(r_device.joystick)) {
		return;
	}
	r_device.haptic = _sdl.OpenHapticFromJoystick(r_device.joystick);
	if (!r_device.haptic) {
		return;
	}
	uint32_t features = _sdl.GetHapticFeatures(r_device.haptic);
	if (features & SDL_HAPTIC_AUTOCENTER) {
		_sdl.SetHapticAutocenter(r_device.haptic, 0); // the game provides all centering
	}
	if (features & SDL_HAPTIC_GAIN) {
		_sdl.SetHapticGain(r_device.haptic, 100);
	}
	if (features & SDL_HAPTIC_CONSTANT) {
		SDL_HapticEffect e;
		SDL_zero(e);
		e.type = SDL_HAPTIC_CONSTANT;
		e.constant.type = SDL_HAPTIC_CONSTANT;
		e.constant.direction.type = SDL_HAPTIC_STEERING_AXIS;
		e.constant.length = SDL_HAPTIC_INFINITY;
		e.constant.level = 0;
		r_device.constant_effect = _sdl.CreateHapticEffect(r_device.haptic, &e);
		if (r_device.constant_effect >= 0) {
			_sdl.RunHapticEffect(r_device.haptic, r_device.constant_effect, 1);
			r_device.ffb = true;
		}
	}
	if (features & SDL_HAPTIC_DAMPER) {
		SDL_HapticEffect e;
		SDL_zero(e);
		e.type = SDL_HAPTIC_DAMPER;
		e.condition.type = SDL_HAPTIC_DAMPER;
		e.condition.direction.type = SDL_HAPTIC_STEERING_AXIS;
		e.condition.length = SDL_HAPTIC_INFINITY;
		r_device.damper_effect = _sdl.CreateHapticEffect(r_device.haptic, &e);
		if (r_device.damper_effect >= 0) {
			_sdl.RunHapticEffect(r_device.haptic, r_device.damper_effect, 1);
			r_device.damper_supported = true;
		}
	}
}

void DeviceManager::_close(Device &r_device) {
	if (r_device.haptic) {
		if (r_device.constant_effect >= 0) {
			_sdl.StopHapticEffect(r_device.haptic, r_device.constant_effect);
			_sdl.DestroyHapticEffect(r_device.haptic, r_device.constant_effect);
		}
		if (r_device.damper_effect >= 0) {
			_sdl.StopHapticEffect(r_device.haptic, r_device.damper_effect);
			_sdl.DestroyHapticEffect(r_device.haptic, r_device.damper_effect);
		}
		_sdl.CloseHaptic(r_device.haptic);
		r_device.haptic = nullptr;
	}
	if (r_device.joystick) {
		_sdl.CloseJoystick(r_device.joystick);
		r_device.joystick = nullptr;
	}
}

// ~500 Hz: smooths the latest target (set at the physics rate) and sends it to the wheel.
void DeviceManager::_ffb_loop() {
	using clock = std::chrono::steady_clock;
	auto next = clock::now();
	const auto period = std::chrono::microseconds(1000000 / FFB_HZ);
	while (_ffb_run) {
		next += period;
		{
			std::lock_guard<std::mutex> lock(_sdl_mutex);
			for (auto &dp : _devices) {
				Device &d = *dp;
				if (!d.ffb) {
					continue;
				}
				FfbState &s = *d.state;
				float target = s.target.load() * s.gain.load();
				int test = s.test_ticks.load();
				if (test > 0) {
					// Test pattern: left, right, centre, 0.4 s each.
					int phase = (FFB_HZ * 6 / 5 - test) / (FFB_HZ * 2 / 5);
					target = phase == 0 ? 0.5f : phase == 1 ? -0.5f : 0.0f;
					s.test_ticks = test - 1;
				}
				float magnitude = std::abs(target);
				s.peak = std::max(magnitude, s.peak.load() * 0.998f);
				// Lift small forces past the wheel's deadband.
				if (magnitude > 0.005f) {
					float lifted = s.min_force + (1.0f - s.min_force) * std::min(magnitude, 1.0f);
					target = std::copysign(lifted, target);
				}
				target = std::clamp(target, -1.0f, 1.0f);
				d.output += (target - d.output) * SMOOTHING;
				float level = s.invert ? d.output : -d.output; // + level turns most wheels right
				SDL_HapticEffect e;
				SDL_zero(e);
				e.type = SDL_HAPTIC_CONSTANT;
				e.constant.type = SDL_HAPTIC_CONSTANT;
				e.constant.direction.type = SDL_HAPTIC_STEERING_AXIS;
				e.constant.length = SDL_HAPTIC_INFINITY;
				e.constant.level = Sint16(std::lround(level * 32767.0f));
				_sdl.UpdateHapticEffect(d.haptic, d.constant_effect, &e);

				float damper = s.damper.load();
				if (d.damper_supported && std::abs(damper - d.sent_damper) > 0.01f) {
					d.sent_damper = damper;
					SDL_HapticEffect c;
					SDL_zero(c);
					c.type = SDL_HAPTIC_DAMPER;
					c.condition.type = SDL_HAPTIC_DAMPER;
					c.condition.direction.type = SDL_HAPTIC_STEERING_AXIS;
					c.condition.length = SDL_HAPTIC_INFINITY;
					Uint16 sat = Uint16(std::lround(std::clamp(damper, 0.0f, 1.0f) * 65535.0f));
					Sint16 coeff = Sint16(std::lround(std::clamp(damper, 0.0f, 1.0f) * 32767.0f));
					c.condition.right_sat[0] = c.condition.left_sat[0] = sat;
					c.condition.right_coeff[0] = c.condition.left_coeff[0] = coeff;
					_sdl.UpdateHapticEffect(d.haptic, d.damper_effect, &c);
				}
			}
		}
		std::this_thread::sleep_until(next);
	}
}

} // namespace noss::input
