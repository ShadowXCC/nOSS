class_name SettingsMenu
extends TabbedPage
## Game settings, shared by everyone on this machine (docs/UI_FLOW.md §9.1), in tabs: Display,
## Sound, Splitscreen, General and Players. Each player's own settings (assists, comfort, HUD,
## controls) live in their profile (PlayerSettingsMenu, "Driving Settings"), reached from the
## Players tab, the Players screen and the pause menu. Changes apply and save immediately.

const RESETS := {
	"Display": ["graphics", "fullscreen"],
	"Sound": ["master_volume", "vol_own_engine", "vol_other_engines", "vol_tires", "vol_effects", "vol_ambience",
		"vol_music", "vol_ui", "vol_spotter", "vol_narration", "mono"],
	"Splitscreen": ["split_two", "split_three", "split_audio", "auto_resolution"],
	"General": ["units", "discord_presence"],
}

## Opened in a player's view mid-session: no Players tab (renaming needs a keyboard).
var in_session := false


func _ready() -> void:
	title = "Settings"
	crumbs = ["Pause", "Settings"] if in_session else ["Settings"]
	tabs = ["Display", "Sound", "Splitscreen", "General"] if in_session else ["Display", "Sound", "Splitscreen", "General", "Players"]
	super._ready()


func _build_tab(which: String) -> void:
	match which:
		"Display":
			add_row(UiKit.spinner("Graphics", [["low", "Low"], ["medium", "Medium"], ["high", "High"]], Settings.graphics,
				func(v: String) -> void: Settings.set_value("graphics", v), "Detail and smoothing. Low runs fastest"))
			add_row(UiKit.check("Fullscreen", Settings.fullscreen, func(on: bool) -> void: Settings.set_value("fullscreen", on)))
		"Sound":
			add_row(UiKit.slider("Volume", Settings.master_volume, func(v: float) -> void: Settings.set_value("master_volume", v), "Everything"))
			for item: Array in [["vol_own_engine", "Own engine"], ["vol_other_engines", "Other engines"], ["vol_tires", "Tires and wind"],
					["vol_effects", "Effects"], ["vol_ambience", "Ambience"], ["vol_music", "Music"], ["vol_ui", "Menus"],
					["vol_spotter", "Spotter voice"], ["vol_narration", "Narration"]]:
				var key: String = item[0]
				add_row(UiKit.slider(item[1], float(Settings.get(key)), func(v: float) -> void: Settings.set_value(key, v)))
			add_row(UiKit.check("Mono", Settings.mono, func(on: bool) -> void: Settings.set_value("mono", on), "Everything in both ears"))
		"Splitscreen":
			add_row(UiKit.spinner("2 players", [["stacked", "One above the other"], ["side", "Side by side"]], Settings.split_two,
				func(v: String) -> void: Settings.set_value("split_two", v)))
			add_row(UiKit.spinner("3 players", [["wide", "Wide top"], ["map", "With track map"]], Settings.split_three,
				func(v: String) -> void: Settings.set_value("split_three", v)))
			add_row(UiKit.spinner("Sound from", [["all", "Every player"], ["p1", "P1 only"]], Settings.split_audio,
				func(v: String) -> void: Settings.set_value("split_audio", v)))
			add_row(UiKit.check("Auto resolution", Settings.auto_resolution, func(on: bool) -> void: Settings.set_value("auto_resolution", on),
				"Lowers each view's detail to hold the frame rate"))
		"General":
			add_row(UiKit.spinner("Units", [["metric", "km/h"], ["imperial", "mph"]], Settings.units,
				func(v: String) -> void: Settings.set_value("units", v), "Speeds and distances"))
			add_row(UiKit.check("Discord status", Settings.discord_presence,
				func(on: bool) -> void: Settings.set_value("discord_presence", on), "Show what you're playing on Discord"))
			var clear := UiKit.button("Clear downloads (%s)" % size_text(ContentStore.size_bytes()), _ask_clear,
				"Cars and tracks from online games")
			if _online():
				clear.disabled = true
				clear.accessibility_description = "Not while online"
			add_row(clear)
		"Players":
			add_row(UiKit.button("Driving Settings", _open_player, "%s: assists, comfort, HUD and controls" % Settings.primary.display_name()))
			add_row(UiKit.button("Profiles", _open_profiles, "Rename, add or delete players"))


func _can_reset(which: String) -> bool:
	return RESETS.has(which)


func _reset(which: String) -> void:
	Settings.reset_keys(RESETS[which])


## "12.3 MB".
static func size_text(bytes: int) -> String:
	if bytes >= 1 << 30:
		return "%.2f GB" % (bytes / float(1 << 30))
	return "%.1f MB" % (bytes / float(1 << 20)) if bytes > 0 else "0 MB"


## Online games share the downloads folder (a host serves from it).
func _online() -> bool:
	return Net.online()


func _ask_clear() -> void:
	var confirm := ConfirmPage.new()
	confirm.title = "Clear downloads?"
	confirm.crumbs = crumbs + PackedStringArray(["Clear downloads"])
	confirm.detail = "%s of cars and tracks from online games. They download again when needed." % size_text(ContentStore.size_bytes())
	confirm.no_text = "Keep"
	confirm.no_hint = "Leave them"
	confirm.yes_text = "Clear"
	confirm.yes_hint = "Delete them now"
	confirm.confirmed.connect(func() -> void:
		ContentStore.clear()
		confirm.closed.emit()
		show_tab(tab, "Clear downloads"))
	open_over(confirm)


func _open_player() -> void:
	var menu := PlayerSettingsMenu.new()
	menu.profile = Settings.primary
	menu.slot = Players.slots[0] if not Players.slots.is_empty() and Players.slots[0].profile == Settings.primary else null
	menu.crumbs = crumbs + PackedStringArray(["Driving Settings"])
	open_over(menu)


func _open_profiles() -> void:
	open_over(ProfilesMenu.new())
