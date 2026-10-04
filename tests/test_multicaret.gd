# TextEdit with several carets: every caret gets handles, each can be dragged on its own.
# Run with:  godot --path <project> res://MobileCaret/tests/test_multicaret.tscn
extends Node

var _failures: int = 0
var _checks: int = 0
var _controller: carets_controller
var _toolbar: caret_toolbar
var _root: Control
var _saved_clipboard: String = ""


func _ready() -> void:
	_controller = get_node("/root/MobileCaret") as carets_controller
	_toolbar = get_node("/root/MobileCaretToolbar") as caret_toolbar
	_saved_clipboard = DisplayServer.clipboard_get()
	await _frames(2)
	await _test_handles_for_every_caret()
	await _test_drag_secondary_caret()
	await _test_per_caret_selection()
	await _test_deselect_is_per_caret()
	await _test_carets_merging_while_dragging()
	await _test_back_to_one_caret()
	DisplayServer.clipboard_set(_saved_clipboard)
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

func _handle(index: int) -> caret_indicator:
	return _controller.get_node("Handles").get_child(index) as caret_indicator

func _visible_handles() -> int:
	var count: int = 0
	for child: Node in _controller.get_node("Handles").get_children():
		if (child as caret_indicator).visible:
			count += 1
	return count

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

func _drag_handle_to(handle: caret_indicator, target_tip: Vector2) -> void:
	var start: Vector2 = handle.global_position + handle.size * 0.5
	var delta: Vector2 = target_tip - handle.get_tip()
	_mouse_move(start)
	_mouse_button(start, true)
	await _frames(1)
	for i: int in range(1, 7):
		_mouse_move(start + delta * (float(i) / 6.0))
		await _frames(1)
	await _frames(3)
	_mouse_button(start + delta, false)
	await _frames(2)

func _tip_of(control: Control, pos: Vector2i) -> Vector2:
	return control.get_global_transform_with_canvas() * caret_text_adapter.for_control(control).get_tip_local(pos)

func _make_edit() -> TextEdit:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var edit: TextEdit = TextEdit.new()
	edit.position = Vector2(20.0, 200.0)
	edit.size = Vector2(600.0, 360.0)
	edit.add_theme_font_size_override("font_size", 26)
	edit.caret_multiple = true
	edit.text = "alpha beta gamma delta\nepsilon zeta eta theta\niota kappa lambda mu\nnu xi omicron pi"
	_root.add_child(edit)
	return edit

func _focus(edit: TextEdit) -> void:
	await _frames(3)
	edit.grab_focus()
	await _frames(4)

#endregion


func _test_handles_for_every_caret() -> void:
	print("\n== A handle for every caret")
	var edit: TextEdit = _make_edit()
	await _focus(edit)
	edit.deselect()
	edit.set_caret_line(0)
	edit.set_caret_column(3)
	edit.add_caret(1, 5)
	edit.add_caret(2, 9)
	await _frames(4)
	_check(edit.get_caret_count() == 3, "three carets")
	_check(_visible_handles() == 3, "three handles are shown (got %d)" % _visible_handles())
	var positions: Array[Vector2i] = [Vector2i(3, 0), Vector2i(5, 1), Vector2i(9, 2)]
	var ok: bool = true
	for i: int in 3:
		var expected: Vector2 = _tip_of(edit, Vector2i(edit.get_caret_column(i), edit.get_caret_line(i)))
		if not (_handle(i * 2).visible and _handle(i * 2).get_tip().distance_to(expected) < 1.5):
			ok = false
	_check(ok, "each handle sits at its own caret")
	_check(_handle(1).visible == false and _handle(3).visible == false and _handle(5).visible == false, "no end handles without selections")


func _test_drag_secondary_caret() -> void:
	print("\n== Dragging a secondary caret")
	var edit: TextEdit = _make_edit()
	await _focus(edit)
	edit.deselect()
	edit.set_caret_line(0)
	edit.set_caret_column(3)
	edit.add_caret(1, 5)
	edit.add_caret(2, 9)
	await _frames(4)
	var before_first: Vector2i = Vector2i(edit.get_caret_column(0), edit.get_caret_line(0))
	var before_third: Vector2i = Vector2i(edit.get_caret_column(2), edit.get_caret_line(2))
	# Carets are sorted by position, so find the one on line 1.
	var index: int = -1
	for i: int in edit.get_caret_count():
		if edit.get_caret_line(i) == 1:
			index = i
	_check(index >= 0, "found the caret on line 1 (index %d)" % index)
	await _drag_handle_to(_handle(index * 2), _tip_of(edit, Vector2i(14, 1)))
	_check(edit.get_caret_count() == 3, "still three carets")
	_check(edit.get_caret_line(index) == 1 and edit.get_caret_column(index) == 14, "the dragged caret moved to column 14 (got %d,%d)" % [edit.get_caret_column(index), edit.get_caret_line(index)])
	var first_same: bool = Vector2i(edit.get_caret_column(0), edit.get_caret_line(0)) == before_first if index != 0 else true
	var third_same: bool = Vector2i(edit.get_caret_column(2), edit.get_caret_line(2)) == before_third if index != 2 else true
	_check(first_same and third_same, "the other carets did not move")
	_check(edit.has_focus() and not edit.has_selection(-1), "focus kept and nothing got selected")
	_check(_visible_handles() == 3, "still three handles")


func _test_per_caret_selection() -> void:
	print("\n== Selections on individual carets")
	var edit: TextEdit = _make_edit()
	await _focus(edit)
	edit.deselect()
	edit.set_caret_line(0)
	edit.set_caret_column(2)
	var second: int = edit.add_caret(2, 1)
	await _frames(3)
	edit.select(2, 1, 2, 5, second)
	await _frames(4)
	_check(edit.has_selection(second) and not edit.has_selection(0), "only the second caret has a selection")
	var shown: int = _visible_handles()
	_check(shown == 3, "caret handle + two selection handles (got %d)" % shown)
	# Find the pair of the selected caret and extend its end.
	var selected: int = -1
	for i: int in edit.get_caret_count():
		if edit.has_selection(i):
			selected = i
	await _drag_handle_to(_handle(selected * 2 + 1), _tip_of(edit, Vector2i(10, 2)))
	_check(edit.has_selection(selected) and edit.get_selection_from_column(selected) == 1 and edit.get_selection_to_column(selected) == 10 and edit.get_selection_to_line(selected) == 2, "the end handle extends that caret's selection to 1..10 (got %d..%d)" % [edit.get_selection_from_column(selected), edit.get_selection_to_column(selected)])
	# The toolbar acts on the selection.
	DisplayServer.clipboard_set("clip")
	for i: int in 90:
		if _toolbar.is_showing():
			break
		await _frames(1)
	await _frames(2)
	_check(_toolbar.is_showing(), "the toolbar shows when any caret has a selection")
	var copy_rect: Rect2 = _toolbar.get_button_rect(&"copy")
	var center: Vector2 = copy_rect.get_center()
	_mouse_move(center)
	_mouse_button(center, true)
	await _frames(1)
	_mouse_button(center, false)
	await _frames(2)
	_check(DisplayServer.clipboard_get() == edit.get_selected_text(selected) and not DisplayServer.clipboard_get().is_empty(), "Copy copies the selection ('%s')" % DisplayServer.clipboard_get())


func _test_carets_merging_while_dragging() -> void:
	print("\n== Carets that run into each other while dragging")
	var edit: TextEdit = _make_edit()
	await _focus(edit)
	edit.deselect()
	edit.set_caret_line(1)
	edit.set_caret_column(4)
	edit.add_caret(1, 12)
	await _frames(4)
	_check(edit.get_caret_count() == 2, "two carets on the same line")
	await _drag_handle_to(_handle(0), _tip_of(edit, Vector2i(12, 1)))
	await _frames(3)
	_check(edit.get_caret_count() == 1, "dragging one caret onto the other merges them (count %d)" % edit.get_caret_count())
	_check(edit.has_focus(), "no problem afterwards: focus kept")
	_check(_visible_handles() == 1, "one handle left (got %d)" % _visible_handles())


func _test_back_to_one_caret() -> void:
	print("\n== Back to a single caret")
	var edit: TextEdit = _make_edit()
	await _focus(edit)
	edit.deselect()
	edit.set_caret_line(0)
	edit.set_caret_column(3)
	edit.add_caret(1, 5)
	await _frames(4)
	_check(_visible_handles() == 2, "two handles for two carets")
	edit.remove_secondary_carets()
	await _frames(4)
	_check(edit.get_caret_count() == 1 and _visible_handles() == 1, "removing the extra caret removes its handle (handles %d)" % _visible_handles())


func _test_deselect_is_per_caret() -> void:
	print("\n== Clearing one caret's selection leaves the others alone")
	var edit: TextEdit = _make_edit()
	await _focus(edit)
	edit.deselect()
	edit.set_caret_line(0)
	edit.set_caret_column(2)
	var second: int = edit.add_caret(2, 1)
	await _frames(3)
	edit.select(0, 0, 0, 5, 0)
	edit.select(2, 1, 2, 6, second)
	await _frames(4)
	_check(edit.has_selection(0) and edit.has_selection(second), "setup: both carets have a selection")
	# Drag the end handle of the second caret back onto its anchor.
	var which: int = -1
	for i: int in edit.get_caret_count():
		if edit.get_caret_line(i) == 2:
			which = i
	await _drag_handle_to(_handle(which * 2 + 1), _tip_of(edit, Vector2i(1, 2)))
	var other: int = 1 - which
	_check(not edit.has_selection(which), "the dragged caret's selection is cleared")
	_check(edit.has_selection(other) and edit.get_selected_text(other) == "alpha", "the other caret keeps its selection ('%s')" % edit.get_selected_text(other))