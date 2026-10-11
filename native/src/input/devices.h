#pragma once

// Wheels, pedals, shifters and other non-gamepad devices through SDL3, with force feedback
// (docs/INPUT.md §2, §5-6, docs/PHYSICS.md §11). Gamepads stay with Godot's own SDL; this
// layer lists them but never opens them, and uses no HIDAPI drivers, so the two SDL copies
// don't fight over a device (risk R1).

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "input/sdl_api.h"

namespace noss::input {

struct FfbState {
	std::atomic<float> target{ 0.0f }; // -1..1, + = pulls the wheel left
	std::atomic<float> damper{ 0.0f }; // 0..1
	std::atomic<float> gain{ 1.0f };
	std::atomic<float> min_force{ 0.0f };
	std::atomic<bool> invert{ false };
	std::atomic<float> peak{ 0.0f }; // largest |output| before clamping, decays (clip meter)
	std::atomic<int> test_ticks{ 0 }; // > 0 while the test pattern plays
};

struct Device {
	uint32_t id = 0; // SDL instance id
	std::string name;
	std::string guid;
	uint16_t vendor = 0;
	uint16_t product = 0;
	bool gamepad = false;
	bool wheel = false; // SDL classifies it as a wheel
	SDL_Joystick *joystick = nullptr;
	SDL_Haptic *haptic = nullptr;
	int axis_count = 0;
	int button_count = 0; // its own buttons; each hat adds 4 more after them (up, right, down, left)
	int hat_count = 0;
	std::vector<float> axes; // -1..1
	std::vector<uint8_t> buttons;
	// Force feedback.
	bool ffb = false;
	bool damper_supported = false;
	SDL_HapticEffectID constant_effect = -1;
	SDL_HapticEffectID damper_effect = -1;
	float output = 0.0f; // smoothed level sent to the device
	float sent_damper = -1.0f;
	std::unique_ptr<FfbState> state = std::make_unique<FfbState>();
};

class DeviceManager {
public:
	~DeviceManager();

	// Loads SDL3 from p_library_dir (or the system) and starts the FFB thread.
	bool start(const std::string &p_library_dir);
	void stop();
	bool running() const { return _running; }
	const std::string &error() const { return _error; }
	std::string sdl_version() const;
	std::string sdl_path() const { return _sdl.path; }

	// Reads axes and buttons and picks up connected or removed devices. Main thread.
	void poll();

	const std::vector<std::unique_ptr<Device>> &devices() const { return _devices; }
	Device *find(uint32_t p_id);

private:
	SdlApi _sdl;
	std::string _error;
	bool _running = false;
	int _poll_count = 0;
	std::vector<std::unique_ptr<Device>> _devices;
	std::mutex _sdl_mutex; // SDL calls never run on two threads at once
	std::thread _ffb_thread;
	std::atomic<bool> _ffb_run{ false };

	void _refresh();
	void _open(uint32_t p_id);
	void _close(Device &r_device);
	void _setup_haptics(Device &r_device);
	void _ffb_loop();
};

// Shared by the script-facing NossInput class.
DeviceManager &device_manager();

} // namespace noss::input
