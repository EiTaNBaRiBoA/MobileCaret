# A base class providing shared properties and helper functions for a custom caret system.
# It is designed to be extended by a more specific controller implementation.
# Defines the core data structures and utility functions for interacting with text controls.
class_name base_carets_controller
extends Control

# The texture for the caret handles, set from the Godot Editor Inspector.
@export var texture_caret: Texture2D

# Reference to the first caret handle, set from the Inspector.
@export var caret_one: caret_indicator
# Reference to the second caret handle, set from the Inspector.
@export var caret_two: caret_indicator

# The currently selected/dragged caret handle.
var current_selected_caret: caret_indicator = null
# A flag to track if a drag operation is in progress.
var _is_caret_drag: bool = false
# A cache for the font of the current UI control.
var current_font: Font = null
# A reference to the currently focused UI text control (e.g., LineEdit, TextEdit).
var current_ui_control: Control = null
# The type of the current UI control, used for type-specific logic.
var current_ui_type: UIControlType = UIControlType.NONE
# Enum for identifying the capabilities of the text control (1D vs. 2D).
enum UIControlType {
	NONE = 1, # Not a supported control.
	X = 2, # Supports horizontal movement (e.g., LineEdit).
	Y = 4, # Supports vertical movement (e.g., TextEdit).
	XY = 6 # Both X and Y
}

# A visual offset for positioning the caret texture, set from the Inspector.
@export var caret_texture_offset: Vector2


# Checks if a given control is a supported text input field and updates internal state.
# Returns true if supported, false otherwise.
func update_current_ui_control(new_ui_control: Control) -> bool:
	var is_support_text_control: bool = false
	# Return immediately if the control is not valid.
	if not is_instance_valid(new_ui_control):
		return is_support_text_control
	if new_ui_control is LineEdit:
		current_ui_type = UIControlType.X
		is_support_text_control = true
	elif new_ui_control is TextEdit:
		# TextEdit supports both horizontal and vertical movement.
		current_ui_type = UIControlType.X | UIControlType.Y as UIControlType
		is_support_text_control = true
	return is_support_text_control

# Resets the selection state of the UI control.
func reset_selection_state() -> void:
	if is_instance_valid(current_ui_control):
		current_ui_control.deselect()
		current_ui_control = null
	if is_instance_valid(current_ui_control) and not _is_caret_drag:
		current_ui_control.deselect()
	elif not is_instance_valid(current_ui_control) && !_is_caret_drag:
		current_ui_control = null
		current_ui_type = UIControlType.NONE


# Gets the font size from the active control, respecting theme overrides.
func get_font_size() -> int:
	if current_ui_control.has_theme_font_size_override("font_size"):
		return current_ui_control.get_theme_font_size("font_size")
	else:
		return current_ui_control.get_theme_default_font_size()

# Gets the font from the active control, respecting theme overrides.
func get_font() -> Font:
	current_font = current_ui_control.get(&"theme_override_fonts/font")
	if null == current_font:
		current_font = current_ui_control.get_theme_default_font()
	return current_font

# Calculates an offset value based on the control's width and the string's rendered width.
func get_string_size_x(offset_str: String) -> float:
	var offset: float = current_ui_control.size.x - get_font().get_string_size(
		offset_str,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		get_font_size(),
		TextServer.JUSTIFICATION_NONE,
		TextServer.DIRECTION_AUTO,
		TextServer.ORIENTATION_HORIZONTAL
	).x
	return offset

# Calculates an offset value based on the control's width and the string's rendered height.
func get_string_size_y(offset_str: String) -> float:
	var offset: float = current_ui_control.size.x - get_font().get_string_size(
		offset_str,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		get_font_size(),
		TextServer.JUSTIFICATION_NONE,
		TextServer.DIRECTION_AUTO,
		TextServer.ORIENTATION_HORIZONTAL
	).y
	return offset

# Calculates the visual offset needed to correctly position the caret handle texture.
func _calculate_caret_offset(font_size: int) -> Vector2:
	var caret_width: int = -1
	if current_ui_control.has_theme_constant("caret_width"):
		caret_width = current_ui_control.get_theme_constant("caret_width") # A small adjustment to better center the caret_one
	var x_offset : float = caret_texture_offset.x + caret_width * 0.5
	var line_height : float = get_font().get_height(font_size)
	var y_offset : float = caret_texture_offset.y + line_height
	return Vector2(x_offset, y_offset)

# Gets the local position of the native caret within the text control.
func get_native_caret_local_pos() -> Vector2:
	match current_ui_type:
		UIControlType.X: # Logic for LineEdit
			var column: int = current_ui_control.get_caret_column()
			var text_before: String = current_ui_control.text.substr(0, column)
			var font_size: int = get_font_size()
			var font: Font = get_font()
			
			# Calculate the position based on the text string before the caret.
			var pos: Vector2 = font.get_string_size(text_before, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			
			# Addition the horizontal scroll offset to get the correct visual position.
			# This was the source of the issue.
			pos.x += current_ui_control.get_scroll_offset()
			
			# Vertically center the caret within the line.
			pos.y = font.get_height(font_size) * 0.5
			
			return pos
			
		UIControlType.X | UIControlType.Y: # Logic for TextEdit
			var line: int = current_ui_control.get_caret_line()
			var column: int = current_ui_control.get_caret_column()
			return current_ui_control.get_pos_at_line_column(line, column)
			
	return Vector2.ZERO


# Checks if the text in the current UI control is empty.
func is_ui_text_empty() -> bool:
	return current_ui_control.text.is_empty()
	
# Checks if the native caret is currently outside the visible area of the control.
func is_ui_caret_not_visible() -> bool:
	match current_ui_type:
		UIControlType.X: # Logic for LineEdit
			# First, calculate the caret's final local X position using the same logic as get_native_caret_local_pos.
			var column: int = current_ui_control.get_caret_column()
			var text_before: String = current_ui_control.text.substr(0, column)
			var caret_absolute_pos_x: float = get_font().get_string_size(
				text_before, HORIZONTAL_ALIGNMENT_LEFT, -1, get_font_size()
			).x
			
			var scroll_offset: float = current_ui_control.get_scroll_offset()
			var stylebox: StyleBox = current_ui_control.get_theme_stylebox("focus" if current_ui_control.has_focus() else "normal")
			var margin_left: float = stylebox.get_content_margin(SIDE_LEFT)
			
			var final_caret_local_x :float = (caret_absolute_pos_x + scroll_offset) + margin_left

			# Now, determine the boundaries of the visible content area.
			var right_bound: float = current_ui_control.size.x - stylebox.get_content_margin(SIDE_RIGHT)
			
			# The caret is NOT visible if its final local position is outside the content area.
			# A small tolerance (e.g., 1.0) is added to the right bound to prevent the caret
			# from disappearing exactly at the edge due to floating point inaccuracies.
			return final_caret_local_x < margin_left or final_caret_local_x > (right_bound + 1.0)

		UIControlType.X | UIControlType.Y: # Logic for TextEdit
			var caret_line: int = current_ui_control.get_caret_line()
			var first_visible_line : int = current_ui_control.get_first_visible_line()
			var last_visible_line : int = first_visible_line + get_visible_line_count()
			return caret_line < first_visible_line or caret_line > last_visible_line
			
	return false

# Gets the number of text lines that can be visible in the control at once.
func get_visible_line_count() -> int:
	if get_font().get_height() > 0:
		return int(current_ui_control.size.y / get_font().get_height())
	return 0
