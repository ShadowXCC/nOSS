#pragma once

// The Discord Social SDK, loaded at runtime (docs/DECISIONS.md D186, and D35 for the same trick
// with SDL3). noss_core neither links nor includes Discord's SDK: the handful of C entry points
// Rich Presence needs are declared here, so the build needs no SDK at all and a missing library
// just means presence is off.
//
// Every handle in the SDK's C API is one opaque pointer, so these declarations are ABI-exact.
// Checked against discord_social_sdk/include/cdiscord.h, SDK 1.10.19337.
//
// Presence does NOT need a Discord login. The SDK's own docs: "On Desktop, rich presence can be
// set before calling Client::Connect ... When Client is not connected, this sets the rich
// presence in the current user's Discord client when available." So we never call Connect, and
// the Discord app already running on the machine publishes it.

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace noss::discord {

extern "C" {

struct Discord_Client {
	void *opaque;
};
struct Discord_Activity {
	void *opaque;
};
struct Discord_ActivityAssets {
	void *opaque;
};
struct Discord_ActivityTimestamps {
	void *opaque;
};
struct Discord_ActivityParty {
	void *opaque;
};
struct Discord_ClientResult {
	void *opaque;
};

// Borrowed UTF-8, never NUL-terminated: always pass the length.
struct Discord_String {
	uint8_t *ptr;
	size_t size;
};

enum Discord_ActivityTypes {
	Discord_ActivityTypes_Playing = 0,
};

using Discord_FreeFn = void (*)(void *);
using Discord_UpdateRichPresenceCallback = void (*)(Discord_ClientResult *, void *);

} // extern "C"

// The entry points, bound by name from the shared library.
struct DiscordApi {
	void *handle = nullptr;
	std::string path;

	void (*RunCallbacks)() = nullptr;

	void (*Client_Init)(Discord_Client *) = nullptr;
	void (*Client_Drop)(Discord_Client *) = nullptr;
	void (*Client_SetApplicationId)(Discord_Client *, uint64_t) = nullptr;
	void (*Client_UpdateRichPresence)(Discord_Client *, Discord_Activity *, Discord_UpdateRichPresenceCallback, Discord_FreeFn, void *) = nullptr;
	void (*Client_ClearRichPresence)(Discord_Client *) = nullptr;

	void (*Activity_Init)(Discord_Activity *) = nullptr;
	void (*Activity_Drop)(Discord_Activity *) = nullptr;
	void (*Activity_SetType)(Discord_Activity *, Discord_ActivityTypes) = nullptr;
	// The optional fields take a pointer; null clears the field.
	void (*Activity_SetState)(Discord_Activity *, Discord_String *) = nullptr;
	void (*Activity_SetDetails)(Discord_Activity *, Discord_String *) = nullptr;
	void (*Activity_SetAssets)(Discord_Activity *, Discord_ActivityAssets *) = nullptr;
	void (*Activity_SetTimestamps)(Discord_Activity *, Discord_ActivityTimestamps *) = nullptr;
	void (*Activity_SetParty)(Discord_Activity *, Discord_ActivityParty *) = nullptr;

	void (*ActivityAssets_Init)(Discord_ActivityAssets *) = nullptr;
	void (*ActivityAssets_Drop)(Discord_ActivityAssets *) = nullptr;
	void (*ActivityAssets_SetLargeImage)(Discord_ActivityAssets *, Discord_String *) = nullptr;
	void (*ActivityAssets_SetLargeText)(Discord_ActivityAssets *, Discord_String *) = nullptr;

	void (*ActivityTimestamps_Init)(Discord_ActivityTimestamps *) = nullptr;
	void (*ActivityTimestamps_Drop)(Discord_ActivityTimestamps *) = nullptr;
	void (*ActivityTimestamps_SetStart)(Discord_ActivityTimestamps *, uint64_t) = nullptr;

	void (*ActivityParty_Init)(Discord_ActivityParty *) = nullptr;
	void (*ActivityParty_Drop)(Discord_ActivityParty *) = nullptr;
	void (*ActivityParty_SetId)(Discord_ActivityParty *, Discord_String) = nullptr;
	void (*ActivityParty_SetCurrentSize)(Discord_ActivityParty *, int32_t) = nullptr;
	void (*ActivityParty_SetMaxSize)(Discord_ActivityParty *, int32_t) = nullptr;

	void (*ClientResult_Drop)(Discord_ClientResult *) = nullptr;

	// Tries each of p_dirs in turn (the game's folder, and native/bin/ in a dev run), then the
	// bare name on the library path.
	bool load(const std::vector<std::string> &p_dirs, std::string &r_error);
	void unload();
	bool loaded() const { return handle != nullptr; }
};

// A Discord_String borrowing a std::string's bytes (the SDK copies what it needs).
Discord_String borrowed(const std::string &p_text);

} // namespace noss::discord
