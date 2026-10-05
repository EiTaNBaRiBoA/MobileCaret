# Checks the floating toolbar (Cut / Copy / Paste / Select all) against LineEdit, TextEdit,
# CodeEdit and SpinBox. Run with:  godot --path <project> res://MobileCaret/tests/test_toolbar.tscn
extends Node

var _failures: int = 0
var _checks: int = 0
var _controller: carets_controller
var _toolbar: caret_toolbar
var _root: Control
var _saved_clipboard: String = ""


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
	await _test_review_fixes()
	await _test_physical_size()
	await _test_without_carets_controller()

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
	for action: StringName in [&"back", &"cut", &"copy", &"paste", &"select_all", &"undo", &"redo", &"share", &"more"]:
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
	_check(DisplayServer.clipboard_get() == "brave", "Copy puts the selection on the clipboard (got '%s')" % DisplayServer.clipboard_get())
	_check(edit.has_selection() and edit.get_selected_text() == "brave", "Copy keeps the selection")
	_check(edit.has_focus(), "the text control keeps focus when a toolbar button is pressed")
	await _frames(15)
	_check(not _toolbar.is_showing(), "the toolbar hides after Copy")

	await _select_and_wait(edit, Vector2i(0, 0), Vector2i(5, 0))
	await _press_button(&"cut")
	_check(edit.text == " brave new world" and DisplayServer.clipboard_get() == "hello", "Cut removes the selection and copies it (text '%s', clipboard '%s')" % [edit.text, DisplayServer.clipboard_get()])

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
	_check(DisplayServer.clipboard_get().replace("\r\n", "\n") == "beta gamma\nseco", "TextEdit: Copy copies a multi-line selection (got '%s')" % DisplayServer.clipboard_get())
	await _select_and_wait(text_edit, Vector2i(0, 2), Vector2i(5, 2))
	await _press_button(&"cut")
	_check(text_edit.get_line(2) == " line", "TextEdit: Cut removes the selection (line '%s')" % text_edit.get_line(2))

	await _select_and_wait(code_edit, Vector2i(5, 1), Vector2i(10, 1))
	_check(_toolbar.is_showing() and _button_ids().size() >= 4, "CodeEdit: the toolbar shows with all buttons (got %s)" % str(_button_ids()))
	await _press_button(&"copy")
	_check(DisplayServer.clipboard_get() == code_edit.get_selected_text() and not DisplayServer.clipboard_get().is_empty(), "CodeEdit: Copy works (got '%s')" % DisplayServer.clipboard_get())
	await _select_and_wait(code_edit, Vector2i(0, 0), Vector2i(4, 0))
	DisplayServer.clipboard_set("XY")
	await _press_button(&"paste")
	_check(code_edit.get_line(0).begins_with("XY"), "CodeEdit: Paste replaces the selection (line '%s')" % code_edit.get_line(0))

	var line: LineEdit = spin.get_line_edit()
	await _select_and_wait(line, Vector2i(1, 0), Vector2i(4, 0))
	_check(_toolbar.is_showing() and _button_ids().size() >= 4, "SpinBox: the toolbar shows for its LineEdit (got %s)" % str(_button_ids()))
	await _press_button(&"copy")
	_check(DisplayServer.clipboard_get() == "234", "SpinBox: Copy works (got '%s')" % DisplayServer.clipboard_get())


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
	_mouse_button(away, false)
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
	_check(DisplayServer.clipboard_get() == selected, "Copy puts the selection on the clipboard (got '%s')" % DisplayServer.clipboard_get())
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
	_check(DisplayServer.clipboard_get() == "works on its own", "and so does Copy (got '%s')" % DisplayServer.clipboard_get())

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