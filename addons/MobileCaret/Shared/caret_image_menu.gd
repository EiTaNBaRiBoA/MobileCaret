# A menu on an image (or any control without text): a long press opens MobileCaret's toolbar with
# the items given for it, such as an app's "Save image". It works beside the image's own input
# (a pan or a pinch is not a long press: the finger, or the image under it, moved).
#
#     var menu := caret_image_menu.attach($Page, [{"id": &"save", "text": "Save image"}])
#     menu.item_pressed.connect(func(id): save_page())
#
# Items are Dictionaries as for caret_toolbar.add_item ("id", "text", "index", "items", "font",
# "icon", "callback"). The menu can be switched off from code like any control's menu:
# MobileCaretToolbar.set_control_menu(image, false).
#
# Where the system clipboard can take an image (caret_image_clipboard: Android, Windows) the menu also
# has a built-in "Copy image" button (MobileCaretToolbar.show_copy_image). The image is the control's
# texture (a TextureRect), what its get_image() returns, what `image_source` returns, or else the
# control as it is on screen when the menu opens.
#
# A view whose own presses do something (a slider, a draggable point, a node of a graph) answers
# is_interactive_at(point): a long press that starts on such a spot opens no menu, so the view works
# as before.
#
# A view that draws its own text (the numbers of a table, the words of a diagram) can make that
# text selectable with a caret delegate (`_get_caret_delegate()`, see caret_delegate_adapter) whose
# has_text_at(point) says where text is. A long press on its text then selects the word there, with
# handles, and the menu has the text's buttons (Copy, Select all) and, under ···, the image's (Copy
# image and the items given here; image_items_in_more); a long press anywhere else opens the
# image's menu as before.
class_name caret_image_menu extends Node

signal item_pressed(id: StringName)
# Copy image finished: "" or what went wrong.
signal image_copied(error: String)

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
# Returns the Image to copy (optional; see the class description for the other sources).
var image_source: Callable = Callable()
# While the image's text is selected, its buttons (Copy image and the items) are under one ··· button
# of the text's menu (Copy, Select all, ···), so the menu stays short and full size on a phone.
# Off: they are in the main row with the text's buttons.
var image_items_in_more: bool = true

var _snapshot: Image = null

var _open: bool = false
var _text_open: bool = false
var _press_while_text: bool = false
# How many times a long press started selecting the text (a new one shows the menu again, even
# on the same word as before).
var _text_round: int = 0
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
	if not (menu is caret_image_menu and is_instance_valid(menu)):
		return null
	var image_menu: caret_image_menu = menu as caret_image_menu
	var delegate: Object = image_menu._text_delegate()
	if delegate != null and not image_menu.is_open():
		return caret_image_text_adapter.new(control, delegate, image_menu)
	return caret_image_adapter.new(control, image_menu)


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


# Whether the image's text is being selected (after a long press on it).
func is_text_open() -> bool:
	return _text_open


# Counts the long presses that selected the text.
func get_text_round() -> int:
	return _text_round


# The image's caret delegate, when it has selectable text (see the class description), or null.
func _text_delegate() -> Object:
	if not is_instance_valid(image) or not image.has_method(caret_text_adapter.DELEGATE_METHOD):
		return null
	var delegate: Variant = image.call(caret_text_adapter.DELEGATE_METHOD)
	return delegate as Object if delegate is Object and is_instance_valid(delegate) else null


# Whether there is selectable text at a point of the image.
func has_text_at(point: Vector2) -> bool:
	var delegate: Object = _text_delegate()
	return delegate != null and delegate.has_method(&"has_text_at") and bool(delegate.call(&"has_text_at", point))


# Selects the word at a point of the image's text, as a long press there does: the handles and the
# menu come with the focus.
func select_text_at(point: Vector2) -> void:
	var delegate: Object = _text_delegate()
	if delegate == null or not caret_menu_settings.is_menu_enabled(image):
		return
	if image.has_focus():
		image.release_focus()
	menu_point = point
	# Copy image takes the image as it is now, before the highlight and the handles cover it
	_snapshot = null
	if _own_image() == null:
		_snapshot = _capture()
	var pos: Variant = delegate.call(&"get_pos_at_local", point) if delegate.has_method(&"get_pos_at_local") else Vector2i.ZERO
	if delegate.has_method(&"select_word_at"):
		delegate.call(&"select_word_at", pos)
	_text_open = true
	_text_round += 1
	_saved_focus_mode = image.focus_mode
	if image.focus_mode == Control.FOCUS_NONE:
		image.focus_mode = Control.FOCUS_CLICK
	image.grab_focus()


# Opens the menu at a point of the image (its own coordinates), as a long press there does.
func open_at(point: Vector2) -> void:
	if not is_instance_valid(image) or not caret_menu_settings.is_menu_enabled(image):
		return
	# from a text selection: that ends first (the menu then is the image's)
	if image.has_focus():
		image.release_focus()
	menu_point = point
	# a view drawn on screen is taken now, before the toolbar covers it
	_snapshot = null
	if _own_image() == null:
		_snapshot = _capture()
	_open = true
	_saved_focus_mode = image.focus_mode
	if image.focus_mode == Control.FOCUS_NONE:
		image.focus_mode = Control.FOCUS_CLICK
	image.grab_focus()


func close() -> void:
	if not _open and not _text_open:
		return
	_open = false
	if _text_open:
		_text_open = false
		var delegate: Object = _text_delegate()
		if delegate != null and delegate.has_method(&"deselect"):
			delegate.call(&"deselect")
	if is_instance_valid(image):
		if image.has_focus():
			image.release_focus()
		image.focus_mode = _saved_focus_mode as Control.FocusMode


# The image the menu stands for (see the class description). Null if there is none.
func get_image() -> Image:
	var own: Image = _own_image()
	return own if own != null else _snapshot


func _own_image() -> Image:
	if not is_instance_valid(image):
		return null
	var got: Variant = null
	if image_source.is_valid():
		got = image_source.call()
	elif image.has_method(&"get_image"):
		got = image.call(&"get_image")
	elif image is TextureRect and (image as TextureRect).texture != null:
		got = (image as TextureRect).texture.get_image()
	if got is Texture2D:
		got = (got as Texture2D).get_image()
	return got as Image if got is Image and not (got as Image).is_empty() else null


# The control as it is on screen (its part of the viewport's last frame).
func _capture() -> Image:
	var viewport: Viewport = image.get_viewport()
	var frame: Image = viewport.get_texture().get_image() if viewport != null else null
	if frame == null:
		return null
	var scale: float = float(frame.get_width()) / maxf(1.0, viewport.get_visible_rect().size.x)
	var rect: Rect2 = image.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, image.size)
	var pixels: Rect2i = Rect2i(Rect2(rect.position * scale, rect.size * scale)).intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	if pixels.size.x <= 0 or pixels.size.y <= 0:
		return null
	return frame.get_region(pixels)


func can_copy_image() -> bool:
	return caret_image_clipboard.supported()


# Puts the image on the clipboard; image_copied tells how it went. The menu closes.
func copy_image() -> void:
	var picture: Image = get_image()
	close()
	if picture == null:
		image_copied.emit("no image")
		return
	caret_image_clipboard.copy_later(picture, func(err: String) -> void: image_copied.emit(err))


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
	# A finger on the toolbar laid over the image: the toolbar takes its mouse press, but the touch
	# Godot also sends reaches the image under it. That press is the toolbar's, not the image's.
	if (pressed or released) and _over_toolbar(on_screen):
		_held = false
		_press_while_text = false
		return
	if pressed:
		# a spot whose press does something in the view (a slider, a node) is not for the menu
		if image.has_method(&"is_interactive_at") and bool(image.call(&"is_interactive_at", local)):
			_held = false
			return
		_held = true
		_press_while_text = _text_open
		_press_local = local
		_press_screen = on_screen
		_image_at = image.get_global_transform_with_canvas().origin
		_press_id += 1
		var id: int = _press_id
		get_tree().create_timer(long_press_time).timeout.connect(func() -> void: _long_press(id))
	elif released:
		# a tap on the image while its text is selected ends the selection, as on a page of text
		if _held and _text_open and _press_while_text:
			image.release_focus()
		_held = false
	elif _held and on_screen.distance_to(_press_screen) > move_limit:
		_held = false


# Whether the toolbar is shown over a point of the image's viewport.
func _over_toolbar(point: Vector2) -> bool:
	var toolbar: Node = get_node_or_null(^"/root/MobileCaretToolbar")
	return toolbar != null and toolbar.has_method(&"covers_point") and bool(toolbar.call(&"covers_point", point, image.get_viewport()))


func _long_press(id: int) -> void:
	if not _held or id != _press_id or not is_instance_valid(image) or not image.is_visible_in_tree():
		return
	_held = false
	if image.get_global_transform_with_canvas().origin.distance_to(_image_at) > move_limit:
		return
	if has_text_at(_press_local):
		select_text_at(_press_local)
	else:
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
