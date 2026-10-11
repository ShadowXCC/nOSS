#include "input/sdl_api.h"

#include <vector>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace noss::input {

namespace {

void *open_library(const std::string &p_path) {
#ifdef _WIN32
	return reinterpret_cast<void *>(LoadLibraryA(p_path.c_str()));
#else
	return dlopen(p_path.c_str(), RTLD_NOW | RTLD_LOCAL);
#endif
}

void close_library(void *p_handle) {
#ifdef _WIN32
	FreeLibrary(reinterpret_cast<HMODULE>(p_handle));
#else
	dlclose(p_handle);
#endif
}

void *symbol(void *p_handle, const char *p_name) {
#ifdef _WIN32
	return reinterpret_cast<void *>(GetProcAddress(reinterpret_cast<HMODULE>(p_handle), p_name));
#else
	return dlsym(p_handle, p_name);
#endif
}

std::vector<std::string> library_names() {
#if defined(_WIN32)
	return { "SDL3.dll" };
#elif defined(__APPLE__)
	return { "libSDL3.0.dylib", "libSDL3.dylib", "SDL3.framework/SDL3" };
#else
	return { "libSDL3.so.0", "libSDL3.so" };
#endif
}

} // namespace

bool SdlApi::load(const std::string &p_dir, std::string &r_error) {
	if (handle) {
		return true;
	}
	std::vector<std::string> tried;
	for (const std::string &name : library_names()) {
		for (const std::string &candidate : { p_dir.empty() ? std::string() : p_dir + "/" + name, name }) {
			if (candidate.empty()) {
				continue;
			}
			tried.push_back(candidate);
			handle = open_library(candidate);
			if (handle) {
				path = candidate;
				break;
			}
		}
		if (handle) {
			break;
		}
	}
	if (!handle) {
		r_error = "SDL3 not found";
		return false;
	}

	bool ok = true;
	auto bind = [&](auto &r_fn, const char *p_name) {
		r_fn = reinterpret_cast<std::remove_reference_t<decltype(r_fn)>>(symbol(handle, p_name));
		if (!r_fn) {
			ok = false;
			r_error = std::string("SDL3 is missing ") + p_name;
		}
	};
	bind(Init, "SDL_Init");
	bind(Quit, "SDL_Quit");
	bind(SetHint, "SDL_SetHint");
	bind(GetVersion, "SDL_GetVersion");
	bind(GetError, "SDL_GetError");
	bind(free, "SDL_free");
	bind(GetJoysticks, "SDL_GetJoysticks");
	bind(GetJoystickNameForID, "SDL_GetJoystickNameForID");
	bind(GetJoystickGUIDForID, "SDL_GetJoystickGUIDForID");
	bind(GetJoystickVendorForID, "SDL_GetJoystickVendorForID");
	bind(GetJoystickProductForID, "SDL_GetJoystickProductForID");
	bind(GetJoystickTypeForID, "SDL_GetJoystickTypeForID");
	bind(IsGamepad, "SDL_IsGamepad");
	bind(OpenJoystick, "SDL_OpenJoystick");
	bind(CloseJoystick, "SDL_CloseJoystick");
	bind(GetNumJoystickAxes, "SDL_GetNumJoystickAxes");
	bind(GetNumJoystickButtons, "SDL_GetNumJoystickButtons");
	bind(GetJoystickAxis, "SDL_GetJoystickAxis");
	bind(GetJoystickButton, "SDL_GetJoystickButton");
	// Optional: without hats, hat buttons just never press.
	GetNumJoystickHats = reinterpret_cast<decltype(GetNumJoystickHats)>(symbol(handle, "SDL_GetNumJoystickHats"));
	GetJoystickHat = reinterpret_cast<decltype(GetJoystickHat)>(symbol(handle, "SDL_GetJoystickHat"));
	if (!GetJoystickHat) {
		GetNumJoystickHats = nullptr;
	}
	bind(UpdateJoysticks, "SDL_UpdateJoysticks");
	bind(GUIDToString, "SDL_GUIDToString");
	bind(IsJoystickHaptic, "SDL_IsJoystickHaptic");
	bind(OpenHapticFromJoystick, "SDL_OpenHapticFromJoystick");
	bind(CloseHaptic, "SDL_CloseHaptic");
	bind(GetHapticFeatures, "SDL_GetHapticFeatures");
	bind(CreateHapticEffect, "SDL_CreateHapticEffect");
	bind(UpdateHapticEffect, "SDL_UpdateHapticEffect");
	bind(RunHapticEffect, "SDL_RunHapticEffect");
	bind(StopHapticEffect, "SDL_StopHapticEffect");
	bind(DestroyHapticEffect, "SDL_DestroyHapticEffect");
	bind(SetHapticGain, "SDL_SetHapticGain");
	bind(SetHapticAutocenter, "SDL_SetHapticAutocenter");
	if (!ok) {
		unload();
	}
	return ok;
}

void SdlApi::unload() {
	if (handle) {
		close_library(handle);
	}
	*this = SdlApi();
}

} // namespace noss::input
