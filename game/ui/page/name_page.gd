class_name NamePage
extends MenuPage
## Asks for a name (Custom's "Save preset", docs/UI_FLOW.md §6.1): a "Name" field, and "Save" in
## the action bar. Enter in the field saves too. The opener closes it (or shows why not in
## `status`).

## The name typed (not empty).
signal named(text: String)

var value := ""
var save_text := "Save"
var save_hint := ""
var status: Label
var _field: LineEdit


func _build() -> void:
	var row := UiKit.text_field("Name", value, func(t: String) -> void: value = t, 40, "", _submit)
	row.name = "Name"
	_field = row.get_child(1) as LineEdit
	add_row(row)
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"PageCrumb"
	status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	add_footer(status)
	var save := UiKit.button(save_text, func() -> void: _submit(value), save_hint)
	save.name = "Save"
	add_action(save)


func _submit(text: String) -> void:
	if text.strip_edges().is_empty():
		status.text = "Type a name"
		return
	named.emit(text.strip_edges())
