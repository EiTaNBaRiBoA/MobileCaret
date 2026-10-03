# A single touch-friendly caret handle (a teardrop, or a custom texture).
# It is purely visual: the carets controller hit-tests it in `_input` and swallows the press,
# so the text control never loses focus. The handle's tip (top-center) is the point that
# sits at the text position.
class_name caret_indicator extends Control

enum Style {
	CARET, # Single caret, no selection.
	LEFT, # Handle at the start of a selection.
	RIGHT, # Handle at the end of a selection.
}

var style: Style = Style.CARET:
	set(value):
		if style != value:
			style = value
			queue_redraw()

# Optional custom texture. When null a default teardrop is drawn.
var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()

var handle_color: Color = Color(0.2, 0.5, 1.0):
	set(value):
		handle_color = value
		queue_redraw()


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


# Sizes the handle; the tip stays at the top-center.
func set_handle_size(handle_size: Vector2) -> void:
	size = handle_size
	custom_minimum_size = handle_size
	queue_redraw()

# Moves the handle so its tip is at `tip` (viewport space).
func set_tip(tip: Vector2) -> void:
	global_position = tip - Vector2(size.x * 0.5, 0.0)

func get_tip() -> Vector2:
	return global_position + Vector2(size.x * 0.5, 0.0)

# Whether a viewport-space point hits the handle, with `margin` extra pixels around it.
func hits(point: Vector2, margin: float) -> bool:
	# A (nearly) faded-out handle can no longer be grabbed.
	return visible and modulate.a > 0.1 and Rect2(global_position, size).grow(margin).has_point(point)


func _draw() -> void:
	if texture != null:
		if style == Style.LEFT:
			# Mirror horizontally.
			draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
		return
	var radius: float = size.x * 0.5 - 1.0
	var side: float = -1.0 if style == Style.LEFT else (1.0 if style == Style.RIGHT else 0.0)
	var center: Vector2 = Vector2(size.x * 0.5 + side * radius * 0.6, size.y - radius - 1.0)
	var tip: Vector2 = Vector2(size.x * 0.5, 0.0)
	draw_colored_polygon(PackedVector2Array([
		tip,
		center + Vector2(-radius * 0.9, -radius * 0.45),
		center + Vector2(radius * 0.9, -radius * 0.45),
	]), handle_color)
	draw_circle(center, radius, handle_color)
