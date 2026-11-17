# Base class that hides the differences between text controls (LineEdit, TextEdit, ...) from the
# carets controller and the toolbar. Text positions are always Vector2i(column, line).
# All "local" coordinates are in the text control's own coordinate space.
# Controls with several carets (a TextEdit with multiple carets) are addressed by `caret_index`;
# index 0 is the main caret.
#
# Custom controls get handles and the toolbar in one of two ways (see "Custom controls" in the
# README):
#  * Without depending on MobileCaret: the control implements `_get_caret_delegate() -> Object`
#    and returns an object (often the control itself) with any of this class's methods. Missing
#    methods fall back to sensible defaults. See caret_delegate_adapter.
#  * With a dependency: register a factory with register_adapter() that returns a subclass of
#    this class for the controls it handles (also works for controls you cannot change).
class_name caret_text_adapter extends RefCounted

# Name of the method a custom control implements to provide its delegate.
const DELEGATE_METHOD: StringName = &"_get_caret_delegate"

# The wrapped text control.
var control: Control
# How much larger than the reference size the handles currently are. Pixel distances such as
# edge-scroll zones are multiplied by it so they stay finger-sized on any screen.
var ui_scale: float = 1.0

# Factories added with register_adapter(), asked first, newest first.
static var _factories: Array[Callable] = []

# Saved caret_color override while the native caret is hidden (see hide_native_caret).
var _caret_hidden: bool = false
var _had_caret_override: bool = false
var _saved_caret_color: Color = Color.WHITE


func _init(text_control: Control) -> void:
	control = text_control


# Adds a factory `func(control: Control) -> caret_text_adapter` that returns an adapter for the
# controls it knows, or null. Registered factories are asked before the built-in adapters, so they
# can also replace the adapter of a LineEdit or TextEdit subclass.
static func register_adapter(factory: Callable) -> void:
	if not _factories.has(factory):
		_factories.push_front(factory)

static func unregister_adapter(factory: Callable) -> void:
	_factories.erase(factory)

# Returns an adapter for a control that can show caret handles (LineEdit, TextEdit and subclasses,
# controls with a delegate, controls a registered factory handles), or null for anything else.
static func for_control(text_control: Control) -> caret_text_adapter:
	var adapter: caret_text_adapter = _custom_adapter(text_control)
	if adapter != null:
		return adapter if adapter.supports_handles() else null
	if text_control is LineEdit:
		return caret_line_edit_adapter.new(text_control)
	if text_control is TextEdit:
		return caret_text_edit_adapter.new(text_control)
	return null

# Like for_control(), but also returns adapters for controls that only support the toolbar
# (selectable RichTextLabels: their selection can be read and copied but not set; custom
# adapters whose supports_handles() is false).
static func for_toolbar(text_control: Control) -> caret_text_adapter:
	var adapter: caret_text_adapter = _custom_adapter(text_control)
	if adapter != null:
		return adapter if adapter.is_usable() else null
	adapter = for_control(text_control)
	if adapter != null:
		return adapter
	if text_control is RichTextLabel and (text_control as RichTextLabel).selection_enabled:
		return caret_rich_text_adapter.new(text_control)
	return null

# An adapter from a registered factory or from the control's delegate, or null.
static func _custom_adapter(text_control: Control) -> caret_text_adapter:
	if not is_instance_valid(text_control):
		return null
	for factory: Callable in _factories.duplicate():
		if not factory.is_valid():
			_factories.erase(factory)
			continue
		var made: Variant = factory.call(text_control)
		if made is caret_text_adapter:
			return made as caret_text_adapter
	if text_control.has_method(DELEGATE_METHOD):
		var delegate: Variant = text_control.call(DELEGATE_METHOD)
		if delegate is Object and is_instance_valid(delegate):
			return caret_delegate_adapter.new(text_control, delegate as Object)
	return null


func is_valid() -> bool:
	return is_instance_valid(control)

# Whether the control can still be served (e.g. a RichTextLabel stops being selectable).
func is_usable() -> bool:
	return is_instance_valid(control)

# Whether caret handles can be shown for this control (false for toolbar-only controls).
func supports_handles() -> bool:
	return true

# Whether the text can be changed by the user (Cut and Paste make sense).
func is_text_editable() -> bool:
	return false

func is_empty() -> bool:
	return true

#region Carets and selection

func get_caret_count() -> int:
	return 1

func get_caret(_caret_index: int = 0) -> Vector2i:
	return Vector2i.ZERO

func set_caret(_pos: Vector2i, _caret_index: int = 0) -> void:
	pass

func has_selection(_caret_index: int = 0) -> bool:
	return false

# True if any caret has a selection.
func has_any_selection() -> bool:
	for i: int in get_caret_count():
		if has_selection(i):
			return true
	return false

# Index of the first caret that has a selection, or -1.
func get_selection_caret() -> int:
	for i: int in get_caret_count():
		if has_selection(i):
			return i
	return -1

# Start (lowest position) of a caret's selection.
func get_selection_from(caret_index: int = 0) -> Vector2i:
	return get_caret(caret_index)

# End (highest position) of a caret's selection.
func get_selection_to(caret_index: int = 0) -> Vector2i:
	return get_caret(caret_index)

# Selects from `anchor` to `caret`; the caret ends up at `caret`. Equal positions clear the
# selection of that caret.
func select(_anchor: Vector2i, _caret: Vector2i, _caret_index: int = 0) -> void:
	pass

# Clears the selection of every caret.
func deselect() -> void:
	pass

# Merges carets that ended up on top of each other (only a multi-caret TextEdit has any).
func merge_carets() -> void:
	pass

# Selects the word around `pos` (with the main caret).
func select_word_at(_pos: Vector2i) -> void:
	pass

#endregion

#region Geometry

# Local position of the bottom of the caret at `pos` (where the handle's tip goes).
func get_tip_local(_pos: Vector2i) -> Vector2:
	return Vector2.ZERO

# Whether `pos` is currently inside the visible area of the control.
func is_pos_visible(_pos: Vector2i) -> bool:
	return false

func get_line_height() -> float:
	return 0.0

# True if a text position lies outside the clip area of an ancestor (e.g. a ScrollContainer that
# has scrolled the text control, or part of it, out of view).
func is_pos_clipped(pos: Vector2i) -> bool:
	var middle: Vector2 = get_tip_local(pos) - Vector2(0.0, get_line_height() * 0.5)
	var point: Vector2 = control.get_global_transform_with_canvas() * middle
	var node: Node = control.get_parent()
	while node is CanvasItem:
		if node is Control:
			var ancestor: Control = node
			if ancestor.clip_contents:
				var area: Rect2 = ancestor.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, ancestor.size)
				if not area.has_point(point):
					return true
		node = node.get_parent()
	return false

# Whether the line of a text position reads right to left (its base direction). Selection handles
# on different rows lean the other way in such a line, so they never cover the selected text.
func is_pos_rtl(_pos: Vector2i) -> bool:
	return false

# Nearest text position for a local point (clamped to the text).
func get_pos_at_local(_local: Vector2) -> Vector2i:
	return Vector2i.ZERO

# Where a dragged handle may go, in the control's coordinates: the control itself. A control whose
# text continues outside its own rectangle (a selection over several paragraphs) gives that area.
func get_drag_rect() -> Rect2:
	return Rect2(Vector2.ZERO, control.size)

# Horizontal extent (local x) of the text on the row at `local_y`: from the first to the last
# caret position of that row. A side whose end is scrolled out of view is -INF / INF.
func get_row_x_extent(local_y: float) -> Vector2:
	var first: Vector2i = get_pos_at_local(Vector2(-1.0e6, local_y))
	var last: Vector2i = get_pos_at_local(Vector2(1.0e6, local_y))
	var low: float = -INF
	var high: float = INF
	if is_pos_visible(first):
		low = get_tip_local(first).x
	if is_pos_visible(last):
		high = get_tip_local(last).x
	return Vector2(low, high)

# Position a dragged handle should select for the local point `local`.
# Also scrolls the control when the point is dragged past an edge.
func get_drag_target(local: Vector2, _current: Vector2i, _delta: float) -> Vector2i:
	return get_pos_at_local(local)

#endregion

#region Toolbar actions

# True for text that must never be copied (a password field).
func is_secret() -> bool:
	return false

# A number that changes whenever the text changes (the toolbar hides when it does).
func get_text_version() -> int:
	return 0

func get_selected_text() -> String:
	return ""

func is_everything_selected() -> bool:
	return false

func copy() -> void:
	if has_any_selection() and not is_secret():
		DisplayServer.clipboard_set(get_selected_text())

func cut() -> void:
	pass

func paste() -> void:
	pass

func select_all() -> void:
	pass

func has_undo() -> bool:
	return false

func has_redo() -> bool:
	return false

func undo() -> void:
	pass

func redo() -> void:
	pass

# Extra toolbar buttons for this control: Dictionaries like the ones caret_toolbar.add_item()
# takes ("id", "text", "index", "items", "when", "font", "icon"); no callback, the press arrives
# in toolbar_item_pressed().
func get_toolbar_items() -> Array:
	return []

func toolbar_item_pressed(_id: StringName) -> void:
	pass

#endregion

#region Native caret

# Hides or shows the control's own caret. The default makes the `caret_color` theme color
# transparent and puts back whatever override was there before.
func hide_native_caret(hidden: bool) -> void:
	if hidden == _caret_hidden or not is_instance_valid(control):
		_caret_hidden = hidden and is_instance_valid(control)
		return
	_caret_hidden = hidden
	if hidden:
		_had_caret_override = control.has_theme_color_override("caret_color")
		_saved_caret_color = control.get_theme_color("caret_color")
		var transparent: Color = _saved_caret_color
		transparent.a = 0.0
		control.add_theme_color_override("caret_color", transparent)
	elif _had_caret_override:
		control.add_theme_color_override("caret_color", _saved_caret_color)
	else:
		control.remove_theme_color_override("caret_color")

#endregion


# Shared by the adapters: finds the word boundaries (as columns) around `column` in `line_text`.
static func word_range(line_text: String, column: int) -> Vector2i:
	var length: int = line_text.length()
	if length == 0:
		return Vector2i.ZERO
	var idx: int = clampi(column, 0, length - 1)
	# A caret sitting at the end of a word belongs to that word.
	if column >= length and idx > 0 and _char_class(line_text[idx]) == 0:
		idx -= 1
	var kind: int = _char_class(line_text[idx])
	var from: int = idx
	var to: int = idx + 1
	while from > 0 and _char_class(line_text[from - 1]) == kind:
		from -= 1
	while to < length and _char_class(line_text[to]) == kind:
		to += 1
	return Vector2i(from, to)

# 0 = whitespace, 1 = word character, 2 = punctuation/other.
static func _char_class(c: String) -> int:
	if c == " " or c == "\t":
		return 0
	if c == "_" or c.unicode_at(0) > 127 or (c >= "0" and c <= "9") or c.to_lower() != c.to_upper():
		return 1
	return 2
