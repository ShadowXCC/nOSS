class_name ChatPanel
extends VBoxContainer
## Online chat (MP-07, docs/ACCESSIBILITY.md §2): the recent lines, a message field and quick
## lines for controller players. New lines are announced to screen readers (a live region) and
## read out when P1's menu narration is on. Lines are added as plain text, never as BBCode.

## The focusable controls, top to bottom, for the menu's focus chain.
var focusables: Array[Control] = []
## Which of this game's players speaks.
var local_index := 0

var _log: RichTextLabel
var _announce: Label
var _input: LineEdit
var _quick := 0


func _ready() -> void:
	_log = RichTextLabel.new()
	_log.bbcode_enabled = false
	_log.scroll_following = true
	_log.fit_content = false
	_log.custom_minimum_size = Vector2(0, 200)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 24)
	_log.focus_mode = Control.FOCUS_NONE
	_log.accessibility_name = "Chat"
	add_child(_log)
	_announce = UiKit.label("", 1)
	_announce.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	_announce.modulate = Color(1, 1, 1, 0)
	add_child(_announce)
	var row := UiKit.text_field("Say", "", func(_t: String) -> void: pass, NetChat.MAX_CHARS,
		"Type a message, then Enter", func(t: String) -> void: _send(t))
	add_child(row)
	_input = row.get_child(1)
	var quick_items := []
	for i in NetChat.QUICK.size():
		quick_items.append([i, NetChat.QUICK[i]])
	var quick := UiKit.spinner("Quick chat", quick_items, 0, func(i: int) -> void: _quick = i, "Pick a line")
	var send_quick := UiKit.button("Send quick", func() -> void: Net.say(NetChat.QUICK[_quick], local_index), "Sends the quick chat line")
	var quick_row := HBoxContainer.new()
	quick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick_row.add_child(quick)
	quick_row.add_child(send_quick)
	add_child(quick_row)
	focusables = [_input, quick, send_quick]
	for line in Net.chat_log:
		_append(line, false)
	Net.chat_line.connect(_on_line)


func _exit_tree() -> void:
	if Net.chat_line.is_connected(_on_line):
		Net.chat_line.disconnect(_on_line)


func _send(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	Net.say(text, local_index)
	_input.clear()


func _on_line(line: Dictionary) -> void:
	_append(line, true)


func _append(line: Dictionary, announce: bool) -> void:
	var text := String(line.text)
	var spoken := text
	if line.kind == "chat":
		_log.push_color(Color.from_string(String(line.color), Color.WHITE))
		_log.add_text(String(line.name) + ": ")
		_log.pop()
		spoken = "%s: %s" % [line.name, text]
	else:
		_log.push_color(UiKit.ACCENT)
	_log.add_text(text)
	if line.kind != "chat":
		_log.pop()
	_log.newline()
	if announce:
		_announce.text = spoken
		if Narrator.menus_on(Settings.primary):
			Narrator.say(spoken)
