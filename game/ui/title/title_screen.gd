extends Control
## Title screen.

@onready var _version_label: Label = %VersionLabel
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version")
	_quit_button.pressed.connect(get_tree().quit)
	_quit_button.grab_focus()
