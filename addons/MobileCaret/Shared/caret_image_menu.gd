# A menu on an image (or any control without text): a long press opens MobileCaret's toolbar with
# the items given for it, such as an app's "Save image". It works beside the image's own input
# (a pan or a pinch is not a long press: the finger, or the image under it, moved).
#
#     var menu := caret_image_menu.attach($Page, [{"id": &"save", "text": "Save image"}])
#     menu.item_pressed.connect(func(id): save_page())
#
# Items are Dictionaries as for caret_toolbar.add_item ("id", "text", "index", "items", "font",
# "icon", "callback"). The menu can be switched off from code like any control's menu:
# MobileCaretToolbar.set_control_menu(image, false). There is no Copy: Godot cannot put an image on
# the clipboard.
class_name caret_image_menu extends Node

signal item_pressed(id: StringName)

# Set on the image while a menu is attached (its value is this node).
const META: StringName = &"mobile_caret_image_menu"

var image: Control = null
var items: Array = []
# How long a press is held still before the menu opens (seconds).
var long_press_time: float = 0.5
# How far the finger, or the image under it (a scrolled page), may move and still be a long press,
# in viewport units.
var move_limit: float = 12.0
# Where the menu points, in the image's coordinates (the long-pressed place).
var menu_point: Vector2 = Vector2.ZERO

var _open: bool = false
var _held: bool = false
var _press_id: int = 0
var _press_local: Vector2 = Vector2.ZERO
var _press_screen: Vector2 = Vector2.ZERO
var _image_at: Vector2 = Vector2.ZERO
var _saved_focus_mode: int = Control.FOCUS_NONE

static var _factory_added: bool = false


# Gives `control` a long-press menu with `menu_items`. Attaching again replaces the menu.
static func attach(control: Control, menu_items: Array, press_time: float = 0.5) -> caret_image_menu:
	if control.has_meta(META):
		var old: Variant = control.get_meta(META)
		if old is caret_image_menu and is_instance_valid(old):
			(old as caret_image_menu).detach()
	var menu: caret_image_menu = caret_image_menu.new()
	menu.name = "ImageMenu"
	menu.image = control
	menu.items = menu_items.duplicate()
	menu.long_press_time = press_time
	control.set_meta(META, menu)
	control.add_child(menu, false, Node.INTERNAL_MODE_BACK)
	control.gui_input.connect(menu._on_gui_input)
	control.focus_exited.connect(menu.close)
	# the image needs its presses
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	if not _factory_added:
		caret_text_adapter.register_adapter(_adapter_for)
		_factory_added = true
	return menu


# The toolbar asks every control it serves: an image with a menu gets an image adapter.
static func _adapter_for(control: Control) -> caret_text_adapter:
	if not is_instance_valid(control) or not control.has_meta(META):
		return null
	var menu: Variant = control.get_meta(META)
	if menu is caret_image_menu and is_instance_valid(menu):
		return caret_image_adapter.new(control, menu as caret_image_menu)
	return null


# Removes the menu from its image.
func detach() -> void:
	close()
	if is_instance_valid(image):
		if image.gui_input.is_connected(_on_gui_input):
			image.gui_input.disconnect(_on_gui_input)
		if image.focus_exited.is_connected(close):
			image.focus_exited.disconnect(close)
		if image.has_meta(META) and image.get_meta(META) == self:
			image.remove_meta(META)
	queue_free()


func is_open() -> bool:
	return _open


# Opens the menu at a point of the image (its own coordinates), as a long press there does.
func open_at(point: Vector2) -> void:
	if not is_instance_valid(image) or not caret_menu_settings.is_menu_enabled(image):
		return
	menu_point = point
	_open = true
	_saved_focus_mode = image.focus_mode
	if image.focus_mode == Control.FOCUS_NONE:
		image.focus_mode = Control.FOCUS_CLICK
	image.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	if is_instance_valid(image):
		if image.has_focus():
			image.release_focus()
		image.focus_mode = _saved_focus_mode as Control.FocusMode


# An item was pressed in the toolbar: tell the app, and close.
func press(id: StringName) -> void:
	item_pressed.emit(id)
	close()


func _on_gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and event.is_pressed()) or (event is InputEventScreenTouch and event.is_pressed())
	var released: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not event.is_pressed()) or (event is InputEventScreenTouch and not event.is_pressed())
	if not (pressed or released or event is InputEventMouseMotion or event is InputEventScreenDrag):
		return
	var local: Vector2 = event.get(&"position")
	# measured on the screen: a page that scrolls moves the image with the finger
	var on_screen: Vector2 = image.get_global_transform_with_canvas() * local
	if pressed:
		_held = true
		_press_local = local
		_press_screen = on_screen
		_image_at = image.get_global_transform_with_canvas().origin
		_press_id += 1
		var id: int = _press_id
		get_tree().create_timer(long_press_time).timeout.connect(func() -> void: _long_press(id))
	elif released:
		_held = false
	elif _held and on_screen.distance_to(_press_screen) > move_limit:
		_held = false


func _long_press(id: int) -> void:
	if not _held or id != _press_id or not is_instance_valid(image) or not image.is_visible_in_tree():
		return
	_held = false
	if image.get_global_transform_with_canvas().origin.distance_to(_image_at) > move_limit:
		return
	open_at(_press_local)


# While open, a press anywhere but the image and the toolbar closes the menu.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	var pressed: bool = (event is InputEventMouseButton and event.is_pressed()) or (event is InputEventScreenTouch and event.is_pressed())
	if not pressed or not is_instance_valid(image):
		return
	var point: Vector2 = event.get(&"position")
	var toolbar: Node = get_node_or_null(^"/root/MobileCaretToolbar")
	if toolbar != null and toolbar.has_method(&"covers_point") and bool(toolbar.call(&"covers_point", point, image.get_viewport())):
		return
	if image.get_global_rect().has_point(point):
		return
	close.call_deferred()
