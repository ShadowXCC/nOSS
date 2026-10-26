class_name PasswordPage
extends MenuPage
## A locked server's password (docs/UI_FLOW.md §7.4), asked before joining: "<server> needs a
## password.", the "Password" field, and "Join" in the action bar (Enter in the field joins too).
## The Join page joins with it, and says here how it went: "Wrong password" keeps the page up.

signal submitted(password: String)

var server_name := ""
var status: Label
var _typed := ""


func _init() -> void:
	back_hint = "Back to Join"


func _ready() -> void:
	title = "Password"
	crumbs = ["Drive Online", "Join", "Password"]
	super._ready()


func _build() -> void:
	add_text("%s needs a password." % server_name, true)
	var row := UiKit.text_field("Password", "", func(t: String) -> void: _typed = t, 128, "", _submit, true)
	row.name = "Password"
	add_row(row)
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"PageCrumb"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	add_footer(status)
	var join := UiKit.button("Join", func() -> void: _submit(_typed), "Join " + server_name)
	join.name = "Join"
	add_action(join)


func _submit(text: String) -> void:
	if text.is_empty():
		status.text = "Type the password"
		return
	submitted.emit(text)
