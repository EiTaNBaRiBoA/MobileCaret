# Base class that hides the differences between text controls (LineEdit, TextEdit)
# from the carets controller. Text positions are always Vector2i(column, line).
# All "local" coordinates are in the text control's own coordinate space.
class_name caret_text_adapter extends RefCounted

# The wrapped text control.
var control: Control
# How much larger than the reference size the handles currently are. Pixel distances such as
# edge-scroll zones are multiplied by it so they stay finger-sized on any screen.
var ui_scale: float = 1.0


func _init(text_control: Control) -> void:
	control = text_control


# Returns an adapter for the control, or null if the control type is not supported.
static func for_control(text_control: Control) -> caret_text_adapter:
	if text_control is LineEdit:
		return caret_line_edit_adapter.new(text_control)
	if text_control is TextEdit:
		return caret_text_edit_adapter.new(text_control)
	return null


func is_valid() -> bool:
	return is_instance_valid(control)

func is_empty() -> bool:
	return true

func get_caret() -> Vector2i:
	return Vector2i.ZERO

func set_caret(_pos: Vector2i) -> void:
	pass

func has_selection() -> bool:
	return false

# Start (lowest position) of the current selection.
func get_selection_from() -> Vector2i:
	return get_caret()

# End (highest position) of the current selection.
func get_selection_to() -> Vector2i:
	return get_caret()

# Selects from `anchor` to `caret`; the native caret ends up at `caret`.
func select(_anchor: Vector2i, _caret: Vector2i) -> void:
	pass

func deselect() -> void:
	pass

# Selects the word around `pos`.
func select_word_at(_pos: Vector2i) -> void:
	pass

# Local position of the bottom of the caret at `pos` (where the handle's tip goes).
func get_tip_local(_pos: Vector2i) -> Vector2:
	return Vector2.ZERO

# Whether `pos` is currently inside the visible area of the control.
func is_pos_visible(_pos: Vector2i) -> bool:
	return false

func get_line_height() -> float:
	return 0.0

# Nearest text position for a local point (clamped to the text).
func get_pos_at_local(_local: Vector2) -> Vector2i:
	return Vector2i.ZERO

# Position a dragged handle should select for the local point `local`.
# Also scrolls the control when the point is dragged past an edge.
func get_drag_target(local: Vector2, _current: Vector2i, _delta: float) -> Vector2i:
	return get_pos_at_local(local)


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
