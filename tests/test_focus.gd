# Checks release_focus_on_tap_outside: tapping outside the focused text control (background, a
# label, empty space) takes the focus away like Android, so the caret and selection go away; taps
# on buttons, the toolbar, other text controls and "keep focus" areas, and drags, do not.
# Run with:  godot --path <project> res://MobileCaret/tests/test_focus.tscn
extends Node

const CustomField = preload("custom_text_field.gd")

var _failures: int = 0
var _checks: int = 0
var _controller: carets_controller
var _toolbar: caret_toolbar
var _root: Control
var _background: ColorRect


func _ready() -> void:
	_controller = get_node("/root/MobileCaret") as carets_controller
	_toolbar = get_node("/root/MobileCaretToolbar") as caret_toolbar
	await _frames(2)

	await _test_background_and_empty_space()
	await _test_taps_that_keep_focus()
	await _test_drag_keeps_focus()
	await _test_other_controls()
	await _test_switch_off()

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

# A fresh scene: a full-screen background that stops the mouse (like a ColorRect behind a UI).
func _reset() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_background = ColorRect.new()
	_background.color = Color(0.12, 0.12, 0.15)
	_background.position = Vector2(0, 0)
	_background.size = Vector2(700, 520)
	_root.add_child(_background)
	_controller.release_focus_on_tap_outside = true
	await _frames(2)

func _to_window(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos

func _mouse_move(pos: Vector2, held: bool = false) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = _to_window(pos)
	ev.global_position = ev.position
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(ev)

func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = _to_window(pos)
	ev.global_position = ev.position
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)

func _tap(pos: Vector2) -> void:
	_mouse_move(pos)
	await _frames(1)
	_mouse_button(pos, true)
	await _frames(1)
	_mouse_button(pos, false)
	await _frames(3)

func _line_edit_with_selection() -> LineEdit:
	var edit: LineEdit = LineEdit.new()
	edit.text = "hello world"
	edit.position = Vector2(40, 60)
	edit.size = Vector2(400, 50)
	_root.add_child(edit)
	await _frames(2)
	edit.grab_focus()
	edit.select(0, 5)
	edit.caret_column = 5
	await _frames(4)
	return edit

func _handle(index: int) -> CanvasItem:
	return _controller.get_node("Handles").get_child(index) as CanvasItem

#endregion


func _test_background_and_empty_space() -> void:
	print("\n== Taps outside release the focus")
	await _reset()
	var edit: LineEdit = await _line_edit_with_selection()
	_check(edit.has_focus() and edit.has_selection() and _handle(0).visible, "start: focused, a selection, handles")
	await _tap(Vector2(300, 400))
	_check(not edit.has_focus(), "a tap on the background (a ColorRect that stops the mouse) releases the focus")
	_check(not edit.has_selection(), "the selection goes away with it")
	_check(not _handle(0).visible and not _handle(1).visible, "and the handles")
	edit.grab_focus()
	edit.caret_column = 2
	await _frames(3)
	await _tap(Vector2(900, 700))
	_check(not edit.has_focus(), "a tap on empty space (no control) releases it too")
	var label: Label = Label.new()
	label.text = "Just a label"
	label.position = Vector2(40, 200)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(label)
	edit.grab_focus()
	await _frames(3)
	await _tap(label.get_global_rect().get_center())
	_check(not edit.has_focus(), "a tap on a label releases it")
	edit.grab_focus()
	await _frames(3)
	await _tap(edit.get_global_rect().get_center())
	_check(edit.has_focus(), "a tap inside the field keeps it")

	var text_edit: TextEdit = TextEdit.new()
	text_edit.text = "line one\nline two"
	text_edit.position = Vector2(40, 260)
	text_edit.size = Vector2(400, 100)
	_root.add_child(text_edit)
	await _frames(2)
	text_edit.grab_focus()
	text_edit.select(0, 0, 0, 4)
	await _frames(3)
	await _tap(Vector2(600, 450))
	_check(not text_edit.has_focus() and not text_edit.has_selection(), "a TextEdit loses focus and selection the same way")

	var field: CustomField = CustomField.new()
	field.text = "custom"
	field.position = Vector2(40, 380)
	field.size = Vector2(300, 50)
	_root.add_child(field)
	await _frames(2)
	field.grab_focus()
	await _frames(3)
	await _tap(Vector2(600, 480))
	_check(not field.has_focus(), "a custom control (delegate) loses focus the same way")


func _test_taps_that_keep_focus() -> void:
	print("\n== Taps that keep the focus")
	await _reset()
	var edit: LineEdit = await _line_edit_with_selection()
	var key: Button = Button.new()
	key.text = "key"
	key.focus_mode = Control.FOCUS_NONE
	key.position = Vector2(40, 200)
	key.size = Vector2(80, 40)
	var presses: Array[int] = [0]
	key.pressed.connect(func() -> void: presses[0] += 1)
	_root.add_child(key)
	await _frames(2)
	await _tap(key.get_global_rect().get_center())
	_check(presses[0] == 1 and edit.has_focus() and edit.has_selection(), "a button that takes no focus (an on-screen key) keeps it")

	var keys: PanelContainer = PanelContainer.new()
	keys.position = Vector2(40, 280)
	keys.size = Vector2(300, 120)
	keys.set_meta(caret_controller_meta(), true)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(300, 120)
	gap.mouse_filter = Control.MOUSE_FILTER_STOP
	keys.add_child(gap)
	_root.add_child(keys)
	await _frames(2)
	await _tap(keys.get_global_rect().get_center())
	_check(edit.has_focus(), "a tap inside a control with the keep-focus meta (a key panel) keeps it")

	_toolbar.add_item(&"focus_test", "Test", 0)
	edit.select(0, 5)
	edit.caret_column = 5
	for i: int in 90:
		if _toolbar.is_showing():
			break
		await _frames(1)
	await _frames(2)
	var rect: Rect2 = _toolbar.get_button_rect(&"focus_test")
	_check(rect.size != Vector2.ZERO, "the toolbar shows")
	await _tap(rect.get_center())
	_check(edit.has_focus(), "a tap on the toolbar keeps it")
	_toolbar.remove_item(&"focus_test")


func _test_drag_keeps_focus() -> void:
	print("\n== A drag is not a tap")
	await _reset()
	var edit: LineEdit = await _line_edit_with_selection()
	var start: Vector2 = Vector2(300, 400)
	_mouse_move(start)
	await _frames(1)
	_mouse_button(start, true)
	await _frames(1)
	for i: int in range(1, 6):
		_mouse_move(start + Vector2(0, -20 * i), true)
		await _frames(1)
	_mouse_button(start + Vector2(0, -100), false)
	await _frames(3)
	_check(edit.has_focus(), "dragging over the background (scrolling) keeps the focus")


func _test_other_controls() -> void:
	print("\n== Tapping another field")
	await _reset()
	var edit: LineEdit = await _line_edit_with_selection()
	var other: LineEdit = LineEdit.new()
	other.position = Vector2(40, 200)
	other.size = Vector2(300, 40)
	_root.add_child(other)
	await _frames(2)
	await _tap(other.get_global_rect().get_center())
	_check(other.has_focus() and not edit.has_selection(), "the other field takes the focus and the first one's selection goes away")
	var focusable: Button = Button.new()
	focusable.text = "focusable"
	focusable.position = Vector2(40, 300)
	focusable.size = Vector2(120, 40)
	_root.add_child(focusable)
	await _frames(2)
	await _tap(focusable.get_global_rect().get_center())
	_check(focusable.has_focus() and not other.has_focus(), "a button that takes the focus gets it")


func _test_switch_off() -> void:
	print("\n== release_focus_on_tap_outside off")
	await _reset()
	_controller.release_focus_on_tap_outside = false
	var edit: LineEdit = await _line_edit_with_selection()
	await _tap(Vector2(300, 400))
	_check(edit.has_focus() and edit.has_selection(), "with the setting off, Godot's behaviour stays: the focus is kept")
	_controller.release_focus_on_tap_outside = true


func caret_controller_meta() -> StringName:
	return carets_controller.KEEP_FOCUS_META
