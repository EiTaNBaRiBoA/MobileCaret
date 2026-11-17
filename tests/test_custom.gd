# Checks that custom controls get caret handles and the toolbar: through a delegate (no dependency
# on MobileCaret, see custom_text_field.gd) and through register_adapter().
# Run with:  godot --path <project> res://MobileCaret/tests/test_custom.tscn
extends Node

const CustomField = preload("custom_text_field.gd")

var _failures: int = 0
var _checks: int = 0
var _controller: carets_controller
var _toolbar: caret_toolbar
var _root: Control
var _saved_clipboard: String = ""


# An adapter for a control that cannot be changed (here a plain ColorRect), registered from code.
class PanelAdapter extends caret_text_adapter:
	var caret: int = 0

	func get_caret(_caret_index: int = 0) -> Vector2i:
		return Vector2i(caret, 0)

	func set_caret(pos: Vector2i, _caret_index: int = 0) -> void:
		caret = pos.x

	func get_tip_local(pos: Vector2i) -> Vector2:
		return Vector2(10.0 + pos.x * 20.0, 40.0)

	func is_pos_visible(_pos: Vector2i) -> bool:
		return true

	func get_line_height() -> float:
		return 30.0

	func get_pos_at_local(local: Vector2) -> Vector2i:
		return Vector2i(clampi(roundi((local.x - 10.0) / 20.0), 0, 10), 0)


# A control whose second row is drawn below its own rectangle (as a selection that continues into
# the next paragraph of a page). With `tall` the delegate says so through get_drag_rect().
class TallBox extends Control:
	var tall: bool = true
	var _delegate: TallDelegate = null

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		_delegate = TallDelegate.new(self)

	func _get_caret_delegate() -> Object:
		return _delegate

	# Where row 1 is drawn: this far below the control's bottom.
	func row_y(line: int) -> float:
		return 40.0 + line * (size.y + 100.0)


class TallDelegate extends RefCounted:
	var box: TallBox
	var caret: Vector2i = Vector2i(2, 0)

	func _init(owner_box: TallBox) -> void:
		box = owner_box

	func get_caret() -> Vector2i:
		return caret

	func set_caret(pos: Vector2i) -> void:
		caret = pos

	func get_tip_local(pos: Vector2i) -> Vector2:
		return Vector2(10.0 + pos.x * 20.0, box.row_y(pos.y))

	func is_pos_visible(_pos: Vector2i) -> bool:
		return true

	func get_line_height() -> float:
		return 30.0

	func get_pos_at_local(local: Vector2) -> Vector2i:
		var line: int = 1 if local.y > box.size.y + 30.0 else 0
		return Vector2i(clampi(roundi((local.x - 10.0) / 20.0), 0, 10), line)

	func get_drag_rect() -> Rect2:
		if box.tall:
			return Rect2(0.0, 0.0, box.size.x, box.row_y(1) + 20.0)
		return Rect2(Vector2.ZERO, box.size)

	# The row below is drawn by another control, which no parent of the box clips.
	func is_pos_clipped(pos: Vector2i) -> bool:
		return not box.tall and pos.y > 0


func _ready() -> void:
	_controller = get_node("/root/MobileCaret") as carets_controller
	_toolbar = get_node("/root/MobileCaretToolbar") as caret_toolbar
	_saved_clipboard = DisplayServer.clipboard_get()
	await _frames(2)

	await _test_lookup()
	await _test_handles()
	await _test_toolbar()
	await _test_long_press_and_native_caret()
	await _test_read_only_and_toolbar_only()
	await _test_registered_factory()
	await _test_toolbar_items()
	await _test_control_items_and_submenus()
	await _test_nested_submenus()
	await _test_drag_rect()

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

func _field(text: String) -> CustomField:
	var field: CustomField = CustomField.new()
	field.text = text
	field.position = Vector2(40.0, 300.0)
	field.size = Vector2(560.0, 60.0)
	_root.add_child(field)
	return field

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
	await _frames(2)

func _handle(index: int) -> caret_indicator:
	return _controller.get_node("Handles").get_child(index) as caret_indicator

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

func _wait_toolbar(showing: bool) -> void:
	for i: int in 90:
		if _toolbar.is_showing() == showing:
			break
		await _frames(1)
	await _frames(2)

func _button_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for action: StringName in [&"back", &"cut", &"copy", &"paste", &"select_all", &"undo", &"redo", &"share", &"more"]:
		if _toolbar.get_button_rect(action).size != Vector2.ZERO:
			ids.append(action)
	return ids

func _press_button(action: StringName) -> void:
	await _click(_toolbar.get_button_rect(action).get_center())

func _tip_of(field: CustomField, column: int) -> Vector2:
	return field.get_global_transform_with_canvas() * Vector2(field.x_of(column), field.size.y * 0.5 + field.get_theme_default_font().get_height(field.font_size) * 0.5)

#endregion


func _test_lookup() -> void:
	print("\n== Which controls get an adapter")
	await _reset()
	var field: CustomField = _field("hello")
	var plain: Control = Control.new()
	_root.add_child(plain)
	var adapter: caret_text_adapter = caret_text_adapter.for_control(field)
	_check(adapter is caret_delegate_adapter, "a control with _get_caret_delegate() gets a delegate adapter")
	_check(caret_text_adapter.for_control(plain) == null and caret_text_adapter.for_toolbar(plain) == null, "a plain Control still gets none")
	var delegate_adapter: caret_delegate_adapter = adapter
	_check(delegate_adapter.has(&"get_caret") and not delegate_adapter.has(&"copy"), "the adapter knows which methods the delegate has")
	field.caret = 3
	_check(adapter.get_caret(0) == Vector2i(3, 0), "methods without caret_index are called with fewer arguments")
	_check(adapter.is_pos_visible(Vector2i(0, 0)), "default is_pos_visible: the caret inside the control is visible")
	field.size.x = 10.0
	_check(not adapter.is_pos_visible(Vector2i(5, 0)), "default is_pos_visible: a caret past the control's edge is not")
	field.size.x = 560.0
	var line_edit: LineEdit = LineEdit.new()
	_root.add_child(line_edit)
	_check(caret_text_adapter.for_control(line_edit) is caret_line_edit_adapter, "LineEdit still gets the built-in adapter")


func _test_handles() -> void:
	print("\n== Handles on a custom control")
	await _reset()
	var field: CustomField = _field("one two three")
	await _frames(2)
	field.grab_focus()
	field.caret = 4
	await _frames(4)
	_check(_handle(0).visible and not _handle(1).visible, "the caret handle shows for the custom control")
	_check(_handle(0).get_tip().distance_to(_tip_of(field, 4)) < 1.5, "the handle sits at the caret the delegate reports")
	await _drag_handle_to(_handle(0), _tip_of(field, 8))
	_check(field.caret == 8, "dragging the handle moves the caret through set_caret (caret %d)" % field.caret)
	field.anchor = 0
	field.caret = 3
	await _frames(4)
	_check(_handle(0).visible and _handle(1).visible, "a selection gets two handles")
	await _drag_handle_to(_handle(1), _tip_of(field, 7))
	_check(field.anchor == 0 and field.caret == 7, "dragging the end handle changes the selection through select (anchor %d caret %d)" % [field.anchor, field.caret])
	field.release_focus()
	await _frames(3)
	_check(not _handle(0).visible and not _handle(1).visible, "the handles go away with the focus")


func _test_toolbar() -> void:
	print("\n== Toolbar actions on a custom control")
	await _reset()
	var field: CustomField = _field("alpha beta gamma")
	await _frames(2)
	field.grab_focus()
	await _frames(3)
	field.anchor = 6
	field.caret = 10
	await _wait_toolbar(true)
	_check(_toolbar.is_showing(), "the toolbar shows for the custom control's selection")
	_check(str(_button_ids()) == str([&"cut", &"copy", &"paste", &"select_all"]), "Cut, Copy, Paste and Select all; no overflow without undo (got %s)" % str(_button_ids()))
	await _press_button(&"copy")
	_check(DisplayServer.clipboard_get() == "beta", "Copy without a copy() method uses get_selected_text (got '%s')" % DisplayServer.clipboard_get())
	_check(field.has_focus(), "the custom control keeps focus")
	field.anchor = 0
	field.caret = 6
	await _wait_toolbar(true)
	await _press_button(&"cut")
	_check(field.text == "beta gamma" and DisplayServer.clipboard_get() == "alpha ", "Cut calls the delegate (text '%s')" % field.text)
	field.caret = field.text.length()
	DisplayServer.clipboard_set("!")
	await _frames(3)
	_toolbar.show_for_caret()
	await _wait_toolbar(true)
	_check(&"paste" in _button_ids() and &"more" in _button_ids(), "the caret toolbar offers Paste, and the overflow menu now that has_undo() is true (got %s)" % str(_button_ids()))
	await _press_button(&"paste")
	_check(field.text == "beta gamma!", "Paste calls the delegate (text '%s')" % field.text)
	field.caret = 2
	await _frames(3)
	_toolbar.show_for_caret()
	await _wait_toolbar(true)
	await _press_button(&"select_all")
	_check(field.anchor == 0 and field.caret == field.text.length(), "Select all calls the delegate")
	await _wait_toolbar(true)
	_check(not (&"select_all" in _button_ids()), "Select all is hidden when is_everything_selected() is true (got %s)" % str(_button_ids()))
	await _press_button(&"more")
	await _frames(3)
	_check(&"undo" in _button_ids() and not (&"redo" in _button_ids()), "the overflow menu offers Undo but not Redo (the delegate has no redo) (got %s)" % str(_button_ids()))
	await _press_button(&"undo")
	_check(field.text == "beta gamma", "Undo calls the delegate (text '%s')" % field.text)


func _test_long_press_and_native_caret() -> void:
	print("\n== Long press and the native caret")
	await _reset()
	var field: CustomField = _field("first second")
	await _frames(2)
	field.grab_focus()
	await _frames(3)
	var point: Vector2 = field.get_global_transform_with_canvas() * Vector2(field.x_of(9), field.size.y * 0.5)
	_mouse_move(point)
	_mouse_button(point, true)
	for i: int in 45:
		await _frames(1)
	_mouse_button(point, false)
	await _frames(3)
	_check(field.calls.has("select_word_at") and field.anchor == 6 and field.caret == 12, "a long press calls select_word_at (anchor %d caret %d)" % [field.anchor, field.caret])
	field.anchor = -1
	_controller.hide_native_caret = true
	field.caret = 2
	await _frames(4)
	_check(field.native_caret_hidden, "hide_native_caret is forwarded to the delegate")
	field.release_focus()
	await _frames(3)
	_check(not field.native_caret_hidden, "the native caret comes back when focus leaves")
	_controller.hide_native_caret = false


func _test_read_only_and_toolbar_only() -> void:
	print("\n== Read-only and toolbar-only custom controls")
	await _reset()
	var field: CustomField = _field("read only text")
	field.editable = false
	await _frames(2)
	field.grab_focus()
	await _frames(3)
	field.anchor = 0
	field.caret = 4
	await _wait_toolbar(true)
	_check(str(_button_ids()) == str([&"copy", &"select_all"]), "a read-only control offers Copy and Select all only (got %s)" % str(_button_ids()))
	field.release_focus()
	await _frames(3)

	var label: CustomField = _field("label text")
	label.toolbar_only = true
	await _frames(2)
	_check(caret_text_adapter.for_control(label) == null and caret_text_adapter.for_toolbar(label) != null, "supports_handles() false: no handle adapter, but a toolbar adapter")
	label.grab_focus()
	await _frames(3)
	label.anchor = 0
	label.caret = 5
	await _wait_toolbar(true)
	_check(_toolbar.is_showing() and not _handle(0).visible and not _handle(1).visible, "a toolbar-only control gets the toolbar and no handles")


func _test_registered_factory() -> void:
	print("\n== register_adapter()")
	await _reset()
	var rect: ColorRect = ColorRect.new()
	rect.color = Color(0.2, 0.2, 0.25)
	rect.position = Vector2(40.0, 300.0)
	rect.size = Vector2(400.0, 60.0)
	rect.focus_mode = Control.FOCUS_ALL
	_root.add_child(rect)
	var factory: Callable = func(control: Control) -> caret_text_adapter:
		return PanelAdapter.new(control) if control is ColorRect else null
	_check(caret_text_adapter.for_control(rect) == null, "before registering, a ColorRect gets no adapter")
	caret_text_adapter.register_adapter(factory)
	caret_text_adapter.register_adapter(factory)
	_check(caret_text_adapter.for_control(rect) is PanelAdapter, "a registered factory provides the adapter")
	_check(caret_text_adapter._factories.size() == 1, "registering the same factory twice keeps one")
	rect.grab_focus()
	await _frames(4)
	_check(_handle(0).visible and _handle(0).get_tip().distance_to(rect.get_global_transform_with_canvas() * Vector2(10.0, 40.0)) < 1.5, "the registered adapter's handle shows at its caret")

	var edit: LineEdit = LineEdit.new()
	_root.add_child(edit)
	var override: Callable = func(control: Control) -> caret_text_adapter:
		return PanelAdapter.new(control) if control is LineEdit else null
	caret_text_adapter.register_adapter(override)
	_check(caret_text_adapter.for_control(edit) is PanelAdapter, "a factory can replace the built-in adapter of a LineEdit")
	caret_text_adapter.unregister_adapter(override)
	caret_text_adapter.unregister_adapter(factory)
	_check(caret_text_adapter.for_control(edit) is caret_line_edit_adapter and caret_text_adapter.for_control(rect) == null, "after unregistering the built-in adapters are back")
	rect.release_focus()
	await _frames(2)


# Every button id on the toolbar right now, left to right.
func _row() -> Array[StringName]:
	var ids: Array[StringName] = []
	var panel: caret_toolbar_panel = _toolbar.get("_panel") as caret_toolbar_panel
	if panel == null or not panel.visible:
		return ids
	for item: Dictionary in panel.items:
		ids.append(item["id"] as StringName)
	return ids

func _line_edit_with_selection() -> LineEdit:
	var edit: LineEdit = LineEdit.new()
	edit.text = "hello world"
	edit.position = Vector2(40.0, 300.0)
	edit.size = Vector2(500.0, 50.0)
	_root.add_child(edit)
	await _frames(2)
	edit.grab_focus()
	await _frames(2)
	edit.select(0, 5)
	edit.caret_column = 5
	await _wait_toolbar(true)
	return edit

func _test_toolbar_items() -> void:
	print("\n== Custom toolbar items (add_item)")
	await _reset()
	var pressed: Array = []
	var callback: Callable = func(control: Control) -> void: pressed.append(control)
	_toolbar.add_item(&"first", "First", 0, callback)
	_toolbar.add_item(&"third", "Third", 2)
	_toolbar.add_item(&"last", "Last", -1)
	_toolbar.add_item(&"only_selection", "Sel", 1, Callable(), [], "selection")
	var edit: LineEdit = await _line_edit_with_selection()
	_check(str(_row()) == str([&"first", &"only_selection", &"third", &"cut", &"copy", &"paste", &"select_all", &"last", &"more"]), "items go to their index (0 = leftmost), -1 goes last before ··· (got %s)" % str(_row()))
	var signals: Array = []
	var on_item: Callable = func(id: StringName, control: Control) -> void: signals.append([id, control])
	_toolbar.item_pressed.connect(on_item)
	await _press_button(&"first")
	_check(pressed.size() == 1 and pressed[0] == edit, "the callback gets the focused control")
	_check(signals.size() == 1 and signals[0][0] == &"first" and signals[0][1] == edit, "item_pressed is emitted with the id and the control")
	_check(edit.has_focus() and edit.has_selection(), "pressing a custom item keeps focus and the selection")
	_toolbar.item_pressed.disconnect(on_item)
	edit.deselect()
	edit.caret_column = 2
	await _frames(3)
	_toolbar.show_for_caret()
	await _wait_toolbar(true)
	_check(not (&"only_selection" in _row()) and &"first" in _row(), "a \"selection\" item is hidden at a bare caret (got %s)" % str(_row()))
	_toolbar.add_item(&"first", "Renamed", 3)
	await _frames(3)
	_check(_row().count(&"first") == 1 and _row().find(&"first") == 3, "adding an id again replaces the item (got %s)" % str(_row()))
	_toolbar.remove_item(&"first")
	await _frames(3)
	_check(not (&"first" in _row()), "remove_item removes it")
	_check(_toolbar.get_items().size() == 3, "get_items lists the rest")
	_toolbar.clear_items()
	await _frames(3)
	_check(str(_row()) == str([&"paste", &"select_all", &"more"]), "clear_items leaves the built-in buttons (got %s)" % str(_row()))
	edit.release_focus()
	await _frames(2)


func _test_nested_submenus() -> void:
	print("\n== Submenus inside submenus")
	await _reset()
	var field: CustomField = _field("alpha beta")
	field.toolbar_items = [
		{"id": &"insert", "text": "Insert", "index": 0, "items": [
			{"id": &"insert_frac", "text": "a/b"},
			{"id": &"symbols", "text": "Symbols", "items": [
				{"id": &"group_arrows", "text": "→", "items": [
					{"id": &"sym_to", "text": "→"},
					{"id": &"sym_implies", "text": "⇒"},
				]},
				{"id": &"group_sets", "text": "∈", "items": [
					{"id": &"sym_in", "text": "∈"},
				]},
			]},
		]},
	]
	await _frames(2)
	field.grab_focus()
	await _frames(3)
	field.anchor = 0
	field.caret = 5
	await _wait_toolbar(true)
	await _press_button(&"insert")
	await _frames(3)
	await _press_button(&"symbols")
	await _frames(3)
	_check(str(_row()) == str([&"back", &"group_arrows", &"group_sets"]), "a submenu item with children opens the next level (got %s)" % str(_row()))
	await _press_button(&"group_arrows")
	await _frames(3)
	_check(str(_row()) == str([&"back", &"sym_to", &"sym_implies"]) and _toolbar.get_open_submenus() == [&"insert", &"symbols", &"group_arrows"], "three levels deep, get_open_submenus lists the path (%s)" % str(_toolbar.get_open_submenus()))
	await _press_button(&"back")
	await _frames(3)
	_check(str(_row()) == str([&"back", &"group_arrows", &"group_sets"]), "‹ goes back one level, to Symbols (got %s)" % str(_row()))
	await _press_button(&"back")
	await _frames(3)
	_check(_row().size() == 3 and _row()[1] == &"insert_frac", "‹ again goes to Insert (got %s)" % str(_row()))
	await _press_button(&"back")
	await _frames(3)
	_check(_row().size() > 0 and _row()[0] == &"insert" and &"copy" in _row(), "and once more to the main row (got %s)" % str(_row()))
	await _press_button(&"insert")
	await _frames(3)
	await _press_button(&"symbols")
	await _frames(3)
	await _press_button(&"group_sets")
	await _frames(3)
	await _press_button(&"sym_in")
	_check(field.pressed_items.has(&"sym_in") and _toolbar.get_open_submenus().is_empty(), "pressing a deep item reaches the control and closes all submenus")
	_toolbar.open_submenu(&"insert")
	_toolbar.open_submenu(&"symbols")
	_toolbar.open_submenu(&"")
	_check(_toolbar.get_open_submenus().is_empty(), "open_submenu(&\"\") closes every level")
	field.release_focus()
	await _frames(2)


func _test_control_items_and_submenus() -> void:
	print("\n== A control's own items and submenus")
	await _reset()
	var field: CustomField = _field("alpha beta")
	var picked: Array = []
	field.toolbar_items = [
		{"id": &"insert", "text": "Insert", "index": 0, "items": [
			{"id": &"insert_frac", "text": "a/b"},
			{"id": &"insert_root", "text": "√", "callback": func(control: Control) -> void: picked.append(control)},
		]},
	]
	await _frames(2)
	field.grab_focus()
	await _frames(3)
	field.anchor = 0
	field.caret = 5
	await _wait_toolbar(true)
	_check(_row().size() > 0 and _row()[0] == &"insert", "the control's item is first (got %s)" % str(_row()))
	await _press_button(&"insert")
	await _frames(3)
	_check(str(_row()) == str([&"back", &"insert_frac", &"insert_root"]), "an item with children opens them as a submenu with ‹ (got %s)" % str(_row()))
	_check(field.pressed_items.is_empty(), "opening a submenu is not a press")
	await _press_button(&"back")
	await _frames(3)
	_check(_row().size() > 0 and _row()[0] == &"insert" and &"copy" in _row(), "‹ goes back to the main row (got %s)" % str(_row()))
	await _press_button(&"insert")
	await _frames(3)
	await _press_button(&"insert_root")
	_check(picked.size() == 1 and picked[0] == field, "a child's callback runs with the control")
	_check(field.pressed_items == [&"insert_root"], "and the control hears toolbar_item_pressed (got %s)" % str(field.pressed_items))
	field.anchor = 0
	field.caret = 4
	await _wait_toolbar(true)
	_check(_row().size() > 0 and _row()[0] == &"insert", "after a press the submenu is closed again (got %s)" % str(_row()))
	var image: Image = Image.create(8, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	field.toolbar_items = [{"id": &"icon_only", "text": "", "index": 0, "icon": ImageTexture.create_from_image(image)}]
	field.anchor = 1
	field.caret = 4
	await _wait_toolbar(false)
	await _wait_toolbar(true)
	var icon_rect: Rect2 = _toolbar.get_button_rect(&"icon_only")
	_check(icon_rect.size.x > 10.0, "an icon-only item gets room for its icon (width %.1f)" % icon_rect.size.x)
	field.release_focus()
	await _frames(2)


# A dragged handle stays inside the control, or inside the area the delegate's get_drag_rect()
# gives: there it can follow the caret to a row drawn below the control.
func _test_drag_rect() -> void:
	print("\n== A delegate's drag area (get_drag_rect)")
	await _reset()
	for tall: bool in [true, false]:
		var box: TallBox = TallBox.new()
		box.tall = tall
		# inside a parent that clips it (as a RichTextLabel clips what is laid over it)
		var clip: Control = Control.new()
		clip.clip_contents = true
		clip.position = Vector2(40.0, 200.0)
		clip.size = Vector2(300.0, 80.0)
		_root.add_child(clip)
		box.size = Vector2(300.0, 80.0)
		clip.add_child(box)
		await _frames(2)
		box.grab_focus()
		await _frames(4)
		var handle: caret_indicator = _handle(0)
		_check(handle.visible, "the caret handle shows (tall %s)" % tall)
		var start_pointer: Vector2 = handle.global_position + handle.size * 0.5
		var row_one: Vector2 = box.get_global_transform_with_canvas() * box._delegate.get_tip_local(Vector2i(2, 1))
		var delta: Vector2 = row_one - handle.get_tip()
		_mouse_move(start_pointer)
		_mouse_button(start_pointer, true)
		await _frames(1)
		for i: int in range(1, 7):
			_mouse_move(start_pointer + delta * (float(i) / 6.0))
			await _frames(1)
		await _frames(3)
		var tip_y: float = handle.get_tip().y
		var bottom: float = box.get_global_rect().end.y
		if tall:
			_check(box._delegate.caret.y == 1 and absf(tip_y - row_one.y) < 1.5, "with get_drag_rect the dragged handle reaches the row below the control (%.0f, row at %.0f)" % [tip_y, row_one.y])
		else:
			_check(tip_y <= bottom + 0.5, "without it the dragged handle stays inside the control (%.0f, bottom %.0f)" % [tip_y, bottom])
		_mouse_button(start_pointer + delta, false)
		await _frames(2)
		if tall:
			# a clipping parent would hide it there; the delegate's is_pos_clipped() says it is seen
			_check(handle.visible and absf(handle.get_tip().y - row_one.y) < 1.5, "after the drag the handle stays on the row below, though a parent clips the control (visible %s)" % handle.visible)
		box.release_focus()
		box.get_parent().queue_free()
		await _frames(2)
