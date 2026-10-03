# Adapter for LineEdit (single line, horizontal scrolling only).
class_name caret_line_edit_adapter extends caret_text_adapter

# Columns per second to advance when a handle is dragged past the left/right edge.
const EDGE_SCROLL_COLUMNS_PER_SECOND: float = 20.0

var _edge_accumulator: float = 0.0


func _edit() -> LineEdit:
	return control as LineEdit

func is_empty() -> bool:
	return _edit().text.is_empty()

func get_caret() -> Vector2i:
	return Vector2i(_edit().caret_column, 0)

func set_caret(pos: Vector2i) -> void:
	_edit().caret_column = pos.x

func has_selection() -> bool:
	return _edit().has_selection()

func get_selection_from() -> Vector2i:
	return Vector2i(_edit().get_selection_from_column(), 0)

func get_selection_to() -> Vector2i:
	return Vector2i(_edit().get_selection_to_column(), 0)

func select(anchor: Vector2i, caret: Vector2i) -> void:
	var edit: LineEdit = _edit()
	if anchor.x == caret.x:
		edit.deselect()
	else:
		edit.select(mini(anchor.x, caret.x), maxi(anchor.x, caret.x))
	edit.caret_column = caret.x

func deselect() -> void:
	_edit().deselect()

func select_word_at(pos: Vector2i) -> void:
	var word: Vector2i = word_range(_edit().text, pos.x)
	if word.x == word.y:
		return
	_edit().select(word.x, word.y)
	_edit().caret_column = word.y

func get_line_height() -> float:
	return _font().get_height(_font_size())

func get_tip_local(pos: Vector2i) -> Vector2:
	var style: StyleBox = _style()
	var height: float = get_line_height()
	var top: float = style.get_margin(SIDE_TOP) + (control.size.y - style.get_minimum_size().y - height) * 0.5
	return Vector2(_text_origin_x() + _width_before(pos.x), top + height)

func is_pos_visible(pos: Vector2i) -> bool:
	var x: float = get_tip_local(pos).x
	var style: StyleBox = _style()
	return x >= style.get_margin(SIDE_LEFT) - 1.0 and x <= control.size.x - style.get_margin(SIDE_RIGHT) + 1.0

func get_pos_at_local(local: Vector2) -> Vector2i:
	var text: String = _measured_text()
	var target: float = local.x - _text_origin_x()
	# Binary search for the first column whose x is at or past the target.
	var low: int = 0
	var high: int = text.length()
	while low < high:
		var mid: int = (low + high) >> 1
		if _width_before(mid) < target:
			low = mid + 1
		else:
			high = mid
	# Pick whichever neighbouring column is closer.
	if low > 0 and target - _width_before(low - 1) < _width_before(low) - target:
		low -= 1
	return Vector2i(low, 0)

func get_drag_target(local: Vector2, current: Vector2i, delta: float) -> Vector2i:
	var style: StyleBox = _style()
	var left: float = style.get_margin(SIDE_LEFT)
	var right: float = control.size.x - style.get_margin(SIDE_RIGHT)
	# Past an edge the visible columns cannot reach further text, so step the caret instead.
	if local.x > right or local.x < left:
		_edge_accumulator += delta * EDGE_SCROLL_COLUMNS_PER_SECOND
		var steps: int = int(_edge_accumulator)
		_edge_accumulator -= steps
		var direction: int = 1 if local.x > right else -1
		return Vector2i(clampi(current.x + direction * steps, 0, _edit().text.length()), 0)
	_edge_accumulator = 0.0
	return get_pos_at_local(local)


#region Geometry helpers

func _style() -> StyleBox:
	return control.get_theme_stylebox("normal" if _edit().editable else "read_only")

func _font() -> Font:
	return control.get_theme_font("font")

func _font_size() -> int:
	return control.get_theme_font_size("font_size")

# The text as it is drawn (a secret LineEdit draws its secret character instead).
func _measured_text() -> String:
	var edit: LineEdit = _edit()
	if edit.secret:
		return edit.secret_character.repeat(edit.text.length())
	return edit.text

func _width_before(column: int) -> float:
	return _font().get_string_size(_measured_text().substr(0, column), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x

# X (in control space) where the first character of the text is drawn.
func _text_origin_x() -> float:
	var style: StyleBox = _style()
	var scroll: float = _edit().get_scroll_offset()
	var left: float = style.get_margin(SIDE_LEFT)
	# The engine reports the scroll as a negative offset once the text is wider than the control.
	if scroll != 0.0:
		return left + scroll
	var free: float = control.size.x - style.get_margin(SIDE_LEFT) - style.get_margin(SIDE_RIGHT) - _width_before(_measured_text().length())
	match _edit().alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return left + floorf(free * 0.5)
		HORIZONTAL_ALIGNMENT_RIGHT:
			return left + free
	return left

#endregion
