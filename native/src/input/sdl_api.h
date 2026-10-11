#pragma once

// SDL3, loaded at runtime (docs/INPUT.md §2, DECISIONS.md D35). noss_core compiles against
// the SDL headers but doesn't link SDL, so the game runs without it (wheels are then off).
// Linux uses the system libSDL3.so.0, Windows and macOS a library shipped next to the game.

#include <string>

#include <SDL3/SDL_error.h>
#include <SDL3/SDL_gamepad.h>
#include <SDL3/SDL_guid.h>
#include <SDL3/SDL_haptic.h>
#include <SDL3/SDL_hints.h>
#include <SDL3/SDL_init.h>
#include <SDL3/SDL_joystick.h>
#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_version.h>

namespace noss::input {

struct SdlApi {
	void *handle = nullptr;
	std::string path;

	decltype(&SDL_Init) Init = nullptr;
	decltype(&SDL_Quit) Quit = nullptr;
	decltype(&SDL_SetHint) SetHint = nullptr;
	decltype(&SDL_GetVersion) GetVersion = nullptr;
	decltype(&SDL_GetError) GetError = nullptr;
	decltype(&SDL_free) free = nullptr;
	decltype(&SDL_GetJoysticks) GetJoysticks = nullptr;
	decltype(&SDL_GetJoystickNameForID) GetJoystickNameForID = nullptr;
	decltype(&SDL_GetJoystickGUIDForID) GetJoystickGUIDForID = nullptr;
	decltype(&SDL_GetJoystickVendorForID) GetJoystickVendorForID = nullptr;
	decltype(&SDL_GetJoystickProductForID) GetJoystickProductForID = nullptr;
	decltype(&SDL_GetJoystickTypeForID) GetJoystickTypeForID = nullptr;
	decltype(&SDL_IsGamepad) IsGamepad = nullptr;
	decltype(&SDL_OpenJoystick) OpenJoystick = nullptr;
	decltype(&SDL_CloseJoystick) CloseJoystick = nullptr;
	decltype(&SDL_GetNumJoystickAxes) GetNumJoystickAxes = nullptr;
	decltype(&SDL_GetNumJoystickButtons) GetNumJoystickButtons = nullptr;
	decltype(&SDL_GetJoystickAxis) GetJoystickAxis = nullptr;
	decltype(&SDL_GetJoystickButton) GetJoystickButton = nullptr;
	decltype(&SDL_GetNumJoystickHats) GetNumJoystickHats = nullptr;
	decltype(&SDL_GetJoystickHat) GetJoystickHat = nullptr;
	decltype(&SDL_UpdateJoysticks) UpdateJoysticks = nullptr;
	decltype(&SDL_GUIDToString) GUIDToString = nullptr;
	decltype(&SDL_IsJoystickHaptic) IsJoystickHaptic = nullptr;
	decltype(&SDL_OpenHapticFromJoystick) OpenHapticFromJoystick = nullptr;
	decltype(&SDL_CloseHaptic) CloseHaptic = nullptr;
	decltype(&SDL_GetHapticFeatures) GetHapticFeatures = nullptr;
	decltype(&SDL_CreateHapticEffect) CreateHapticEffect = nullptr;
	decltype(&SDL_UpdateHapticEffect) UpdateHapticEffect = nullptr;
	decltype(&SDL_RunHapticEffect) RunHapticEffect = nullptr;
	decltype(&SDL_StopHapticEffect) StopHapticEffect = nullptr;
	decltype(&SDL_DestroyHapticEffect) DestroyHapticEffect = nullptr;
	decltype(&SDL_SetHapticGain) SetHapticGain = nullptr;
	decltype(&SDL_SetHapticAutocenter) SetHapticAutocenter = nullptr;

	// Tries p_dir (the folder holding noss_core) first, then the system library path.
	bool load(const std::string &p_dir, std::string &r_error);
	void unload();
	bool loaded() const { return handle != nullptr; }
};

} // namespace noss::input
