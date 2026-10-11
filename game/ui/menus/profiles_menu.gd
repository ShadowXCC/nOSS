class_name ProfilesMenu
extends Control
## Player profiles (ACC-01): rename, edit their settings, delete, add. P1's profile and the
## profiles of joined players can't be deleted.

signal closed

var _rows: Array = []


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	# Freed after this frame: the button that asked for the rebuild may still be signalling.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rows.clear()
	var list := UiKit.panel(self, "Profiles", 980)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var in_use := Players.slots.map(func(s: PlayerSlot) -> String: return s.profile.id)
	for id in Settings.profile_ids():
		var p := Settings.get_profile(id)
		var row := HBoxContainer.new()
		var name_row := UiKit.text_field("Name", p.display_name(), func(t: String) -> void:
			if not t.strip_edges().is_empty():
				p.set_value("name", t.strip_edges()), 24)
		name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_row)
		var edit := UiKit.button("Settings", func() -> void: _open(p), "Settings of " + p.display_name())
		row.add_child(edit)
		var del := UiKit.button("Delete", func() -> void:
			Settings.delete_profile(id)
			_build(), "Delete " + p.display_name())
		del.disabled = id == Settings.primary.id or id in in_use
		row.add_child(del)
		rows.add_child(row)
		_rows.append_array([name_row, edit, del])
	var add := UiKit.button("New profile", func() -> void:
		Settings.new_profile()
		_build())
	list.add_child(add)
	_rows.append(add)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(back)
	UiKit.chain_focus(_rows)


func _open(p: PlayerProfile) -> void:
	var menu := PlayerSettingsMenu.new()
	menu.profile = p
	for slot in Players.slots:
		if slot.profile == p:
			menu.slot = slot
	UiKit.open_sub(self, menu, func() -> void: UiKit.chain_focus(_rows))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and get_child_count() > 0 and get_child(0).visible:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit:
			return
		get_viewport().set_input_as_handled()
		closed.emit()
