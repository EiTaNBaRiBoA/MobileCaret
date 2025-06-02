# Manages the primary logic for mobile caret interaction, including selection and dragging.
# This script builds upon the base functionality provided by `base_carets_controller`.
extends base_carets_controller


# Stores the starting position of a text selection for a TextEdit node.
# The line where the selection gesture begins.
var _selection_anchor_line: int = 0
# The column where the selection gesture begins.
var _selection_anchor_col: int = 0


# Called when the node enters the scene tree for the first time.
# Initializes the carets by hiding them and setting their textures.
func _ready() -> void:
	caret_one.hide_caret()
	caret_two.hide_caret()
	caret_one.set_caret_texture(texture_caret)
	caret_two.set_caret_texture(texture_caret)

# Called every frame. The main loop for managing caret state.
func _process(_delta: float) -> void:
	# Get the UI element that currently has focus.
	var current_focused_ui = get_viewport().gui_get_focus_owner()

	# If the focused element is a supported text control...
	if update_current_ui_control(current_focused_ui):
		# If focus has switched to a new text control...
		if current_focused_ui != current_ui_control:
			# Reset the old control and initialize the new one.
			on_ui_deselected()
			current_ui_control = current_focused_ui
			on_ui_selected()
		# Update caret positions every frame for the active control.
		on_ui_update()
	# If a caret was being dragged and the user released the touch/click...
	elif current_selected_caret != null and Input.is_action_just_released("click") and _is_caret_drag:
		on_carets_stop_dragging()
	# If the user is interacting with a caret handle (which is a BaseButton)...
	elif current_focused_ui is BaseButton:
		# If the user just pressed the caret, initiate the selection.
		if Input.is_action_just_pressed("click"):
			# Ensure the caret is a valid child before proceeding.
			if current_focused_ui.get_parent() == null && current_focused_ui.get_parent() is not ControllerCaret: return
			on_caret_selected(current_focused_ui.get_parent())
		# If the drag flag is active, continue handling the drag.
		if _is_caret_drag:
			on_caret_dragging()
	# If the user clicks anywhere else that is not a caret...
	elif Input.is_action_just_pressed("click") and not (current_focused_ui is BaseButton):
		# Stop any active selection and hide carets.
		on_carets_stop_dragging()
	# If focus is lost or on an unsupported control...
	else:
		on_ui_deselected()


# Called once when a supported UI control is selected.
func on_ui_selected() -> void:
	pass

# Called once when a supported UI control is deselected or loses focus.
func on_ui_deselected() -> void:
	reset_selection_state()
	_is_caret_drag = false
	current_selected_caret = null
	caret_one.hide_caret()
	caret_two.hide_caret()

# Called every frame while a supported UI control is active.
func on_ui_update() -> void:
	_update_carets_to_typing_pos()


# Called when a user presses a caret handle.
func on_caret_selected(caret_focused: ControllerCaret) -> void:
	if current_selected_caret != caret_focused:
		_start_caret_selection(caret_focused)

# Called every frame while a caret handle is being dragged.
func on_caret_dragging() -> void:
	_handle_selection_drag()

# Called when the user stops dragging a caret handle.
func on_carets_stop_dragging() -> void:
	_is_caret_drag = false
	on_ui_update()
	current_selected_caret = null

# Updates the visibility and position of the carets based on the text cursor.
func _update_carets_to_typing_pos() -> void:
	# Hide carets if the control is invalid, empty, or the cursor is out of view.
	if not is_instance_valid(current_ui_control) or is_ui_text_empty() or is_ui_caret_not_visible():
		caret_one.hide_caret()
		caret_two.hide_caret()
		return
	# If a selection is in progress, show both carets.
	elif current_selected_caret != null:
		caret_one.show_caret()
		caret_two.show_caret()
	# If just typing (no selection), show only one caret.
	else:
		# Only show one caret when not selecting
		caret_one.show_caret()
		caret_two.hide_caret()

	# Get the local position of the native typing cursor.
	var caret_pos_local: Vector2 = get_native_caret_local_pos()
	# Convert the local position to global screen coordinates.
	var caret_pos_global: Vector2 = current_ui_control.global_position + caret_pos_local
	
	# If a caret is being dragged, update its position. The other caret's position
	# is handled by the selection logic.
	if current_selected_caret != null:
		var not_current_caret: ControllerCaret = caret_two if (current_selected_caret == caret_one) else caret_one
		current_selected_caret.global_position = caret_pos_global + _calculate_caret_offset(get_font_size())
	# If not selecting, position both carets at the typing cursor (only one will be visible).
	else:
		caret_one.global_position = caret_pos_global + _calculate_caret_offset(get_font_size())
		caret_two.global_position = caret_one.global_position

# Sets up the initial state when a selection drag begins.
func _start_caret_selection(caret_focused: ControllerCaret) -> void:
	_is_caret_drag = true
	#caret_focused.grab_focus()
	current_selected_caret = caret_focused

	caret_one.show_caret()
	caret_two.show_caret()
	var textlabel: Label = null
	# Store the current cursor position as the fixed anchor for the selection.
	match current_ui_type:
		ui_control_type.X:
			_selection_anchor_line = current_ui_control.get_caret_column()
			_selection_anchor_col = 0
		ui_control_type.X | ui_control_type.Y:
			_selection_anchor_line = current_ui_control.get_caret_line()
			_selection_anchor_col = current_ui_control.get_caret_column()
	
# Routes the drag handling to the appropriate function based on the control type.
func _handle_selection_drag() -> void:
	# Update the position of the controller being dragged to the global mouse position
	# We use get_global_mouse_position() directly for accuracy during the drag
	match current_ui_type:
		ui_control_type.X:
			_select_text_line_edit()
		ui_control_type.X | ui_control_type.Y:
			_select_text_text_edit()


# Manages text selection logic for a LineEdit control.
func _select_text_line_edit() -> void:
	current_selected_caret.global_position.x = get_global_mouse_position().x
	# Determine the start and end positions for the selection.
	var pos1: int = _get_char_index_from_pos(caret_one)
	var pos2: int = _get_char_index_from_pos(caret_two)
	
	# Select the text between the two positions.
	current_ui_control.select(min(pos1, pos2), max(pos1, pos2))
	
	# Update the native caret position to match the dragged handle.
	var active_pos = _get_char_index_from_pos(current_selected_caret)
	current_ui_control.set_caret_column(active_pos)

# Manages text selection logic for a TextEdit control.
func _select_text_text_edit() -> void:
	current_selected_caret.global_position = get_global_mouse_position()
	# Get the mouse position in the TextEdit's local coordinates.
	var local_mouse_pos: Vector2 = current_ui_control.get_local_mouse_position()
	
	# Find the line and column at the mouse position.
	var new_line: int = current_ui_control.get_line_at_pos(local_mouse_pos)
	var new_col: int = current_ui_control.get_column_at_pos(local_mouse_pos, true)
	
	# Ensure the new position is within the bounds of the text.
	new_line = clamp(new_line, 0, current_ui_control.get_line_count() - 1)
	new_col = clamp(new_col, 0, current_ui_control.get_line_text(new_line).length())

	# Move the native caret to the new position.
	current_ui_control.set_caret_line(new_line)
	current_ui_control.set_caret_column(new_col)
	
	# Select text from the original anchor point to the new cursor position.
	current_ui_control.select(_selection_anchor_line, _selection_anchor_col, new_line, new_col)
	
	# Update the visual position of the anchor handle (the one not being dragged).
	var anchor_controller = caret_one if current_selected_caret == caret_two else caret_two
	var anchor_pos_local = current_ui_control.get_pos_at_line_column(_selection_anchor_line, _selection_anchor_col)
	# Convert local anchor position to global coordinates.
	anchor_controller.global_position = current_ui_control.global_position + anchor_pos_local + _calculate_caret_offset(get_font_size())


#region Helper Functions

# Determines the character index in a LineEdit from a caret's global position.
func _get_char_index_from_pos(controller: ControllerCaret) -> int:
	if not current_ui_control is LineEdit: return 0
	
	# 1. Get the LineEdit's global transform and create its inverse.
	var inverse_transform: Transform2D = current_ui_control.get_global_transform().affine_inverse()
	
	# 2. Correctly convert the caret's global position to the LineEdit's local coordinates.
	# This is the proper Godot 4 replacement for the old to_local() method.
	var local_pos: Vector2 = inverse_transform * controller.global_position

	# 3. Get the necessary values to translate from the control's local space to the full string's space.
	var scroll_offset: float = current_ui_control.get_scroll_offset()
	var stylebox: StyleBox = current_ui_control.get_theme_stylebox("focus" if current_ui_control.has_focus() else "normal")
	var margin_left: float = stylebox.get_content_margin(SIDE_LEFT)

	# 4. Calculate the target X position in the coordinate system of the FULL, UNSCROLLED text string.
	# This formula correctly accounts for the control's internal padding and horizontal scrolling.
	var target_x_in_string: float = (local_pos.x - margin_left) + scroll_offset

	var text: String = current_ui_control.text
	var font_size: int = get_font_size()
	
	# 5. Iterate through the string to find the character index closest to our calculated target position.
	var closest_index: int = 0
	var min_dist: float = INF
	
	for i in range(text.length() + 1):
		var char_pos: float = get_font().get_string_size(text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var dist: float = abs(target_x_in_string - char_pos)
		
		if dist < min_dist:
			min_dist = dist
			closest_index = i
		else:
			break # Optimization
			
	return closest_index
#endregion


#region Optional
# This function can be used to toggle the visibility of the native engine caret.
#func _enable_native_caret(enable: bool) -> void:
	#if not is_instance_valid(_line_edit): return
	#var color: Color = _line_edit.get_theme_color("font_color")
	#color.a = 1.0 if enable else 0.0
	#_line_edit.add_theme_color_override("caret_color", color)
#endregion
