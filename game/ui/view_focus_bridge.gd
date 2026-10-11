class_name ViewFocusBridge
extends Control
## Screen readers follow the player who acted last (D57). Godot tells the screen reader about one
## focused control per OS window, and a player's menu lives inside their view's SubViewport, so
## on its own the window would report nothing useful. Two of these sit in the main window and
## take turns holding its focus while a view's control has focus, each reading out as that
## control: its role, name, description, checked state or value. Taking turns makes every
## change a real focus change, which screen readers announce. Activating one presses the
## control it stands for.

static var _target: Control
static var _flip := 0

## Which control this one stands for while it has focus.
var stands_for: Control


## Puts the pair in the main window (Players does this at start).
static func install(root: Window) -> void:
	for i in 2:
		var b := ViewFocusBridge.new()
		b.name = "ViewFocusBridge%d" % i
		root.add_child.call_deferred(b)


## Only while a screen reader is reading (or --screen-reader for checks): holding the window's
## focus takes it from the view, so every player input gives it back first (Players.push_action).
static func enabled() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return Game.dev.has("screen-reader") or DisplayServer.accessibility_screen_reader_active() == 1


## A player's view focused `c` (or its state changed): the screen reader hears it. Call it after
## the view has handled the input.
static func point_at(c: Control) -> void:
	_target = c
	if not enabled():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var root := tree.root
	var current := root.gui_get_focus_owner()
	# Never take focus from a real menu in the main window.
	if current != null and not current is ViewFocusBridge:
		return
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		if current is ViewFocusBridge:
			current.release_focus()
		return
	_flip = 1 - _flip
	var bridge := root.get_node_or_null("ViewFocusBridge%d" % _flip) as ViewFocusBridge
	if bridge == null:
		return
	bridge.stands_for = c
	bridge.visible = true
	bridge.focus_mode = Control.FOCUS_ALL
	bridge.grab_focus()
	bridge.queue_accessibility_update()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2.ONE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_idle()
	focus_exited.connect(_idle)


## Not standing for anything: hidden from screen readers and not focusable.
func _idle() -> void:
	focus_mode = Control.FOCUS_NONE
	visible = false


func _process(_delta: float) -> void:
	# The menu it stood for went away: let go of the window's focus.
	if has_focus() and (stands_for == null or not is_instance_valid(stands_for) or not stands_for.is_visible_in_tree()):
		release_focus()


func _notification(what: int) -> void:
	if what != NOTIFICATION_ACCESSIBILITY_UPDATE or stands_for == null or not is_instance_valid(stands_for):
		return
	var ae := get_accessibility_element()
	var c := stands_for
	var role := AccessibilityServer.ROLE_BUTTON
	if c is CheckButton or c is CheckBox:
		role = AccessibilityServer.ROLE_CHECK_BOX
	elif c is Range:
		role = AccessibilityServer.ROLE_SLIDER
	elif c is LineEdit:
		role = AccessibilityServer.ROLE_TEXT_FIELD
	AccessibilityServer.update_set_role(ae, role)
	var label := String(c.accessibility_name)
	if label.is_empty() and "text" in c:
		label = String(c.get("text"))
	AccessibilityServer.update_set_name(ae, label)
	AccessibilityServer.update_set_description(ae, String(c.accessibility_description))
	if c is BaseButton and (c as BaseButton).toggle_mode:
		AccessibilityServer.update_set_checked(ae, (c as BaseButton).button_pressed)
	if c is Range:
		var r := c as Range
		AccessibilityServer.update_set_num_range(ae, r.min_value, r.max_value)
		AccessibilityServer.update_set_num_step(ae, r.step)
		AccessibilityServer.update_set_num_value(ae, r.value)
	if c is BaseButton:
		AccessibilityServer.update_add_action(ae, AccessibilityServer.ACTION_CLICK, func(_data: Variant) -> void:
			if is_instance_valid(c):
				(c as BaseButton).pressed.emit())
