#include "discord/gd_discord.h"

#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <string>
#include <vector>

#include "discord/discord_api.h"

using namespace godot;
using namespace noss::discord;

namespace noss {

namespace {

struct State {
	DiscordApi api;
	Discord_Client client{};
	bool client_made = false;
	std::string error = "not started";
};

State &state() {
	static State s;
	return s;
}

// Where the library can be: beside the game binary in an export, and in native/bin/ in a dev
// run. Unlike SDL3 there is no system copy to fall back on.
std::vector<std::string> library_dirs() {
	std::vector<std::string> dirs;
	dirs.push_back(std::string(OS::get_singleton()->get_executable_path().get_base_dir().utf8().get_data()));
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings) {
		dirs.push_back(std::string(settings->globalize_path("res://native/bin").utf8().get_data()));
	}
	return dirs;
}

std::string utf8_of(const Variant &p_value) {
	return std::string(String(p_value).utf8().get_data());
}

// RunCallbacks() dispatches this whether or not we care about the outcome, so it must not be
// null -- a null one segfaults there -- and it is handed the result to own, so it has to drop
// it. There is nothing to do with the outcome: a failure only means Discord is not listening.
void presence_updated(Discord_ClientResult *p_result, void *) {
	State &s = state();
	if (p_result && s.api.ClientResult_Drop) {
		s.api.ClientResult_Drop(p_result);
	}
}

// Paired with the null user data below; the SDK may call it either way.
void free_nothing(void *) {
}

} // namespace

void NossDiscord::_bind_methods() {
	ClassDB::bind_static_method("NossDiscord", D_METHOD("start", "app_id"), &NossDiscord::start);
	ClassDB::bind_static_method("NossDiscord", D_METHOD("stop"), &NossDiscord::stop);
	ClassDB::bind_static_method("NossDiscord", D_METHOD("is_running"), &NossDiscord::is_running);
	ClassDB::bind_static_method("NossDiscord", D_METHOD("get_error"), &NossDiscord::get_error);
	ClassDB::bind_static_method("NossDiscord", D_METHOD("library_path"), &NossDiscord::library_path);
	ClassDB::bind_static_method("NossDiscord", D_METHOD("poll"), &NossDiscord::poll);
	ClassDB::bind_static_method("NossDiscord", D_METHOD("set_presence", "activity"), &NossDiscord::set_presence);
	ClassDB::bind_static_method("NossDiscord", D_METHOD("clear_presence"), &NossDiscord::clear_presence);
}

bool NossDiscord::start(uint64_t p_app_id) {
	State &s = state();
	if (s.client_made) {
		return true;
	}
	if (!s.api.load(library_dirs(), s.error)) {
		return false;
	}
	s.api.Client_Init(&s.client);
	s.api.Client_SetApplicationId(&s.client, p_app_id);
	s.client_made = true;
	s.error.clear();
	return true;
}

void NossDiscord::stop() {
	State &s = state();
	if (s.client_made) {
		s.api.Client_ClearRichPresence(&s.client);
		// One last turn, so the clear reaches Discord before the client goes.
		s.api.RunCallbacks();
		s.api.Client_Drop(&s.client);
		s.client = Discord_Client{};
		s.client_made = false;
	}
	s.api.unload();
	s.error = "not started";
}

bool NossDiscord::is_running() {
	return state().client_made;
}

String NossDiscord::get_error() {
	return String(state().error.c_str());
}

String NossDiscord::library_path() {
	return String(state().api.path.c_str());
}

void NossDiscord::poll() {
	State &s = state();
	if (s.client_made) {
		s.api.RunCallbacks();
	}
}

void NossDiscord::set_presence(const Dictionary &p_activity) {
	State &s = state();
	if (!s.client_made) {
		return;
	}
	DiscordApi &api = s.api;

	Discord_Activity activity{};
	api.Activity_Init(&activity);
	api.Activity_SetType(&activity, Discord_ActivityTypes_Playing);

	// These strings must outlive the Set* calls that borrow them.
	std::string details = utf8_of(p_activity.get("details", ""));
	std::string status = utf8_of(p_activity.get("state", ""));
	std::string large_image = utf8_of(p_activity.get("large_image", ""));
	std::string large_text = utf8_of(p_activity.get("large_text", ""));
	std::string party_id = utf8_of(p_activity.get("party_id", ""));

	if (!details.empty()) {
		Discord_String value = borrowed(details);
		api.Activity_SetDetails(&activity, &value);
	}
	if (!status.empty()) {
		Discord_String value = borrowed(status);
		api.Activity_SetState(&activity, &value);
	}

	Discord_ActivityAssets assets{};
	bool has_assets = !large_image.empty();
	if (has_assets) {
		api.ActivityAssets_Init(&assets);
		Discord_String image = borrowed(large_image);
		api.ActivityAssets_SetLargeImage(&assets, &image);
		if (!large_text.empty()) {
			Discord_String text = borrowed(large_text);
			api.ActivityAssets_SetLargeText(&assets, &text);
		}
		api.Activity_SetAssets(&activity, &assets);
	}

	Discord_ActivityTimestamps timestamps{};
	uint64_t start_unix = uint64_t(int64_t(p_activity.get("start_unix", 0)));
	bool has_timestamps = start_unix > 0;
	if (has_timestamps) {
		api.ActivityTimestamps_Init(&timestamps);
		api.ActivityTimestamps_SetStart(&timestamps, start_unix);
		api.Activity_SetTimestamps(&activity, &timestamps);
	}

	Discord_ActivityParty party{};
	int32_t party_size = int32_t(int64_t(p_activity.get("party_size", 0)));
	int32_t party_max = int32_t(int64_t(p_activity.get("party_max", 0)));
	// Discord only shows a party when it has a size and room to describe, and it needs an id.
	bool has_party = party_size > 0 && party_max > 0 && !party_id.empty();
	if (has_party) {
		api.ActivityParty_Init(&party);
		api.ActivityParty_SetId(&party, borrowed(party_id));
		api.ActivityParty_SetCurrentSize(&party, party_size);
		api.ActivityParty_SetMaxSize(&party, party_max);
		api.Activity_SetParty(&activity, &party);
	}

	api.Client_UpdateRichPresence(&s.client, &activity, presence_updated, free_nothing, nullptr);

	if (has_party) {
		api.ActivityParty_Drop(&party);
	}
	if (has_timestamps) {
		api.ActivityTimestamps_Drop(&timestamps);
	}
	if (has_assets) {
		api.ActivityAssets_Drop(&assets);
	}
	api.Activity_Drop(&activity);
}

void NossDiscord::clear_presence() {
	State &s = state();
	if (s.client_made) {
		s.api.Client_ClearRichPresence(&s.client);
	}
}

} // namespace noss
