# Integration test: drives real input events through the viewport against the example scene.
# Run with:  godot --path <project> res://MobileCaret/tests/test_carets.tscn
# Exits with code 0 when everything passes, 1 otherwise.
extends Node

const EXAMPLE_SCENE: String = "res://MobileCaret/addons/MobileCaret/Examples/example_scene.tscn"

var _failures: int = 0
var _checks: int = 0
var _example: Node
var _controller: carets_controller
var _screenshots_dir: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_screenshots_dir = arg.trim_prefix("--shots=")
	_controller = get_node("/root/MobileCaret") as carets_controller
	_example = (load(EXAMPLE_SCENE) as PackedScene).instantiate()
	add_child(_example)
	await _frames(3)
	await _test_line_edit_caret_drag()
	await _test_line_edit_selection()
	await _test_line_edit_edge_scroll()
	await _test_text_edit_geometry()
	await _test_text_edit_caret_drag()
	await _test_text_edit_selection()
	await _test_text_edit_edge_scroll()
	await _test_long_press()
	await _test_focus_changes()

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

func _node(path: String) -> Control:
	return _example.get_node("Panel/MarginContainer/VBoxContainer/" + path) as Control

func _handle(index: int) -> caret_indicator:
	return _controller.get_node("Handles").get_child(index) as caret_indicator

func _visible_handles() -> int:
	return int(_handle(0).visible) + int(_handle(1).visible)

# Viewport position of the middle of the line at a text position.
func _text_point(control: Control, pos: Vector2i) -> Vector2:
	var adapter: caret_text_adapter = caret_text_adapter.for_control(control)
	var tip: Vector2 = adapter.get_tip_local(pos)
	# One pixel right of the column boundary, so the engine's rounding is unambiguous.
	return control.get_global_transform_with_canvas() * (tip + Vector2(1.0, -adapter.get_line_height() * 0.5))

# Events are injected like the OS does: in window pixels, before the stretch transform.
func _to_window(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos

func _mouse_move(logical_pos: Vector2) -> void:
	var pos: Vector2 = _to_window(logical_pos)
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)

func _mouse_button(logical_pos: Vector2, pressed: bool, double_click: bool = false) -> void:
	var pos: Vector2 = _to_window(logical_pos)
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.double_click = double_click
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)

func _click(pos: Vector2, double_click: bool = false) -> void:
	_mouse_move(pos)
	_mouse_button(pos, true, double_click)
	await _frames(1)
	_mouse_button(pos, false)
	await _frames(1)

# Presses a handle, drags its tip to `target_tip` (viewport space) and releases.
func _drag_handle_to(handle: caret_indicator, target_tip: Vector2, hold_frames: int = 3) -> void:
	var start_pointer: Vector2 = handle.global_position + handle.size * 0.5
	var delta: Vector2 = target_tip - handle.get_tip()
	_mouse_move(start_pointer)
	_mouse_button(start_pointer, true)
	await _frames(1)
	var steps: int = 6
	for i: int in range(1, steps + 1):
		_mouse_move(start_pointer + delta * (float(i) / steps))
		await _frames(1)
	await _frames(hold_frames)
	_mouse_button(start_pointer + delta, false)
	await _frames(2)

func _focus(control: Control) -> void:
	control.grab_focus()
	await _frames(3)

func _sel(edit: LineEdit) -> String:
	if not edit.has_selection():
		return "none"
	return "%d..%d" % [edit.get_selection_from_column(), edit.get_selection_to_column()]

func _tip_of(control: Control, pos: Vector2i) -> Vector2:
	var adapter: caret_text_adapter = caret_text_adapter.for_control(control)
	return control.get_global_transform_with_canvas() * adapter.get_tip_local(pos)

func _screenshot(name: String) -> void:
	if _screenshots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_screenshots_dir.path_join(name + ".png"))

#endregion


#region LineEdit

# Godot's own click-to-caret is the oracle for where each column is drawn.
func _test_line_edit_geometry() -> void:
	print("\n== LineEdit geometry")
	var edit: LineEdit = _node("LineEdit") as LineEdit
	var text: String = "The quick brown fox jumps over the lazy dog and keeps on running far away"
	var cases: Array[Dictionary] = [
		{"alignment": HORIZONTAL_ALIGNMENT_LEFT, "text": "short"},
		{"alignment": HORIZONTAL_ALIGNMENT_LEFT, "text": text},
		{"alignment": HORIZONTAL_ALIGNMENT_CENTER, "text": "short"},
		{"alignment": HORIZONTAL_ALIGNMENT_RIGHT, "text": "short"},
	]
	for case: Dictionary in cases:
		edit.alignment = case["alignment"]
		edit.text = case["text"]
		await _focus(edit)
		var length: int = edit.text.length()
		var columns: Array[int] = [0, length / 3, length / 2, length]
		for column: int in columns:
			edit.caret_column = column
			await _frames(2)
			# Click where my adapter says `target` is, expect the engine to agree.
			# The caret stays where it is, so long texts are tested in their scrolled state.
			var target: int = clampi(column - 2, 0, length)
			var point: Vector2 = _text_point(edit, Vector2i(target, 0))
			edit.deselect()
			await _frames(1)
			await _click(point)
			_check(edit.caret_column == target, "LineEdit align=%d len=%d scroll=%s: click on col %d -> caret %d" % [case["alignment"], length, str(edit.get_scroll_offset()), target, edit.caret_column])
	edit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	edit.text = "Drag the handle under the caret to move it"

func _test_line_edit_caret_drag() -> void:
	print("\n== LineEdit caret drag")
	var edit: LineEdit = _node("LineEdit") as LineEdit
	edit.text = "Drag the handle under the caret to move it"
	await _focus(edit)
	edit.caret_column = 4
	await _frames(2)
	_check(_handle(0).visible and not _handle(1).visible, "single handle visible under caret")
	var expected_tip: Vector2 = _tip_of(edit, Vector2i(4, 0))
	_check(_handle(0).get_tip().distance_to(expected_tip) < 1.5, "handle tip at caret (%s vs %s)" % [str(_handle(0).get_tip()), str(expected_tip)])
	await _screenshot("lineedit_caret")

	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(15, 0)))
	_check(edit.caret_column == 15, "dragging handle moves caret to col 15 (got %d)" % edit.caret_column)
	_check(not edit.has_selection(), "dragging the single handle does not select")
	_check(edit.has_focus(), "LineEdit keeps focus while handle is dragged")
	_check(_handle(0).visible and not _handle(1).visible, "still one handle after drag")

	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(2, 0)))
	_check(edit.caret_column == 2, "dragging handle back moves caret to col 2 (got %d)" % edit.caret_column)

func _test_line_edit_selection() -> void:
	print("\n== LineEdit selection")
	var edit: LineEdit = _node("LineEdit") as LineEdit
	edit.text = "Drag the handle under the caret to move it"
	await _focus(edit)
	edit.select(3, 9)
	edit.caret_column = 9
	await _frames(3)
	_check(_visible_handles() == 2, "two handles for a selection")
	_check(_handle(0).get_tip().distance_to(_tip_of(edit, Vector2i(3, 0))) < 1.5, "start handle at selection start")
	_check(_handle(1).get_tip().distance_to(_tip_of(edit, Vector2i(9, 0))) < 1.5, "end handle at selection end")
	await _screenshot("lineedit_selection")

	await _drag_handle_to(_handle(1), _tip_of(edit, Vector2i(14, 0)))
	_check(edit.has_selection() and edit.get_selection_from_column() == 3 and edit.get_selection_to_column() == 14, "end handle extends selection to 3..14 (got %s)" % [_sel(edit)])
	_check(edit.has_focus(), "focus retained after selection drag")

	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(6, 0)))
	_check(edit.has_selection() and edit.get_selection_from_column() == 6 and edit.get_selection_to_column() == 14, "start handle shrinks selection to 6..14 (got %s)" % [_sel(edit)])

	# Drag the start handle past the end handle: the selection flips.
	var start_handle: caret_indicator = _handle(0) if _handle(0).get_tip().x < _handle(1).get_tip().x else _handle(1)
	await _drag_handle_to(start_handle, _tip_of(edit, Vector2i(20, 0)))
	_check(edit.has_selection() and edit.get_selection_from_column() == 14 and edit.get_selection_to_column() == 20, "crossing handles gives selection 14..20 (got %s)" % [_sel(edit)])
	_check(_visible_handles() == 2, "two handles after crossing")

func _test_line_edit_edge_scroll() -> void:
	print("\n== LineEdit edge scroll")
	var edit: LineEdit = _node("LineEdit") as LineEdit
	edit.text = "The quick brown fox jumps over the lazy dog and keeps on running far away"
	await _focus(edit)
	edit.caret_column = 3
	await _frames(3)
	var handle: caret_indicator = _handle(0)
	var right_edge: Vector2 = Vector2(edit.get_global_rect().end.x + 30.0, handle.get_tip().y)
	await _drag_handle_to(handle, right_edge, 90)
	_check(edit.caret_column > 20, "dragging past the right edge scrolls the caret along (col %d)" % edit.caret_column)
	_check(edit.get_scroll_offset() < 0.0, "LineEdit scrolled")
	_check(_handle(0).visible, "handle visible while scrolled to caret")
	await _screenshot("lineedit_scrolled")
	var left_edge: Vector2 = Vector2(edit.get_global_rect().position.x - 30.0, _handle(0).get_tip().y)
	var before: int = edit.caret_column
	await _drag_handle_to(_handle(0), left_edge, 90)
	_check(edit.caret_column < before, "dragging past the left edge moves caret back (col %d -> %d)" % [before, edit.caret_column])
	edit.text = "Drag the handle under the caret to move it"

#endregion


#region TextEdit

func _test_text_edit_geometry() -> void:
	print("\n== TextEdit geometry")
	# The native caret's draw position is the oracle for every column of every line,
	# including wrap boundaries.
	var tall: TextEdit = _node("TextEdit") as TextEdit
	var old_height: float = tall.custom_minimum_size.y
	tall.custom_minimum_size.y = 400.0
	await _focus(tall)
	tall.scroll_vertical = 0
	var mismatches: int = 0
	var compared: int = 0
	for line: int in tall.get_line_count():
		for column: int in tall.get_line(line).length() + 1:
			tall.set_caret_line(line)
			tall.set_caret_column(column)
			await _frames(1)
			var adapter: caret_text_adapter = caret_text_adapter.for_control(tall)
			if not adapter.is_pos_visible(Vector2i(column, line)):
				continue
			compared += 1
			var tip: Vector2 = adapter.get_tip_local(Vector2i(column, line))
			var draw: Vector2 = Vector2(tall.get_caret_draw_pos())
			if absf(tip.x - draw.x) > 1.5 or absf(tip.y - draw.y) > 3.0:
				mismatches += 1
				printerr("  mismatch at (%d,%d): tip %s vs native caret %s" % [column, line, str(tip), str(draw)])
	_check(compared > 100 and mismatches == 0, "TextEdit(wrapped): handle tip matches native caret at %d positions, %d mismatches" % [compared, mismatches])
	tall.custom_minimum_size.y = old_height
	await _frames(2)

	for name: String in ["TextEdit", "NoWrapTextEdit"]:
		var edit: TextEdit = _node(name) as TextEdit
		await _focus(edit)
		edit.scroll_vertical = 0
		var positions: Array[Vector2i] = [Vector2i(0, 0), Vector2i(10, 0), Vector2i(5, 1), Vector2i(3, 2)]
		for pos: Vector2i in positions:
			if pos.y >= edit.get_line_count():
				continue
			edit.set_caret_line(pos.y)
			edit.set_caret_column(pos.x)
			await _frames(2)
			var adapter: caret_text_adapter = caret_text_adapter.for_control(edit)
			if not adapter.is_pos_visible(pos):
				continue
			edit.deselect()
			edit.set_caret_line(0)
			edit.set_caret_column(0)
			await _frames(1)
			await _click(_text_point(edit, pos))
			_check(Vector2i(edit.get_caret_column(), edit.get_caret_line()) == pos, "%s: click on %s -> caret (%d,%d)" % [name, str(pos), edit.get_caret_column(), edit.get_caret_line()])

func _test_text_edit_caret_drag() -> void:
	print("\n== TextEdit caret drag")
	var edit: TextEdit = _node("TextEdit") as TextEdit
	await _focus(edit)
	edit.scroll_vertical = 0
	edit.deselect()
	edit.set_caret_line(0)
	edit.set_caret_column(4)
	await _frames(3)
	_check(_handle(0).visible and not _handle(1).visible, "single handle visible (h0=%s h1=%s scroll=%s caret=%s rect=%s)" % [_handle(0).visible, _handle(1).visible, edit.scroll_vertical, caret_text_adapter.for_control(edit).get_caret(), edit.get_rect_at_line_column(0, 4)])
	_check(_handle(0).get_tip().distance_to(_tip_of(edit, Vector2i(4, 0))) < 1.5, "handle tip at caret")
	await _screenshot("textedit_caret")
	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(10, 2)))
	_check(edit.get_caret_line() == 2 and edit.get_caret_column() == 10, "drag moves caret to (10,2) (got %d,%d)" % [edit.get_caret_column(), edit.get_caret_line()])
	_check(not edit.has_selection(), "no selection from single-handle drag")
	_check(edit.has_focus(), "TextEdit keeps focus")

func _test_text_edit_selection() -> void:
	print("\n== TextEdit selection")
	var edit: TextEdit = _node("TextEdit") as TextEdit
	await _focus(edit)
	edit.scroll_vertical = 0
	edit.select(0, 4, 0, 15)
	await _frames(3)
	_check(_visible_handles() == 2, "two handles for selection")
	await _screenshot("textedit_selection")
	await _drag_handle_to(_handle(1), _tip_of(edit, Vector2i(6, 2)))
	_check(edit.get_selection_from_line() == 0 and edit.get_selection_from_column() == 4 and edit.get_selection_to_line() == 2 and edit.get_selection_to_column() == 6,
		"end handle extends selection across lines to (4,0)..(6,2) (got (%d,%d)..(%d,%d))" % [edit.get_selection_from_column(), edit.get_selection_from_line(), edit.get_selection_to_column(), edit.get_selection_to_line()])
	var selected: String = edit.get_selected_text()
	_check(selected.begins_with("quick") and selected.ends_with("Third "), "selected text spans lines")
	_check(edit.has_focus(), "focus retained")
	# Drag the start handle below the end handle.
	var start_handle: caret_indicator = _handle(0) if (_handle(0).get_tip().y < _handle(1).get_tip().y or (is_equal_approx(_handle(0).get_tip().y, _handle(1).get_tip().y) and _handle(0).get_tip().x < _handle(1).get_tip().x)) else _handle(1)
	await _drag_handle_to(start_handle, _tip_of(edit, Vector2i(5, 3)))
	_check(edit.get_selection_from_line() == 2 and edit.get_selection_to_line() == 3, "crossing handles flips selection to lines 2..3 (got %d..%d)" % [edit.get_selection_from_line(), edit.get_selection_to_line()])

func _test_text_edit_edge_scroll() -> void:
	print("\n== TextEdit edge scroll")
	var edit: TextEdit = _node("TextEdit") as TextEdit
	var lines: PackedStringArray = []
	for i: int in 40:
		lines.append("Line number %d with some text" % i)
	edit.text = "\n".join(lines)
	await _focus(edit)
	edit.scroll_vertical = 0
	edit.deselect()
	edit.set_caret_line(0)
	edit.set_caret_column(2)
	await _frames(3)
	var below: Vector2 = Vector2(_handle(0).get_tip().x, edit.get_global_rect().end.y + 20.0)
	await _drag_handle_to(_handle(0), below, 60)
	_check(edit.scroll_vertical > 2.0, "dragging below the control scrolls it (scroll %s)" % str(edit.scroll_vertical))
	_check(edit.get_caret_line() > 4, "caret followed the drag (line %d)" % edit.get_caret_line())
	var scrolled_caret_line: int = edit.get_caret_line()
	await _screenshot("textedit_scrolled")
	# Selection with the anchor scrolled out of view: only one handle should show.
	edit.select(0, 2, scrolled_caret_line, 5)
	edit.scroll_vertical = scrolled_caret_line - 2
	await _frames(3)
	_check(_visible_handles() == 1, "anchor handle hidden when its line is scrolled out of view (visible: %d)" % _visible_handles())
	edit.deselect()
	edit.text = "The quick brown fox jumps over the lazy dog.\nSecond line of the wrapped text edit, long enough that it needs to wrap around the edge.\nThird line.\nFourth line.\nFifth line."
	edit.scroll_vertical = 0
	await _frames(2)

#endregion


func _test_long_press() -> void:
	print("\n== Long press")
	var edit: LineEdit = _node("LineEdit") as LineEdit
	edit.text = "Drag the handle under the caret to move it"
	await _focus(edit)
	edit.deselect()
	var point: Vector2 = _text_point(edit, Vector2i(11, 0)) # inside "handle"
	_mouse_move(point)
	_mouse_button(point, true)
	await _frames(1)
	_check(not edit.has_selection(), "no selection immediately after pressing")
	await get_tree().create_timer(_controller.long_press_seconds + 0.25).timeout
	_mouse_button(point, false)
	await _frames(2)
	_check(edit.has_selection() and edit.get_selected_text() == "handle", "long press selects the word under the finger (got '%s')" % edit.get_selected_text())
	_check(_visible_handles() == 2, "selection handles shown after long press")

	var text_edit: TextEdit = _node("TextEdit") as TextEdit
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await _frames(3)
	await _focus(text_edit)
	text_edit.deselect()
	text_edit.set_caret_line(0)
	text_edit.set_caret_column(0)
	text_edit.scroll_vertical = 0
	await _frames(3)
	var tpoint: Vector2 = _text_point(text_edit, Vector2i(22, 0)) # inside "jumps"
	_mouse_move(tpoint)
	_mouse_button(tpoint, true)
	await _frames(1)
	var pressed_pos: Vector2i = Vector2i(text_edit.get_caret_column(), text_edit.get_caret_line())
	var expected_word: Vector2i = caret_text_adapter.word_range(text_edit.get_line(pressed_pos.y), pressed_pos.x)
	var expected_text: String = text_edit.get_line(pressed_pos.y).substr(expected_word.x, expected_word.y - expected_word.x)
	await get_tree().create_timer(_controller.long_press_seconds + 0.25).timeout
	_mouse_button(tpoint, false)
	await _frames(2)
	_check(not expected_text.is_empty() and text_edit.get_selected_text() == expected_text, "TextEdit long press selects word under the finger (expected '%s', got '%s')" % [expected_text, text_edit.get_selected_text()])
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await _frames(3)

func _test_focus_changes() -> void:
	print("\n== Focus changes")
	var edit: LineEdit = _node("LineEdit") as LineEdit
	var other: TextEdit = _node("NoWrapTextEdit") as TextEdit
	await _focus(edit)
	edit.deselect()
	edit.caret_column = 3
	await _frames(2)
	_check(_handle(0).visible, "handle shown for focused LineEdit")
	await _focus(other)
	other.deselect()
	other.set_caret_line(0)
	other.set_caret_column(5)
	await _frames(2)
	var tip: Vector2 = _handle(0).get_tip()
	_check(_handle(0).visible and tip.distance_to(_tip_of(other, Vector2i(5, 0))) < 1.5, "handle follows focus to the other control")
	other.release_focus()
	await _frames(3)
	_check(_visible_handles() == 0, "handles hidden when focus is lost")
	var label: Control = _node("LineEditTitle")
	_check(not (label is LineEdit), "sanity: label unsupported")
	# Hidden control while focused.
	await _focus(edit)
	edit.caret_column = 3
	await _frames(2)
	edit.hide()
	await _frames(3)
	_check(_visible_handles() == 0, "handles hidden when control is hidden")
	edit.show()
