# The toolbar's view of an image with a menu (caret_image_menu) whose control also has selectable
# text (a caret delegate, see caret_delegate_adapter): a chart or a diagram that draws its own words
# or numbers. While its text is selected, the menu has the text's buttons (Copy, Select all) and
# also the image's: Copy image and the image menu's own items, such as an app's "Save image".
class_name caret_image_text_adapter extends caret_delegate_adapter

var menu: caret_image_menu


func _init(image: Control, target: Object, image_menu: caret_image_menu) -> void:
	super(image, target)
	menu = image_menu


func is_valid() -> bool:
	return super() and is_instance_valid(menu)

# A new long press on the text is a new selection for the toolbar, even on the word selected before
# (after Copy hid the menu, the same word long-pressed again shows it again).
func get_text_version() -> int:
	return super() + (menu.get_text_round() * 1000003 if is_valid() else 0)

func can_copy_image() -> bool:
	return is_valid() and menu.can_copy_image()

# The image as it was when the text was long-pressed (before the highlight and the handles).
func copy_image() -> void:
	if is_valid():
		menu.copy_image()

func get_toolbar_items() -> Array:
	var items: Array = super()
	if is_valid():
		items.append_array(menu.items)
	return items

func toolbar_item_pressed(id: StringName) -> void:
	if is_valid():
		for item: Variant in menu.items:
			if item is Dictionary and StringName((item as Dictionary).get("id", &"")) == id:
				menu.press(id)
				return
	super(id)
