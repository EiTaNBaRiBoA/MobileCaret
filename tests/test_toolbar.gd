# Checks the floating toolbar (Cut / Copy / Paste / Select all) against LineEdit, TextEdit,
# CodeEdit and SpinBox. Run with:  godot --path <project> res://MobileCaret/tests/test_toolbar.tscn
extends Node

var _failures: int = 0
var _checks: int = 0
var _controller: carets_controller
var _toolbar: caret_toolbar
var _root: Control
var _saved_clipboard: String = ""


# A custom control with selected text whose delegate chooses its own buttons (get_toolbar_actions).
class ChoosyLabel extends Control:
	var delegate: ChoosyDelegate = ChoosyDelegate.new()

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL

	func _get_caret_delegate() -> Object:
		return delegate


class ChoosyDelegate extends RefCounted:
	var actions: Array = [&"copy"]

	func supports_handles() -> bool:
		return false

	func is_text_editable() -> bool:
		return true

	func is_empty() -> bool:
		return false

	func has_selection() -> bool:
		return true

	func get_selection_from() -> Vector2i:
		return Vector2i(0, 0)

	func get_selection_to() -> Vector2i:
		return Vector2i(4, 0)

	func get_tip_local(pos: Vector2i) -> Vector2:
		return Vector2(20.0 + pos.x * 12.0, 30.0)

	func is_pos_visible(_pos: Vector2i) -> bool:
		return true

	func get_line_height() -> float:
		return 24.0

	func get_selected_text() -> String:
		return "text"

	func cut() -> void:
		pass

	func paste() -> void:
		pass

	func get_toolbar_actions() -> Array:
		return actions


func _ready() -> void:
	_apply_window_args()
	_controller = get_node("/root/MobileCaret") as carets_controller
	_toolbar = get_node("/root/MobileCaretToolbar") as caret_toolbar
	_saved_clipboard = DisplayServer.clipboard_get()
	await _frames(2)

	await _test_line_edit_actions()
	await _test_read_only()
	await _test_placement()
	await _test_other_controls()
	await _test_switches()
	await _test_caret_toolbar_from_handle_tap()
	await _test_hides_when_text_changes()
	await _test_overflow_menu()
	await _test_tap_on_selection()
	await _test_rich_text_label()
	await _test_empty_field()
	await _test_clipboard_reads()
	await _test_review_fixes()
	await _test_physical_size()
	await _test_without_carets_controller()
	await _test_control_menu_settings()
	await _test_delete_button()
	await _test_image_menu()
	await _test_copy_image()
	await _test_image_menu_on_a_view()
	await _test_image_menu_with_text()

	DisplayServer.clipboard_set(_saved_clipboard)
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

# Waits (up to 20 frames) for a condition. The system clipboard can lag behind a copy for a
# moment on Windows, so clipboard checks wait for it first.
func _wait_for(condition: Callable) -> void:
	for i: int in 20:
		if condition.call():
			return
		await _frames(1)

# Reads the system clipboard. On Windows a read can come back empty while another program (a
# clipboard manager) has the clipboard open, so an empty read is tried again.
func _clip() -> String:
	for i: int in 5:
		var value: String = DisplayServer.clipboard_get()
		if value != "":
			return value
		OS.delay_msec(10)
	return ""

func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame

# Starts a fresh, empty setup.
func _reset() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_toolbar.enabled = true
	DisplayServer.clipboard_set("clip")
	await _frames(3)

func _line_edit(text: String, position: Vector2, size: Vector2 = Vector2(500.0, 50.0)) -> LineEdit:
	var edit: LineEdit = LineEdit.new()
	edit.position = position
	edit.size = size
	edit.text = text
	_root.add_child(edit)
	return edit

func _to_window(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos

func _mouse_move(pos: Vector2) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = _to_window(pos)
	ev.global_position = ev.position
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)

func _mouse_button(pos: Vector2, pressed: bool, double_click: bool = false) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = _to_window(pos)
	ev.global_position = ev.position
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.double_click = double_click
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)

func _click(pos: Vector2) -> void:
	_mouse_move(pos)
	_mouse_button(pos, true)
	await _frames(1)
	_mouse_button(pos, false)
	await _frames(2)

func _focus(control: Control) -> void:
	control.grab_focus()
	await _frames(4)

# Waits (up to ~1.5 s) until the toolbar's visibility matches `showing`.
func _wait_toolbar(showing: bool) -> void:
	for i: int in 90:
		if _toolbar.is_showing() == showing:
			break
		await _frames(1)
	await _frames(2)

# Selects text in a control and waits for the toolbar to appear.
func _select_and_wait(control: Control, from: Vector2i, to: Vector2i) -> void:
	await _focus(control)
	if control is LineEdit:
		(control as LineEdit).select(from.x, to.x)
		(control as LineEdit).caret_column = to.x
	else:
		(control as TextEdit).select(from.y, from.x, to.y, to.x)
	await _wait_toolbar(true)

func _button_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for action: StringName in [&"back", &"copy_image", &"cut", &"delete", &"copy", &"paste", &"select_all", &"undo", &"redo", &"share", &"more"]:
		if _toolbar.get_button_rect(action).size != Vector2.ZERO:
			ids.append(action)
	return ids

func _buttons_are(expected: Array) -> bool:
	return str(_button_ids()) == str(expected)

func _press_button(action: StringName) -> void:
	var rect: Rect2 = _toolbar.get_button_rect(action)
	await _click(rect.get_center())

func _tip_of(control: Control, pos: Vector2i) -> Vector2:
	return control.get_global_transform_with_canvas() * caret_text_adapter.for_control(control).get_tip_local(pos)

#endregion


func _test_line_edit_actions() -> void:
	print("\n== LineEdit: Cut / Copy / Paste / Select all")
	await _reset()
	var edit: LineEdit = _line_edit("hello brave new world", Vector2(40.0, 300.0))
	await _frames(2)
	await _select_and_wait(edit, Vector2i(6, 0), Vector2i(11, 0))
	_check(_toolbar.is_showing(), "the toolbar shows for a selection")
	_check(_buttons_are([&"cut", &"copy", &"paste", &"select_all", &"more"]), "all four buttons and the overflow button are offered (got %s)" % str(_button_ids()))
	var bar: Rect2 = _toolbar.get_toolbar_rect()
	var selection_top: float = _tip_of(edit, Vector2i(6, 0)).y - edit.get_theme_font("font").get_height(edit.get_theme_font_size("font_size"))
	_check(bar.end.y <= selection_top + 0.5, "the toolbar sits above the selection (bar bottom %.1f, selection top %.1f)" % [bar.end.y, selection_top])
	_check(get_viewport().get_visible_rect().encloses(bar), "the toolbar stays inside the viewport")

	await _press_button(&"copy")
	await _wait_for(func() -> bool: return _clip() == "brave")
	_check(_clip() == "brave", "Copy puts the selection on the clipboard (got '%s')" % _clip())
	_check(edit.has_selection() and edit.get_selected_text() == "brave", "Copy keeps the selection")
	_check(edit.has_focus(), "the text control keeps focus when a toolbar button is pressed")
	await _frames(15)
	_check(not _toolbar.is_showing(), "the toolbar hides after Copy")

	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(5, 0))
	await _press_button(&"cut")
	await _wait_for(func() -> bool: return edit.text == " brave new world" and _clip() == "hello")
	_check(edit.text == " brave new world" and _clip() == "hello", "Cut removes the selection and copies it (text '%s', clipboard '%s')" % [edit.text, _clip()])

	# Paste at the caret: shown through show_for_caret().
	DisplayServer.clipboard_set("AB")
	edit.deselect()
	edit.caret_column = 0
	await _frames(3)
	_toolbar.show_for_caret()
	await _wait_toolbar(true)
	_check(_buttons_are([&"paste", &"select_all", &"more"]), "the caret toolbar offers Paste, Select all and the overflow button (got %s)" % str(_button_ids()))
	await _press_button(&"paste")
	_check(edit.text == "AB brave new world", "Paste inserts at the caret (text '%s')" % edit.text)

	edit.deselect()
	edit.caret_column = 2
	await _frames(3)
	_toolbar.show_for_caret()
	await _wait_toolbar(true)
	await _press_button(&"select_all")
	_check(edit.has_selection() and edit.get_selected_text() == edit.text, "Select all selects everything")
	await _wait_toolbar(true)
	_check(not (&"select_all" in _button_ids()), "Select all is not offered when everything is selected")

	# The action signal.
	var received: Array[StringName] = []
	_toolbar.action_pressed.connect(func(action: StringName) -> void: received.append(action))
	await _press_button(&"copy")
	_check(str(received) == str([&"copy"]), "action_pressed is emitted with the action (got %s)" % str(received))


func _test_read_only() -> void:
	print("\n== Read-only control")
	await _reset()
	var edit: LineEdit = _line_edit("read only text", Vector2(40.0, 300.0))
	edit.editable = false
	await _frames(2)
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(4, 0))
	_check(_buttons_are([&"copy", &"select_all"]), "read-only: only Copy and Select all (got %s)" % str(_button_ids()))
	var text_edit: TextEdit = TextEdit.new()
	text_edit.position = Vector2(40.0, 400.0)
	text_edit.size = Vector2(500.0, 120.0)
	text_edit.text = "read only\ntext edit"
	text_edit.editable = false
	_root.add_child(text_edit)
	await _frames(2)
	await _select_and_wait(text_edit, Vector2i(0, 0), Vector2i(4, 1))
	_check(_buttons_are([&"copy", &"select_all"]), "read-only TextEdit: only Copy and Select all (got %s)" % str(_button_ids()))


func _test_placement() -> void:
	print("\n== Placement")
	await _reset()
	# Near the top of the screen there is no room above: the toolbar goes below the selection.
	var edit: LineEdit = _line_edit("near the top of the screen", Vector2(40.0, 4.0))
	await _frames(2)
	await _select_and_wait(edit, Vector2i(5, 0), Vector2i(8, 0))
	var bar: Rect2 = _toolbar.get_toolbar_rect()
	_check(bar.position.y >= edit.get_global_rect().end.y - 0.5, "no room above: the toolbar goes below the control (bar top %.1f, control bottom %.1f)" % [bar.position.y, edit.get_global_rect().end.y])
	_check(get_viewport().get_visible_rect().encloses(bar), "and stays inside the viewport")
	# Just clear of the handles and their grab area (the controller says how far they reach).
	var tip_y: float = (edit.get_global_transform_with_canvas() * caret_text_adapter.for_control(edit).get_tip_local(Vector2i(8, 0))).y
	var expected_top: float = tip_y + _controller.get_handle_reach(get_viewport()) + caret_screen.mm_to_logical(get_viewport(), _toolbar.gap_mm)
	_check(absf(bar.position.y - expected_top) < 1.0, "below the selection it sits just past the handles' reach (top %.1f, expected %.1f)" % [bar.position.y, expected_top])

	# At the far right edge it is pushed back inside.
	await _reset()
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var edge: LineEdit = _line_edit("right edge", Vector2(viewport_rect.end.x - 160.0, 300.0), Vector2(150.0, 50.0))
	await _frames(2)
	await _select_and_wait(edge, Vector2i(0, 0), Vector2i(10, 0))
	_check(viewport_rect.encloses(_toolbar.get_toolbar_rect()), "at the right edge the toolbar is kept inside the viewport (%s)" % str(_toolbar.get_toolbar_rect()))


func _test_other_controls() -> void:
	print("\n== TextEdit, CodeEdit and SpinBox")
	await _reset()
	var text_edit: TextEdit = TextEdit.new()
	text_edit.position = Vector2(40.0, 300.0)
	text_edit.size = Vector2(500.0, 160.0)
	text_edit.text = "alpha beta gamma\nsecond line here\nthird line"
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_root.add_child(text_edit)
	var code_edit: CodeEdit = CodeEdit.new()
	code_edit.position = Vector2(40.0, 520.0)
	code_edit.size = Vector2(500.0, 160.0)
	code_edit.gutters_draw_line_numbers = true
	code_edit.text = "func f() -> void:\n\tprint(\"hi\")\n\treturn"
	_root.add_child(code_edit)
	var spin: SpinBox = SpinBox.new()
	spin.position = Vector2(40.0, 720.0)
	spin.size = Vector2(300.0, 50.0)
	spin.max_value = 1000000.0
	spin.value = 123456.0
	_root.add_child(spin)
	await _frames(3)

	await _select_and_wait(text_edit, Vector2i(6, 0), Vector2i(4, 1))
	_check(_toolbar.is_showing() and _button_ids().size() >= 4, "TextEdit: the toolbar shows with all buttons (got %s)" % str(_button_ids()))
	_check(_toolbar.get_toolbar_rect().end.y <= _tip_of(text_edit, Vector2i(6, 0)).y, "TextEdit: the toolbar is above the selection")
	await _press_button(&"copy")
	await _wait_for(func() -> bool: return _clip().replace("\r\n", "\n") == "beta gamma\nseco")
	_check(_clip().replace("\r\n", "\n") == "beta gamma\nseco", "TextEdit: Copy copies a multi-line selection (got '%s')" % _clip())
	await _select_and_wait(text_edit, Vector2i(0, 2), Vector2i(5, 2))
	await _press_button(&"cut")
	_check(text_edit.get_line(2) == " line", "TextEdit: Cut removes the selection (line '%s')" % text_edit.get_line(2))

	await _select_and_wait(code_edit, Vector2i(5, 1), Vector2i(10, 1))
	_check(_toolbar.is_showing() and _button_ids().size() >= 4, "CodeEdit: the toolbar shows with all buttons (got %s)" % str(_button_ids()))
	await _press_button(&"copy")
	await _wait_for(func() -> bool: return _clip() == code_edit.get_selected_text() and not _clip().is_empty())
	_check(_clip() == code_edit.get_selected_text() and not _clip().is_empty(), "CodeEdit: Copy works (got '%s')" % _clip())
	await _select_and_wait(code_edit, Vector2i(0, 0), Vector2i(4, 0))
	DisplayServer.clipboard_set("XY")
	await _press_button(&"paste")
	_check(code_edit.get_line(0).begins_with("XY"), "CodeEdit: Paste replaces the selection (line '%s')" % code_edit.get_line(0))

	var line: LineEdit = spin.get_line_edit()
	await _select_and_wait(line, Vector2i(1, 0), Vector2i(4, 0))
	_check(_toolbar.is_showing() and _button_ids().size() >= 4, "SpinBox: the toolbar shows for its LineEdit (got %s)" % str(_button_ids()))
	await _press_button(&"copy")
	await _wait_for(func() -> bool: return _clip() == "234")
	_check(_clip() == "234", "SpinBox: Copy works (got '%s')" % _clip())


func _test_switches() -> void:
	print("\n== Switching the toolbar on and off, and hiding while pressed")
	await _reset()
	var edit: LineEdit = _line_edit("switch me on and off", Vector2(40.0, 300.0))
	await _frames(2)
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(6, 0))
	_check(_toolbar.is_showing(), "shown while enabled")
	_toolbar.enabled = false
	await _frames(3)
	_check(not _toolbar.is_showing(), "enabled = false hides it")
	await _frames(20)
	_check(not _toolbar.is_showing(), "and keeps it hidden while the selection stays")
	_toolbar.show_for_caret()
	await _frames(20)
	_check(not _toolbar.is_showing(), "show_for_caret() does nothing while disabled")
	_toolbar.enabled = true
	edit.select(0, 6)
	await _wait_toolbar(true)
	_check(_toolbar.is_showing(), "enabled = true brings it back")

	# Hidden while a mouse button is held (dragging handles or text selection).
	var away: Vector2 = Vector2(600.0, 700.0)
	_mouse_move(away)
	_mouse_button(away, true)
	await _frames(3)
	_check(not _toolbar.is_showing(), "hidden while a mouse button is held down")
	# Released after a drag: a plain tap out here would take the focus away (release_focus_on_tap_outside).
	_mouse_move(away + Vector2(0.0, -60.0))
	await _frames(1)
	_mouse_button(away + Vector2(0.0, -60.0), false)
	await _wait_toolbar(true)

	# Individual buttons can be turned off.
	_toolbar.show_cut = false
	_toolbar.show_select_all = false
	await _frames(4)
	_check(_buttons_are([&"copy", &"paste", &"more"]), "show_cut / show_select_all hide those buttons (got %s)" % str(_button_ids()))
	_toolbar.show_cut = true
	_toolbar.show_select_all = true
	_toolbar.text_copy = "Kopieren"
	await _frames(4)
	_check((_toolbar.get_button_rect(&"copy").size.x > 0.0) and _toolbar._panel.items.any(func(item: Dictionary) -> bool: return item["text"] == "Kopieren"), "button texts can be changed for localization")
	_toolbar.text_copy = "Copy"
	await _frames(3)


func _test_caret_toolbar_from_handle_tap() -> void:
	print("\n== Tapping the caret handle shows the toolbar (optional link to the carets controller)")
	await _reset()
	var edit: LineEdit = _line_edit("tap the handle under me", Vector2(40.0, 300.0))
	await _frames(2)
	await _focus(edit)
	edit.deselect()
	edit.caret_column = 6
	await _frames(4)
	_check(not _toolbar.is_showing(), "no toolbar for a plain caret")
	var handle: caret_indicator = _controller.get_node("Handles").get_child(0) as caret_indicator
	_check(handle.visible, "the caret handle is shown")
	var center: Vector2 = handle.global_position + handle.size * 0.5
	await _click(center)
	await _wait_toolbar(true)
	_check(edit.caret_column == 6 and not edit.has_selection(), "tapping the handle does not move the caret (col %d)" % edit.caret_column)
	_check(_toolbar.is_showing() and _buttons_are([&"paste", &"select_all", &"more"]), "tapping the handle shows Paste / Select all (got %s)" % str(_button_ids()))
	edit.caret_column = 9
	await _frames(4)
	_check(not _toolbar.is_showing(), "moving the caret hides the toolbar again")


func _test_hides_when_text_changes() -> void:
	print("\n== Typing hides the toolbar")
	await _reset()
	var edit: LineEdit = _line_edit("type over me", Vector2(40.0, 300.0))
	await _frames(2)
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(4, 0))
	for pressed: bool in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.pressed = pressed
		ev.unicode = "Z".unicode_at(0)
		ev.keycode = KEY_Z
		ev.physical_keycode = KEY_Z
		Input.parse_input_event(ev)
		await _frames(1)
	await _frames(4)
	_check(edit.text.begins_with("Z") and not edit.has_selection(), "typing replaced the selection (text '%s')" % edit.text)
	_check(not _toolbar.is_showing(), "the toolbar is hidden after typing")


func _test_physical_size() -> void:
	print("\n== Toolbar keeps its physical size")
	await _reset()
	var edit: LineEdit = _line_edit("size check text", Vector2(40.0, 300.0))
	await _frames(2)
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(4, 0))
	var window: Window = get_window()
	var saved_factor: float = window.content_scale_factor
	var dpi: float = float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		dpi = 96.0
	var expected: float = _toolbar.height_mm * dpi / 25.4
	for factor: float in [1.0, 1.5, 0.75]:
		window.content_scale_factor = factor
		await _frames(6)
		var screen_scale: float = get_viewport().get_final_transform().get_scale().x
		var on_screen: float = _toolbar.get_toolbar_rect().size.y * screen_scale
		_check(absf(on_screen - expected) < 1.5, "content scale %.2f: the toolbar is %.1f px tall on screen (expected %.1f)" % [factor, on_screen, expected])
	window.content_scale_factor = saved_factor
	await _frames(3)


func _test_overflow_menu() -> void:
	print("\n== Overflow menu: Undo / Redo / Share")
	await _reset()
	var edit: TextEdit = TextEdit.new()
	edit.position = Vector2(40.0, 300.0)
	edit.size = Vector2(500.0, 120.0)
	edit.text = "hello world"
	_root.add_child(edit)
	await _frames(3)
	await _focus(edit)
	# An edit gives something to undo.
	edit.set_caret_line(0)
	edit.set_caret_column(11)
	edit.insert_text_at_caret(" again")
	await _frames(2)
	_check(edit.text == "hello world again", "setup: text edited")
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(5, 0))
	_check(&"more" in _button_ids(), "the main row has the overflow button (got %s)" % str(_button_ids()))
	_check(not (&"undo" in _button_ids()), "Undo is not in the main row")
	await _press_button(&"more")
	await _frames(3)
	_check(_buttons_are([&"back", &"undo"]), "the overflow menu offers Back and Undo (nothing to redo yet; got %s)" % str(_button_ids()))
	_check(edit.has_focus() and edit.has_selection(), "opening the menu keeps focus and the selection")
	await _press_button(&"back")
	await _frames(3)
	_check(&"copy" in _button_ids() and &"more" in _button_ids(), "Back returns to the main row (got %s)" % str(_button_ids()))
	await _press_button(&"more")
	await _frames(3)
	var received: Array = []
	_toolbar.action_pressed.connect(func(action: StringName) -> void: received.append(action))
	await _press_button(&"undo")
	_check(edit.text == "hello world", "Undo reverts the edit (text '%s')" % edit.text)
	_check(received == [&"undo"], "action_pressed(undo) is emitted")
	# Now there is something to redo.
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(5, 0))
	await _press_button(&"more")
	await _frames(3)
	_check(&"back" in _button_ids() and &"redo" in _button_ids(), "after Undo the menu offers Redo (got %s)" % str(_button_ids()))
	await _press_button(&"redo")
	_check(edit.text == "hello world again", "Redo re-applies the edit (text '%s')" % edit.text)

	# Share is off by default and only reports the selected text.
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(5, 0))
	await _press_button(&"more")
	await _frames(3)
	_check(not (&"share" in _button_ids()), "no Share button unless show_share is on")
	_toolbar.show_share = true
	await _frames(3)
	_check(&"share" in _button_ids(), "show_share adds the Share button (got %s)" % str(_button_ids()))
	var shared: Array = []
	_toolbar.share_requested.connect(func(text: String) -> void: shared.append(text))
	await _press_button(&"share")
	_check(shared == ["hello"], "Share reports the selected text (got %s)" % str(shared))
	_toolbar.show_share = false
	# The overflow menu can be turned off.
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(5, 0))
	_toolbar.show_overflow = false
	await _frames(3)
	_check(not (&"more" in _button_ids()), "show_overflow = false removes the overflow button")
	_toolbar.show_overflow = true
	# Read-only controls have nothing to undo.
	edit.editable = false
	await _frames(4)
	_check(not (&"more" in _button_ids()), "a read-only control has no overflow menu")


func _test_tap_on_selection() -> void:
	print("\n== Tapping an existing selection")
	await _reset()
	var edit: LineEdit = _line_edit("tap on the selected words please", Vector2(40.0, 300.0))
	await _frames(2)
	await _select_and_wait(edit, Vector2i(4, 0), Vector2i(16, 0))
	var adapter: caret_text_adapter = caret_text_adapter.for_control(edit)
	var inside: Vector2 = edit.get_global_transform_with_canvas() * (adapter.get_tip_local(Vector2i(10, 0)) - Vector2(0.0, adapter.get_line_height() * 0.5))
	await _click(inside)
	_check(edit.has_selection() and edit.get_selected_text() == "on the selec", "a tap inside the selection keeps it (got '%s')" % edit.get_selected_text())
	await _frames(3)
	_check(not _toolbar.is_showing(), "and hides the visible toolbar")
	await _frames(20)
	_check(not _toolbar.is_showing(), "it stays hidden")
	await _click(inside)
	await _wait_toolbar(true)
	_check(edit.has_selection() and _toolbar.is_showing(), "tapping the selection again brings the toolbar back")
	# After Copy the toolbar is dismissed; tapping the selection brings it back too.
	await _press_button(&"copy")
	await _frames(15)
	_check(not _toolbar.is_showing() and edit.has_selection(), "Copy hides it and keeps the selection")
	await _click(inside)
	await _wait_toolbar(true)
	_check(_toolbar.is_showing() and edit.has_selection(), "a tap on the selection shows it again after Copy")
	# A tap outside the selection collapses it as usual.
	var outside: Vector2 = edit.get_global_transform_with_canvas() * (adapter.get_tip_local(Vector2i(29, 0)) - Vector2(0.0, adapter.get_line_height() * 0.5))
	await _click(outside)
	await _frames(4)
	_check(not edit.has_selection(), "a tap outside the selection collapses it")
	# The behaviour can be turned off.
	_toolbar.tap_selection_toggles_toolbar = false
	await _select_and_wait(edit, Vector2i(4, 0), Vector2i(16, 0))
	await _click(inside)
	await _frames(4)
	_check(not edit.has_selection(), "with tap_selection_toggles_toolbar = false a tap collapses the selection")
	_toolbar.tap_selection_toggles_toolbar = true
	# The same for a TextEdit, on a selection spanning two lines.
	var text_edit: TextEdit = TextEdit.new()
	text_edit.position = Vector2(40.0, 420.0)
	text_edit.size = Vector2(500.0, 120.0)
	text_edit.text = "first line of the text\nsecond line of the text"
	_root.add_child(text_edit)
	await _frames(3)
	await _select_and_wait(text_edit, Vector2i(6, 0), Vector2i(6, 1))
	var text_adapter: caret_text_adapter = caret_text_adapter.for_control(text_edit)
	var in_second_line: Vector2 = text_edit.get_global_transform_with_canvas() * (text_adapter.get_tip_local(Vector2i(2, 1)) - Vector2(0.0, text_adapter.get_line_height() * 0.5))
	await _click(in_second_line)
	_check(text_edit.has_selection() and text_edit.get_selected_text().begins_with("line of the text"), "TextEdit: a tap inside a multi-line selection keeps it")
	_check(not _toolbar.is_showing(), "TextEdit: and hides the toolbar")


func _test_rich_text_label() -> void:
	print("\n== Selectable RichTextLabel (toolbar only, no handles)")
	await _reset()
	var label: RichTextLabel = RichTextLabel.new()
	label.position = Vector2(40.0, 300.0)
	label.size = Vector2(520.0, 120.0)
	label.selection_enabled = true
	label.focus_mode = Control.FOCUS_ALL
	label.scroll_active = false
	label.add_theme_font_size_override("normal_font_size", 28)
	label.text = "Selectable rich text for the toolbar"
	_root.add_child(label)
	await _frames(4)
	# Select a word with a double click, like a user would.
	var y: float = label.global_position.y + 18.0
	var word_point: Vector2 = Vector2(label.global_position.x + 60.0, y)
	_mouse_move(word_point)
	_mouse_button(word_point, true)
	await _frames(1)
	_mouse_button(word_point, false)
	await _frames(1)
	_mouse_button(word_point, true, true)
	await _frames(1)
	_mouse_button(word_point, false)
	await _frames(2)
	_check(label.has_focus(), "the label took focus")
	_check(label.get_selected_text() == "Selectable", "a double click selected a word ('%s')" % label.get_selected_text())
	await _wait_toolbar(true)
	_check(_toolbar.is_showing(), "the toolbar shows for a selectable label")
	_check(_buttons_are([&"copy", &"select_all"]), "only Copy and Select all (got %s)" % str(_button_ids()))
	var bar: Rect2 = _toolbar.get_toolbar_rect()
	_check(get_viewport().get_visible_rect().encloses(bar) and bar.end.y <= label.global_position.y + 30.0, "the toolbar is placed over the label (%s)" % str(bar))
	var selected: String = label.get_selected_text()
	await _press_button(&"copy")
	await _wait_for(func() -> bool: return _clip() == selected)
	_check(_clip() == selected, "Copy puts the selection on the clipboard (got '%s')" % _clip())
	await _frames(15)
	_check(not _toolbar.is_showing(), "the toolbar hides after Copy")
	# Tapping the label keeps the selection and brings the toolbar back.
	await _click(word_point)
	await _wait_toolbar(true)
	_check(label.get_selected_text() == selected and _toolbar.is_showing(), "a tap on the label keeps its selection and shows the toolbar")
	await _press_button(&"select_all")
	await _frames(3)
	_check(label.get_selected_text() == label.get_parsed_text(), "Select all selects everything")
	await _wait_toolbar(true)
	_check(_buttons_are([&"copy"]), "with everything selected only Copy is left (got %s)" % str(_button_ids()))
	# A plain tap never reaches the label as a press, a drag that starts in the selection does.
	var presses: Array = []
	label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			presses.append(true))
	await _click(word_point)
	await _frames(2)
	_check(presses.is_empty(), "a tap on the selected label does not reach it as a press")
	_mouse_move(word_point)
	_mouse_button(word_point, true)
	await _frames(1)
	for i: int in range(1, 5):
		_mouse_move(word_point + Vector2(float(i) * 25.0, 0.0))
		await _frames(1)
	await _frames(2)
	_mouse_button(word_point + Vector2(100.0, 0.0), false)
	await _frames(2)
	_check(presses.size() == 1, "a drag starting inside the selection hands the press to the label (%d presses)" % presses.size())
	# No caret handles exist for a label.
	_check(not (_controller.get_node("Handles").get_child(0) as caret_indicator).visible, "no caret handles for a RichTextLabel")


# The toolbar must work when there is no carets controller at all.
func _test_without_carets_controller() -> void:
	print("\n== Toolbar without the carets controller")
	_controller.queue_free()
	await _frames(4)
	await _reset()
	var edit: LineEdit = _line_edit("works on its own", Vector2(40.0, 300.0))
	await _frames(2)
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(5, 0))
	_check(not is_instance_valid(_controller) or _controller.is_queued_for_deletion(), "the carets controller is gone")
	_check(_toolbar.is_showing() and &"copy" in _button_ids(), "the toolbar still shows for a selection (got %s)" % str(_button_ids()))
	await _press_button(&"select_all")
	_check(edit.get_selected_text() == edit.text, "and Select all works")
	await _wait_toolbar(true)
	await _press_button(&"copy")
	await _wait_for(func() -> bool: return _clip() == "works on its own")
	_check(_clip() == "works on its own", "and so does Copy (got '%s')" % _clip())

# Regressions found by the code review.
func _test_review_fixes() -> void:
	print("\n== Review fixes")
	await _reset()
	# 1. A tap on a selection must not leave the long-press timer running (it would collapse the
	# selection to a single word half a second later).
	var edit: LineEdit = _line_edit("one two three four five six", Vector2(40.0, 300.0))
	await _frames(2)
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(13, 0))
	var adapter: caret_text_adapter = caret_text_adapter.for_control(edit)
	var inside: Vector2 = edit.get_global_transform_with_canvas() * (adapter.get_tip_local(Vector2i(6, 0)) - Vector2(0.0, adapter.get_line_height() * 0.5))
	await _click(inside)
	await get_tree().create_timer(_controller.long_press_seconds + 0.4).timeout
	_check(edit.get_selected_text() == "one two three", "after a tap on the selection nothing collapses it later (got '%s')" % edit.get_selected_text())
	# 4. Colors set at runtime apply to the visible toolbar.
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(12, 0))
	_toolbar.text_color = Color(1.0, 0.0, 0.0)
	_toolbar.background_color = Color(0.0, 0.5, 0.0, 1.0)
	await _frames(3)
	_check(_toolbar._panel.text_color == Color(1.0, 0.0, 0.0) and _toolbar._panel.background_color == Color(0.0, 0.5, 0.0, 1.0), "changing the toolbar colors at runtime updates the visible bar")
	_toolbar.text_color = Color.WHITE
	_toolbar.background_color = Color(0.13, 0.14, 0.17, 0.97)
	await _frames(2)
	# 5. A password field never offers Copy, Cut or Share.
	var secret: LineEdit = _line_edit("hunter2 secret", Vector2(40.0, 420.0))
	secret.secret = true
	await _frames(2)
	_toolbar.show_share = true
	await _select_and_wait(secret, Vector2i(0, 0), Vector2i(7, 0))
	var ids: Array[StringName] = _button_ids()
	_check(not (&"copy" in ids) and not (&"cut" in ids), "a secret LineEdit offers no Copy or Cut (got %s)" % str(ids))
	_toolbar.show_share = false
	# 7/8. Hiding the toolbar mid-press does not leave a button stuck.
	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(11, 0))
	var copy_center: Vector2 = _toolbar.get_button_rect(&"copy").get_center()
	_mouse_move(copy_center)
	_mouse_button(copy_center, true)
	await _frames(2)
	_check(_toolbar._pressed_action == &"copy", "setup: a button is held down")
	_toolbar.enabled = false
	await _frames(2)
	_toolbar.enabled = true
	_mouse_button(copy_center, false)
	await _frames(2)
	_check(_toolbar._pressed_action == &"" and _toolbar._panel.pressed_index == -1, "switching the toolbar off clears a held button")
	# 6. The toolbar relinks to a new carets controller.
	var old_controller: Node = _controller
	_check(_toolbar._linked_controller == old_controller, "the toolbar is linked to the carets controller")
	# 13. A control scrolled out of a ScrollContainer takes the toolbar with it.
	await _reset()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(40.0, 200.0)
	scroll.size = Vector2(500.0, 200.0)
	_root.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var top_pad: Control = Control.new()
	top_pad.custom_minimum_size = Vector2(0.0, 100.0)
	box.add_child(top_pad)
	var scrolled: LineEdit = LineEdit.new()
	scrolled.text = "inside a scroll container"
	box.add_child(scrolled)
	var bottom_pad: Control = Control.new()
	bottom_pad.custom_minimum_size = Vector2(0.0, 800.0)
	box.add_child(bottom_pad)
	await _frames(3)
	await _select_and_wait(scrolled, Vector2i(0, 0), Vector2i(6, 0))
	_check(_toolbar.is_showing(), "the toolbar shows while the control is visible in the container")
	scroll.scroll_vertical = 500
	await _frames(5)
	_check(not _toolbar.is_showing(), "the toolbar hides when the control is scrolled out of the container")
	scroll.scroll_vertical = 0
	await _wait_toolbar(true)
	_check(_toolbar.is_showing(), "and comes back when it scrolls into view")



# Tapping the handle in an empty field offers Paste.
# While it shows, the toolbar reads the system clipboard (for Paste) only now and then: on a phone
# each read is a call to another process. Text copied elsewhere still brings Paste soon.
func _test_clipboard_reads() -> void:
	print("\n== Clipboard reads")
	await _reset()
	var edit: LineEdit = _line_edit("hello brave world", Vector2(40.0, 300.0))
	await _select_and_wait(edit, Vector2i(6, 0), Vector2i(11, 0))
	var reads_before: int = _toolbar._clipboard_reads
	var started: int = Time.get_ticks_msec()
	await _frames(30)
	var reads: int = _toolbar._clipboard_reads - reads_before
	var allowed: int = (Time.get_ticks_msec() - started) / 500 + 1
	_check(_toolbar.is_showing() and reads <= allowed, "30 frames with the toolbar showing read the clipboard about twice a second, not every frame (%d reads, %d allowed)" % [reads, allowed])
	# still read now and then, so text copied in another app is noticed
	var reads_then: int = _toolbar._clipboard_reads
	await _frames(45)
	_check(_toolbar._clipboard_reads > reads_then, "the clipboard is read again while the toolbar stays open")
	# the next time the toolbar opens it reads the clipboard at once
	_toolbar.hide_toolbar()
	await _frames(2)
	var reads_hidden: int = _toolbar._clipboard_reads
	edit.select(0, 5)
	await _wait_toolbar(true)
	_check(_toolbar._clipboard_reads > reads_hidden, "a toolbar that opens again reads the clipboard at once")


func _test_empty_field() -> void:
	print("\n== Empty field")
	await _reset()
	var edit: LineEdit = _line_edit("", Vector2(40.0, 300.0))
	edit.placeholder_text = "Write text here..."
	await _frames(2)
	await _focus(edit)
	await _frames(3)
	var handle: caret_indicator = _controller.get_node("Handles").get_child(0) as caret_indicator
	_check(handle.visible, "the caret handle shows in an empty field")
	_check(not _toolbar.is_showing(), "no toolbar until the handle is tapped")
	await _click(handle.global_position + handle.size * 0.5)
	await _wait_toolbar(true)
	_check(_toolbar.is_showing() and _buttons_are([&"paste", &"more"]), "tapping the handle offers Paste (no Select all on empty text; got %s)" % str(_button_ids()))
	await _press_button(&"paste")
	_check(edit.text == "clip", "Paste fills the field (text '%s')" % edit.text)


# Each control can have its own menu: switched off, or limited to some of the built-in buttons
# (set from code, on any control; a custom control's delegate can answer get_toolbar_actions()).
func _test_control_menu_settings() -> void:
	print("\n== The menu of one control: on or off, and which buttons")
	await _reset()
	var plain: LineEdit = _line_edit("an ordinary field", Vector2(40.0, 200.0))
	var limited: LineEdit = _line_edit("a field with only copy", Vector2(40.0, 400.0))
	await _frames(2)
	_toolbar.set_control_actions(limited, [&"copy"])
	await _select_and_wait(limited, Vector2i(0, 0), Vector2i(7, 0))
	_check(_buttons_are([&"copy"]), "set_control_actions limits the buttons of that control (got %s)" % str(_button_ids()))
	await _select_and_wait(plain, Vector2i(0, 0), Vector2i(6, 0))
	_check(_button_ids().has(&"cut") and _button_ids().has(&"paste"), "another control keeps all its buttons (got %s)" % str(_button_ids()))
	_toolbar.set_control_menu(plain, false)
	await _frames(6)
	_check(not _toolbar.is_showing(), "set_control_menu(control, false) hides the menu of that control")
	plain.select(0, 3)
	await _frames(30)
	_check(not _toolbar.is_showing(), "and it stays hidden when the selection changes")
	_toolbar.set_control_menu(plain, true)
	plain.select(0, 6)
	await _wait_toolbar(true)
	_check(_toolbar.is_showing(), "set_control_menu(control, true) brings it back")
	_toolbar.clear_control_settings(limited)
	await _select_and_wait(limited, Vector2i(0, 0), Vector2i(7, 0))
	_check(_button_ids().has(&"cut"), "clear_control_settings gives a control all its buttons again (got %s)" % str(_button_ids()))
	_check(_toolbar.get_control_actions(plain).is_empty() and _toolbar.is_control_menu_enabled(plain), "a control without settings: every button, menu on")
	# a custom control's delegate can choose its buttons; a setting on the control wins
	var choosy: ChoosyLabel = ChoosyLabel.new()
	choosy.position = Vector2(40.0, 600.0)
	choosy.size = Vector2(300.0, 60.0)
	_root.add_child(choosy)
	await _focus(choosy)
	await _wait_toolbar(true)
	_check(_buttons_are([&"copy"]), "a delegate's get_toolbar_actions() chooses its buttons (got %s)" % str(_button_ids()))
	_toolbar.set_control_actions(choosy, [&"cut", &"copy"])
	await _frames(4)
	_check(_buttons_are([&"cut", &"copy"]), "set_control_actions on the control comes first (got %s)" % str(_button_ids()))
	await _frames(2)


# Delete removes the selected text (not to the clipboard). Off by default, like Share; only for
# text that can be edited.
func _test_delete_button() -> void:
	print("\n== The Delete button")
	await _reset()
	var edit: LineEdit = _line_edit("delete this word", Vector2(40.0, 300.0))
	var fixed: LineEdit = _line_edit("read only text", Vector2(40.0, 450.0))
	fixed.editable = false
	await _frames(2)
	await _select_and_wait(edit, Vector2i(7, 0), Vector2i(12, 0))
	_check(not _button_ids().has(&"delete"), "no Delete button by default")
	_toolbar.show_delete = true
	await _frames(4)
	_check(_button_ids().has(&"delete"), "show_delete = true shows it for an editable selection (got %s)" % str(_button_ids()))
	DisplayServer.clipboard_set("kept")
	await _press_button(&"delete")
	await _frames(3)
	_check(edit.text == "delete word", "Delete removes the selected text (got '%s')" % edit.text)
	_check(DisplayServer.clipboard_get() == "kept", "and leaves the clipboard alone")
	await _select_and_wait(fixed, Vector2i(0, 0), Vector2i(4, 0))
	_check(not _button_ids().has(&"delete"), "no Delete for text that cannot be edited")
	var area: TextEdit = TextEdit.new()
	area.text = "first line\nsecond line"
	area.position = Vector2(40.0, 600.0)
	area.size = Vector2(500.0, 120.0)
	_root.add_child(area)
	await _frames(2)
	await _select_and_wait(area, Vector2i(0, 1), Vector2i(7, 1))
	await _press_button(&"delete")
	await _frames(3)
	_check(area.text == "first line\nline", "Delete in a TextEdit too (got %s)" % area.text.c_escape())
	_toolbar.show_delete = false
	await _frames(2)


# A long press on an image opens the menu with the items given for it (an app's "Save image").
# There are no text buttons for an image, and no Copy: Godot cannot put an image on the clipboard.
func _test_image_menu() -> void:
	print("\n== A menu on an image (caret_image_menu)")
	await _reset()
	var img: Image = Image.create(200, 150, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.8))
	var pic: TextureRect = TextureRect.new()
	pic.texture = ImageTexture.create_from_image(img)
	pic.position = Vector2(80.0, 300.0)
	pic.size = Vector2(200.0, 150.0)
	_root.add_child(pic)
	var pressed: Array = []
	var menu: caret_image_menu = caret_image_menu.attach(pic, [{"id": &"save_image", "text": "Save image"}])
	menu.item_pressed.connect(func(id: StringName) -> void: pressed.append(id))
	await _frames(2)
	var at: Vector2 = pic.get_global_rect().get_center()
	# a short tap opens nothing
	await _click(at)
	await _frames(30)
	_check(not _toolbar.is_showing(), "a short tap on the image opens no menu")
	# a press held still opens it (it shows once the finger is lifted, as for text)
	_mouse_move(at)
	_mouse_button(at, true)
	await get_tree().create_timer(menu.long_press_time + 0.2).timeout
	_mouse_button(at, false)
	await _wait_toolbar(true)
	_check(_toolbar.is_showing() and _toolbar.get_button_rect(&"save_image").size != Vector2.ZERO, "a long press on the image opens its menu with its items")
	_check(_button_ids().all(func(id: StringName) -> bool: return id == &"copy_image"), "no text buttons (Cut, Copy, Select all) for an image (got %s)" % str(_button_ids()))
	var item_rect: Rect2 = _toolbar.get_button_rect(&"save_image")
	_check(item_rect.end.y <= at.y + 1.0, "the menu is above the finger (%.0f, finger at %.0f)" % [item_rect.end.y, at.y])
	await _click(item_rect.get_center())
	await _frames(4)
	_check(pressed == [&"save_image"], "pressing an item tells the app (got %s)" % str(pressed))
	_check(not _toolbar.is_showing() and not pic.has_focus(), "and the menu closes")
	# a press held while the finger moves (a drag or pan) is not a long press
	_mouse_move(at)
	_mouse_button(at, true)
	for i: int in 8:
		_mouse_move(at + Vector2(6.0 * i, 0.0))
		await _frames(2)
	await get_tree().create_timer(menu.long_press_time + 0.1).timeout
	_mouse_button(at + Vector2(42.0, 0.0), false)
	await _frames(30)
	_check(not _toolbar.is_showing(), "a press that moves (a pan) opens no menu")
	# open, then a tap elsewhere closes it
	_mouse_move(at)
	_mouse_button(at, true)
	await get_tree().create_timer(menu.long_press_time + 0.2).timeout
	_mouse_button(at, false)
	await _wait_toolbar(true)
	await _click(Vector2(600.0, 700.0))
	await _wait_toolbar(false)
	_check(not _toolbar.is_showing() and not pic.has_focus(), "a tap elsewhere closes the image menu")
	# switched off from code
	_toolbar.set_control_menu(pic, false)
	_mouse_move(at)
	_mouse_button(at, true)
	await get_tree().create_timer(menu.long_press_time + 0.2).timeout
	_mouse_button(at, false)
	await _frames(30)
	_check(not _toolbar.is_showing(), "set_control_menu(image, false) switches the image menu off")
	_toolbar.clear_control_settings(pic)
	menu.detach()
	_check(not pic.has_meta(caret_image_menu.META), "detach() removes it from the image")
	await _frames(2)


# Copy image: a built-in button of an image's menu, where the system clipboard can take an image
# (caret_image_clipboard: Android through Godot's Java bridge, Windows through PowerShell).
func _test_copy_image() -> void:
	print("\n== Copy image (caret_image_clipboard)")
	await _reset()
	var img: Image = Image.create(120, 80, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.2, 0.1))
	var pic: TextureRect = TextureRect.new()
	pic.texture = ImageTexture.create_from_image(img)
	pic.position = Vector2(80.0, 300.0)
	pic.size = Vector2(120.0, 80.0)
	_root.add_child(pic)
	var menu: caret_image_menu = caret_image_menu.attach(pic, [{"id": &"save_image", "text": "Save image"}])
	var results: Array = []
	menu.image_copied.connect(func(error: String) -> void: results.append(error))
	await _frames(2)
	_check(menu.get_image() != null and menu.get_image().get_size() == Vector2i(120, 80), "the menu's image is the TextureRect's own")
	var supported: bool = caret_image_clipboard.supported()
	_check(supported == (OS.get_name() in ["Windows", "Android"]), "caret_image_clipboard.supported() on %s: %s" % [OS.get_name(), supported])
	menu.open_at(Vector2(60.0, 40.0))
	await _wait_toolbar(true)
	_check(_button_ids().has(&"copy_image") == supported, "Copy image is in the menu where the clipboard can take an image (got %s)" % str(_button_ids()))
	if supported:
		_check(_toolbar.get_button_rect(&"copy_image").position.x < _toolbar.get_button_rect(&"save_image").position.x, "it comes first, before the app's own items")
		DisplayServer.clipboard_set("text before")
		await _press_button(&"copy_image")
		for i: int in 600:
			if not results.is_empty():
				break
			await _frames(1)
		_check(results == [""], "pressing it copies the image (result %s)" % str(results))
		_check(DisplayServer.clipboard_has_image(), "the clipboard now holds an image")
		_check(not menu.is_open(), "and the menu closes")
	# the toolbar's switch and the control's own settings
	_toolbar.show_copy_image = false
	menu.open_at(Vector2(60.0, 40.0))
	await _wait_toolbar(true)
	_check(not _button_ids().has(&"copy_image"), "show_copy_image = false hides it")
	_toolbar.show_copy_image = true
	_toolbar.set_control_actions(pic, [])
	await _frames(4)
	_check(not _button_ids().has(&"copy_image"), "set_control_actions(image, []) hides it for that image")
	_toolbar.clear_control_settings(pic)
	menu.close()
	menu.detach()
	await _frames(2)


# A menu on a view whose own presses do something (a slider, a bit, a node of an interactive
# plot): is_interactive_at(point) keeps the long press away from those spots. A view without a
# texture is copied as it is on screen.
class ViewWithKnob extends ColorRect:
	var presses: int = 0

	func is_interactive_at(point: Vector2) -> bool:
		return point.x < size.x * 0.5

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and is_interactive_at(event.position):
			presses += 1


func _test_image_menu_on_a_view() -> void:
	print("\n== A menu on a view with interactive spots")
	await _reset()
	var view: ViewWithKnob = ViewWithKnob.new()
	view.color = Color(0.1, 0.6, 0.2)
	view.position = Vector2(80.0, 300.0)
	view.size = Vector2(300.0, 160.0)
	_root.add_child(view)
	var menu: caret_image_menu = caret_image_menu.attach(view, [{"id": &"save_image", "text": "Save image"}])
	await _frames(3)
	var knob: Vector2 = view.global_position + Vector2(60.0, 80.0)
	_mouse_move(knob)
	_mouse_button(knob, true)
	await get_tree().create_timer(menu.long_press_time + 0.2).timeout
	_mouse_button(knob, false)
	await _frames(30)
	_check(not _toolbar.is_showing() and not menu.is_open(), "a long press on an interactive spot opens no menu")
	_check(view.presses == 1, "and the view gets its press as usual (%d)" % view.presses)
	var empty: Vector2 = view.global_position + Vector2(240.0, 80.0)
	_mouse_move(empty)
	_mouse_button(empty, true)
	await get_tree().create_timer(menu.long_press_time + 0.2).timeout
	_mouse_button(empty, false)
	await _wait_toolbar(true)
	_check(menu.is_open() and view.presses == 1, "a long press on an empty spot opens the menu, and the view does nothing")
	var shot: Image = menu.get_image()
	var mid: Color = shot.get_pixel(shot.get_width() / 2, shot.get_height() / 2) if shot != null else Color.BLACK
	_check(shot != null and absf(float(shot.get_width()) / shot.get_height() - 300.0 / 160.0) < 0.05 and absf(mid.g - 0.6) < 0.05 and mid.r < 0.2, "a view without a texture is taken as it is on screen (%s, middle %s)" % [str(shot.get_size()) if shot != null else "none", mid])
	menu.close()
	menu.detach()
	await _frames(2)


# A view that draws its own words, made selectable with a caret delegate: one line, "abc def",
# 20 px per character from x = 20, from y = 20 to 50, on the left of the view.
class DrawnWords extends RefCounted:
	var text: String = "abc def"
	var anchor: int = 0
	var caret: int = 0

	func _x(column: int) -> float:
		return 20.0 + 20.0 * column

	func has_text_at(point: Vector2) -> bool:
		var column: int = int(floor((point.x - 20.0) / 20.0))
		return point.y >= 20.0 and point.y <= 50.0 and column >= 0 and column < text.length() and text[column] != " "

	func supports_handles() -> bool:
		return true

	func is_text_editable() -> bool:
		return false

	func is_empty() -> bool:
		return false

	func get_caret() -> Vector2i:
		return Vector2i(caret, 0)

	func set_caret(pos: Vector2i) -> void:
		anchor = pos.x
		caret = pos.x

	func select(from: Vector2i, to: Vector2i) -> void:
		anchor = from.x
		caret = to.x

	func deselect() -> void:
		anchor = caret

	func has_selection() -> bool:
		return anchor != caret

	func get_selection_from() -> Vector2i:
		return Vector2i(mini(anchor, caret), 0)

	func get_selection_to() -> Vector2i:
		return Vector2i(maxi(anchor, caret), 0)

	func get_selected_text() -> String:
		return text.substr(mini(anchor, caret), absi(caret - anchor))

	func select_word_at(pos: Vector2i) -> void:
		var from: int = pos.x
		while from > 0 and text[from - 1] != " ":
			from -= 1
		var to: int = pos.x
		while to < text.length() and text[to] != " ":
			to += 1
		anchor = from
		caret = to

	func get_pos_at_local(local: Vector2) -> Vector2i:
		return Vector2i(clampi(roundi((local.x - 20.0) / 20.0), 0, text.length()), 0)

	func get_tip_local(pos: Vector2i) -> Vector2:
		return Vector2(_x(pos.x), 50.0)

	func get_line_height() -> float:
		return 30.0


class ViewWithWords extends ColorRect:
	var words: DrawnWords = DrawnWords.new()

	func _get_caret_delegate() -> Object:
		return words


func _test_image_menu_with_text() -> void:
	print("\n== A menu on a view that draws selectable text")
	await _reset()
	var view: ViewWithWords = ViewWithWords.new()
	view.color = Color(0.95, 0.95, 0.9)
	view.position = Vector2(80.0, 300.0)
	view.size = Vector2(320.0, 160.0)
	_root.add_child(view)
	var pressed: Array = []
	var menu: caret_image_menu = caret_image_menu.attach(view, [{"id": &"save_image", "text": "Save image"}])
	menu.item_pressed.connect(func(id: StringName) -> void: pressed.append(id))
	await _frames(3)
	var on_word: Vector2 = view.global_position + Vector2(50.0, 35.0)
	_check(menu.has_text_at(Vector2(50.0, 35.0)) and not menu.has_text_at(Vector2(250.0, 120.0)), "has_text_at: the delegate tells where the view's text is")
	_mouse_move(on_word)
	_mouse_button(on_word, true)
	await get_tree().create_timer(menu.long_press_time + 0.2).timeout
	_mouse_button(on_word, false)
	await _wait_toolbar(true)
	await _frames(4)
	_check(menu.is_text_open() and not menu.is_open() and view.has_focus(), "a long press on the view's text selects it (not the image menu)")
	_check(view.words.get_selected_text() == "abc", "the word under the finger is selected (got %s)" % view.words.get_selected_text())
	var ids: Array[StringName] = _button_ids()
	var more_at: Rect2 = _toolbar.get_button_rect(caret_image_text_adapter.MORE_ID)
	# On a phone the toolbar can lie over the view, and a finger comes as a mouse press (the toolbar
	# takes it) and a touch (which reaches the view under the toolbar): that touch is not a tap on
	# the view and must not end the selection.
	var to_local: Transform2D = view.get_global_transform_with_canvas().affine_inverse()
	for down: bool in [true, false]:
		var touch: InputEventScreenTouch = InputEventScreenTouch.new()
		touch.pressed = down
		touch.position = to_local * more_at.get_center()
		menu._on_gui_input(touch)
	await _frames(2)
	_check(menu.is_text_open() and view.words.has_selection() and view.has_focus(), "a touch on the toolbar over the view does not end the selection")
	_check(ids.has(&"copy") and ids.has(&"select_all") and not ids.has(&"copy_image") and _toolbar.get_button_rect(&"save_image").size == Vector2.ZERO and more_at.size != Vector2.ZERO, "the main row has the text's buttons and ···; the image's buttons are not in it (got %s)" % str(ids))
	await _click(more_at.get_center())
	await _frames(4)
	var copy_image_at: Rect2 = _toolbar.get_button_rect(caret_image_text_adapter.COPY_IMAGE_ID)
	_check(_toolbar.get_button_rect(&"save_image").size != Vector2.ZERO and not _button_ids().has(&"copy"), "··· opens the image's items (got %s)" % str(_button_ids()))
	_check((copy_image_at.size != Vector2.ZERO) == caret_image_clipboard.supported(), "with Copy image first where the clipboard can take an image")
	if copy_image_at.size != Vector2.ZERO:
		_check(copy_image_at.position.x < _toolbar.get_button_rect(&"save_image").position.x, "Copy image comes before the image menu's own items")
	await _press_button(&"back")
	await _frames(4)
	_check(_button_ids().has(&"copy") and menu.is_text_open(), "‹ goes back to the text's buttons, the text still selected")
	menu.image_items_in_more = false
	await _frames(4)
	_check(_toolbar.get_button_rect(&"save_image").size != Vector2.ZERO and _button_ids().has(&"copy_image") == caret_image_clipboard.supported(), "image_items_in_more = false puts them in the main row (got %s)" % str(_button_ids()))
	menu.image_items_in_more = true
	await _frames(4)
	_check(_toolbar.get_button_rect(&"save_image").size == Vector2.ZERO and _toolbar.get_button_rect(&"copy").size != Vector2.ZERO, "and back under ··· when it is on again")
	DisplayServer.clipboard_set("before")
	await _press_button(&"copy")
	await _frames(4)
	_check(DisplayServer.clipboard_get() == "abc", "Copy puts the selected text on the clipboard (got %s)" % DisplayServer.clipboard_get())
	# again, then the image's item from the same menu
	_mouse_move(on_word)
	_mouse_button(on_word, true)
	await get_tree().create_timer(menu.long_press_time + 0.2).timeout
	_mouse_button(on_word, false)
	await _wait_toolbar(true)
	await _frames(4)
	await _click(_toolbar.get_button_rect(caret_image_text_adapter.MORE_ID).get_center())
	await _frames(4)
	var save_at: Rect2 = _toolbar.get_button_rect(&"save_image")
	await _click(save_at.get_center())
	await _frames(4)
	_check(pressed == [&"save_image"], "the image's item works from the text menu (got %s)" % str(pressed))
	_check(not menu.is_text_open() and not view.words.has_selection() and not view.has_focus(), "and the selection ends")
	_check(menu.get_image() != null, "the image to save is there (taken when the text was long-pressed)")
	# a tap on the view while its text is selected ends the selection
	_mouse_move(on_word)
	_mouse_button(on_word, true)
	await get_tree().create_timer(menu.long_press_time + 0.2).timeout
	_mouse_button(on_word, false)
	await _wait_toolbar(true)
	await _click(view.global_position + Vector2(250.0, 120.0))
	await _wait_toolbar(false)
	_check(not view.words.has_selection() and not view.has_focus() and not _toolbar.is_showing(), "a tap on the view ends the text selection")
	# a long press away from the text: the image menu, as before
	var blank: Vector2 = view.global_position + Vector2(250.0, 120.0)
	_mouse_move(blank)
	_mouse_button(blank, true)
	await get_tree().create_timer(menu.long_press_time + 0.2).timeout
	_mouse_button(blank, false)
	await _wait_toolbar(true)
	await _frames(4)
	_check(menu.is_open() and not menu.is_text_open() and not view.words.has_selection(), "a long press away from the text opens the image menu")
	_check(not _button_ids().has(&"copy") and _toolbar.get_button_rect(&"save_image").size != Vector2.ZERO, "with the image's items only (got %s)" % str(_button_ids()))
	menu.close()
	menu.detach()
	await _frames(2)
