extends base_carets_controller




# Selection anchor for TextEdit
var _selection_anchor_line: int = 0
var _selection_anchor_col: int = 0






func _ready() -> void:
	caret_one.hide_caret()
	caret_two.hide_caret()
	caret_one.set_caret_texture(texture_caret)
	caret_two.set_caret_texture(texture_caret)


func _process(_delta: float) -> void:
	var current_focused_ui = get_viewport().gui_get_focus_owner()
	if update_current_ui_control(current_focused_ui):
		if current_focused_ui != current_ui_control:
			on_ui_deselected()
		current_ui_control = current_focused_ui
		on_ui_selected()
		
	elif current_focused_ui is ControllerCaret:
		on_caret_selected(current_focused_ui)
		on_caret_dragging()
		
	# If we click anywhere else, deselect text and hide carets
	elif Input.is_action_just_pressed("click") and not (current_focused_ui is ControllerCaret):
		on_carets_deselected()
	
	else:
		on_ui_deselected()
		on_carets_deselected()


func on_ui_selected() -> void:
	_update_carets_to_typing_pos()


func on_ui_deselected() -> void:
	if is_instance_valid(current_ui_control):
		current_ui_control.deselect()
		current_ui_control= null
	current_ui_type = ui_control_type.NONE






func on_caret_selected(caret_focused : ControllerCaret) -> void:
	if current_selected_caret != caret_focused:
		_start_caret_selection(caret_focused)

func on_caret_dragging() -> void:
	_handle_selection_drag()

func on_carets_deselected() -> void:
	_is_caret_drag = false
	current_selected_caret = null
	caret_one.hide_caret()
	caret_two.hide_caret()


func _update_carets_to_typing_pos() -> void:
	if not is_instance_valid(current_ui_control) or is_ui_text_empty():
		caret_one.hide_caret()
		caret_two.hide_caret()
		return
	else:
		# Only show one caret when not selecting
		caret_one.show_caret()
		caret_two.hide_caret()

	# Position the primary caret at the typing cursor
	var caret_pos_local: Vector2 = get_native_caret_local_pos()
	# Godot 4 Correction: Convert local to global position
	var caret_pos_global: Vector2 = current_ui_control.global_position + caret_pos_local
	
	caret_one.global_position = caret_pos_global + _calculate_caret_offset( get_font_size())
	caret_two.global_position = caret_one.global_position


func _start_caret_selection(caret_focused: ControllerCaret) -> void:
	_is_caret_drag = true
	#caret_focused.grab_focus()
	current_selected_caret = caret_focused

	caret_one.show_caret()
	caret_two.show_caret()
	
	match current_ui_type:
		ui_control_type.X:
			_selection_anchor_line = current_ui_control.get_caret_line()
			_selection_anchor_col = 0
		ui_control_type.X | ui_control_type.Y:
			_selection_anchor_line = current_ui_control.get_caret_line()
			_selection_anchor_col = current_ui_control.get_caret_column()
	

func _handle_selection_drag() -> void:
	if Input.is_action_just_released("click"):
		_is_caret_drag = false
	# Update the position of the controller being dragged to the global mouse position
	# We use get_global_mouse_position() directly for accuracy during the drag
	current_selected_caret.global_position = get_global_mouse_position()
	match current_ui_type:
		ui_control_type.X:
			_select_text_line_edit()
		ui_control_type.X | ui_control_type.Y:
			_select_text_text_edit()



func _select_text_line_edit() -> void:
	var pos1: int = _get_char_index_from_pos(caret_one)
	var pos2: int = _get_char_index_from_pos(caret_two)
	
	current_ui_control.select(min(pos1, pos2), max(pos1, pos2))
	
	var active_pos = _get_char_index_from_pos(current_selected_caret)
	current_ui_control.set_caret_column(active_pos)


func _select_text_text_edit() -> void:
	# Godot 4 Correction: Use get_local_mouse_position() for direct conversion
	var local_mouse_pos: Vector2 = current_ui_control.get_local_mouse_position()
	
	var new_line: int = current_ui_control.get_line_at_pos(local_mouse_pos)
	var new_col: int = current_ui_control.get_column_at_pos(local_mouse_pos, true)
	
	new_line = clamp(new_line, 0, current_ui_control.get_line_count() - 1)
	new_col = clamp(new_col, 0, current_ui_control.get_line_text(new_line).length())

	current_ui_control.set_caret_line(new_line)
	current_ui_control.set_caret_column(new_col)
	
	current_ui_control.select(_selection_anchor_line, _selection_anchor_col, new_line, new_col)
	
	var anchor_controller = caret_one if current_selected_caret == caret_two else caret_two
	var anchor_pos_local = current_ui_control.get_pos_at_line_column(_selection_anchor_line, _selection_anchor_col)
	# Godot 4 Correction: Convert local to global position
	anchor_controller.global_position = current_ui_control.global_position + anchor_pos_local + _calculate_caret_offset(get_font_size())




#region Helper Functions









func _get_char_index_from_pos(controller: ControllerCaret) -> int:
	if not current_ui_control is LineEdit: return 0
	
	# Godot 4 Correction: Convert global position to local using the inverse transform.
	# This is the robust way that accounts for potential UI scaling or rotation.
	var local_pos = current_ui_control.get_global_transform().affine_inverse().basis_xform(controller.global_position)
	var local_x = local_pos.x
	
	var text = current_ui_control.text
	var font_size = get_font_size()
	
	var closest_index = 0
	var min_dist = INF
	for i in range(text.length() + 1):
		var char_pos = get_font().get_string_size(text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var dist = abs(local_x - char_pos)
		if dist < min_dist:
			min_dist = dist
			closest_index = i
		else:
			break
	return closest_index

#endregion


#region Optional
#func _enable_native_caret(enable: bool) -> void:
	#if not is_instance_valid(_line_edit): return
	#var color: Color = _line_edit.get_theme_color("font_color")
	#color.a = 1.0 if enable else 0.0
	#_line_edit.add_theme_color_override("caret_color", color)
#endregion
