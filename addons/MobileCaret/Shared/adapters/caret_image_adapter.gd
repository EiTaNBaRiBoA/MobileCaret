# The toolbar's view of an image with a menu (caret_image_menu): while the menu is open the image
# counts as "selected", so the toolbar shows its items above the point that was long-pressed. An
# image has no text, so none of the built-in buttons apply (and Godot cannot put an image on the
# clipboard, so there is no Copy for it).
class_name caret_image_adapter extends caret_text_adapter

var menu: caret_image_menu


func _init(image: Control, image_menu: caret_image_menu) -> void:
	super(image)
	menu = image_menu


func is_valid() -> bool:
	return super() and is_instance_valid(menu)

func is_usable() -> bool:
	return is_valid() and menu.is_open()

func supports_handles() -> bool:
	return false

func is_text_editable() -> bool:
	return false

func is_empty() -> bool:
	return true

func has_selection(_caret_index: int = 0) -> bool:
	return is_usable()

func get_selection_from(_caret_index: int = 0) -> Vector2i:
	return Vector2i.ZERO

func get_selection_to(_caret_index: int = 0) -> Vector2i:
	return Vector2i(1, 0)

# The menu points at the place that was long-pressed.
func get_tip_local(_pos: Vector2i) -> Vector2:
	return menu.menu_point if is_valid() else Vector2.ZERO

func is_pos_visible(_pos: Vector2i) -> bool:
	return true

func get_line_height() -> float:
	return 24.0 * ui_scale

func get_selected_text() -> String:
	return ""

func allows_action(_action: StringName) -> bool:
	return false

func get_toolbar_items() -> Array:
	return menu.items.duplicate() if is_valid() else []

func toolbar_item_pressed(id: StringName) -> void:
	if is_valid():
		menu.press(id)
