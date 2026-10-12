class_name TrackEditor
extends Control
## The track editor (EDT-01…EDT-07, docs/TRACK_EDITOR.md §2): a panel of tools on the left, the
## track in a 3D view on the right. Every control has a name and a place in the focus order; the
## view works with the mouse, the keyboard alone or a controller (D95); the status line is read
## out. The draft (Game.track_draft) and its undo history last through test drives; it's
## autosaved every AUTOSAVE_S while it changes.

signal closed

const AUTOSAVE_S := 120.0
const PANEL_WIDTH := 640
const FONT_SIZE := 24
const TOOL_ORDER := ["Road", "Terrain", "Paint", "Props", "Race", "Check", "File"]

var draft: TrackDraft
var view := EditorView.new()
var tools := {} # title -> EditorTool
var tool: EditorTool
var _title: Label
var _tool_bar: HFlowContainer
var _tool_buttons := {}
var _content: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _hint: Label
var _actions: Array = []
var _overlay: Control
var _autosave_time := 0.0
var _autosaved_version := -1


func _ready() -> void:
	var t := UiKit.theme().duplicate() as Theme
	t.default_font_size = FONT_SIZE
	theme = t
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 0)
	add_child(split)
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	split.add_child(left)
	var column := VBoxContainer.new()
	left.add_child(column)
	_title = UiKit.label("", 34)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_title)
	_tool_bar = HFlowContainer.new()
	column.add_child(_tool_bar)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_status = UiKit.label("", 22)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	column.add_child(_status)
	var row := HFlowContainer.new()
	column.add_child(row)
	_actions = [
		UiKit.button("Test drive", func() -> void: test_drive(false), "Drive it from the cursor (F5)"),
		UiKit.button("Undo", undo, "Ctrl+Z"),
		UiKit.button("Redo", redo, "Ctrl+Y"),
		UiKit.button("Save", save, "Save to your tracks"),
		UiKit.button("Exit", exit_editor, "Back to the title screen"),
	]
	for b: Button in _actions:
		b.custom_minimum_size = Vector2(0, 52)
		row.add_child(b)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(view)
	_hint = UiKit.label("", 20)
	_hint.modulate = Color(1, 1, 1, 0.7)
	right.add_child(_hint)
	view.pointer.connect(_on_pointer)
	view.action.connect(_on_view_action)
	view.zoomed.connect(func() -> void:
		if tool:
			tool.refresh_gizmos())

	draft = Game.track_draft
	if draft == null:
		var autosaved := TrackDraft.autosaves()
		draft = TrackDraft.blank()
		if not autosaved.is_empty() and not Game.dev.has("editor-track") and not Game.dev.has("editor-template"):
			_offer_restore(autosaved[0])
		Game.track_draft = draft
	_open_draft(draft)


## Shows `d` (a new or restored draft) in the editor.
func _open_draft(d: TrackDraft) -> void:
	if draft and draft != d and draft.changed.is_connected(_on_draft_changed):
		draft.changed.disconnect(_on_draft_changed)
	draft = d
	Game.track_draft = d
	_autosaved_version = d.history.version()
	view.open_draft(d, String(d.layout.get("style", StyleProfile.DEFAULT)))
	d.changed.connect(_on_draft_changed)
	_make_tools()
	var state: Dictionary = d.view
	if state.has("camera"):
		view.camera.restore(state.camera)
	else:
		_frame_track()
	show_tool(String(state.get("tool", "Road" if tools.has("Road") else "File")))
	_update_title()


## Every tool, the ones built so far.
func _make_tools() -> void:
	tools.clear()
	for child in _tool_bar.get_children():
		child.queue_free()
	_tool_buttons.clear()
	for t: EditorTool in [FileTool.new()] + _extra_tools():
		t.editor = self
		t.draft = draft
		t.view = view
		tools[t.title()] = t
	for title: String in TOOL_ORDER:
		if not tools.has(title):
			continue
		var b := UiKit.button(title, show_tool.bind(title))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 48)
		_tool_bar.add_child(b)
		_tool_buttons[title] = b


## Tools added by later steps (Road, Terrain, ...).
func _extra_tools() -> Array:
	var out := []
	for path: String in ["res://game/editor/track_editor/tools/road_tool.gd", "res://game/editor/track_editor/tools/terrain_tool.gd",
			"res://game/editor/track_editor/tools/paint_tool.gd", "res://game/editor/track_editor/tools/props_tool.gd",
			"res://game/editor/track_editor/tools/race_tool.gd", "res://game/editor/track_editor/tools/check_tool.gd"]:
		if ResourceLoader.exists(path):
			out.append((load(path) as GDScript).new())
	return out


func show_tool(title: String) -> void:
	if not tools.has(title):
		title = tools.keys()[0]
	if tool:
		tool.deactivate()
	tool = tools[title]
	for t: String in _tool_buttons:
		(_tool_buttons[t] as Button).set_pressed_no_signal(t == title)
	tool.activate()
	refresh_panel()
	tool.refresh_gizmos()
	_hint.text = tool.hint()


## Rebuilds the tool's panel (after a change that alters what it shows).
func refresh_panel(focus_first := false) -> void:
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_text := UiKit.text_of(owner) if owner is Button else ""
	var focus_name := String(owner.accessibility_name) if owner else ""
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var controls: Array = tool.panel()
	for c: Control in controls:
		_content.add_child(c)
	var chain: Array = _tool_buttons.values() + controls + _actions
	UiKit.chain_focus(chain, false)
	# Back to the control that had the focus, when it's still there.
	for c: Control in controls:
		for f: Control in [c] + c.find_children("*", "Control", true, false):
			if f.focus_mode != Control.FOCUS_NONE and owner and owner.get_parent() == null and (UiKit.text_of(f as Button) == focus_text if f is Button else String(f.accessibility_name) == focus_name):
				UiKit.focus_later(f)
				return
	if focus_first and not controls.is_empty():
		UiKit.focus_later(_tool_buttons.get(tool.title(), controls[0]))


func say(text: String) -> void:
	_status.text = text


func _update_title() -> void:
	_title.text = String(draft.info.get("name", "Track")) + (" •" if draft.dirty() else "")
	_title.accessibility_name = _title.text


func _on_pointer(e: Dictionary) -> void:
	if _overlay:
		return
	tool.pointer(e)


func _on_view_action(name: String) -> void:
	if _overlay:
		return
	match name:
		"undo":
			undo()
		"redo":
			redo()
		"test":
			test_drive(false)
		"test_grid":
			test_drive(true)
		"panel":
			UiKit.focus_later(_tool_buttons.get(tool.title(), _actions[0]))
		_:
			if name.begins_with("tool_"):
				var i := int(name.trim_prefix("tool_")) - 1
				var titles := TOOL_ORDER.filter(func(t: String) -> bool: return tools.has(t))
				if i < titles.size():
					show_tool(titles[i])
					view.grab_focus()
					say(titles[i])
			elif not tool.action(name) and name == "delete":
				say("Nothing to delete")


func _on_draft_changed(what: StringName, _info: Dictionary) -> void:
	_update_title()
	for t: EditorTool in tools.values():
		t.draft_changed(what)
	tool.refresh_gizmos()


func undo() -> void:
	var name := draft.undo()
	say("Undone: " + name if name else "Nothing to undo")
	refresh_panel()


func redo() -> void:
	var name := draft.redo()
	say("Redone: " + name if name else "Nothing to redo")
	refresh_panel()


## Saves to the library (minimap and thumbnail first). Errors block it (TrackValidator).
func save() -> void:
	var problems := _errors()
	if not problems.is_empty():
		say("Can't save: " + problems[0])
		return
	await render_images()
	var r := draft.save()
	if r.ok:
		draft.delete_autosave()
		say("Saved" if not r.unchanged else "No changes")
	else:
		say(String(r.error))
	_update_title()


## The validator's errors ("" list without a validator yet).
func _errors() -> Array:
	if ResourceLoader.exists("res://game/world/track_validator.gd"):
		var v: GDScript = load("res://game/world/track_validator.gd")
		return (v.call("check", draft) as Array).filter(func(p: Dictionary) -> bool: return p.level == "error").map(func(p: Dictionary) -> String: return p.text)
	return []


## minimap.png drawn from the road; thumb.png from the view, without the gizmos.
func render_images() -> void:
	var t := draft.track()
	if t.samples.size() > 2:
		draft.images["minimap.png"] = minimap(t).save_png_to_buffer()
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	view.gizmos.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := view.viewport.get_texture().get_image()
	view.gizmos.visible = true
	if img and img.get_width() > 0:
		var w := 512
		var h := int(512.0 * img.get_height() / img.get_width())
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		draft.images["thumb.png"] = img.save_png_to_buffer()


## The road from above on 256 px.
static func minimap(t: TrackData) -> Image:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var box := Rect2(Vector2(t.samples[0].x, t.samples[0].z), Vector2.ZERO)
	for p in t.samples:
		box = box.expand(Vector2(p.x, p.z))
	var fit := 230.0 / maxf(box.size.x, box.size.y)
	var offset := (Vector2(256, 256) - box.size * fit) / 2.0
	for k in t.samples.size():
		var a := t.samples[k]
		var at := offset + (Vector2(a.x, a.z) - box.position) * fit
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var px := Vector2i(at) + Vector2i(dx, dy)
				if Rect2i(0, 0, 256, 256).has_point(px):
					img.set_pixelv(px, Color(0.9, 0.9, 0.88) if absi(dx) < 2 and absi(dy) < 2 else Color(0, 0, 0))
	return img


func test_drive(from_grid: bool) -> void:
	if not Game.has_method("start_test_drive"):
		say("Test drive comes next")
		return
	var t := draft.track()
	if t.samples.size() < 3:
		say("Add at least 3 points first")
		return
	remember_view()
	Game.call("start_test_drive", draft, null if from_grid else view.pick(view.cursor()).position)


## Keeps the camera, tool and selection for coming back.
func remember_view() -> void:
	draft.view = { "camera": view.camera.state(), "tool": tool.title() if tool else "Road" }
	if tool and tool.has_method("selection_state"):
		draft.view.merge(tool.call("selection_state"))


func exit_editor() -> void:
	if draft.dirty():
		_ask("Save changes to %s?" % draft.info.name, [
			["Save", func() -> void:
				_close_overlay()
				await save()
				if not draft.dirty():
					_leave()],
			["Don't save", func() -> void:
				draft.delete_autosave()
				_leave()],
			["Cancel", _close_overlay],
		])
		return
	_leave()


func _leave() -> void:
	Game.track_draft = null
	closed.emit()
	Game.go_title()


func _offer_restore(entry: Dictionary) -> void:
	_ask("Restore %s from your last session?" % entry.name, [
		["Restore", func() -> void:
			_close_overlay()
			var d := TrackDraft.from_autosave(entry)
			if d:
				_open_draft(d)
				say("Restored")
			else:
				say("Couldn't restore it")],
		["Start new", func() -> void:
			_close_overlay()
			TrackDraft.remove_autosave(String(entry.dir))],
	])


## A question over the editor: `choices` are [text, callable].
func _ask(question: String, choices: Array) -> void:
	_close_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var list := UiKit.panel(_overlay, question, 760)
	var buttons := []
	for c: Array in choices:
		var b := UiKit.button(String(c[0]), c[1])
		list.add_child(b)
		buttons.append(b)
	add_child(_overlay)
	UiKit.chain_focus(buttons)


func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	if is_inside_tree():
		UiKit.focus_later(_tool_buttons.get(tool.title() if tool else "", view))


## Shows the whole track (or the terrain) from above at an angle.
func _frame_track() -> void:
	var t := draft.track()
	var box := Rect2()
	if t.samples.size() > 2:
		box = Rect2(Vector2(t.samples[0].x, t.samples[0].z), Vector2.ZERO)
		for p in t.samples:
			box = box.expand(Vector2(p.x, p.z))
	elif draft.terrain:
		box = draft.terrain.area().grow(-draft.terrain.area().size.x * 0.3)
	var c := box.get_center()
	var h := draft.terrain.height_at(c.x, c.y) if draft.terrain else 0.0
	view.camera.set_pivot(Vector3(c.x, h, c.y), true)
	view.camera.focus(Vector3(c.x, h, c.y), maxf(box.size.length() * 0.75, 120.0))


func _process(delta: float) -> void:
	_autosave_time += delta
	if _autosave_time >= AUTOSAVE_S:
		_autosave_time = 0.0
		if draft.history.version() != _autosaved_version and not PlayerProfile.read_only:
			_autosaved_version = draft.history.version()
			draft.autosave_async(self, func(err: String) -> void: say("Autosave failed: " + err if err else "Autosaved"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.ctrl_pressed and key.physical_keycode == KEY_Z:
			redo() if key.shift_pressed else undo()
			get_viewport().set_input_as_handled()
		elif key.ctrl_pressed and key.physical_keycode == KEY_Y:
			redo()
			get_viewport().set_input_as_handled()
		elif key.ctrl_pressed and key.physical_keycode == KEY_S:
			save()
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_F5:
			test_drive(key.shift_pressed)
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_F6:
			view.grab_focus()
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _overlay:
			_close_overlay()
		else:
			exit_editor()


func _exit_tree() -> void:
	if draft and draft.changed.is_connected(_on_draft_changed):
		draft.changed.disconnect(_on_draft_changed)


## The File tool: the track's name, author and license; save, copy, a new track or another.
class FileTool:
	extends EditorTool

	func title() -> String:
		return "File"

	func hint() -> String:
		return "Ctrl+S saves. Esc leaves."

	func panel() -> Array:
		var t := draft.track()
		var out := []
		out.append(UiKit.text_field("Name", String(draft.info.name), func(v: String) -> void:
			if v.strip_edges():
				draft.set_info("name", v.strip_edges().left(64)), 64))
		out.append(UiKit.text_field("Author", String(draft.info.author), func(v: String) -> void:
			if v.strip_edges():
				draft.set_info("author", v.strip_edges().left(64)), 64))
		out.append(UiKit.spinner("License", TrackDraft.LICENSES, String(draft.info.license), func(v: String) -> void: draft.set_info("license", v),
			"Personal-use tracks stay offline"))
		var facts := "%.2f km · %d points" % [t.length / 1000.0, draft.points().size()] if t.samples.size() > 2 else "%d points" % draft.points().size()
		facts += " · saved" if not draft.dirty() and draft.path else " · not saved"
		out.append(UiKit.label(facts, 22))
		out.append(UiKit.button("Save", func() -> void: editor.save(), "Save to your tracks"))
		out.append(UiKit.button("Save as a copy", func() -> void:
			draft.id = PackageWriter.new_uuid()
			draft.path = ""
			draft.set_info("name", "%s copy" % draft.info.name)
			editor.save(), "A new track from this one"))
		out.append(UiKit.button("New track", _new, "Start again"))
		out.append(UiKit.button("Open track", _open, "Edit another track"))
		out.append(UiKit.button("Show track files", func() -> void:
			DirAccess.make_dir_recursive_absolute(TrackLibrary.user_dir)
			OS.shell_open(ProjectSettings.globalize_path(TrackLibrary.user_dir)), "Your .nosstrack files, to share"))
		return out

	func draft_changed(what: StringName) -> void:
		if what == &"info" and editor.tool == self:
			editor.refresh_panel()

	func _new() -> void:
		var choices := []
		for t: Array in TrackTemplates.list():
			choices.append([String(t[1]), func() -> void:
				editor._close_overlay()
				editor._open_draft(TrackTemplates.make(String(t[0])))
				editor.say("New track")])
		choices.append(["Cancel", editor._close_overlay])
		editor._ask("New track", choices)

	func _open() -> void:
		var choices := []
		for e in TrackLibrary.list():
			var path: String = e.path
			choices.append([TrackLibrary.label(e) + (" (a copy)" if e.builtin else ""), func() -> void:
				editor._close_overlay()
				var pkg := TrackLoader.load_package(path)
				if not pkg.ok():
					editor.say(pkg.error)
					return
				editor._open_draft(TrackDraft.from_package(pkg))
				editor.say("Opened " + pkg.display_name())])
		choices.append(["Cancel", editor._close_overlay])
		editor._ask("Open track", choices)
