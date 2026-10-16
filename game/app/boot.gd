extends Node
## First scene. Checks the native core, then opens the title screen.

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"


func _ready() -> void:
	var core := core_version()
	if core.is_empty():
		push_error("noss_core not loaded")
	print("nOSS %s (core %s)" % [game_version(), core if core else "missing"])
	if Game.dedicated:
		Game.start_server.call_deferred()
	elif Game.dev.has("bay"):
		Game.open_fitting_bay.call_deferred()
	elif Game.dev.has("garage"):
		Game.open_garage.call_deferred()
	elif Game.dev.has("editor"):
		Game.open_dev_editor.call_deferred()
	elif Game.dev.has("race") or Game.dev.has("time-trial") or Game.dev.has("highway") or Game.dev_kart():
		Game.start_dev_event.call_deferred()
	elif Game.first_scene().is_empty():
		Game.start_free_drive.call_deferred()
	else:
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)


static func game_version() -> String:
	return ProjectSettings.get_setting("application/config/version")


## Version of the noss_core GDExtension, or "" if it isn't loaded.
static func core_version() -> String:
	if not ClassDB.class_exists(&"NossCore"):
		return ""
	return ClassDB.class_call_static(&"NossCore", &"version")
