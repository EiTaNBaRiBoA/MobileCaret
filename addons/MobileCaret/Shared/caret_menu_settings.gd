# The menu settings of one control, kept on the control itself (as metadata), so they work for any
# control: a LineEdit, a TextEdit, a custom control with a delegate, an image with caret_image_menu.
# Set them through MobileCaretToolbar (set_control_menu, set_control_actions, clear_control_settings).
class_name caret_menu_settings extends RefCounted

# Whether the menu shows at all for the control (bool; missing means true).
const META_MENU: StringName = &"mobile_caret_menu"
# The built-in buttons the control may have (Array of StringName: cut, copy, paste, select_all,
# delete, undo, redo, share); missing means all of them.
const META_ACTIONS: StringName = &"mobile_caret_actions"


static func set_menu_enabled(control: Control, enabled: bool) -> void:
	if is_instance_valid(control):
		control.set_meta(META_MENU, enabled)

static func is_menu_enabled(control: Control) -> bool:
	return not is_instance_valid(control) or bool(control.get_meta(META_MENU, true))

static func set_actions(control: Control, actions: Array) -> void:
	if not is_instance_valid(control):
		return
	var names: Array[StringName] = []
	for action: Variant in actions:
		names.append(StringName(str(action)))
	control.set_meta(META_ACTIONS, names)

# The buttons set for the control, or an empty array when it has none set (all buttons).
static func get_actions(control: Control) -> Array:
	if not is_instance_valid(control) or not control.has_meta(META_ACTIONS):
		return []
	return (control.get_meta(META_ACTIONS) as Array).duplicate()

static func has_actions(control: Control) -> bool:
	return is_instance_valid(control) and control.has_meta(META_ACTIONS)

static func allows(control: Control, action: StringName) -> bool:
	if not has_actions(control):
		return true
	return (control.get_meta(META_ACTIONS) as Array).has(action)

static func clear(control: Control) -> void:
	if not is_instance_valid(control):
		return
	control.remove_meta(META_MENU)
	control.remove_meta(META_ACTIONS)
