# Checks the carets in setups beyond the example scene: controls inside a ScrollContainer,
# CodeEdit (gutters), SpinBox, and controls under a scaled/offset CanvasLayer.
# Run with:  godot --path <project> res://MobileCaret/tests/test_setups.tscn
extends Node

var _failures: int = 0
var _checks: int = 0
var _controller: carets_controller
var _root: Control
var _canvas_layer: CanvasLayer


func _ready() -> void:
	_apply_window_args()
	_controller = get_node("/root/MobileCaret") as carets_controller
	await _frames(2)

	await _test_scroll_container()
	await _test_code_edit()
	await _test_spin_box()
	await _test_canvas_layer()

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

func _handle(index: int) -> caret_indicator:
	return _controller.get_node("Handles").get_child(index) as caret_indicator

func _visible_handles() -> int:
	return int(_handle(0).visible) + int(_handle(1).visible)

# Starts a fresh, empty setup.
func _reset() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	if is_instance_valid(_canvas_layer):
		_canvas_layer.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_canvas_layer = null
	await _frames(2)

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

func _click(pos: Vector2) -> void:
	_mouse_move(pos)
	_mouse_button(pos, true)
	await _frames(1)
	_mouse_button(pos, false)
	await _frames(1)

func _drag_handle_to(handle: caret_indicator, target_tip: Vector2) -> void:
	var start_pointer: Vector2 = handle.global_position + handle.size * 0.5
	var delta: Vector2 = target_tip - handle.get_tip()
	_mouse_move(start_pointer)
	_mouse_button(start_pointer, true)
	await _frames(1)
	for i: int in range(1, 7):
		_mouse_move(start_pointer + delta * (float(i) / 6.0))
		await _frames(1)
	await _frames(3)
	_mouse_button(start_pointer + delta, false)
	await _frames(2)

func _focus(control: Control) -> void:
	control.grab_focus()
	await _frames(4)

# Expected viewport-space tip of the handle for a text position.
func _tip_of(control: Control, pos: Vector2i) -> Vector2:
	var adapter: caret_text_adapter = caret_text_adapter.for_control(control)
	return control.get_global_transform_with_canvas() * adapter.get_tip_local(pos)

# Viewport-space point on the text line of a position, slightly right of the column boundary.
func _text_point(control: Control, pos: Vector2i) -> Vector2:
	var adapter: caret_text_adapter = caret_text_adapter.for_control(control)
	var tip: Vector2 = adapter.get_tip_local(pos)
	return control.get_global_transform_with_canvas() * (tip + Vector2(1.0, -adapter.get_line_height() * 0.5))

func _long_text(lines: int) -> String:
	var parts: PackedStringArray = []
	for i: int in lines:
		parts.append("Line %d: the quick brown fox jumps over the lazy dog" % i)
	return "\n".join(parts)

# The native caret's draw position is the oracle for a TextEdit/CodeEdit. The engine reports half
# the caret height for empty lines, so only x is compared there. `layer_scale` is the canvas scale.
func _check_text_edit_tip(edit: TextEdit, pos: Vector2i, label: String, layer_scale: float = 1.0) -> void:
	edit.set_caret_line(pos.y)
	edit.set_caret_column(pos.x)
	await _frames(3)
	var native: Vector2 = edit.get_global_transform_with_canvas() * Vector2(edit.get_caret_draw_pos())
	var tip: Vector2 = _handle(0).get_tip()
	var empty_line: bool = edit.get_line(pos.y).is_empty()
	var y_ok: bool = empty_line or absf(tip.y - native.y) < 3.0 * layer_scale + 0.5
	_check(_handle(0).visible and absf(tip.x - native.x) < 2.0 * layer_scale and y_ok,"%s: handle tip %s matches the native caret %s at %s" % [label, str(tip), str(native), str(pos)])

#endregion


#region ScrollContainer

func _test_scroll_container() -> void:
	print("\n== TextEdit inside a ScrollContainer")
	await _reset()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(40.0, 40.0)
	scroll.size = Vector2(600.0, 400.0)
	_root.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 100.0)
	box.add_child(spacer)
	var edit: TextEdit = TextEdit.new()
	edit.custom_minimum_size = Vector2(0.0, 150.0)
	edit.text = _long_text(8)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(edit)
	var bottom: Control = Control.new()
	bottom.custom_minimum_size = Vector2(0.0, 700.0)
	box.add_child(bottom)
	await _frames(3)

	await _focus(edit)
	await _check_text_edit_tip(edit, Vector2i(4, 0), "unscrolled")
	var tip_before: Vector2 = _handle(0).get_tip()
	scroll.scroll_vertical = 40
	await _frames(3)
	_check(absf((_handle(0).get_tip().y - tip_before.y) + 40.0) < 1.5, "handle follows the container when it scrolls (moved %.1f)" % (_handle(0).get_tip().y - tip_before.y))
	await _check_text_edit_tip(edit, Vector2i(10, 1), "scrolled 40")

	# Dragging the handle moves the caret and must not scroll the container.
	scroll.scroll_vertical = 0
	await _frames(2)
	edit.set_caret_line(0)
	edit.set_caret_column(2)
	await _frames(3)
	var scroll_before: int = scroll.scroll_vertical
	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(12, 1)))
	_check(edit.get_caret_line() == 1 and edit.get_caret_column() == 12, "dragging the handle moves the caret in a ScrollContainer (got %d,%d)" % [edit.get_caret_column(), edit.get_caret_line()])
	_check(scroll.scroll_vertical == scroll_before, "the container does not scroll while the handle is dragged")
	_check(edit.has_focus(), "focus kept")

	# Selection handles.
	edit.select(0, 5, 1, 10)
	await _frames(3)
	_check(_visible_handles() == 2, "two selection handles in a ScrollContainer")

	# The caret scrolled out of the container's visible area: the handle must not float above/below it.
	edit.deselect()
	edit.set_caret_line(0)
	edit.set_caret_column(3)
	scroll.scroll_vertical = 260
	await _frames(4)
	var visible_rect: Rect2 = scroll.get_global_rect()
	_check(not _handle(0).visible or visible_rect.has_point(_handle(0).get_tip()), "handle is hidden when the caret is scrolled out of the container (visible=%s tip=%s container=%s)" % [_handle(0).visible, str(_handle(0).get_tip()), str(visible_rect)])
	# And comes back when scrolled into view.
	scroll.scroll_vertical = 60
	await _frames(4)
	_check(_handle(0).visible, "handle returns when scrolled back into view")

#endregion


#region CodeEdit

func _test_code_edit() -> void:
	print("\n== CodeEdit with line-number gutter")
	await _reset()
	var edit: CodeEdit = CodeEdit.new()
	edit.position = Vector2(40.0, 40.0)
	edit.size = Vector2(620.0, 360.0)
	edit.gutters_draw_line_numbers = true
	edit.text = "func _ready() -> void:\n\tprint(\"hello world\")\n\tvar x: int = 12345\n\treturn\n\n# a comment line that is fairly long"
	_root.add_child(edit)
	await _frames(3)
	await _focus(edit)
	for pos: Vector2i in [Vector2i(0, 0), Vector2i(5, 0), Vector2i(3, 1), Vector2i(10, 2), Vector2i(0, 4), Vector2i(20, 5)]:
		await _check_text_edit_tip(edit, pos, "CodeEdit")
	edit.set_caret_line(1)
	edit.set_caret_column(3)
	await _frames(3)
	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(8, 2)))
	_check(edit.get_caret_line() == 2 and edit.get_caret_column() == 8 and not edit.has_selection(), "CodeEdit: dragging the handle moves the caret (got %d,%d)" % [edit.get_caret_column(), edit.get_caret_line()])
	edit.select(0, 0, 0, 8)
	await _frames(3)
	_check(_visible_handles() == 2, "CodeEdit: two selection handles")
	await _drag_handle_to(_handle(1), _tip_of(edit, Vector2i(5, 1)))
	_check(edit.get_selection_from_line() == 0 and edit.get_selection_to_line() == 1 and edit.get_selection_to_column() == 5, "CodeEdit: end handle extends the selection to (5,1) (got (%d,%d))" % [edit.get_selection_to_column(), edit.get_selection_to_line()])

#endregion


#region SpinBox

func _test_spin_box() -> void:
	print("\n== SpinBox")
	await _reset()
	var spin: SpinBox = SpinBox.new()
	spin.position = Vector2(40.0, 40.0)
	spin.size = Vector2(400.0, 60.0)
	spin.min_value = 0.0
	spin.max_value = 1000000.0
	spin.value = 123456.0
	spin.add_theme_font_size_override("font_size", 32)
	_root.add_child(spin)
	await _frames(3)
	var line: LineEdit = spin.get_line_edit()
	await _focus(line)
	line.caret_column = 3
	await _frames(3)
	_check(_handle(0).visible, "handle appears for the SpinBox's LineEdit")
	_check(caret_text_adapter.for_control(spin) == null, "the SpinBox itself is not treated as a text control")
	# The click oracle: clicking where the adapter says column 2 is must put the caret on column 2.
	line.deselect()
	await _click(_text_point(line, Vector2i(2, 0)))
	_check(line.caret_column == 2, "click on the computed column position lands on it (caret %d)" % line.caret_column)
	await _drag_handle_to(_handle(0), _tip_of(line, Vector2i(5, 0)))
	_check(line.caret_column == 5 and not line.has_selection(), "dragging the handle moves the caret in a SpinBox (got %d)" % line.caret_column)
	_check(line.has_focus(), "SpinBox keeps focus while dragging")
	line.select(1, 4)
	line.caret_column = 4
	await _frames(3)
	_check(_visible_handles() == 2, "two selection handles in a SpinBox")
	await _drag_handle_to(_handle(1), _tip_of(line, Vector2i(6, 0)))
	_check(line.has_selection() and line.get_selection_from_column() == 1 and line.get_selection_to_column() == 6, "extending the selection in a SpinBox works")
	_check(is_equal_approx(spin.value, 123456.0), "dragging the handle did not change the SpinBox value (%s)" % str(spin.value))

#endregion


#region CanvasLayer

func _test_canvas_layer() -> void:
	print("\n== Controls under a scaled and offset CanvasLayer")
	await _reset()
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 5
	_canvas_layer.offset = Vector2(60.0, 80.0)
	_canvas_layer.scale = Vector2(1.5, 1.5)
	add_child(_canvas_layer)
	var edit: LineEdit = LineEdit.new()
	edit.position = Vector2(20.0, 20.0)
	edit.size = Vector2(380.0, 50.0)
	edit.text = "scaled and offset layer text"
	_canvas_layer.add_child(edit)
	var text_edit: TextEdit = TextEdit.new()
	text_edit.position = Vector2(20.0, 100.0)
	text_edit.size = Vector2(380.0, 120.0)
	text_edit.text = _long_text(5)
	_canvas_layer.add_child(text_edit)
	await _frames(3)

	await _focus(edit)
	edit.caret_column = 7
	await _frames(3)
	_check(_handle(0).visible and _handle(0).get_tip().distance_to(_tip_of(edit, Vector2i(7, 0))) < 1.5, "LineEdit: handle sits at the caret under the layer transform")
	edit.deselect()
	await _click(_text_point(edit, Vector2i(10, 0)))
	_check(edit.caret_column == 10, "LineEdit: computed column position matches a real click under the layer transform (caret %d)" % edit.caret_column)
	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(4, 0)))
	_check(edit.caret_column == 4, "LineEdit: dragging works under the layer transform (got %d)" % edit.caret_column)

	await _focus(text_edit)
	await _check_text_edit_tip(text_edit, Vector2i(6, 1), "TextEdit under the layer", 1.5)
	await _drag_handle_to(_handle(0), _tip_of(text_edit, Vector2i(9, 2)))
	_check(text_edit.get_caret_line() == 2 and text_edit.get_caret_column() == 9, "TextEdit: dragging works under the layer transform (got %d,%d)" % [text_edit.get_caret_column(), text_edit.get_caret_line()])

#endregion
