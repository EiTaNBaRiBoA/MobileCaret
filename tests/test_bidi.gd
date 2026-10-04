# Right-to-left and mixed-direction text: handle positions must match the engine's own caret.
# Run with:  godot --path <project> res://MobileCaret/tests/test_bidi.tscn
extends Node

const HEBREW: String = "שלום עולם זה טקסט"
const ARABIC: String = "مرحبا بالعالم هذا نص"
const MIXED: String = "Hello שלום world عالم 123 end"
const LONG_HEBREW: String = "שלום עולם זה טקסט ארוך מאוד כדי לבדוק גלילה של שדה הטקסט הזה כשהוא ארוך יותר מהרוחב"

var _failures: int = 0
var _checks: int = 0
var _controller: carets_controller
var _root: Control


func _ready() -> void:
	_controller = get_node("/root/MobileCaret") as carets_controller
	var toolbar: Node = get_node_or_null("/root/MobileCaretToolbar")
	if toolbar != null:
		toolbar.set("enabled", false)
	await _frames(2)
	await _test_line_edit_caret_positions()
	await _test_line_edit_clicks()
	await _test_line_edit_drag()
	await _test_line_edit_edge_scroll()
	await _test_text_edit_caret_positions()
	await _test_text_edit_scrolled_and_gutters()
	await _test_text_edit_handles()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


#region Helpers

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)
	else:
		print("ok:   ", message)

func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame

func _reset() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	await _frames(3)

func _handle(index: int) -> caret_indicator:
	return _controller.get_node("Handles").get_child(index) as caret_indicator

func _to_window(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos

func _mouse_move(pos: Vector2) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = _to_window(pos)
	ev.global_position = ev.position
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)

func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = _to_window(pos)
	ev.global_position = ev.position
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)

# A click that bypasses the handles (they can cover the text next to the caret).
func _click(pos: Vector2) -> void:
	_controller.visible = false
	_mouse_move(pos)
	_mouse_button(pos, true)
	await _frames(1)
	_mouse_button(pos, false)
	await _frames(2)
	_controller.visible = true

func _drag_handle_to(handle: caret_indicator, target_tip: Vector2, hold_frames: int = 3) -> void:
	var start_pointer: Vector2 = handle.global_position + handle.size * 0.5
	var delta: Vector2 = target_tip - handle.get_tip()
	_mouse_move(start_pointer)
	_mouse_button(start_pointer, true)
	await _frames(1)
	for i: int in range(1, 7):
		_mouse_move(start_pointer + delta * (float(i) / 6.0))
		await _frames(1)
	await _frames(hold_frames)
	_mouse_button(start_pointer + delta, false)
	await _frames(2)

func _focus(control: Control) -> void:
	control.grab_focus()
	await _frames(4)

func _tip_of(control: Control, pos: Vector2i) -> Vector2:
	return control.get_global_transform_with_canvas() * caret_text_adapter.for_control(control).get_tip_local(pos)

# X positions (viewport space) of the red caret pixels on a control's middle row.
func _red_caret_xs(control: Control) -> Array[float]:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var image_scale: float = float(image.get_width()) / get_viewport().get_visible_rect().size.x
	var middle: Vector2 = control.get_global_rect().get_center()
	var y: int = int(middle.y * image_scale)
	var found: Array[float] = []
	for x: int in image.get_width():
		var color: Color = image.get_pixel(x, y)
		# A faint red is enough: in a scaled window the 1 px caret can straddle two pixels.
		if color.r - maxf(color.g, color.b) > 0.1:
			found.append((float(x) + 0.5) / image_scale)
	return found

func _red_line_edit(position: Vector2, size: Vector2 = Vector2(500.0, 60.0)) -> LineEdit:
	var edit: LineEdit = LineEdit.new()
	edit.position = position
	edit.size = size
	edit.add_theme_font_size_override("font_size", 32)
	edit.add_theme_color_override("caret_color", Color(1.0, 0.0, 0.0))
	edit.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0))
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.9, 0.9, 0.9)
	# Asymmetric margins, so alignment maths that ignores them would be caught.
	style.content_margin_left = 6.0
	style.content_margin_right = 22.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_stylebox_override("focus", style)
	edit.caret_blink = false
	_root.add_child(edit)
	return edit

#endregion


#region LineEdit

# The adapter's caret x must match the caret the engine really draws.
func _test_line_edit_caret_positions() -> void:
	print("\n== LineEdit: caret positions in right-to-left and mixed text")
	await _reset()
	var edit: LineEdit = _red_line_edit(Vector2(20.0, 100.0))
	await _frames(2)
	await _focus(edit)
	var adapter: caret_text_adapter = caret_text_adapter.for_control(edit)
	for layout: int in [Control.LAYOUT_DIRECTION_LTR, Control.LAYOUT_DIRECTION_RTL]:
		for alignment: int in [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT]:
			edit.layout_direction = layout as Control.LayoutDirection
			edit.alignment = alignment as HorizontalAlignment
			for sample: String in [HEBREW, ARABIC, MIXED, LONG_HEBREW, "Plain ASCII text"]:
				edit.text = sample
				var checked: int = 0
				var wrong: int = 0
				for column: int in range(0, sample.length() + 1):
					edit.caret_column = column
					await _frames(2)
					var real: Array[float] = await _red_caret_xs(edit)
					if real.is_empty():
						continue
					var mine: float = _tip_of(edit, Vector2i(column, 0)).x
					var nearest: float = INF
					for x: float in real:
						nearest = minf(nearest, absf(x - mine))
					# A direction change has two carets; seeing only the other one is fine too.
					var other: float = (adapter as caret_line_edit_adapter).get_alternative_caret_x(column)
					if not is_nan(other):
						var other_viewport_x: float = edit.get_global_transform_with_canvas().x.x * other + edit.get_global_transform_with_canvas().origin.x
						for x: float in real:
							nearest = minf(nearest, absf(x - other_viewport_x))
					checked += 1
					if nearest > maxf(2.0, 1.5 / get_viewport().get_final_transform().get_scale().x):
						wrong += 1
				# (In a scaled window the thin caret is sometimes not drawn at all, so a few columns
				# cannot be observed; those are skipped.)
				var needed: int = 3 if get_viewport().get_final_transform().get_scale().x >= 0.8 else 1
				_check(checked >= needed and wrong == 0, "layout %s align %d '%s': %d of %d caret positions match the real caret" % ["RTL" if layout == Control.LAYOUT_DIRECTION_RTL else "LTR", alignment, sample.left(14), checked - wrong, checked])
	edit.layout_direction = Control.LAYOUT_DIRECTION_LTR
	edit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# The clear button pushes centered and right-aligned text inwards.
	edit.clear_button_enabled = true
	for alignment: int in [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT]:
		edit.alignment = alignment as HorizontalAlignment
		edit.text = "clear button text"
		var checked: int = 0
		var wrong: int = 0
		for column: int in range(0, 18):
			edit.caret_column = column
			await _frames(2)
			var real: Array[float] = await _red_caret_xs(edit)
			if real.is_empty():
				continue
			var mine: float = _tip_of(edit, Vector2i(column, 0)).x
			var nearest: float = INF
			for x: float in real:
				nearest = minf(nearest, absf(x - mine))
			checked += 1
			if nearest > maxf(2.5, 1.5 / get_viewport().get_final_transform().get_scale().x):
				wrong += 1
		_check(checked >= (1 if get_viewport().get_final_transform().get_scale().x < 0.8 else 3) and wrong == 0, "clear button, align %d: %d of %d caret positions match the real caret" % [alignment, checked - wrong, checked])
	edit.clear_button_enabled = false
	edit.alignment = HORIZONTAL_ALIGNMENT_LEFT

# Clicking where the adapter says a column is must land the caret on that visual spot.
func _test_line_edit_clicks() -> void:
	print("\n== LineEdit: clicking right-to-left and mixed text")
	await _reset()
	var edit: LineEdit = _red_line_edit(Vector2(20.0, 100.0))
	await _frames(2)
	await _focus(edit)
	var adapter: caret_text_adapter = caret_text_adapter.for_control(edit)
	for sample: String in [HEBREW, ARABIC, MIXED]:
		edit.text = sample
		await _frames(2)
		var checked: int = 0
		var wrong: int = 0
		for column: int in range(1, sample.length(), 3):
			var target: Vector2 = _tip_of(edit, Vector2i(column, 0)) - Vector2(0.0, adapter.get_line_height() * 0.5)
			edit.caret_column = 0
			await _frames(1)
			await _click(target)
			var landed: float = _tip_of(edit, Vector2i(edit.caret_column, 0)).x
			checked += 1
			if absf(landed - target.x) > 2.0:
				wrong += 1
		_check(wrong == 0, "'%s': %d of %d clicks land on the caret position that was aimed at" % [sample.left(14), checked - wrong, checked])
		# And the adapter's own position-from-point agrees with the engine's click.
		var agree: int = 0
		var tried: int = 0
		var disagreements: String = ""
		for x: float in [60.0, 120.0, 200.0, 300.0, 400.0]:
			var wanted_point: Vector2 = Vector2(edit.global_position.x + x, edit.global_position.y + edit.size.y * 0.5)
			# Injected clicks are rounded to whole window pixels; compare with the rounded point.
			var final_transform: Transform2D = get_viewport().get_final_transform()
			var point: Vector2 = final_transform.affine_inverse() * (final_transform * wanted_point).round()
			edit.caret_column = 0
			await _frames(1)
			await _click(point)
			var local: Vector2 = edit.get_global_transform_with_canvas().affine_inverse() * point
			var mine: Vector2i = adapter.get_pos_at_local(local)
			tried += 1
			var mine_x: float = _tip_of(edit, mine).x
			var engine_x: float = _tip_of(edit, Vector2i(edit.caret_column, 0)).x
			# A click exactly halfway between two carets can fairly go either way.
			var halfway: bool = absf(point.x - (mine_x + engine_x) * 0.5) <= 1.5
			if absf(mine_x - engine_x) < 2.0 or halfway:
				agree += 1
			else:
				disagreements += " [x %.0f local %.2f: engine col %d, mine col %d]" % [x, local.x, edit.caret_column, mine.x]
		_check(agree == tried, "'%s': get_pos_at_local agrees with the engine's click (%d of %d)%s" % [sample.left(14), agree, tried, disagreements])

func _test_line_edit_drag() -> void:
	print("\n== LineEdit: dragging handles in right-to-left text")
	await _reset()
	var edit: LineEdit = _red_line_edit(Vector2(20.0, 100.0))
	edit.text = HEBREW
	await _frames(2)
	await _focus(edit)
	edit.deselect()
	edit.caret_column = 3
	await _frames(4)
	var adapter: caret_text_adapter = caret_text_adapter.for_control(edit)
	_check(_handle(0).visible and _handle(0).get_tip().distance_to(_tip_of(edit, Vector2i(3, 0))) < 1.5, "the handle sits at the caret in Hebrew text")
	# In right-to-left text a higher column is further LEFT on screen.
	_check(_tip_of(edit, Vector2i(10, 0)).x < _tip_of(edit, Vector2i(3, 0)).x, "sanity: column 10 is left of column 3")
	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(10, 0)))
	_check(edit.caret_column == 10, "dragging the handle to the left moves to column 10 (got %d)" % edit.caret_column)
	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(2, 0)))
	_check(edit.caret_column == 2, "dragging back to the right moves to column 2 (got %d)" % edit.caret_column)
	# Selection handles.
	edit.select(4, 9)
	edit.caret_column = 9
	await _frames(4)
	var visible_count: int = int(_handle(0).visible) + int(_handle(1).visible)
	_check(visible_count == 2, "two selection handles in Hebrew text")
	var tips: Array[float] = [_handle(0).get_tip().x, _handle(1).get_tip().x]
	var expected: Array[float] = [_tip_of(edit, Vector2i(4, 0)).x, _tip_of(edit, Vector2i(9, 0)).x]
	_check(absf(tips[0] - expected[0]) < 1.5 and absf(tips[1] - expected[1]) < 1.5, "the selection handles sit at both ends of the selection")
	# Drag the end handle (logical end, visually left) further left.
	await _drag_handle_to(_handle(1), _tip_of(edit, Vector2i(13, 0)))
	_check(edit.has_selection() and edit.get_selection_from_column() == 4 and edit.get_selection_to_column() == 13, "dragging the end handle extends the selection to 4..13 (got %d..%d)" % [edit.get_selection_from_column(), edit.get_selection_to_column()])

func _test_line_edit_edge_scroll() -> void:
	print("\n== LineEdit: edge scrolling follows the visual direction")
	await _reset()
	var edit: LineEdit = _red_line_edit(Vector2(20.0, 100.0), Vector2(400.0, 60.0))
	edit.text = LONG_HEBREW
	await _frames(2)
	await _focus(edit)
	edit.deselect()
	edit.caret_column = 40
	await _frames(4)
	var rect: Rect2 = edit.get_global_rect()
	var start_column: int = edit.caret_column
	# Dragging past the visual RIGHT edge moves towards the start of right-to-left text.
	await _drag_handle_to(_handle(0), Vector2(rect.end.x + 40.0, _handle(0).get_tip().y), 60)
	_check(edit.caret_column < start_column, "dragging past the right edge moves back in Hebrew text (col %d -> %d)" % [start_column, edit.caret_column])
	var middle_column: int = edit.caret_column
	await _drag_handle_to(_handle(0), Vector2(rect.position.x - 40.0, _handle(0).get_tip().y), 60)
	_check(edit.caret_column > middle_column, "dragging past the left edge moves forward in Hebrew text (col %d -> %d)" % [middle_column, edit.caret_column])

#endregion


#region TextEdit

# Native caret x for every column of every line, including wrap boundaries.
func _check_text_edit_positions(edit: TextEdit, label: String) -> void:
	var adapter: caret_text_adapter = caret_text_adapter.for_control(edit)
	var checked: int = 0
	var wrong: int = 0
	var ambiguous: int = 0
	var first_wrong: String = ""
	for line: int in edit.get_line_count():
		for column: int in edit.get_line(line).length() + 1:
			edit.set_caret_line(line)
			edit.set_caret_column(column)
			await _frames(2)
			var pos: Vector2i = Vector2i(column, line)
			if not adapter.is_pos_visible(pos):
				continue
			var native: Vector2 = Vector2(edit.get_caret_draw_pos())
			var tip: Vector2 = adapter.get_tip_local(pos)
			checked += 1
			var empty_line: bool = edit.get_line(line).is_empty()
			# At a direction change there are two valid carets; the engine may draw either one.
			var x_ok: bool = absf(tip.x - native.x) <= 2.0
			var alternative: float = (adapter as caret_text_edit_adapter).last_alternative_x
			if not x_ok and not is_nan(alternative) and absf(alternative - native.x) <= 2.0:
				x_ok = true
				ambiguous += 1
			if not x_ok or (not empty_line and absf(tip.y - native.y) > 4.0):
				wrong += 1
				if first_wrong.is_empty():
					first_wrong = " (first: %s mine %s native %s)" % [str(pos), str(tip), str(native)]
	_check(checked > 20 and wrong == 0, "%s: %d of %d caret positions match the native caret (%d at direction changes where the engine drew the other valid one)%s" % [label, checked - wrong, checked, ambiguous, first_wrong])

func _test_text_edit_caret_positions() -> void:
	print("\n== TextEdit: caret positions in right-to-left and mixed text")
	await _reset()
	var edit: TextEdit = TextEdit.new()
	edit.position = Vector2(20.0, 100.0)
	edit.size = Vector2(560.0, 420.0)
	edit.add_theme_font_size_override("font_size", 28)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_root.add_child(edit)
	await _frames(2)
	await _focus(edit)
	edit.text = "%s\n%s\n%s\nabc שלום 123 def مرحبا\n%s" % [HEBREW, ARABIC, MIXED, LONG_HEBREW]
	await _frames(3)
	await _check_text_edit_positions(edit, "wrapped LTR layout")
	edit.text_direction = Control.TEXT_DIRECTION_RTL
	await _frames(3)
	await _check_text_edit_positions(edit, "wrapped, text direction RTL")
	edit.text_direction = Control.TEXT_DIRECTION_INHERITED
	edit.layout_direction = Control.LAYOUT_DIRECTION_RTL
	await _frames(3)
	await _check_text_edit_positions(edit, "wrapped, layout direction RTL")
	edit.layout_direction = Control.LAYOUT_DIRECTION_LTR
	# A long text makes the vertical scrollbar appear.
	var lines: PackedStringArray = []
	for i: int in 40:
		lines.append("%s %d" % [HEBREW, i])
	edit.text = "\n".join(lines)
	await _frames(3)
	edit.scroll_vertical = 0
	await _check_text_edit_positions(edit, "with the vertical scrollbar showing")
	edit.layout_direction = Control.LAYOUT_DIRECTION_RTL
	await _frames(3)
	await _check_text_edit_positions(edit, "scrollbar showing, RTL layout")
	edit.layout_direction = Control.LAYOUT_DIRECTION_LTR

func _test_text_edit_scrolled_and_gutters() -> void:
	print("\n== TextEdit / CodeEdit: gutters and horizontal scrolling with right-to-left text")
	await _reset()
	var code: CodeEdit = CodeEdit.new()
	code.position = Vector2(20.0, 100.0)
	code.size = Vector2(560.0, 300.0)
	code.add_theme_font_size_override("font_size", 24)
	code.gutters_draw_line_numbers = true
	code.text = "# %s\nvar name = \"%s\"\nprint(\"%s\")\nfunc f():\n\treturn 1" % [HEBREW, ARABIC, MIXED]
	_root.add_child(code)
	await _frames(3)
	await _focus(code)
	await _check_text_edit_positions(code, "CodeEdit with line numbers")
	var plain: TextEdit = TextEdit.new()
	plain.position = Vector2(20.0, 420.0)
	plain.size = Vector2(300.0, 160.0)
	plain.add_theme_font_size_override("font_size", 24)
	plain.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	plain.text = "%s %s\n%s" % [LONG_HEBREW, MIXED, HEBREW]
	_root.add_child(plain)
	await _frames(3)
	await _focus(plain)
	plain.set_caret_line(0)
	plain.set_caret_column(20)
	await _frames(3)
	plain.scroll_horizontal = 150
	await _frames(3)
	await _check_text_edit_positions(plain, "no wrap, scrolled sideways")

func _test_text_edit_handles() -> void:
	print("\n== TextEdit: handles on right-to-left text")
	await _reset()
	var edit: TextEdit = TextEdit.new()
	edit.position = Vector2(20.0, 100.0)
	edit.size = Vector2(560.0, 300.0)
	edit.add_theme_font_size_override("font_size", 28)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.text = "%s\n%s\n%s" % [HEBREW, ARABIC, MIXED]
	_root.add_child(edit)
	await _frames(3)
	await _focus(edit)
	edit.set_caret_line(0)
	edit.set_caret_column(3)
	await _frames(4)
	_check(_handle(0).visible and _handle(0).get_tip().distance_to(_tip_of(edit, Vector2i(3, 0))) < 1.5, "the handle sits at the caret in Hebrew text")
	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(9, 1)))
	_check(edit.get_caret_line() == 1 and edit.get_caret_column() == 9, "dragging the handle to column 9 of the Arabic line (got %d,%d)" % [edit.get_caret_column(), edit.get_caret_line()])
	edit.select(0, 2, 0, 9)
	await _frames(4)
	_check(int(_handle(0).visible) + int(_handle(1).visible) == 2, "two selection handles in Hebrew text")
	_check(_handle(0).get_tip().distance_to(_tip_of(edit, Vector2i(2, 0))) < 1.5 and _handle(1).get_tip().distance_to(_tip_of(edit, Vector2i(9, 0))) < 1.5, "the selection handles sit at both ends")
	await _drag_handle_to(_handle(1), _tip_of(edit, Vector2i(5, 1)))
	_check(edit.get_selection_from_line() == 0 and edit.get_selection_from_column() == 2 and edit.get_selection_to_line() == 1 and edit.get_selection_to_column() == 5, "dragging the end handle extends across lines to (2,0)..(5,1) (got (%d,%d)..(%d,%d))" % [edit.get_selection_from_column(), edit.get_selection_from_line(), edit.get_selection_to_column(), edit.get_selection_to_line()])

#endregion
