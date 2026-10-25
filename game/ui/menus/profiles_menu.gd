class_name ProfilesMenu
extends MenuPage
## Player profiles (ACC-01): rename, edit their Driving Settings, delete, add. P1's profile and
## the profiles of joined players can't be deleted. A page (docs/UI_FLOW.md §9.1) opened from
## Settings' Players tab.


func _ready() -> void:
	title = "Profiles"
	if crumbs.is_empty():
		crumbs = ["Settings", "Profiles"]
	super._ready()


func _build() -> void:
	var in_use := Players.slots.map(func(s: PlayerSlot) -> String: return s.profile.id)
	for id in Settings.profile_ids():
		var p := Settings.get_profile(id)
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = UiKit.ROW_HEIGHT
		var name_row := UiKit.text_field("Name", p.display_name(), func(t: String) -> void:
			if not t.strip_edges().is_empty():
				p.set_value("name", t.strip_edges()), 24)
		name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_row)
		var edit := UiKit.button("Driving Settings", func() -> void: _open(p), "Driving Settings of " + p.display_name())
		row.add_child(edit)
		var del := UiKit.button("Delete", func() -> void:
			Settings.delete_profile(id)
			_rebuild(), "Delete " + p.display_name())
		del.disabled = id == Settings.primary.id or id in in_use
		row.add_child(del)
		body.add_child(row)
		# Each of the three in the focus order, top to bottom.
		_rows.append_array([name_row, edit, del])
	add_row(UiKit.button("New profile", func() -> void:
		Settings.new_profile()
		_rebuild()))


func _rebuild() -> void:
	rebuild_rows(_build)


func _open(p: PlayerProfile) -> void:
	var menu := PlayerSettingsMenu.new()
	menu.profile = p
	for slot in Players.slots:
		if slot.profile == p:
			menu.slot = slot
	menu.crumbs = crumbs + PackedStringArray(["Driving Settings"])
	open_over(menu)
