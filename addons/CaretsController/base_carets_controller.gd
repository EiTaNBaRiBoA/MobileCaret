extends Control
class_name base_carets_controller

const OFFSET_BY: String = "_"
# Custom texture for the carets
@export var texture_caret: Texture2D

# References to the two caret controllers
@export var caret_one: ControllerCaret
@export var caret_two: ControllerCaret

var current_selected_caret: ControllerCaret = null
var _is_caret_drag: bool = false
var current_font : Font = null
var current_ui_control : Control = null
var current_ui_type : ui_control_type =  ui_control_type.NONE
enum ui_control_type {
	NONE = 1,
	X = 2,
	Y = 4
}

# Visual offset for the caret image
@export var caret_texture_offset: Vector2



func update_current_ui_control(new_ui_control : Control) -> bool:
	var is_support_text_control: bool = false
	if not is_instance_valid(new_ui_control) : 
		return is_support_text_control
	current_ui_control = new_ui_control
	if current_ui_control is LineEdit:
		current_ui_type = ui_control_type.X
		is_support_text_control = true
	elif current_ui_control is TextEdit:
		current_ui_type = (ui_control_type.X | ui_control_type.Y)
		is_support_text_control = true
	_reset_selection_state()
	return is_support_text_control

func _reset_selection_state() -> void:
	if is_instance_valid(current_ui_control) and _is_caret_drag:
		current_ui_control.deselect()

	current_ui_control = null



func get_font_size() -> int:
	if current_ui_control.has_theme_font_size_override("font_size"):
		return current_ui_control.get_theme_font_size("font_size")
	else:
		return current_ui_control.get_theme_default_font_size()

func get_font() -> Font:
	current_font = current_ui_control.get(&"theme_override_fonts/font")
	if null == current_font:
		current_font = current_ui_control.get_theme_default_font()
	return current_font

	

func get_string_size_x()-> float:
	var offset : float = current_ui_control.size.x - get_font().get_string_size(
		OFFSET_BY,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		get_font_size(),
		TextServer.JUSTIFICATION_NONE,
		TextServer.DIRECTION_AUTO,
		TextServer.ORIENTATION_HORIZONTAL
	).x
	return offset

func get_string_size_y() -> float:
	var offset : float = current_ui_control.size.x - get_font().get_string_size(
		OFFSET_BY,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		get_font_size(),
		TextServer.JUSTIFICATION_NONE,
		TextServer.DIRECTION_AUTO,
		TextServer.ORIENTATION_HORIZONTAL
	).y
	return offset


func _calculate_caret_offset(font_size: float) -> Vector2:
	var caret_width : int = -1
	if current_ui_control.has_theme_constant("caret_width"):
		caret_width = current_ui_control.get_theme_constant("caret_width") # A small adjustment to better center the caret_one
	var x_offset = caret_texture_offset.x + caret_width * 0.5
	var line_height = get_font().get_height(font_size)
	var y_offset = caret_texture_offset.y + line_height
	return Vector2(x_offset, y_offset)


func get_native_caret_local_pos() -> Vector2:
	match current_ui_type:
		ui_control_type.X:
			var column = current_ui_control.get_caret_column()
			var text_before = current_ui_control.text.substr(0, column)
			var font_size = get_font_size()
			var pos = get_font().get_string_size(text_before, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			pos.y = get_font().get_height(font_size) * 0.5
			return pos
		ui_control_type.X | ui_control_type.Y:
			var line = current_ui_control.get_caret_line()
			var column = current_ui_control.get_caret_column()
			return current_ui_control.get_pos_at_line_column(line, column)
	return Vector2.ZERO



func is_ui_text_empty() -> bool:
	return current_ui_control.text.is_empty()
