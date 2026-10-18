class_name DownloadsMenu
extends Control
## What a host sent you (docs/NETWORKING.md §7): the cars and tracks sitting in the content
## cache, to keep in the garage or your tracks, or to write out as a file. The cache is thrown
## away from time to time, so anything worth keeping has to be saved out of it.

signal closed
## The file a download landed in, once it's in the garage or the track library.
signal saved(path)

## "cars" or "tracks".
var kind := "cars"

var _status: Label
## The "already here" question, over the list.
var _ask: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var cars := kind == "cars"
	var panel := UiKit.panel(self, "Downloaded cars" if cars else "Downloaded tracks", 900)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	var controls := []
	var entries := ContentImport.list(kind)
	if entries.is_empty():
		rows.add_child(UiKit.label("Nothing downloaded yet. Cars and tracks land here when you join a host.", 24))
	for e: Dictionary in entries:
		var row := HBoxContainer.new()
		var name_label := UiKit.label(ContentImport.label(e), 24)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		for b: Button in [
			UiKit.button("Save to garage" if cars else "Save to my tracks", _save.bind(e), "Keep it as your own"),
			UiKit.button("Export…", _export.bind(e), "Write it out as a file"),
		]:
			b.custom_minimum_size = Vector2(0, 52)
			b.disabled = not e.complete
			if b.disabled:
				b.focus_mode = Control.FOCUS_NONE
			else:
				controls.append(b)
			row.add_child(b)
		rows.add_child(row)

	_status = UiKit.label("", 22)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	panel.add_child(_status)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	panel.add_child(back)
	controls.append(back)
	UiKit.chain_focus(controls)


func _save(e: Dictionary) -> void:
	var id := String((e.manifest as Dictionary).get("id", ""))
	var owned := GarageFiles.with_id(id) if kind == "cars" else ContentImport.owned_track(id)
	if owned.is_empty():
		_write(e, false)
	else:
		_ask_about_copy(e, owned)


## It's already here: write over that one, or keep both.
func _ask_about_copy(e: Dictionary, owned: String) -> void:
	_close_ask()
	var menu := Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var list := UiKit.panel(menu, "%s is already yours." % String((e.manifest as Dictionary).get("name", "That one")), 760)
	var choices := [
		UiKit.button("Replace my copy", func() -> void:
			_close_ask()
			_write(e, false), "Writes over " + owned.get_file()),
		UiKit.button("Keep both", func() -> void:
			_close_ask()
			_write(e, true), "Saves it beside the one you have"),
		UiKit.button("Cancel", _close_ask),
	]
	for b: Button in choices:
		list.add_child(b)
	_ask = menu
	add_child(menu)
	UiKit.chain_focus(choices)


func _close_ask() -> void:
	if is_instance_valid(_ask):
		_ask.queue_free()
	_ask = null


func _write(e: Dictionary, as_copy: bool) -> void:
	var result := ContentImport.save_car(String(e.dir), as_copy) if kind == "cars" else ContentImport.save_track(String(e.dir), as_copy)
	if not result.ok:
		_say(String(result.error))
		return
	saved.emit(String(result.path))
	_say("Saved as " + String(result.path).get_file())


func _export(e: Dictionary) -> void:
	var name := String((e.manifest as Dictionary).get("name", "download"))
	UiKit.save_dialog(self, "Export " + name, ".noss" if kind == "cars" else ".nosstrack", name, func(dest: String) -> void:
		var result := ContentImport.export_package(kind, String(e.dir), dest)
		_say("Exported to " + dest.get_file() if result.ok else String(result.error)))


func _say(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_ask):
			_close_ask()
		else:
			closed.emit()
