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
	_apply_window_args()
	_controller = get_node("/root/MobileCaret") as carets_controller
	_example = (load(EXAMPLE_SCENE) as PackedScene).instantiate()
	add_child(_example)
	# Keep the tested columns/lines on screen whatever the window shape: a smaller LineEdit font
	# and a TextEdit tall enough for all five lines even when they wrap more.
	(_node("LineEdit") as LineEdit).add_theme_font_size_override("font_size", 32)
	(_node("TextEdit") as TextEdit).custom_minimum_size.y = 400.0
	await _frames(3)

	await _test_line_edit_geometry()
	await _test_line_edit_caret_drag()
	await _test_line_edit_selection()
	await _test_line_edit_edge_scroll()
	await _test_text_edit_geometry()
	await _test_text_edit_caret_drag()
	await _test_text_edit_selection()
	await _test_text_edit_edge_scroll()
	await _test_long_press()
	await _test_drag_precision()
	await _test_native_caret_hiding()
	await _test_caret_fade()
	await _test_edge_scroll_steadiness()
	await _test_typing_and_taps()
	await _test_focus_changes()

	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# Optional window setup from the command line, to test other aspect ratios and stretch modes:
#   -- --stretch=disabled|canvas_items|viewport --aspect=keep|expand|ignore|keep_width|keep_height --scale=2.0
func _apply_window_args() -> void:
	var window: Window = get_window()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--stretch="):
			match arg.trim_prefix("--stretch="):
				"disabled": window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
				"canvas_items": window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
				"viewport": window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		elif arg.begins_with("--aspect="):
			match arg.trim_prefix("--aspect="):
				"keep": window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
				"expand": window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
				"ignore": window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
				"keep_width": window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
				"keep_height": window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT
		elif arg.begins_with("--scale="):
			window.content_scale_factor = arg.trim_prefix("--scale=").to_float()

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

	var pre_alpha: float = _handle(0).modulate.a
	var pre_tip: Vector2 = _handle(0).get_tip()
	var pre_vis: bool = _handle(0).visible
	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(15, 0)))
	_check(edit.caret_column == 15, "dragging handle moves caret to col 15 (got %d; before: alpha %.2f visible %s tip %s idle %.2f scroll %s)" % [edit.caret_column, pre_alpha, pre_vis, str(pre_tip), _controller._idle_time, str(edit.get_scroll_offset())])
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

	var dbg_h0: String = "h0 tip %s vis %s | h1 tip %s vis %s | size %s scroll %s | target tip %s" % [str(_handle(0).get_tip()), _handle(0).visible, str(_handle(1).get_tip()), _handle(1).visible, str(edit.size), str(edit.get_scroll_offset()), str(_tip_of(edit, Vector2i(6, 0)))]
	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(6, 0)))
	_check(edit.has_selection() and edit.get_selection_from_column() == 6 and edit.get_selection_to_column() == 14, "start handle shrinks selection to 6..14 (got %s) %s" % [_sel(edit), dbg_h0])

	# Drag the start handle past the end handle: the selection flips.
	var start_handle: caret_indicator = _handle(0) if _handle(0).get_tip().x < _handle(1).get_tip().x else _handle(1)
	await _drag_handle_to(start_handle, _tip_of(edit, Vector2i(20, 0)))
	_check(edit.has_selection() and edit.get_selection_from_column() == 14 and edit.get_selection_to_column() == 20, "crossing handles gives selection 14..20 (got %s)" % [_sel(edit)])
	_check(_visible_handles() == 2, "two handles after crossing")

func _test_line_edit_edge_scroll() -> void:
	print("\n== LineEdit edge scroll")
	var edit: LineEdit = _node("LineEdit") as LineEdit
	edit.text = "The quick brown fox jumps over the lazy dog and keeps on running far away ".repeat(int(edit.size.x / 400.0) + 1)
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
	edit.scroll_vertical = edit.get_scroll_pos_for_line(maxi(scrolled_caret_line - 2, 0))
	await _frames(3)
	_check(_visible_handles() == 1, "anchor handle hidden when its line is scrolled out of view (visible: %d; h0 %s %s h1 %s %s; scroll %s first-vis %d caret %d sel-from %d size %s)" % [_visible_handles(), _handle(0).visible, str(_handle(0).get_tip()), _handle(1).visible, str(_handle(1).get_tip()), str(edit.scroll_vertical), edit.get_first_visible_line(), scrolled_caret_line, edit.get_selection_from_line(), str(edit.size)])
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
	var saved_scale_mode: Window.ContentScaleMode = get_window().content_scale_mode
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await _frames(3)
	if not get_viewport().get_final_transform().is_equal_approx(Transform2D.IDENTITY):
		# TextEdit's click-hold timer reads the viewport's stored mouse position, which injected
		# events get wrong whenever any scaling is active. The LineEdit long press above covers it.
		print("skip: TextEdit long press (injected input is inexact under scaling)")
		get_window().content_scale_mode = saved_scale_mode
		await _frames(3)
		return
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
	get_window().content_scale_mode = saved_scale_mode
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


#region Drag precision, native caret, fade

func _test_drag_precision() -> void:
	print("\n== Drag precision")
	var edit: LineEdit = _node("LineEdit") as LineEdit
	edit.text = "Drag the handle under the caret to move it"
	await _focus(edit)
	edit.deselect()
	edit.caret_column = 4
	await _frames(3)
	var handle: caret_indicator = _handle(0)
	# Aim between columns 8 and 9, a bit closer to 9.
	var x8: float = _tip_of(edit, Vector2i(8, 0)).x
	var x9: float = _tip_of(edit, Vector2i(9, 0)).x
	var target_x: float = x8 + (x9 - x8) * 0.7
	var start_pointer: Vector2 = handle.global_position + handle.size * 0.5
	var delta_x: float = target_x - handle.get_tip().x
	_mouse_move(start_pointer)
	_mouse_button(start_pointer, true)
	await _frames(1)
	for i: int in range(1, 7):
		_mouse_move(start_pointer + Vector2(delta_x * i / 6.0, 0.0))
		await _frames(1)
	await _frames(2)
	var snapped_y: float = _tip_of(edit, Vector2i(9, 0)).y
	_check(absf(handle.get_tip().x - target_x) < 1.5, "mid-drag the handle follows the finger smoothly (tip x %.1f, finger x %.1f)" % [handle.get_tip().x, target_x])
	_check(absf(handle.get_tip().y - snapped_y) < 1.5, "mid-drag the handle stays snapped to the text line")
	_check(edit.caret_column == 9, "the caret snaps to the nearest character (got %d)" % edit.caret_column)
	_mouse_button(start_pointer + Vector2(delta_x, 0.0), false)
	await _frames(3)
	_check(handle.get_tip().distance_to(_tip_of(edit, Vector2i(9, 0))) < 1.5, "after release the handle snaps to the caret")
	# Dragging far outside the control keeps the handle inside it horizontally.
	var far_pointer: Vector2 = handle.global_position + handle.size * 0.5
	_mouse_move(far_pointer)
	_mouse_button(far_pointer, true)
	await _frames(1)
	_mouse_move(Vector2(edit.get_global_rect().end.x + 200.0, far_pointer.y))
	await _frames(3)
	_check(handle.get_tip().x <= edit.get_global_rect().end.x + 0.5, "dragged handle is kept inside the control horizontally")
	_mouse_button(far_pointer, false)
	await _frames(2)

func _caret_alpha(control: Control) -> float:
	return control.get_theme_color("caret_color").a

func _test_native_caret_hiding() -> void:
	print("\n== Native caret hiding")
	var edit: LineEdit = _node("CenteredLineEdit") as LineEdit
	var other: LineEdit = _node("LineEdit") as LineEdit
	edit.text = "centered text"
	# Case 1: no override on the control -> removed again afterwards.
	var original: Color = edit.get_theme_color("caret_color")
	var had_override: bool = edit.has_theme_color_override("caret_color")
	edit.remove_theme_color_override("caret_color")
	var default_alpha: float = _caret_alpha(edit)
	_controller.hide_native_caret = true
	_controller.hide_native_caret_while_dragging = false
	await _focus(edit)
	edit.caret_column = 3
	await _frames(3)
	_check(_caret_alpha(edit) == 0.0, "hide_native_caret hides the native caret while the handle shows")
	await _focus(other)
	await _frames(3)
	_check(not edit.has_theme_color_override("caret_color") and is_equal_approx(_caret_alpha(edit), default_alpha), "native caret restored (override removed) after focus leaves")
	# Case 2: an existing override is restored exactly.
	var custom: Color = Color(1.0, 0.0, 0.0, 0.8)
	edit.add_theme_color_override("caret_color", custom)
	await _focus(edit)
	edit.caret_column = 3
	await _frames(3)
	_check(_caret_alpha(edit) == 0.0, "native caret hidden with an existing override")
	await _focus(other)
	await _frames(3)
	_check(edit.has_theme_color_override("caret_color") and edit.get_theme_color("caret_color") == custom, "existing caret_color override restored exactly")
	# Case 3: only while dragging.
	_controller.hide_native_caret = false
	_controller.hide_native_caret_while_dragging = true
	await _focus(edit)
	edit.deselect()
	edit.caret_column = 3
	await _frames(3)
	_check(edit.get_theme_color("caret_color") == custom, "native caret visible when not dragging")
	var handle: caret_indicator = _handle(0)
	var pointer: Vector2 = handle.global_position + handle.size * 0.5
	_mouse_move(pointer)
	_mouse_button(pointer, true)
	await _frames(1)
	_mouse_move(pointer + Vector2(30.0, 0.0))
	await _frames(3)
	_check(_caret_alpha(edit) == 0.0, "native caret hidden while a handle is dragged")
	_mouse_button(pointer + Vector2(30.0, 0.0), false)
	await _frames(3)
	_check(edit.get_theme_color("caret_color") == custom, "native caret back after the drag ends")
	# Case 4: both off -> never touched.
	_controller.hide_native_caret_while_dragging = false
	await _focus(edit)
	var pointer2: Vector2 = _handle(0).global_position + _handle(0).size * 0.5
	_mouse_move(pointer2)
	_mouse_button(pointer2, true)
	await _frames(1)
	_mouse_move(pointer2 + Vector2(20.0, 0.0))
	await _frames(3)
	_check(edit.get_theme_color("caret_color") == custom, "both toggles off leave the native caret alone")
	_mouse_button(pointer2 + Vector2(20.0, 0.0), false)
	await _frames(2)
	# Restore the scene and defaults.
	await _focus(other)
	if had_override:
		edit.add_theme_color_override("caret_color", original)
	else:
		edit.remove_theme_color_override("caret_color")
	_controller.hide_native_caret = false
	_controller.hide_native_caret_while_dragging = true

func _test_caret_fade() -> void:
	print("\n== Caret handle fade")
	var edit: LineEdit = _node("LineEdit") as LineEdit
	edit.text = "Drag the handle under the caret to move it"
	_controller.caret_fade_delay = 0.4
	_controller.caret_fade_duration = 0.1
	await _focus(edit)
	edit.deselect()
	edit.caret_column = 5
	await _frames(3)
	_check(_handle(0).modulate.a > 0.99, "caret handle starts fully visible")
	await get_tree().create_timer(0.9).timeout
	_check(_handle(0).modulate.a < 0.05, "caret handle fades out after the idle delay (alpha %.2f)" % _handle(0).modulate.a)
	# With the native caret hidden by the toggle, a faded handle must give the real caret back.
	_controller.hide_native_caret = true
	await _frames(3)
	_check(_caret_alpha(edit) > 0.0, "native caret shown again while the handle is faded")
	_controller.hide_native_caret = false
	# A faded handle cannot be grabbed: the press reaches the text control.
	var tip: Vector2 = _handle(0).get_tip()
	var pointer: Vector2 = _handle(0).global_position + _handle(0).size * 0.5
	_mouse_move(pointer)
	_mouse_button(pointer, true)
	await _frames(1)
	_check(_controller._drag_handle == null, "a faded handle is not draggable")
	_mouse_button(pointer, false)
	await _frames(2)
	# Activity (moving the caret) brings it back.
	edit.caret_column = 8
	await get_tree().create_timer(0.3).timeout
	_check(_handle(0).modulate.a > 0.99, "moving the caret brings the handle back (alpha %.2f)" % _handle(0).modulate.a)
	# A tap in the text also counts as activity.
	await get_tree().create_timer(0.9).timeout
	_check(_handle(0).modulate.a < 0.05, "faded again after idling")
	await _click(_text_point(edit, Vector2i(6, 0)))
	await get_tree().create_timer(0.3).timeout
	_check(_handle(0).modulate.a > 0.99, "tapping the text brings the handle back")
	# Selection handles never fade.
	edit.select(2, 8)
	await get_tree().create_timer(0.9).timeout
	_check(_visible_handles() == 2 and _handle(0).modulate.a > 0.99 and _handle(1).modulate.a > 0.99, "selection handles never fade")
	# Delay 0 disables fading entirely.
	edit.deselect()
	_controller.caret_fade_delay = 0.0
	await get_tree().create_timer(0.9).timeout
	_check(_handle(0).modulate.a > 0.99, "caret_fade_delay = 0 disables the fade")
	_controller.caret_fade_delay = 4.0
	_controller.caret_fade_duration = 0.25

#endregion


#region Typing and taps

func _type(text: String) -> void:
	for ch: String in text:
		for pressed: bool in [true, false]:
			var ev: InputEventKey = InputEventKey.new()
			ev.pressed = pressed
			ev.unicode = ch.unicode_at(0)
			ev.keycode = ch.to_upper().unicode_at(0) as Key
			ev.physical_keycode = ev.keycode
			Input.parse_input_event(ev)
		await _frames(1)

func _test_typing_and_taps() -> void:
	print("\n== Typing over a selection and taps")
	var edit: LineEdit = _node("LineEdit") as LineEdit
	edit.text = "Drag the handle under the caret"
	await _focus(edit)
	edit.select(5, 8)
	edit.caret_column = 8
	await _frames(3)
	_check(_visible_handles() == 2, "selection handles shown")
	await _type("X")
	_check(edit.text == "Drag X handle under the caret", "typing replaces the selected text (got '%s')" % edit.text)
	_check(not edit.has_selection() and edit.caret_column == 6, "selection collapses with the caret after the new text")
	await _frames(2)
	_check(_visible_handles() == 1 and _handle(0).get_tip().distance_to(_tip_of(edit, Vector2i(6, 0))) < 1.5, "handles collapse to a single handle at the caret after typing")

	# Tapping the text collapses a selection and moves the caret.
	edit.select(2, 10)
	await _frames(3)
	await _click(_text_point(edit, Vector2i(15, 0)))
	await _frames(2)
	_check(not edit.has_selection() and edit.caret_column == 15, "tap collapses the selection and moves the caret (col %d)" % edit.caret_column)
	_check(_visible_handles() == 1, "single handle after the tap")

	# Double tap selects a word and shows both handles.
	await _click(_text_point(edit, Vector2i(9, 0)))
	await _click(_text_point(edit, Vector2i(9, 0)), true)
	await _frames(3)
	_check(edit.has_selection() and edit.get_selected_text() == "handle", "double tap selects the word (got '%s')" % edit.get_selected_text())
	_check(_visible_handles() == 2, "two handles after a double tap")

	# Same for TextEdit.
	var text_edit: TextEdit = _node("TextEdit") as TextEdit
	text_edit.text = "alpha beta gamma\nsecond line"
	await _focus(text_edit)
	text_edit.scroll_vertical = 0
	text_edit.select(0, 6, 0, 10)
	await _frames(3)
	await _type("Z")
	_check(text_edit.get_line(0) == "alpha Z gamma", "TextEdit: typing replaces the selection (got '%s')" % text_edit.get_line(0))
	await _frames(2)
	_check(_visible_handles() == 1, "TextEdit: single handle after typing over a selection")
	# Which word the engine picks for an injected double-click is not reliable (TextEdit reads the
	# viewport's stored mouse position), so only check that the handles follow whatever it selected.
	await _click(_text_point(text_edit, Vector2i(3, 1)))
	await _click(_text_point(text_edit, Vector2i(3, 1)), true)
	await _frames(3)
	_check(text_edit.has_selection(), "TextEdit: double tap selects a word")
	_check(_visible_handles() == 2, "TextEdit: two handles after a double tap")
	var sel_from: Vector2i = Vector2i(text_edit.get_selection_from_column(), text_edit.get_selection_from_line())
	var sel_to: Vector2i = Vector2i(text_edit.get_selection_to_column(), text_edit.get_selection_to_line())
	_check(_handle(0).get_tip().distance_to(_tip_of(text_edit, sel_from)) < 1.5 and _handle(1).get_tip().distance_to(_tip_of(text_edit, sel_to)) < 1.5, "TextEdit: handles sit at both ends of the double-tap selection")

#endregion


# Dragging a handle past the top/bottom edge must scroll smoothly: the dragged handle stays
# visible and steady, and the caret/scroll position only ever moves in one direction.
func _test_edge_scroll_steadiness() -> void:
	print("\n== Edge scroll steadiness")
	var edit: TextEdit = _node("TextEdit") as TextEdit
	var lines: PackedStringArray = []
	for i: int in 40:
		lines.append("Line number %d with some text" % i)
	edit.text = "\n".join(lines)
	await _focus(edit)
	var rect: Rect2 = edit.get_global_rect()
	# [direction, with_selection]
	for case: Array in [[1, false], [-1, false], [1, true], [-1, true]]:
		var direction: int = case[0]
		var with_selection: bool = case[1]
		edit.deselect()
		if direction == 1:
			edit.scroll_vertical = 0
			edit.set_caret_line(0)
			edit.set_caret_column(2)
			if with_selection:
				edit.select(0, 2, 2, 6)
		else:
			edit.scroll_vertical = 20
			edit.set_caret_line(24)
			edit.set_caret_column(2)
			if with_selection:
				edit.select(23, 2, 24, 6)
		await _frames(4)
		# With a selection the end handle is the one past the anchor.
		var handle: caret_indicator = _handle(0)
		if with_selection:
			handle = _handle(1) if direction == 1 else _handle(0)
		var label: String = "%s%s" % ["down" if direction == 1 else "up", " (selection)" if with_selection else ""]
		_check(handle.visible, "scrolling %s: handle visible before the drag" % label)
		var start: Vector2 = handle.global_position + handle.size * 0.5
		_mouse_move(start)
		_mouse_button(start, true)
		await _frames(1)
		var far: Vector2 = Vector2(start.x, rect.end.y + 60.0) if direction == 1 else Vector2(start.x, rect.position.y - 60.0)
		_mouse_move(far)
		var hidden_frames: int = 0
		var min_y: float = INF
		var max_y: float = -INF
		var start_scroll: float = edit.scroll_vertical
		var reversals: int = 0
		var last_scroll: float = start_scroll
		var last_line: int = edit.get_caret_line()
		for i: int in 50:
			await _frames(1)
			if not handle.visible:
				hidden_frames += 1
			if i > 5:
				min_y = minf(min_y, handle.get_tip().y)
				max_y = maxf(max_y, handle.get_tip().y)
			if (edit.scroll_vertical - last_scroll) * direction < -0.001 or (edit.get_caret_line() - last_line) * direction < 0:
				reversals += 1
			last_scroll = edit.scroll_vertical
			last_line = edit.get_caret_line()
		_check(hidden_frames == 0, "scrolling %s: dragged handle never disappears (%d hidden frames)" % [label, hidden_frames])
		_check(max_y - min_y < 1.5, "scrolling %s: dragged handle is steady at the edge (y range %.1f)" % [label, max_y - min_y])
		_check(reversals == 0, "scrolling %s: scroll and caret only move one way (%d reversals)" % [label, reversals])
		_check(handle.get_tip().y <= rect.end.y + 0.5 and handle.get_tip().y >= rect.position.y, "scrolling %s: handle stays inside the control" % label)
		_check(absf(edit.scroll_vertical - start_scroll) > 2.0, "scrolling %s: the text actually scrolls" % label)
		_mouse_button(far, false)
		await _frames(3)
	edit.text = "The quick brown fox jumps over the lazy dog.\nSecond line of the wrapped text edit, long enough that it needs to wrap around the edge.\nThird line.\nFourth line.\nFifth line."
	edit.scroll_vertical = 0
	await _frames(2)