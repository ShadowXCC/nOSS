#include "discord/discord_api.h"

#include <vector>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace noss::discord {

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
	return { "discord_partner_sdk.dll" };
#elif defined(__APPLE__)
	return { "libdiscord_partner_sdk.dylib" };
#else
	return { "libdiscord_partner_sdk.so" };
#endif
}

} // namespace

Discord_String borrowed(const std::string &p_text) {
	Discord_String out{};
	// The SDK takes UTF-8 with an explicit length and copies what it keeps, so casting away
	// const on a string that outlives the call is safe.
	out.ptr = reinterpret_cast<uint8_t *>(const_cast<char *>(p_text.data()));
	out.size = p_text.size();
	return out;
}

bool DiscordApi::load(const std::vector<std::string> &p_dirs, std::string &r_error) {
	if (handle) {
		return true;
	}
	// Unlike SDL3 this is never a system library: it ships beside the game, and in a dev run it
	// sits in native/bin/. The bare name is tried last, for a copy on the library path.
	for (const std::string &name : library_names()) {
		std::vector<std::string> candidates;
		for (const std::string &dir : p_dirs) {
			if (!dir.empty()) {
				candidates.push_back(dir + "/" + name);
			}
		}
		candidates.push_back(name);
		for (const std::string &candidate : candidates) {
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
		r_error = "Discord library not found";
		return false;
	}

	bool ok = true;
	auto bind = [&](auto &r_fn, const char *p_name) {
		r_fn = reinterpret_cast<std::remove_reference_t<decltype(r_fn)>>(symbol(handle, p_name));
		if (!r_fn) {
			ok = false;
			r_error = std::string("Discord library is missing ") + p_name;
		}
	};
	bind(RunCallbacks, "Discord_RunCallbacks");
	bind(Client_Init, "Discord_Client_Init");
	bind(Client_Drop, "Discord_Client_Drop");
	bind(Client_SetApplicationId, "Discord_Client_SetApplicationId");
	bind(Client_UpdateRichPresence, "Discord_Client_UpdateRichPresence");
	bind(Client_ClearRichPresence, "Discord_Client_ClearRichPresence");
	bind(Activity_Init, "Discord_Activity_Init");
	bind(Activity_Drop, "Discord_Activity_Drop");
	bind(Activity_SetType, "Discord_Activity_SetType");
	bind(Activity_SetState, "Discord_Activity_SetState");
	bind(Activity_SetDetails, "Discord_Activity_SetDetails");
	bind(Activity_SetAssets, "Discord_Activity_SetAssets");
	bind(Activity_SetTimestamps, "Discord_Activity_SetTimestamps");
	bind(Activity_SetParty, "Discord_Activity_SetParty");
	bind(ActivityAssets_Init, "Discord_ActivityAssets_Init");
	bind(ActivityAssets_Drop, "Discord_ActivityAssets_Drop");
	bind(ActivityAssets_SetLargeImage, "Discord_ActivityAssets_SetLargeImage");
	bind(ActivityAssets_SetLargeText, "Discord_ActivityAssets_SetLargeText");
	bind(ActivityTimestamps_Init, "Discord_ActivityTimestamps_Init");
	bind(ActivityTimestamps_Drop, "Discord_ActivityTimestamps_Drop");
	bind(ActivityTimestamps_SetStart, "Discord_ActivityTimestamps_SetStart");
	bind(ActivityParty_Init, "Discord_ActivityParty_Init");
	bind(ActivityParty_Drop, "Discord_ActivityParty_Drop");
	bind(ActivityParty_SetId, "Discord_ActivityParty_SetId");
	bind(ActivityParty_SetCurrentSize, "Discord_ActivityParty_SetCurrentSize");
	bind(ActivityParty_SetMaxSize, "Discord_ActivityParty_SetMaxSize");
	bind(ClientResult_Drop, "Discord_ClientResult_Drop");
	if (!ok) {
		unload();
	}
	return ok;
}

void DiscordApi::unload() {
	if (handle) {
		close_library(handle);
	}
	*this = DiscordApi();
}

} // namespace noss::discord
