# A small custom single-line text control (it does not extend LineEdit or TextEdit) used by
# test_custom.gd. It knows nothing about MobileCaret: it only implements `_get_caret_delegate()`
# and returns a helper object with some of caret_text_adapter's methods. Its methods leave out the
# `caret_index` parameter (it has a single caret), which the delegate adapter allows.
extends Control

const Field = preload("custom_text_field.gd")

var text: String = ""
var caret: int = 0
# Selection anchor, or -1 for no selection.
var anchor: int = -1
var editable: bool = true
var undo_stack: Array[String] = []
var font_size: int = 24
# Calls the delegate received, by name (the tests read it).
var calls: Dictionary = {}
# When true, the delegate says the control is toolbar-only (no handles).
var toolbar_only: bool = false
var native_caret_hidden: bool = false
# Toolbar items this control adds (see get_toolbar_items), and the ids pressed.
var toolbar_items: Array = []
var pressed_items: Array[StringName] = []
# The end that stays put, as each step of a selection handle drag gave it (get_selection_drag_target).
var drag_anchors: Array[int] = []


class Delegate extends RefCounted:
	var field: Field

	func _init(owner_field: Field) -> void:
		field = owner_field

	func _note(method: String) -> void:
		field.calls[method] = int(field.calls.get(method, 0)) + 1

	func supports_handles() -> bool:
		return not field.toolbar_only

	func is_text_editable() -> bool:
		return field.editable

	func is_empty() -> bool:
		return field.text.is_empty()

	func get_caret() -> Vector2i:
		return Vector2i(field.caret, 0)

	func set_caret(pos: Vector2i) -> void:
		_note("set_caret")
		field.caret = clampi(pos.x, 0, field.text.length())
		field.anchor = -1
		field.queue_redraw()

	func has_selection() -> bool:
		return field.anchor >= 0 and field.anchor != field.caret

	func get_selection_from() -> Vector2i:
		return Vector2i(mini(field.anchor, field.caret) if has_selection() else field.caret, 0)

	func get_selection_to() -> Vector2i:
		return Vector2i(maxi(field.anchor, field.caret) if has_selection() else field.caret, 0)

	func select(from: Vector2i, to: Vector2i) -> void:
		_note("select")
		field.anchor = from.x
		field.caret = to.x
		field.queue_redraw()

	func deselect() -> void:
		field.anchor = -1

	func select_word_at(pos: Vector2i) -> void:
		_note("select_word_at")
		var from: int = pos.x
		var to: int = pos.x
		while from > 0 and field.text[from - 1] != " ":
			from -= 1
		while to < field.text.length() and field.text[to] != " ":
			to += 1
		select(Vector2i(from, 0), Vector2i(to, 0))

	func get_line_height() -> float:
		return field.get_theme_default_font().get_height(field.font_size)

	func get_tip_local(pos: Vector2i) -> Vector2:
		return Vector2(field.x_of(pos.x), field.size.y * 0.5 + get_line_height() * 0.5)

	func get_pos_at_local(local: Vector2) -> Vector2i:
		var best: int = 0
		for i: int in field.text.length() + 1:
			if absf(field.x_of(i) - local.x) < absf(field.x_of(best) - local.x):
				best = i
		return Vector2i(best, 0)

	func get_selection_drag_target(local: Vector2, anchor_pos: Vector2i, _current: Vector2i, _delta: float) -> Vector2i:
		field.drag_anchors.append(anchor_pos.x)
		return get_pos_at_local(local)

	func get_text_version() -> int:
		return field.text.hash()

	func get_selected_text() -> String:
		return field.text.substr(get_selection_from().x, get_selection_to().x - get_selection_from().x)

	func is_everything_selected() -> bool:
		return has_selection() and get_selection_from().x == 0 and get_selection_to().x == field.text.length()

	# No copy(): the adapter's default puts get_selected_text() on the clipboard.

	func cut() -> void:
		_note("cut")
		DisplayServer.clipboard_set(get_selected_text())
		field.replace_selection("")

	func paste() -> void:
		_note("paste")
		field.replace_selection(DisplayServer.clipboard_get())

	func select_all() -> void:
		select(Vector2i.ZERO, Vector2i(field.text.length(), 0))

	func has_undo() -> bool:
		return not field.undo_stack.is_empty()

	func undo() -> void:
		field.text = field.undo_stack.pop_back()
		field.caret = field.text.length()
		field.anchor = -1

	func hide_native_caret(hidden: bool) -> void:
		field.native_caret_hidden = hidden

	func get_toolbar_items() -> Array:
		return field.toolbar_items

	func toolbar_item_pressed(id: StringName) -> void:
		field.pressed_items.append(id)


var _delegate: Delegate = null


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_delegate = Delegate.new(self)

func _get_caret_delegate() -> Object:
	return _delegate

func x_of(column: int) -> float:
	return 8.0 + get_theme_default_font().get_string_size(text.substr(0, column), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

func replace_selection(with: String) -> void:
	undo_stack.append(text)
	var from: int = _delegate.get_selection_from().x
	var to: int = _delegate.get_selection_to().x
	text = text.substr(0, from) + with + text.substr(to)
	caret = from + with.length()
	anchor = -1
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		grab_focus()
		caret = _delegate.get_pos_at_local((event as InputEventMouseButton).position).x
		anchor = -1
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.15, 0.18))
	var font: Font = get_theme_default_font()
	var baseline: float = size.y * 0.5 + font.get_ascent(font_size) * 0.5
	if _delegate.has_selection():
		var from: float = x_of(_delegate.get_selection_from().x)
		var to: float = x_of(_delegate.get_selection_to().x)
		draw_rect(Rect2(from, 4.0, to - from, size.y - 8.0), Color(0.3, 0.5, 1.0, 0.4))
	draw_string(font, Vector2(8.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	if has_focus() and not native_caret_hidden:
		draw_line(Vector2(x_of(caret), 6.0), Vector2(x_of(caret), size.y - 6.0), Color.WHITE, 2.0)
