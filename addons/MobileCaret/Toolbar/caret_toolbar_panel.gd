# The visual part of the floating toolbar: a rounded bar of text buttons.
# It only draws and lays out; clicks are hit-tested by the toolbar (see caret_toolbar), because a
# GUI press on a non-text control would make the text control lose focus and its selection.
class_name caret_toolbar_panel extends Control

# Entries: { "id": StringName, "text": String, "rect": Rect2 } with rects in this control's space.
var items: Array[Dictionary] = []
# Index of the item currently held down, or -1.
var pressed_index: int = -1:
	set(value):
		if pressed_index != value:
			pressed_index = value
			queue_redraw()

var background_color: Color = Color(0.13, 0.14, 0.17, 0.97):
	set(value):
		if background_color != value:
			background_color = value
			queue_redraw()
var text_color: Color = Color(1.0, 1.0, 1.0):
	set(value):
		if text_color != value:
			text_color = value
			queue_redraw()
var pressed_color: Color = Color(1.0, 1.0, 1.0, 0.18):
	set(value):
		if pressed_color != value:
			pressed_color = value
			queue_redraw()
var separator_color: Color = Color(1.0, 1.0, 1.0, 0.18)
# Height of the bar and font size, in logical pixels.
var bar_height: float = 40.0
var font_size: int = 16


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


# Replaces the buttons and lays them out left to right.
func set_items(entries: Array[Dictionary]) -> void:
	items = entries
	pressed_index = -1
	relayout()

func relayout() -> void:
	var font: Font = get_theme_default_font()
	var x: float = 0.0
	for item: Dictionary in items:
		var text_width: float = font.get_string_size(item["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var width: float = text_width + bar_height * 0.9
		item["rect"] = Rect2(x, 0.0, width, bar_height)
		x += width
	# The minimum size goes first: a Control's size can't be set below its current minimum.
	custom_minimum_size = Vector2(x, bar_height)
	size = Vector2(x, bar_height)
	queue_redraw()

# Index of the item at a point in this control's space, or -1.
func item_at(local_point: Vector2) -> int:
	for i: int in items.size():
		if (items[i]["rect"] as Rect2).has_point(local_point):
			return i
	return -1


func _draw() -> void:
	if items.is_empty():
		return
	var radius: int = int(bar_height * 0.32)
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = background_color
	background.set_corner_radius_all(radius)
	background.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
	background.shadow_size = int(bar_height * 0.12)
	draw_style_box(background, Rect2(Vector2.ZERO, size))

	var font: Font = get_theme_default_font()
	for i: int in items.size():
		var rect: Rect2 = items[i]["rect"]
		if i == pressed_index:
			var highlight: StyleBoxFlat = StyleBoxFlat.new()
			highlight.bg_color = pressed_color
			highlight.set_corner_radius_all(radius)
			draw_style_box(highlight, rect.grow(-1.0))
		elif i > 0:
			draw_line(Vector2(rect.position.x, rect.size.y * 0.25), Vector2(rect.position.x, rect.size.y * 0.75), separator_color, 1.0)
		var text: String = items[i]["text"]
		var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline: float = rect.position.y + (rect.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		draw_string(font, Vector2(rect.position.x + (rect.size.x - text_size.x) * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
