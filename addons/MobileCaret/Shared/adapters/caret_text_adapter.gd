# Base class that hides the differences between text controls (LineEdit, TextEdit, ...) from the
# carets controller and the toolbar. Text positions are always Vector2i(column, line).
# All "local" coordinates are in the text control's own coordinate space.
# Controls with several carets (a TextEdit with multiple carets) are addressed by `caret_index`;
# index 0 is the main caret.
class_name caret_text_adapter extends RefCounted

# The wrapped text control.
var control: Control
# How much larger than the reference size the handles currently are. Pixel distances such as
# edge-scroll zones are multiplied by it so they stay finger-sized on any screen.
var ui_scale: float = 1.0


func _init(text_control: Control) -> void:
	control = text_control


# Returns an adapter for a control that can show caret handles (LineEdit, TextEdit and subclasses),
# or null for anything else.
static func for_control(text_control: Control) -> caret_text_adapter:
	if text_control is LineEdit:
		return caret_line_edit_adapter.new(text_control)
	if text_control is TextEdit:
		return caret_text_edit_adapter.new(text_control)
	return null

# Like for_control(), but also returns adapters for controls that only support the toolbar
# (selectable RichTextLabels: their selection can be read and copied but not set).
static func for_toolbar(text_control: Control) -> caret_text_adapter:
	var adapter: caret_text_adapter = for_control(text_control)
	if adapter != null:
		return adapter
	if text_control is RichTextLabel and (text_control as RichTextLabel).selection_enabled:
		return caret_rich_text_adapter.new(text_control)
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

# Nearest text position for a local point (clamped to the text).
func get_pos_at_local(_local: Vector2) -> Vector2i:
	return Vector2i.ZERO

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
