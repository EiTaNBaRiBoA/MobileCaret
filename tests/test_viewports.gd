# Handles and toolbar for text controls inside a SubViewport (also scaled), an embedded Window and
# a separate native Window. Events are pushed straight into the viewport that holds the control.
# Run with:  godot --path <project> res://MobileCaret/tests/test_viewports.tscn
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
	await _test_sub_viewport(1.0)
	await _test_sub_viewport(1.5)
	await _test_embedded_window()
	await _test_native_window()
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

func _reset() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	DisplayServer.clipboard_set("clip")
	await _frames(3)

# The handles that live inside `viewport`.
func _handle(viewport: Viewport, index: int) -> caret_indicator:
	return viewport.get_node("MobileCaretHandles/Handles").get_child(index) as caret_indicator

func _push_move(viewport: Viewport, pos: Vector2) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(ev, true)

func _push_button(viewport: Viewport, pos: Vector2, pressed: bool) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	viewport.push_input(ev, true)

func _click_in(viewport: Viewport, pos: Vector2) -> void:
	_push_move(viewport, pos)
	_push_button(viewport, pos, true)
	await _frames(1)
	_push_button(viewport, pos, false)
	await _frames(2)

func _drag_handle_to(viewport: Viewport, handle: caret_indicator, target_tip: Vector2) -> void:
	var start: Vector2 = handle.global_position + handle.size * 0.5
	var delta: Vector2 = target_tip - handle.get_tip()
	_push_move(viewport, start)
	_push_button(viewport, start, true)
	await _frames(1)
	for i: int in range(1, 7):
		_push_move(viewport, start + delta * (float(i) / 6.0))
		await _frames(1)
	await _frames(3)
	_push_button(viewport, start + delta, false)
	await _frames(2)

func _tip_of(control: Control, pos: Vector2i) -> Vector2:
	return control.get_global_transform_with_canvas() * caret_text_adapter.for_control(control).get_tip_local(pos)

func _wait_toolbar(showing: bool) -> void:
	for i: int in 90:
		if _toolbar.is_showing() == showing:
			break
		await _frames(1)
	await _frames(2)

# One round of checks for a LineEdit and a TextEdit that live in `viewport`.
func _check_controls_in(viewport: Viewport, edit: LineEdit, text_edit: TextEdit, label: String, expected_size_px: Vector2) -> void:
	edit.grab_focus()
	await _frames(4)
	edit.deselect()
	edit.caret_column = 4
	await _frames(4)
	var handle: caret_indicator = _handle(viewport, 0)
	_check(handle.visible and handle.get_tip().distance_to(_tip_of(edit, Vector2i(4, 0))) < 1.5, "%s: the caret handle sits at the caret of the LineEdit" % label)
	_check(not (_controller.get_node("Handles").get_child(0) as caret_indicator).visible, "%s: nothing is drawn in the main window" % label)
	var screen_scale: float = caret_screen.viewport_scale(viewport)
	_check(absf(handle.size.x * screen_scale - expected_size_px.x) < 1.5 and absf(handle.size.y * screen_scale - expected_size_px.y) < 1.5, "%s: the handle is %s px on screen (expected %s)" % [label, str((handle.size * screen_scale).snapped(Vector2(0.1, 0.1))), str(expected_size_px.snapped(Vector2(0.1, 0.1)))])

	await _drag_handle_to(viewport, handle, _tip_of(edit, Vector2i(12, 0)))
	_check(edit.caret_column == 12 and not edit.has_selection(), "%s: dragging the handle moves the caret to column 12 (got %d)" % [label, edit.caret_column])
	_check(edit.has_focus(), "%s: the LineEdit keeps focus" % label)

	edit.select(3, 9)
	edit.caret_column = 9
	await _frames(4)
	_check(int(_handle(viewport, 0).visible) + int(_handle(viewport, 1).visible) == 2, "%s: two selection handles" % label)
	await _drag_handle_to(viewport, _handle(viewport, 1), _tip_of(edit, Vector2i(14, 0)))
	_check(edit.has_selection() and edit.get_selection_from_column() == 3 and edit.get_selection_to_column() == 14, "%s: the end handle extends the selection to 3..14" % label)

	# The toolbar appears inside the same viewport and its buttons work there.
	await _wait_toolbar(true)
	_check(_toolbar.is_showing(), "%s: the toolbar shows" % label)
	var panel: Node = viewport.get_node_or_null("MobileCaretToolbar/Panel")
	_check(panel != null and (panel as Control).visible, "%s: the toolbar panel lives in that viewport" % label)
	var copy_rect: Rect2 = _toolbar.get_button_rect(&"copy")
	_check(copy_rect.size != Vector2.ZERO and viewport.get_visible_rect().encloses(_toolbar.get_toolbar_rect()), "%s: the toolbar is inside the viewport" % label)
	await _click_in(viewport, copy_rect.get_center())
	_check(DisplayServer.clipboard_get() == edit.get_selected_text() and not edit.get_selected_text().is_empty(), "%s: Copy works (clipboard '%s')" % [label, DisplayServer.clipboard_get()])
	_check(edit.has_focus(), "%s: pressing a toolbar button keeps focus" % label)

	# The TextEdit in the same viewport.
	text_edit.grab_focus()
	await _frames(4)
	text_edit.deselect()
	text_edit.set_caret_line(0)
	text_edit.set_caret_column(3)
	await _frames(4)
	_check(_handle(viewport, 0).visible and _handle(viewport, 0).get_tip().distance_to(_tip_of(text_edit, Vector2i(3, 0))) < 1.5, "%s: the handle moves to the TextEdit" % label)
	await _drag_handle_to(viewport, _handle(viewport, 0), _tip_of(text_edit, Vector2i(6, 1)))
	_check(text_edit.get_caret_line() == 1 and text_edit.get_caret_column() == 6, "%s: dragging works in the TextEdit (got %d,%d)" % [label, text_edit.get_caret_column(), text_edit.get_caret_line()])

#endregion


func _test_sub_viewport(container_scale: float) -> void:
	print("\n== SubViewport (container scale %.1f)" % container_scale)
	await _reset()
	var container: SubViewportContainer = SubViewportContainer.new()
	container.position = Vector2(40.0, 100.0)
	container.stretch = true
	container.size = Vector2(600.0, 420.0)
	container.scale = Vector2(container_scale, container_scale)
	_root.add_child(container)
	var sub: SubViewport = SubViewport.new()
	sub.size = Vector2i(600, 420)
	container.add_child(sub)
	var edit: LineEdit = LineEdit.new()
	edit.position = Vector2(20.0, 20.0)
	edit.size = Vector2(500.0, 50.0)
	edit.text = "text inside a sub viewport"
	sub.add_child(edit)
	var text_edit: TextEdit = TextEdit.new()
	text_edit.position = Vector2(20.0, 120.0)
	text_edit.size = Vector2(500.0, 160.0)
	text_edit.text = "first line of text\nsecond line of text\nthird line"
	sub.add_child(text_edit)
	await _frames(4)
	# The handle keeps its physical size even though the content is scaled twice (stretch + container).
	var dpi: float = caret_screen.dpi(get_viewport())
	var expected: Vector2 = _controller.handle_size_mm * (dpi / 25.4)
	await _check_controls_in(sub, edit, text_edit, "SubViewport x%.1f" % container_scale, expected)

func _test_embedded_window() -> void:
	print("\n== Embedded Window")
	await _reset()
	var saved_embed: bool = get_viewport().gui_embed_subwindows
	get_viewport().gui_embed_subwindows = true
	var window: Window = Window.new()
	window.title = "embedded"
	window.size = Vector2i(560, 420)
	window.position = Vector2i(40, 100)
	window.transient = false
	_root.add_child(window)
	var edit: LineEdit = LineEdit.new()
	edit.position = Vector2(20.0, 20.0)
	edit.size = Vector2(480.0, 50.0)
	edit.text = "text inside an embedded window"
	window.add_child(edit)
	var text_edit: TextEdit = TextEdit.new()
	text_edit.position = Vector2(20.0, 120.0)
	text_edit.size = Vector2(480.0, 160.0)
	text_edit.text = "first line of text\nsecond line of text\nthird line"
	window.add_child(text_edit)
	window.show()
	await _frames(6)
	_check(window.is_embedded(), "the window is embedded")
	var expected: Vector2 = _controller.handle_size_mm * (caret_screen.dpi(window) / 25.4)
	await _check_controls_in(window, edit, text_edit, "embedded Window", expected)
	window.hide()
	await _frames(3)
	window.queue_free()
	get_viewport().gui_embed_subwindows = saved_embed
	await _frames(3)

func _test_native_window() -> void:
	print("\n== Separate native Window")
	await _reset()
	var saved_embed: bool = get_viewport().gui_embed_subwindows
	get_viewport().gui_embed_subwindows = false
	var window: Window = Window.new()
	window.title = "MobileCaret test window"
	window.size = Vector2i(560, 420)
	window.position = Vector2i(120, 120)
	window.transient = false
	_root.add_child(window)
	var edit: LineEdit = LineEdit.new()
	edit.position = Vector2(20.0, 20.0)
	edit.size = Vector2(480.0, 50.0)
	edit.text = "text inside a native window"
	window.add_child(edit)
	var text_edit: TextEdit = TextEdit.new()
	text_edit.position = Vector2(20.0, 120.0)
	text_edit.size = Vector2(480.0, 160.0)
	text_edit.text = "first line of text\nsecond line of text\nthird line"
	window.add_child(text_edit)
	window.show()
	await _frames(10)
	_check(not window.is_embedded(), "the window is a separate OS window")
	var expected: Vector2 = _controller.handle_size_mm * (caret_screen.dpi(window) / 25.4)
	await _check_controls_in(window, edit, text_edit, "native Window", expected)
	window.hide()
	await _frames(3)
	window.queue_free()
	get_viewport().gui_embed_subwindows = saved_embed
	await _frames(3)
