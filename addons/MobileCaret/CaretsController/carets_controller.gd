# Manages the primary logic for mobile caret interaction, including selection and dragging.
# This script builds upon the base functionality provided by `base_carets_controller`.
class_name carets_controller extends base_carets_controller


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
	var current_focused_ui: Control = get_viewport().gui_get_focus_owner()

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
			var parent: Variant = current_focused_ui.get_parent()
			if not is_instance_valid(parent) or not parent is caret_indicator:
				return
			on_caret_selected(parent)
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
func on_caret_selected(caret_focused: caret_indicator) -> void:
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
	# If a selection is in progress, update visibility based on scrolling.
	elif _is_caret_drag:
		update_caret_visibility()
	# If just typing (no selection), show only one caret.
	else:
		# Only show one caret when not selecting
		caret_one.show_caret()
		caret_two.hide_caret()

	# Get the local position of the native typing cursor.
	var caret_pos_local: Vector2 = get_native_caret_local_pos()
	# Convert the local position to global screen coordinates.
	var caret_pos_global: Vector2 = current_ui_control.global_position + caret_pos_local
	
	# If a caret is being dragged, its position is handled by the drag logic.
	# If not, position the visible caret(s) at the typing cursor.
	if not _is_caret_drag:
		caret_one.global_position = caret_pos_global + _calculate_caret_offset(get_font_size())
		caret_two.global_position = caret_one.global_position


# Sets up the initial state when a selection drag begins.
func _start_caret_selection(caret_focused: caret_indicator) -> void:
	_is_caret_drag = true
	current_selected_caret = caret_focused

	caret_one.show_caret()
	caret_two.show_caret()
	
	# Store the current cursor position as the fixed anchor for the selection.
	match current_ui_type:
		UIControlType.X: # LineEdit
			_selection_anchor_line = 0 # Line is always 0 for LineEdit
			_selection_anchor_col = current_ui_control.get_caret_column()
		UIControlType.X | UIControlType.Y: # TextEdit
			_selection_anchor_line = current_ui_control.get_caret_line()
			_selection_anchor_col = current_ui_control.get_caret_column()
	
# Routes the drag handling to the appropriate function based on the control type.
func _handle_selection_drag() -> void:
	match current_ui_type:
		UIControlType.X:
			_select_text_line_edit()
		UIControlType.X | UIControlType.Y:
			_select_text_text_edit()


# Manages text selection logic for a LineEdit control.
func _select_text_line_edit() -> void:
	current_selected_caret.global_position.x = get_global_mouse_position().x
	
	# Determine the start and end positions for the selection.
	var pos1: int = _get_char_index_from_pos(caret_one)
	var pos2: int = _get_char_index_from_pos(caret_two)
	
	current_ui_control.select(min(pos1, pos2), max(pos1, pos2))
	
	# Update the native caret position to match the dragged handle.
	var active_pos: int = _get_char_index_from_pos(current_selected_caret)
	current_ui_control.set_caret_column(active_pos)

# Manages text selection logic for a TextEdit control.
func _select_text_text_edit() -> void:
	var line_count: int = current_ui_control.get_line_count()
	if line_count == 0:
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	
	# STEP 1: Handle automatic scrolling when dragging near the control's edges.
	var control_rect: Rect2 = current_ui_control.get_global_rect()
	var scroll_speed: float = 300.0
	var scroll_margin: float = 40.0

	if mouse_pos.y < control_rect.position.y + scroll_margin:
		current_ui_control.scroll_vertical -= scroll_speed * get_process_delta_time()
	elif mouse_pos.y > control_rect.end.y - scroll_margin:
		current_ui_control.scroll_vertical += scroll_speed * get_process_delta_time()

	# STEP 2: Clamp the visual handle's position to within the control's bounds.
	var clamped_pos: Vector2 = mouse_pos
	clamped_pos.y = clamp(clamped_pos.y, control_rect.position.y, control_rect.end.y)
	current_selected_caret.global_position = clamped_pos
	
	# STEP 3: Convert the handle's position to a line/column and update the selection.
	var inverse_transform: Transform2D = current_ui_control.get_global_transform().affine_inverse()
	var local_pos: Vector2 = inverse_transform * current_selected_caret.global_position
	
	var line_col_at_pos: Vector2i = current_ui_control.get_line_column_at_pos(local_pos, true)
	var new_line: int = clamp(line_col_at_pos.y, 0, line_count - 1)
	var new_col: int = clamp(line_col_at_pos.x, 0, current_ui_control.get_line(new_line).length())

	# Update the native caret position without auto-scrolling (we handle it manually).
	current_ui_control.set_caret_line(new_line, false, false)
	current_ui_control.set_caret_column(new_col)
	current_ui_control.select(_selection_anchor_line, _selection_anchor_col, new_line, new_col)
		
	# STEP 4: Update the visual position of the anchor handle (the one not being dragged).
	var anchor_controller: caret_indicator = caret_one if current_selected_caret == caret_two else caret_two
	var anchor_rect: Rect2 = current_ui_control.get_rect_at_line_column(_selection_anchor_line, _selection_anchor_col)
	var anchor_pos_local: Vector2 = anchor_rect.position
	var anchor_pos_global: Vector2 = current_ui_control.get_global_transform() * anchor_pos_local
	
	anchor_controller.global_position = anchor_pos_global + _calculate_caret_offset(get_font_size())
	
	# STEP 5: Update visibility based on whether the anchor is visible.
	update_caret_visibility()


#region Helper Functions

# REVISED: Correctly hides the anchor caret if it scrolls out of view.
func update_caret_visibility() -> void:
	if not is_instance_valid(current_ui_control) or current_ui_type != (UIControlType.X | UIControlType.Y):
		return

	var anchor_controller: caret_indicator = caret_two if (current_selected_caret == caret_one) else caret_one
	
	var first_visible_line: int = current_ui_control.get_first_visible_line()
	var last_visible_line: int = first_visible_line + current_ui_control.get_visible_line_count() - 1

	# Check if the anchor's line is outside the visible range.
	if _selection_anchor_line < first_visible_line or _selection_anchor_line > last_visible_line:
		# Anchor is out of view, so hide the anchor handle.
		anchor_controller.hide()
		current_selected_caret.show() # Ensure the active one is visible.
	else:
		# Anchor is in view, show both.
		anchor_controller.show()
		current_selected_caret.show()

# Determines the character index in a LineEdit from a caret's global position.
func _get_char_index_from_pos(controller: caret_indicator) -> int:
	if not current_ui_control is LineEdit: return 0
	
	var inverse_transform: Transform2D = current_ui_control.get_global_transform().affine_inverse()
	var local_pos: Vector2 = inverse_transform * controller.global_position

	var scroll_offset: float = current_ui_control.get_scroll_offset()
	var stylebox: StyleBox = current_ui_control.get_theme_stylebox("normal")
	var margin_left: float = stylebox.get_content_margin(SIDE_LEFT)

	var target_x_in_string: float = (local_pos.x - margin_left) + scroll_offset

	var text: String = current_ui_control.text
	var font_size: int = get_font_size()
	var font: Font = get_font()
	
	var closest_index: int = 0
	var min_dist: float = INF
	
	for i : int in range(text.length() + 1):
		var char_pos: float = font.get_string_size(text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var dist: float = abs(target_x_in_string - char_pos)
		
		if dist < min_dist:
			min_dist = dist
			closest_index = i
		else:
			break # Optimization: Since character positions are monotonic, we can stop once the distance increases.
			
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
