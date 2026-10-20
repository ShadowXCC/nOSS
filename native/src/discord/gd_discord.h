#pragma once

// Script access to Discord Rich Presence, e.g. NossDiscord.start(app_id). The game's `Discord`
// autoload drives it; see game/app/discord.gd and docs/DECISIONS.md D186.
//
// Presence only: this never calls the SDK's Connect(), so there is no Discord login, no token
// and no account handling. Invites and lobbies would need that and are not wired up.

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace noss {

class NossDiscord : public godot::Object {
	GDCLASS(NossDiscord, godot::Object)

protected:
	static void _bind_methods();

public:
	// Loads the library and makes a client for `p_app_id` (the Discord application id). False if
	// the library is missing: presence is then simply off, see get_error().
	static bool start(uint64_t p_app_id);
	static void stop();
	static bool is_running();
	static godot::String get_error();
	// The library that was loaded, for the boot log.
	static godot::String library_path();
	// Hands time to the SDK; call once a frame while running.
	static void poll();
	// Keys, all optional: details, state, large_image, large_text, party_id,
	// party_size, party_max, start_unix.
	static void set_presence(const godot::Dictionary &p_activity);
	static void clear_presence();
};

} // namespace noss
