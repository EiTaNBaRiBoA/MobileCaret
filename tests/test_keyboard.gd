# Checks caret_keyboard_inset: the controls it is given end above the keyboard and inside the safe
# area, the field being typed in is scrolled into sight when the keyboard opens, and "is the keyboard
# open" follows the focus. A desktop has no keyboard, so the tests set simulate_keyboard_height.
# Run with:  godot --path <project> res://MobileCaret/tests/test_keyboard.tscn
extends Node

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	await _frames(2)
	await _test_nothing_on_desktop()
	await _test_lift()
	await _test_safe_area()
	await _test_default_target_and_signal()
	await _test_focus_into_view()
	await _test_keyboard_open()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


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


func _full_rect() -> Control:
	var c: Control = Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _test_nothing_on_desktop() -> void:
	var screens: Control = _full_rect()
	var inset: caret_keyboard_inset = caret_keyboard_inset.new()
	inset.targets = [screens]
	add_child(inset)
	await _frames(2)
	_check(is_zero_approx(screens.offset_bottom) and is_zero_approx(screens.offset_top) and is_zero_approx(inset.get_keyboard_height()), "on a desktop without a keyboard nothing moves")
	inset.queue_free()
	screens.queue_free()
	await _frames(1)


func _test_lift() -> void:
	var screens: Control = _full_rect()
	var overlay: Control = _full_rect()
	var inset: caret_keyboard_inset = caret_keyboard_inset.new()
	inset.targets = [screens, overlay]
	add_child(inset)
	inset.simulate_keyboard_height = 300.0
	await _frames(2)
	_check(is_equal_approx(screens.offset_bottom, -300.0) and is_equal_approx(overlay.offset_bottom, -300.0), "with the keyboard open every target ends above it (%.0f, %.0f)" % [screens.offset_bottom, overlay.offset_bottom])
	_check(is_equal_approx(screens.size.y, get_viewport().get_visible_rect().size.y - 300.0), "so the target is shorter by the keyboard's height (%.0f)" % screens.size.y)
	inset.simulate_keyboard_height = 0.0
	await _frames(2)
	_check(is_zero_approx(screens.offset_bottom) and is_zero_approx(inset.get_keyboard_height()), "closed, the target reaches the bottom again")
	inset.queue_free()
	screens.queue_free()
	overlay.queue_free()
	await _frames(1)


func _test_safe_area() -> void:
	var screens: Control = _full_rect()
	var inset: caret_keyboard_inset = caret_keyboard_inset.new()
	inset.targets = [screens]
	add_child(inset)
	inset.simulate_safe_area = Vector2(24.0, 48.0)
	await _frames(2)
	_check(is_equal_approx(screens.offset_top, 24.0) and is_equal_approx(screens.offset_bottom, -48.0), "the target keeps clear of the status bar and the navigation bar")
	_check(is_equal_approx(inset.get_uncovered_bar(), 48.0) and is_equal_approx(inset.get_bottom_lift(), 48.0), "the whole navigation bar shows while the keyboard is closed")
	inset.simulate_keyboard_height = 300.0
	await _frames(2)
	_check(is_equal_approx(screens.offset_bottom, -300.0) and is_zero_approx(inset.get_uncovered_bar()) and inset.get_safe_insets() == Vector2(24.0, 48.0), "the keyboard covers the navigation bar: the lift is the keyboard alone")
	inset.simulate_keyboard_height = -1.0
	inset.simulate_safe_area = Vector2(-1.0, -1.0)
	await _frames(2)
	_check(is_zero_approx(screens.offset_top) and is_zero_approx(screens.offset_bottom), "the simulation ends on a desktop: the target reaches the edges again")
	inset.queue_free()
	screens.queue_free()
	await _frames(1)


func _test_default_target_and_signal() -> void:
	var screens: Control = _full_rect()
	var inset: caret_keyboard_inset = caret_keyboard_inset.new()
	screens.add_child(inset)
	var seen: Array = []
	inset.insets_changed.connect(func(top: float, bottom: float, keyboard: float) -> void: seen.append([top, bottom, keyboard]))
	inset.simulate_keyboard_height = 250.0
	await _frames(2)
	_check(inset.targets == [screens] and is_equal_approx(screens.offset_bottom, -250.0), "with no targets it lifts its parent")
	_check(seen.size() == 1 and is_equal_approx(float(seen[0][2]), 250.0), "insets_changed is emitted once per change (%s)" % [seen])
	screens.queue_free()
	await _frames(1)


func _test_focus_into_view() -> void:
	var screens: Control = _full_rect()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	screens.add_child(scroll)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(10, get_viewport().get_visible_rect().size.y - 60.0)
	column.add_child(spacer)
	var field: LineEdit = LineEdit.new()
	column.add_child(field)
	var below: Control = Control.new()
	below.custom_minimum_size = Vector2(10, 400)
	column.add_child(below)
	var inset: caret_keyboard_inset = caret_keyboard_inset.new()
	inset.targets = [screens]
	inset.focus_delay = 0.0
	add_child(inset)
	await _frames(2)
	field.grab_focus()
	await _frames(2)
	_check(scroll.scroll_vertical == 0, "before the keyboard the field is in sight without scrolling")
	inset.simulate_keyboard_height = 300.0
	await get_tree().create_timer(0.1).timeout
	await _frames(2)
	var field_bottom: float = field.get_global_rect().end.y
	_check(scroll.scroll_vertical > 0 and field_bottom <= screens.get_global_rect().end.y + 0.5, "the keyboard opens: the field is scrolled into sight above it (scroll %d, field ends at %.0f, screen at %.0f)" % [scroll.scroll_vertical, field_bottom, screens.get_global_rect().end.y])
	inset.queue_free()
	screens.queue_free()
	await _frames(1)


func _test_keyboard_open() -> void:
	var screens: Control = _full_rect()
	var field: LineEdit = LineEdit.new()
	screens.add_child(field)
	var button: Button = Button.new()
	button.position = Vector2(0, 80)
	screens.add_child(button)
	var inset: caret_keyboard_inset = caret_keyboard_inset.new()
	inset.targets = [screens]
	inset.keep_focus_visible = false
	add_child(inset)
	field.grab_focus()
	inset.simulate_keyboard_height = 300.0
	await _frames(2)
	_check(inset.is_keyboard_open(), "typing in a field with the keyboard up: open")
	inset.simulate_keyboard_height = 0.0
	await _frames(2)
	_check(inset.is_keyboard_open(), "just closed (a back gesture closing it): still counts as open for a moment")
	inset.open_grace_ms = 0
	_check(not inset.is_keyboard_open(), "after the grace time: closed")
	inset.open_grace_ms = 400
	inset.simulate_keyboard_height = 300.0
	await _frames(2)
	button.grab_focus()
	_check(not inset.is_keyboard_open(), "the focus on a button: not typing, so not open")
	inset.queue_free()
	screens.queue_free()
	await _frames(1)
