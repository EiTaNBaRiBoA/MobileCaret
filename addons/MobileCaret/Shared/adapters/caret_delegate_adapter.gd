# Adapter for custom controls that do not depend on MobileCaret. The control implements
#
#     func _get_caret_delegate() -> Object
#
# and returns an object (the control itself, or a helper) that has any of caret_text_adapter's
# methods, with the same names and parameters. Each call is forwarded when the delegate has that
# method; otherwise a default is used. A method may also leave out its trailing parameters (for
# example `get_caret()` without `caret_index` for a control with one caret): only as many
# arguments as it declares are passed.
#
# For handles the delegate needs at least get_caret, set_caret, get_tip_local, get_pos_at_local
# and get_line_height (plus the selection methods for selection handles). For the toolbar it needs
# has_selection, get_selection_from / get_selection_to, get_selected_text and the actions it
# supports (copy, cut, paste, select_all, undo, redo, with is_text_editable / has_undo / has_redo).
# get_toolbar_items() / toolbar_item_pressed(id) add the control's own toolbar buttons.
# Return false from supports_handles() for a toolbar-only control.
class_name caret_delegate_adapter extends caret_text_adapter

var delegate: Object
# Number of declared arguments per method name, or -1 when the delegate lacks the method.
var _arg_counts: Dictionary = {}


func _init(text_control: Control, target: Object) -> void:
	super(text_control)
	delegate = target


# Whether the delegate implements `method`.
func has(method: StringName) -> bool:
	return _arg_count(method) >= 0

func _arg_count(method: StringName) -> int:
	if not _arg_counts.has(method):
		var count: int = -1
		if is_instance_valid(delegate) and delegate.has_method(method):
			count = delegate.get_method_argument_count(method)
		_arg_counts[method] = count
	return _arg_counts[method]

# Calls `method` with as many of `args` as it declares, or returns `fallback` if it is missing.
func _forward(method: StringName, args: Array, fallback: Variant) -> Variant:
	var count: int = _arg_count(method)
	if count < 0 or not is_instance_valid(delegate):
		return fallback
	return delegate.callv(method, args.slice(0, mini(count, args.size())))


func is_valid() -> bool:
	return is_instance_valid(control) and is_instance_valid(delegate)

func is_usable() -> bool:
	return is_valid() and bool(_forward(&"is_usable", [], true))

func supports_handles() -> bool:
	return bool(_forward(&"supports_handles", [], true))

func is_text_editable() -> bool:
	return bool(_forward(&"is_text_editable", [], false))

func is_empty() -> bool:
	return bool(_forward(&"is_empty", [], false))

func get_caret_count() -> int:
	return int(_forward(&"get_caret_count", [], 1))

func get_caret(caret_index: int = 0) -> Vector2i:
	return _forward(&"get_caret", [caret_index], Vector2i.ZERO) as Vector2i

func set_caret(pos: Vector2i, caret_index: int = 0) -> void:
	_forward(&"set_caret", [pos, caret_index], null)

func has_selection(caret_index: int = 0) -> bool:
	return bool(_forward(&"has_selection", [caret_index], false))

func has_any_selection() -> bool:
	if has(&"has_any_selection"):
		return bool(_forward(&"has_any_selection", [], false))
	return super()

func get_selection_from(caret_index: int = 0) -> Vector2i:
	return _forward(&"get_selection_from", [caret_index], get_caret(caret_index)) as Vector2i

func get_selection_to(caret_index: int = 0) -> Vector2i:
	return _forward(&"get_selection_to", [caret_index], get_caret(caret_index)) as Vector2i

func select(anchor: Vector2i, caret: Vector2i, caret_index: int = 0) -> void:
	_forward(&"select", [anchor, caret, caret_index], null)

func deselect() -> void:
	_forward(&"deselect", [], null)

func merge_carets() -> void:
	_forward(&"merge_carets", [], null)

func select_word_at(pos: Vector2i) -> void:
	_forward(&"select_word_at", [pos], null)

func get_tip_local(pos: Vector2i) -> Vector2:
	return _forward(&"get_tip_local", [pos], Vector2.ZERO) as Vector2

# Default: visible when the caret's tip is inside the control.
func is_pos_visible(pos: Vector2i) -> bool:
	if has(&"is_pos_visible"):
		return bool(_forward(&"is_pos_visible", [pos], false))
	var tip: Vector2 = get_tip_local(pos)
	return Rect2(Vector2.ZERO, control.size).grow(1.0).has_point(tip - Vector2(0.0, get_line_height() * 0.5))

func get_line_height() -> float:
	return float(_forward(&"get_line_height", [], 16.0))

func get_pos_at_local(local: Vector2) -> Vector2i:
	return _forward(&"get_pos_at_local", [local], Vector2i.ZERO) as Vector2i

func get_row_x_extent(local_y: float) -> Vector2:
	if has(&"get_row_x_extent"):
		return _forward(&"get_row_x_extent", [local_y], Vector2(-INF, INF)) as Vector2
	return super(local_y)

func get_drag_target(local: Vector2, current: Vector2i, delta: float) -> Vector2i:
	if has(&"get_drag_target"):
		return _forward(&"get_drag_target", [local, current, delta], current) as Vector2i
	return get_pos_at_local(local)

func is_secret() -> bool:
	return bool(_forward(&"is_secret", [], false))

func get_text_version() -> int:
	return int(_forward(&"get_text_version", [], 0))

func get_selected_text() -> String:
	return str(_forward(&"get_selected_text", [], ""))

func is_everything_selected() -> bool:
	return bool(_forward(&"is_everything_selected", [], false))

# Default: put the selected text on the clipboard.
func copy() -> void:
	if has(&"copy"):
		_forward(&"copy", [], null)
	else:
		super()

func cut() -> void:
	_forward(&"cut", [], null)

func paste() -> void:
	_forward(&"paste", [], null)

func select_all() -> void:
	_forward(&"select_all", [], null)

func has_undo() -> bool:
	return bool(_forward(&"has_undo", [], false))

func has_redo() -> bool:
	return bool(_forward(&"has_redo", [], false))

func undo() -> void:
	_forward(&"undo", [], null)

func redo() -> void:
	_forward(&"redo", [], null)

func get_toolbar_items() -> Array:
	var items: Variant = _forward(&"get_toolbar_items", [], [])
	return items as Array if items is Array else []

func toolbar_item_pressed(id: StringName) -> void:
	_forward(&"toolbar_item_pressed", [id], null)

# Default: the `caret_color` theme override, like the built-in controls.
func hide_native_caret(hidden: bool) -> void:
	if has(&"hide_native_caret"):
		_forward(&"hide_native_caret", [hidden], null)
	else:
		super(hidden)
