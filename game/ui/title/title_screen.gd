extends Control
## Title screen.

@onready var _version_label: Label = %VersionLabel
@onready var _drive_button: Button = %FreeDriveButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton

var _picker: CarPicker
var _settings: SettingsMenu


func _ready() -> void:
	theme = UiKit.theme()
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version")
	_drive_button.accessibility_description = "Drive the Proving Ground"
	_drive_button.pressed.connect(_open_picker)
	_settings_button.pressed.connect(_open_settings)
	_quit_button.pressed.connect(get_tree().quit)
	for b: Button in [_drive_button, _settings_button, _quit_button]:
		b.accessibility_name = b.text
	UiKit.chain_focus([_drive_button, _settings_button, _quit_button])
	match Game.dev.get("menu", ""): # dev: open a menu directly
		"cars": _open_picker()
		"settings": _open_settings()


func _open_picker() -> void:
	_picker = CarPicker.new()
	_picker.current = String(Settings.profile.get("last_car", ""))
	_picker.picked.connect(func(path: String) -> void: Game.start_free_drive(path))
	_picker.closed.connect(func() -> void:
		_picker.queue_free()
		_drive_button.grab_focus())
	add_child(_picker)


func _open_settings() -> void:
	_settings = SettingsMenu.new()
	_settings.closed.connect(func() -> void:
		_settings.queue_free()
		_settings_button.grab_focus())
	add_child(_settings)
