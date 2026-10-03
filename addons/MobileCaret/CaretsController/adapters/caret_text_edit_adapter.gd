# Adapter for TextEdit (multi-line, vertical and horizontal scrolling, optional wrapping).
class_name caret_text_edit_adapter extends caret_text_adapter

# Lines per second to scroll when a handle is dragged past the top/bottom edge.
const EDGE_SCROLL_LINES_PER_SECOND: float = 10.0
# Pixels per second to scroll horizontally when a handle is dragged past the left/right edge.
const EDGE_SCROLL_PIXELS_PER_SECOND: float = 400.0
# Distance from an edge (in pixels) where edge scrolling starts.
const EDGE_MARGIN: float = 16.0


func _edit() -> TextEdit:
	return control as TextEdit

func is_empty() -> bool:
	return _edit().text.is_empty()

func get_caret() -> Vector2i:
	return Vector2i(_edit().get_caret_column(), _edit().get_caret_line())

func set_caret(pos: Vector2i) -> void:
	var edit: TextEdit = _edit()
	edit.set_caret_line(pos.y, false)
	edit.set_caret_column(pos.x, false)

func has_selection() -> bool:
	return _edit().has_selection()

func get_selection_from() -> Vector2i:
	return Vector2i(_edit().get_selection_from_column(), _edit().get_selection_from_line())

func get_selection_to() -> Vector2i:
	return Vector2i(_edit().get_selection_to_column(), _edit().get_selection_to_line())

func select(anchor: Vector2i, caret: Vector2i) -> void:
	var edit: TextEdit = _edit()
	if anchor == caret:
		edit.deselect()
		set_caret(caret)
		return
	# `adjust_viewport` is off: edge scrolling is handled by get_drag_target.
	edit.select(anchor.y, anchor.x, caret.y, caret.x)
	edit.set_caret_line(caret.y, false)
	edit.set_caret_column(caret.x, false)

func deselect() -> void:
	_edit().deselect()

func select_word_at(pos: Vector2i) -> void:
	var edit: TextEdit = _edit()
	var word: Vector2i = word_range(edit.get_line(pos.y), pos.x)
	if word.x == word.y:
		return
	select(Vector2i(word.x, pos.y), Vector2i(word.y, pos.y))

func get_line_height() -> float:
	return float(_edit().get_line_height())

func get_tip_local(pos: Vector2i) -> Vector2:
	var top_left: Vector2 = _caret_top_left(pos)
	return Vector2(top_left.x, top_left.y + get_line_height())

func is_pos_visible(pos: Vector2i) -> bool:
	var edit: TextEdit = _edit()
	var top_left: Vector2 = _caret_top_left(pos)
	# The engine reports -1 for positions outside of the viewable area.
	if top_left.x < 0.0 or top_left.y < 0.0:
		return false
	return top_left.x <= edit.size.x and top_left.y + get_line_height() <= edit.size.y + 1.0

# Top-left of the caret for a text position, in local space, or (-1, -1) if not viewable.
# In Godot 4.7 get_rect_at_line_column(line, column) returns the rect of the character
# *before* `column` (column 0 returns the first character), so the caret sits at its right
# edge. At a wrap boundary that rect belongs to the previous visual row, so the rect of the
# character after the column (the first one on the new row) is used instead.
func _caret_top_left(pos: Vector2i) -> Vector2:
	var edit: TextEdit = _edit()
	var line_length: int = edit.get_line(pos.y).length()
	var rect: Rect2i = edit.get_rect_at_line_column(pos.y, pos.x)
	if rect.position.x < 0 or rect.position.y < 0:
		return Vector2(-1.0, -1.0)
	if pos.x == 0:
		return Vector2(rect.position)
	if pos.x < line_length and edit.get_line_wrap_index_at_column(pos.y, pos.x) != edit.get_line_wrap_index_at_column(pos.y, pos.x - 1):
		var next: Rect2i = edit.get_rect_at_line_column(pos.y, pos.x + 1)
		return Vector2(next.position)
	return Vector2(rect.position.x + rect.size.x, rect.position.y)

func get_pos_at_local(local: Vector2) -> Vector2i:
	var edit: TextEdit = _edit()
	var clamped: Vector2 = Vector2(local.x, clampf(local.y, 1.0, maxf(edit.size.y - 1.0, 1.0)))
	var column_line: Vector2i = edit.get_line_column_at_pos(Vector2i(clamped), true, true)
	var line: int = clampi(column_line.y, 0, edit.get_line_count() - 1)
	return Vector2i(clampi(column_line.x, 0, edit.get_line(line).length()), line)

func get_drag_target(local: Vector2, _current: Vector2i, delta: float) -> Vector2i:
	var edit: TextEdit = _edit()
	var margin: float = EDGE_MARGIN * ui_scale
	if local.y < margin:
		edit.scroll_vertical -= EDGE_SCROLL_LINES_PER_SECOND * delta
	elif local.y > edit.size.y - margin:
		edit.scroll_vertical += EDGE_SCROLL_LINES_PER_SECOND * delta
	# Horizontal scrolling only exists when lines are not wrapped.
	if edit.wrap_mode == TextEdit.LINE_WRAPPING_NONE:
		if local.x < margin:
			edit.scroll_horizontal -= int(EDGE_SCROLL_PIXELS_PER_SECOND * ui_scale * delta)
		elif local.x > edit.size.x - margin:
			edit.scroll_horizontal += int(EDGE_SCROLL_PIXELS_PER_SECOND * ui_scale * delta)
	return get_pos_at_local(local)
