extends Control

# Custom texture button to represent a caret (e.g., an image or icon)
@export var texture_caret: Texture2D

@export var controller_one: ControllerCaret
@export var controller_two: ControllerCaret
# Optional offset to adjust the position of caret_one relative to the text caret
@export var image_offset_caret: Vector2

# Flag indicating if text selection is in progress
var _is_selecting: bool = false

# Reference to the currently focused LineEdit or TextEdit control
var line_edit: Control = null

# Font used by the currently focused LineEdit or TextEdit
var font: Font = null

var selected_controller: ControllerCaret = null


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Initially hide caret_one since no LineEdit/TextEdit has focus yet
	controller_one.hide_caret()
	controller_two.hide_caret()
	controller_one.set_caret_texture(texture_caret)
	controller_two.set_caret_texture(texture_caret)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	# Get the control that currently has focus in the viewport
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	# Check if the focused control is a LineEdit or TextEdit
	if (focus_owner is LineEdit or focus_owner is TextEdit) and not Input.is_action_just_pressed('click'):
		if not _is_selecting:
			if selected_controller == controller_one:
				#If selected caret is the first controller, don't move the second one
				move_controller_under_text_typing(focus_owner, controller_one)
			elif selected_controller == controller_two:
				#If selected caret is the second controller, don't move the first one
				move_controller_under_text_typing(focus_owner, controller_two)
			else:
				# If no selected caret was made
				# Store a reference to the focused LineEdit/TextEdit
				line_edit = focus_owner

				move_controller_under_text_typing(focus_owner, controller_one)
				move_controller_under_text_typing(focus_owner, controller_two)
				# Enable blinking of the default text caret
				line_edit.set_caret_blink_enabled(true)
				_enable_caret(true)
		else:
			# Moves the selected_controller that was picked in elif
			move_caret_selected()
	# If a BaseButton is focused, initiate text selection in the previously focused LineEdit/TextEdit
	elif focus_owner is BaseButton and (focus_owner == controller_one.caret or focus_owner == controller_two.caret):
		set_selected_caret(focus_owner)
	elif Input.is_action_just_pressed('click'):
		#  remove two carets if just selected on a text without selecting on the caret
		selected_controller = null
		if line_edit:
			line_edit.deselect()


## Responsible to move caret under text when typing and not selecting the caret
func move_controller_under_text_typing(focus_owner: Control, controller: ControllerCaret) -> void:
	# Get the font used by the LineEdit/TextEdit
	if focus_owner is LineEdit:
		font = line_edit.get_theme_font('font', 'LineEdit')
	else:
		font = line_edit.get_theme_font('font', 'TextEdit')

	# Show/hide caret_one based on whether there's text in the LineEdit/TextEdit
	if not line_edit.text.is_empty():
		controller.show_caret()
	else:
		controller.hide_caret()

	# Calculate the position of the text caret within the LineEdit/TextEdit
	var caret_pos: Vector2 = _get_caret_position_in_text()
	# Calculate the offset to position caret_one relative to the LineEdit/TextEdit's origin
	var caret_offset: Vector2 = line_edit.global_position + _get_text_offset()
	# Get the effective font size (accounting for theme overrides)
	var current_font_size: int = _get_font_size(line_edit)
	# Calculate the final global position of caret_one
	controller.global_position = Vector2(
		caret_pos.x + caret_offset.x + _calculate_x_pos(current_font_size),
		caret_pos.y + caret_offset.y + _calculate_y_pos(current_font_size)
	)

## Handles clicking on the caret and moving it
func move_caret_selected() -> void:
	_enable_caret(false)
	# Handle text selection logic 
	if Input.is_action_just_released('click'):
		# End selection and re-enable caret blinking
		_is_selecting = false
	else:
		# Update caret_one's x position to follow the mouse
		var new_caret_pos: Vector2 = Vector2.ZERO
		if line_edit is LineEdit:
			selected_controller.global_position.x = get_global_mouse_position().x
		elif line_edit is TextEdit:
			selected_controller.global_position = get_global_mouse_position()
			new_caret_pos.y = calculate_node_caret_y_pos(selected_controller)
			line_edit.set_caret_line(new_caret_pos.y)
		new_caret_pos.x = calculate_node_caret_x_pos(selected_controller)

		# Update the LineEdit/TextEdit's caret position
		line_edit.set_caret_column(new_caret_pos.x)
		
		# Checking if there are two carets away from each other
		if selected_controller != null:
			if line_edit is LineEdit:
				select_text_line_edit(new_caret_pos.x)
			elif line_edit is TextEdit:
				select_text_text_edit(new_caret_pos)

## Setting the selected caret to be able to move it and grab focus of line edit
func set_selected_caret(focus_owner: BaseButton) -> void:
		_is_selecting = true
		line_edit.grab_focus()
		selected_controller = focus_owner.get_parent() as ControllerCaret
		controller_two.show_caret()


## Responsible to select text when moving two carets away from each other
func select_text_line_edit(selected_caret_pos: int) -> void:
	var other_caret_pos: int = 0
	if selected_controller != controller_one:
		other_caret_pos = calculate_node_caret_x_pos(controller_one)
	else:
		other_caret_pos = calculate_node_caret_x_pos(controller_two)
	var min_letter: int = min(other_caret_pos, selected_caret_pos)
	var max_letter: int = max(other_caret_pos, selected_caret_pos)
	line_edit.select(min_letter, max_letter)

func select_text_text_edit(selected_caret_pos : Vector2) -> void:
		selected_controller.global_position = get_global_mouse_position()
		var other_caret_pos: Vector2 = Vector2.ZERO
		if selected_controller != controller_one:
			other_caret_pos.x = calculate_node_caret_x_pos(controller_one)
			other_caret_pos.y = calculate_node_caret_y_pos(controller_one)
		else:
			other_caret_pos.x = calculate_node_caret_x_pos(controller_two)
			other_caret_pos.y = calculate_node_caret_y_pos(controller_two)
		line_edit.select(other_caret_pos.y, other_caret_pos.x, selected_caret_pos.y, selected_caret_pos.x)

#region private functions
# Calculate the vertical offset to position caret_one relative to the baseline
func _calculate_y_pos(current_font_size: float) -> float:
	# Get the height of a single-line string (e.g., "A")
	var line_height: float = font.get_string_size("A", _get_text_alignment(), -1, current_font_size).y
	# Center the caret_one vertically within the line height
	var y_offset: float = current_font_size / ThemeDB.fallback_font_size
	var baseline_offset: float = -line_height / y_offset - y_offset * y_offset / 1.3
	return baseline_offset

# Calculate the horizontal offset to position caret_one
func _calculate_x_pos(current_font_size: float) -> float:
	# Adjust for caret width and custom offset
	var caret_width: int = -1
	if line_edit.has_theme_constant("caret_width"):
		caret_width = line_edit.get_theme_constant("caret_width") # A small adjustment to better center the caret_one
	var final_x_offset: float = image_offset_caret.x + caret_width
	return final_x_offset

# Helper function to get the effective font size of the LineEdit/TextEdit
func _get_font_size(line_edit: Control) -> int:
	if line_edit.has_theme_font_size_override("font_size"):
		return line_edit.get_theme_font_size("font_size")
	else:
		return line_edit.get_theme_default_font_size()

#region Calculation Node Caret Pos
func calculate_node_caret_x_pos(controller_caret: ControllerCaret) -> int:
	# Calculate the offset to position caret_one relative to the LineEdit/TextEdit's origin
	var caret_offset: float = line_edit.global_position.x + _get_text_offset().x
	# Get the effective font size (accounting for theme overrides)
	var current_font_size: int = _get_font_size(line_edit)
	# Calculate the relative x distance between the mouse and the LineEdit/TextEdit's left edge
	var rel_x = controller_caret.global_position.x - caret_offset - image_offset_caret.x - _calculate_x_pos(current_font_size)
	# Find the new caret position based on the relative x distance
	var new_caret_pos: int = 0
	for i in range(len(line_edit.text) + 1):
		if _get_caret_position_in_text(i).x <= rel_x:
			new_caret_pos = i
		else:
			break
	return new_caret_pos
	#region Calculation Node Caret Pos
func calculate_node_caret_y_pos(controller_caret: ControllerCaret) -> int:
	if line_edit is TextEdit:
		var caret_offset: float = line_edit.global_position.y + _get_text_offset().y
		var current_font_size: int = _get_font_size(line_edit)
		var line_height: float = font.get_string_size("A", _get_text_alignment(), -1, current_font_size).y
		var rel_y = controller_caret.global_position.y - caret_offset - _calculate_y_pos(current_font_size)

		# Find the line number based on the relative y position
		var new_caret_line: int = int(rel_y / line_height)

		# Clamp the line number to be within the valid range
		new_caret_line = clamp(new_caret_line, 0, line_edit.get_line_count() - 1)

		return new_caret_line
	return 0
#endregion

func _enable_caret(enable_caret: bool) -> void:
	if line_edit.has_theme_color_override("caret_color"):
		var color: Color = line_edit.get_theme_color("caret_color")
		if enable_caret:
			color.a = 1
		else: color.a = 0
		line_edit.add_theme_color_override("caret_color", color)
	

# Get the position of the text caret in pixels , i won't be -1 is for the moving caret texture
func _get_caret_position_in_text(i: int = -1) -> Vector2:
	var caret_column: int = line_edit.get_caret_column()
	var text_before_caret: String = ""
	if i == -1:
		text_before_caret = line_edit.text.substr(0, caret_column)
	else:
		text_before_caret = line_edit.text.substr(0, i)

	var current_font_size: int = _get_font_size(line_edit)

	var caret_pos: Vector2 = font.get_string_size(text_before_caret, _get_text_alignment(), -1, current_font_size)
	if text_before_caret.is_empty():
		text_before_caret = 'a' # Default to avoid on index 0 caret texture go up
		caret_pos.y = font.get_string_size(text_before_caret, _get_text_alignment(), -1, current_font_size).y
	return caret_pos

# Calculate the offset to position text within the LineEdit based on alignment
func _get_text_offset() -> Vector2:
	var rect_size: Vector2 = line_edit.size
	var text_size: Vector2 = font.get_string_size(line_edit.text)
	var offset_caret: Vector2 = Vector2.ZERO

	# Handle horizontal alignment
	match _get_text_alignment():
		HORIZONTAL_ALIGNMENT_LEFT:
			offset_caret.x = 0
		HORIZONTAL_ALIGNMENT_CENTER:
			offset_caret.x = rect_size.x / 2 - text_size.x / 2
		HORIZONTAL_ALIGNMENT_RIGHT:
			offset_caret.x = rect_size.x - text_size.x

		# Handle vertical alignment (assuming center alignment for now)
	offset_caret.y = rect_size.y / 2 - text_size.y / 2
	return offset_caret

func _get_text_alignment() -> HorizontalAlignment:
	var caret_alignment: HorizontalAlignment = 0
	if line_edit is LineEdit:
		caret_alignment = line_edit.alignment
	return caret_alignment
#endregion
