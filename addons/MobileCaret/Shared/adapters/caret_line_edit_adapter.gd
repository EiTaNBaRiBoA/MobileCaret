# Adapter for LineEdit (single line, horizontal scrolling only).
# Caret positions come from Godot's TextServer, shaped with the same font, size, language and
# direction the LineEdit renders with, so right-to-left and mixed-direction text is handled.
class_name caret_line_edit_adapter extends caret_text_adapter

# Columns per second to advance when a handle is dragged past the left/right edge.
const EDGE_SCROLL_COLUMNS_PER_SECOND: float = 20.0

var _edge_accumulator: float = 0.0
# The shaped text, rebuilt whenever anything that affects shaping changes.
var _line: TextLine = null
var _line_key: String = ""


func _edit() -> LineEdit:
	return control as LineEdit

func is_text_editable() -> bool:
	return _edit().editable

func is_empty() -> bool:
	return _edit().text.is_empty()

# A LineEdit has a single caret, so the caret index is ignored.
func get_caret(_caret_index: int = 0) -> Vector2i:
	return Vector2i(_edit().caret_column, 0)

func set_caret(pos: Vector2i, _caret_index: int = 0) -> void:
	_edit().caret_column = pos.x

func has_selection(_caret_index: int = 0) -> bool:
	return _edit().has_selection()

func get_selection_from(_caret_index: int = 0) -> Vector2i:
	return Vector2i(_edit().get_selection_from_column(), 0)

func get_selection_to(_caret_index: int = 0) -> Vector2i:
	return Vector2i(_edit().get_selection_to_column(), 0)

func select(anchor: Vector2i, caret: Vector2i, _caret_index: int = 0) -> void:
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
	return Vector2(_text_origin_x() + _caret_x(pos.x), top + height)

func is_pos_visible(pos: Vector2i) -> bool:
	var x: float = get_tip_local(pos).x
	var style: StyleBox = _style()
	return x >= style.get_margin(SIDE_LEFT) - 1.0 and x <= control.size.x - style.get_margin(SIDE_RIGHT) - _right_icon_width() + 1.0

func get_pos_at_local(local: Vector2) -> Vector2i:
	var rid: RID = _shaped().get_rid()
	var column: int = TextServerManager.get_primary_interface().shaped_text_hit_test_position(rid, local.x - _text_origin_x())
	return Vector2i(clampi(column, 0, _edit().text.length()), 0)

func get_drag_target(local: Vector2, current: Vector2i, delta: float) -> Vector2i:
	var style: StyleBox = _style()
	var left: float = style.get_margin(SIDE_LEFT)
	var right: float = control.size.x - style.get_margin(SIDE_RIGHT) - _right_icon_width()
	# Past an edge the visible columns cannot reach further text, so step the caret instead.
	if local.x > right or local.x < left:
		_edge_accumulator += delta * EDGE_SCROLL_COLUMNS_PER_SECOND
		var steps: int = int(_edge_accumulator)
		_edge_accumulator -= steps
		# Which way is "visually right" depends on the text direction around the caret.
		var direction: int = _visual_right_step(current.x) if local.x > right else -_visual_right_step(current.x)
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

# The text direction the LineEdit shapes with (an inherited direction follows the layout).
func _text_direction() -> int:
	var edit: LineEdit = _edit()
	match edit.text_direction:
		Control.TEXT_DIRECTION_LTR:
			return TextServer.DIRECTION_LTR
		Control.TEXT_DIRECTION_RTL:
			return TextServer.DIRECTION_RTL
		Control.TEXT_DIRECTION_AUTO:
			return TextServer.DIRECTION_AUTO
	return TextServer.DIRECTION_RTL if edit.is_layout_rtl() else TextServer.DIRECTION_LTR

# Shapes the text like the LineEdit does, reusing the result until something changes.
func _shaped() -> TextLine:
	var edit: LineEdit = _edit()
	var font: Font = _font()
	var text: String = _measured_text()
	var direction: int = _text_direction()
	var options: Array = edit.structured_text_bidi_override_options
	var key: String = "%s|%d|%d|%d|%s|%d|%s" % [text, _font_size(), font.get_instance_id(), direction, edit.language, edit.structured_text_bidi_override, str(options)]
	if _line == null or key != _line_key:
		_line_key = key
		_line = TextLine.new()
		_line.direction = direction as TextServer.Direction
		if edit.structured_text_bidi_override != TextServer.STRUCTURED_TEXT_DEFAULT:
			_line.set_bidi_override(TextServerManager.get_primary_interface().parse_structured_text(edit.structured_text_bidi_override as TextServer.StructuredTextParser, options, text))
		_line.add_string(text, font, _font_size(), edit.language)
	return _line

# X of the caret at a column, relative to where the text starts.
func _caret_x(column: int) -> float:
	var carets: Dictionary = TextServerManager.get_primary_interface().shaped_text_get_carets(_shaped().get_rid(), clampi(column, 0, _edit().text.length()))
	# Use the leading caret; at the start of a right-to-left run it is empty and the real caret is
	# the trailing one.
	var leading: Rect2 = carets.get("leading_rect", Rect2())
	if leading.size.y > 0.0:
		return leading.position.x
	return (carets.get("trailing_rect", Rect2()) as Rect2).position.x

# At a direction change the engine draws two carets (one at the end of the previous run, one at
# the start of the next). Returns the x (control space) of the one the handle does not use, or NAN
# when there is only one.
func get_alternative_caret_x(column: int) -> float:
	var carets: Dictionary = TextServerManager.get_primary_interface().shaped_text_get_carets(_shaped().get_rid(), clampi(column, 0, _edit().text.length()))
	var leading: Rect2 = carets.get("leading_rect", Rect2())
	var trailing: Rect2 = carets.get("trailing_rect", Rect2())
	if leading.size.y <= 0.0 or trailing.size.y <= 0.0 or is_equal_approx(leading.position.x, trailing.position.x):
		return NAN
	return _text_origin_x() + trailing.position.x

# +1 if moving the caret one column forward moves it to the right on screen, otherwise -1.
func _visual_right_step(column: int) -> int:
	var length: int = _edit().text.length()
	if length == 0:
		return 1
	if column < length:
		return 1 if _caret_x(column + 1) >= _caret_x(column) else -1
	return 1 if _caret_x(column) >= _caret_x(column - 1) else -1

# Width taken by the clear button or the right icon, which push centered and right-aligned text
# (and the visible area) inwards. Zero when neither is shown.
func _right_icon_width() -> float:
	var edit: LineEdit = _edit()
	if edit.right_icon != null:
		return float(edit.right_icon.get_width())
	if edit.clear_button_enabled and edit.editable and not edit.text.is_empty():
		return float(edit.get_theme_icon("clear").get_width())
	return 0.0

# X (in control space) where the text starts: margins, alignment (swapped for right-to-left
# layouts) and the scroll offset the engine reports (negative once the text is wider).
func _text_origin_x() -> float:
	var style: StyleBox = _style()
	var left: float = style.get_margin(SIDE_LEFT)
	var right: float = style.get_margin(SIDE_RIGHT)
	var scroll: float = _edit().get_scroll_offset()
	var width: float = _shaped().get_line_width()
	var icon: float = _right_icon_width()
	var alignment: int = _edit().alignment
	if alignment == HORIZONTAL_ALIGNMENT_FILL:
		alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _edit().is_layout_rtl() and alignment != HORIZONTAL_ALIGNMENT_CENTER:
		alignment = HORIZONTAL_ALIGNMENT_RIGHT if alignment == HORIZONTAL_ALIGNMENT_LEFT else HORIZONTAL_ALIGNMENT_LEFT
	match alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			if scroll != 0.0:
				return left + scroll
			return left + maxf(0.0, floorf((control.size.x - left - right - width - icon) * 0.5))
		HORIZONTAL_ALIGNMENT_RIGHT:
			# With an icon the engine keeps a second right margin as well.
			var icon_space: float = icon + right if icon > 0.0 else 0.0
			return maxf(left, control.size.x - right - width - icon_space) + scroll
	return left + scroll

#endregion
