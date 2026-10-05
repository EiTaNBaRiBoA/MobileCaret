# Adapter for TextEdit (multi-line, vertical and horizontal scrolling, optional wrapping).
class_name caret_text_edit_adapter extends caret_text_adapter

# Lines per second to scroll when a handle is dragged past the top/bottom edge.
const EDGE_SCROLL_LINES_PER_SECOND: float = 10.0
# Pixels per second to scroll horizontally when a handle is dragged past the left/right edge.
const EDGE_SCROLL_PIXELS_PER_SECOND: float = 400.0
# Distance from an edge (in pixels) where edge scrolling starts.
const EDGE_MARGIN: float = 16.0
# Shaped rows are cached by their text and shaping settings (bounded, oldest first).
const MAX_CACHED_ROWS: int = 12

var _row_cache: Dictionary = {}
# Set by the last right-to-left lookup: the other valid caret x when a direction change gives two
# (NAN otherwise). The engine picks one depending on its input direction, which cannot be read.
var last_alternative_x: float = NAN


func _edit() -> TextEdit:
	return control as TextEdit

func is_text_editable() -> bool:
	return _edit().editable

func is_empty() -> bool:
	return _edit().text.is_empty()

func get_caret_count() -> int:
	return _edit().get_caret_count()

func get_caret(caret_index: int = 0) -> Vector2i:
	var edit: TextEdit = _edit()
	return Vector2i(edit.get_caret_column(caret_index), edit.get_caret_line(caret_index))

func set_caret(pos: Vector2i, caret_index: int = 0) -> void:
	var edit: TextEdit = _edit()
	# `adjust_viewport` is off: edge scrolling is handled by get_drag_target.
	edit.set_caret_line(pos.y, false, true, 0, caret_index)
	edit.set_caret_column(pos.x, false, caret_index)

func has_selection(caret_index: int = 0) -> bool:
	return _edit().has_selection(caret_index)

func has_any_selection() -> bool:
	return _edit().has_selection(-1)

func get_selection_from(caret_index: int = 0) -> Vector2i:
	var edit: TextEdit = _edit()
	return Vector2i(edit.get_selection_from_column(caret_index), edit.get_selection_from_line(caret_index))

func get_selection_to(caret_index: int = 0) -> Vector2i:
	var edit: TextEdit = _edit()
	return Vector2i(edit.get_selection_to_column(caret_index), edit.get_selection_to_line(caret_index))

func select(anchor: Vector2i, caret: Vector2i, caret_index: int = 0) -> void:
	var edit: TextEdit = _edit()
	if anchor == caret:
		# Selecting from a position to itself clears the selection of that caret.
		edit.select(caret.y, caret.x, caret.y, caret.x, caret_index)
		set_caret(caret, caret_index)
		return
	edit.select(anchor.y, anchor.x, caret.y, caret.x, caret_index)
	set_caret(caret, caret_index)

func deselect() -> void:
	_edit().deselect()

func merge_carets() -> void:
	if _edit().get_caret_count() > 1:
		_edit().merge_overlapping_carets()

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
	# The vertical scrollbar takes a strip on the right (on the left in a right-to-left layout).
	var bar: VScrollBar = edit.get_v_scroll_bar()
	var bar_width: float = bar.size.x if bar.visible else 0.0
	var left_limit: float = bar_width if edit.is_layout_rtl() else 0.0
	var right_limit: float = edit.size.x - (0.0 if edit.is_layout_rtl() else bar_width)
	return top_left.x >= left_limit and top_left.x <= right_limit and top_left.y + get_line_height() <= edit.size.y + 1.0

# Top-left of the caret for a text position, in local space, or (-1, -1) if not viewable.
# In Godot 4.7 get_rect_at_line_column(line, column) returns the rect of the character
# *before* `column` (column 0 returns the first character), so the caret sits at its right
# edge. At a wrap boundary that rect belongs to the previous visual row, so the rect of the
# character after the column (the first one on the new row) is used instead.
func _caret_top_left(pos: Vector2i) -> Vector2:
	var edit: TextEdit = _edit()
	var line_length: int = edit.get_line(pos.y).length()
	# A completely empty text has no rows to measure (the engine reports a zero rect), so the
	# caret sits where the first row would start.
	if line_length == 0 and edit.get_line_count() == 1:
		var style: StyleBox = edit.get_theme_stylebox("normal" if edit.editable else "read_only")
		return Vector2(_text_origin_x(0.0), style.get_margin(SIDE_TOP))
	var rect: Rect2i = edit.get_rect_at_line_column(pos.y, pos.x)
	if rect.position.x < 0 or rect.position.y < 0:
		return Vector2(-1.0, -1.0)
	var top_left: Vector2
	if pos.x == 0:
		top_left = Vector2(rect.position)
	elif pos.x < line_length and edit.get_line_wrap_index_at_column(pos.y, pos.x) != edit.get_line_wrap_index_at_column(pos.y, pos.x - 1):
		top_left = Vector2(edit.get_rect_at_line_column(pos.y, pos.x + 1).position)
	else:
		top_left = Vector2(rect.position.x + rect.size.x, rect.position.y)
	# Rows with right-to-left text: the engine rects point at the wrong side of a character, so the
	# x comes from the text server instead (the y found above is still right).
	var bidi_x: float = _bidi_caret_x(pos)
	if not is_nan(bidi_x):
		top_left.x = bidi_x
	return top_left


#region Right-to-left and mixed-direction text

# X of the caret (local space) for a position in a row that contains right-to-left text,
# or NAN when the row is plain left-to-right (the engine rects are right there).
func _bidi_caret_x(pos: Vector2i) -> float:
	var edit: TextEdit = _edit()
	var line_text: String = edit.get_line(pos.y)
	var direction: int = _text_direction()
	if direction != TextServer.DIRECTION_RTL and not _has_rtl_text(line_text):
		return NAN
	# The visual row that holds the caret, and the column where that row starts.
	var rows: PackedStringArray = edit.get_line_wrapped_text(pos.y)
	var row_index: int = clampi(edit.get_line_wrap_index_at_column(pos.y, pos.x), 0, rows.size() - 1)
	var row_start: int = 0
	for i: int in row_index:
		row_start += rows[i].length()
	var row_text: String = rows[row_index]
	var shaped: TextLine = _shape_row(row_text, direction)
	var carets: Dictionary = TextServerManager.get_primary_interface().shaped_text_get_carets(shaped.get_rid(), clampi(pos.x - row_start, 0, row_text.length()))
	var leading: Rect2 = carets.get("leading_rect", Rect2())
	var trailing: Rect2 = carets.get("trailing_rect", Rect2())
	var caret_x: float = leading.position.x
	last_alternative_x = NAN
	var alternative_x: float = NAN
	if leading.size.y <= 0.0:
		caret_x = trailing.position.x
	elif trailing.size.y > 0.0 and not is_equal_approx(leading.position.x, trailing.position.x):
		# Two possible positions (a direction change): prefer the right-to-left one, or the
		# trailing one if both are left-to-right.
		var leading_rtl: bool = carets.get("leading_direction", TextServer.DIRECTION_LTR) == TextServer.DIRECTION_RTL
		var trailing_rtl: bool = carets.get("trailing_direction", TextServer.DIRECTION_LTR) == TextServer.DIRECTION_RTL
		var use_leading: bool = leading_rtl and not trailing_rtl
		caret_x = leading.position.x if use_leading else trailing.position.x
		alternative_x = trailing.position.x if use_leading else leading.position.x
	var origin: float = _text_origin_x(shaped.get_line_width())
	if not is_nan(alternative_x):
		last_alternative_x = origin + alternative_x
	return origin + caret_x

# Where text starts in a row: the left margin, the gutters, minus the horizontal scroll. In a
# right-to-left layout the rows are right-aligned instead.
func _text_origin_x(row_width: float) -> float:
	var edit: TextEdit = _edit()
	var style: StyleBox = edit.get_theme_stylebox("normal" if edit.editable else "read_only")
	if edit.is_layout_rtl():
		return edit.size.x - style.get_margin(SIDE_RIGHT) - row_width + float(edit.scroll_horizontal)
	return style.get_margin(SIDE_LEFT) + float(edit.get_total_gutter_width()) - float(edit.scroll_horizontal)

func _text_direction() -> int:
	var edit: TextEdit = _edit()
	match edit.text_direction:
		Control.TEXT_DIRECTION_LTR:
			return TextServer.DIRECTION_LTR
		Control.TEXT_DIRECTION_RTL:
			return TextServer.DIRECTION_RTL
		Control.TEXT_DIRECTION_AUTO:
			return TextServer.DIRECTION_AUTO
	return TextServer.DIRECTION_RTL if edit.is_layout_rtl() else TextServer.DIRECTION_LTR

# Shapes one visual row like the TextEdit does (cached).
func _shape_row(row_text: String, direction: int) -> TextLine:
	var edit: TextEdit = _edit()
	var font: Font = edit.get_theme_font("font")
	var font_size: int = edit.get_theme_font_size("font_size")
	var options: Array = edit.structured_text_bidi_override_options
	var key: String = "%s|%d|%d|%d|%s|%d|%s" % [row_text, font_size, font.get_instance_id(), direction, edit.language, edit.structured_text_bidi_override, str(options)]
	if _row_cache.has(key):
		return _row_cache[key]
	var line: TextLine = TextLine.new()
	line.direction = direction as TextServer.Direction
	if edit.structured_text_bidi_override != TextServer.STRUCTURED_TEXT_DEFAULT:
		line.set_bidi_override(TextServerManager.get_primary_interface().parse_structured_text(edit.structured_text_bidi_override as TextServer.StructuredTextParser, options, row_text))
	line.add_string(row_text, font, font_size, edit.language)
	if _row_cache.size() >= MAX_CACHED_ROWS:
		_row_cache.erase(_row_cache.keys()[0])
	_row_cache[key] = line
	return line

# True if the text has characters from a right-to-left script or a bidi control character.
static func _has_rtl_text(text: String) -> bool:
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if code < 0x590:
			continue
		if (code <= 0x8FF) or (code >= 0xFB1D and code <= 0xFDFF) or (code >= 0xFE70 and code <= 0xFEFF) or (code >= 0x200E and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069) or (code >= 0x10800 and code <= 0x10FFF) or (code >= 0x1E800 and code <= 0x1EFFF):
			return true
	return false

#endregion


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
