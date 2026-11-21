# The toolbar's view of an image with a menu (caret_image_menu) whose control also has selectable
# text (a caret delegate, see caret_delegate_adapter): a chart or a diagram that draws its own words
# or numbers. While its text is selected, the menu has the text's buttons (Copy, Select all) and
# also the image's: Copy image and the image menu's own items, such as an app's "Save image". With
# the menu's image_items_in_more (the default) the image's buttons are under one ··· button, so the
# main row stays short and full size on a phone; otherwise they are in the main row.
class_name caret_image_text_adapter extends caret_delegate_adapter

# The ··· button that opens the image's buttons, and Copy image inside it.
const MORE_ID: StringName = &"mobile_caret_image_more"
const COPY_IMAGE_ID: StringName = &"mobile_caret_copy_image"

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

# The built-in Copy image button of the main row (under ··· it is an item of its own).
func can_copy_image() -> bool:
	return is_valid() and not menu.image_items_in_more and menu.can_copy_image()

# The image as it was when the text was long-pressed (before the highlight and the handles).
func copy_image() -> void:
	if is_valid():
		menu.copy_image()

func get_toolbar_items() -> Array:
	var items: Array = super()
	if not is_valid():
		return items
	if not menu.image_items_in_more:
		items.append_array(menu.items)
		return items
	var children: Array = []
	var toolbar: Node = control.get_node_or_null(^"/root/MobileCaretToolbar") if is_instance_valid(control) else null
	var shows_copy_image: bool = toolbar == null or bool(toolbar.get(&"show_copy_image"))
	if shows_copy_image and menu.can_copy_image() and allows_action(&"copy_image"):
		var copy_text: String = str(toolbar.get(&"text_copy_image")) if toolbar != null else "Copy image"
		children.append({"id": COPY_IMAGE_ID, "text": copy_text})
	children.append_array(menu.items)
	if not children.is_empty():
		var more_text: String = str(toolbar.get(&"text_more")) if toolbar != null else "···"
		items.append({"id": MORE_ID, "text": more_text, "items": children})
	return items

func toolbar_item_pressed(id: StringName) -> void:
	if is_valid():
		if id == COPY_IMAGE_ID:
			menu.copy_image()
			return
		for item: Variant in menu.items:
			if item is Dictionary and StringName((item as Dictionary).get("id", &"")) == id:
				menu.press(id)
				return
	super(id)
