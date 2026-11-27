# Keeps controls clear of the phone's on-screen keyboard and of the status and navigation bars.
# Godot does not resize the window when the keyboard opens, so bottom buttons and the field being
# typed in end up under it. Add this node anywhere in the scene and give it the controls to lift
# (`targets`, default: its parent): their top and bottom offsets follow the safe area and the
# keyboard, and the field being typed in is scrolled into sight when the keyboard opens or changes
# height. It does nothing on a desktop unless a test sets `simulate_keyboard_height`.
#
#   var inset: caret_keyboard_inset = caret_keyboard_inset.new()
#   inset.targets = [screens, overlay]
#   add_child(inset)
#   inset.insets_changed.connect(func(top: float, bottom: float, keyboard: float) -> void: ...)
class_name caret_keyboard_inset extends Node

## Emitted when the lift changes: the safe-area top, the safe-area bottom and the keyboard height,
## all in the targets' own units (logical pixels of their viewport).
signal insets_changed(top: float, bottom: float, keyboard: float)

## The controls kept clear of the bars and the keyboard (their offset_top and offset_bottom are set;
## anchor them to the full rect). Empty: the parent, when it is a Control.
@export var targets: Array[Control] = []
## Also keep clear of the status bar and the navigation bar (the display's safe area), for an app
## drawn edge to edge. Off: only the keyboard lifts the bottom.
@export var use_safe_area: bool = true
## Scroll the focused text control into sight (in its nearest ScrollContainer) once the keyboard
## opens or changes height.
@export var keep_focus_visible: bool = true
## Seconds to wait before that scroll, so the containers have their new height first.
@export var focus_delay: float = 0.05
## Work only on Android and iOS (the default). Off: also on a desktop with a virtual keyboard.
@export var only_on_mobile: bool = true
## How long (ms) the keyboard still counts as open after it was last seen: Android may hide it just
## before a back gesture reaches the app, which should then only close the keyboard.
@export var open_grace_ms: int = 400
## Tests: a keyboard of this height (in the targets' units) and a safe area of these insets, instead
## of the device's. Negative: the device's.
var simulate_keyboard_height: float = -1.0
var simulate_safe_area: Vector2 = Vector2(-1.0, -1.0)

var _top: float = 0.0
var _bottom: float = 0.0
var _keyboard: float = 0.0
var _seen_ms: int = -100000
var _applied: bool = false


func _ready() -> void:
	if targets.is_empty() and get_parent() is Control:
		targets = [get_parent() as Control]


func _process(_delta: float) -> void:
	update()


## Measures the bars and the keyboard now and lifts the targets (also run every frame).
func update() -> void:
	var simulated: bool = simulate_keyboard_height >= 0.0 or simulate_safe_area.x >= 0.0
	if not simulated and only_on_mobile and not OS.has_feature("mobile"):
		# a simulation just ended on a desktop: the targets reach the edges again
		if _applied:
			_applied = false
			_top = 0.0
			_bottom = 0.0
			_keyboard = 0.0
			for target: Control in targets:
				if is_instance_valid(target):
					target.offset_top = 0.0
					target.offset_bottom = 0.0
			insets_changed.emit(0.0, 0.0, 0.0)
		return
	var scale: float = _scale()
	if scale <= 0.0:
		return
	var top: float = 0.0
	var bottom: float = 0.0
	if simulate_safe_area.x >= 0.0:
		top = simulate_safe_area.x
		bottom = simulate_safe_area.y
	elif use_safe_area and not simulated:
		var win: Vector2i = DisplayServer.window_get_size()
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		if safe.size.x > 0 and safe.size.y > 0:
			top = maxf(0.0, float(safe.position.y)) / scale
			bottom = maxf(0.0, float(win.y - safe.end.y)) / scale
	var keyboard: float = 0.0
	if simulate_keyboard_height >= 0.0:
		keyboard = simulate_keyboard_height
	elif not simulated and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		keyboard = float(DisplayServer.virtual_keyboard_get_height()) / scale
	if keyboard > 0.0:
		_seen_ms = Time.get_ticks_msec()
	var keyboard_changed: bool = not is_equal_approx(keyboard, _keyboard)
	if _applied and not keyboard_changed and is_equal_approx(top, _top) and is_equal_approx(bottom, _bottom):
		return
	_top = top
	_bottom = bottom
	_keyboard = keyboard
	_applied = true
	for target: Control in targets:
		if is_instance_valid(target):
			target.offset_top = top
			target.offset_bottom = -maxf(bottom, keyboard)
	insets_changed.emit(top, bottom, keyboard)
	if keyboard_changed and keyboard > 0.0 and keep_focus_visible and is_inside_tree():
		get_tree().create_timer(focus_delay).timeout.connect(scroll_focus_into_view)


## The keyboard's height in the targets' units (0 when closed).
func get_keyboard_height() -> float:
	return _keyboard


## The safe-area insets at the top and the bottom (the status bar, the navigation bar).
func get_safe_insets() -> Vector2:
	return Vector2(_top, _bottom)


## How far the targets end above the screen's bottom edge: the navigation bar or the keyboard,
## whichever is taller.
func get_bottom_lift() -> float:
	return maxf(_bottom, _keyboard)


## The part of the navigation bar the keyboard does not cover (0 while the keyboard is open). A sheet
## that reaches the bottom edge keeps its content this far up.
func get_uncovered_bar() -> float:
	return maxf(0.0, _bottom - _keyboard)


## True while a text control has the focus and the keyboard is up (or was, a moment ago).
func is_keyboard_open() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused == null or not _is_text_control(focused):
		return false
	return _keyboard > 0.0 or Time.get_ticks_msec() - _seen_ms < open_grace_ms


## Scrolls the focused control into sight in its nearest ScrollContainer.
func scroll_focus_into_view() -> void:
	if not is_inside_tree():
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null:
		return
	var node: Node = focused.get_parent()
	while node != null:
		if node is ScrollContainer:
			(node as ScrollContainer).ensure_control_visible(focused)
			return
		node = node.get_parent()


func _is_text_control(control: Control) -> bool:
	return control is LineEdit or control is TextEdit or control.has_method(&"_get_caret_delegate")


# Screen pixels per logical pixel of the targets' viewport.
func _scale() -> float:
	if not is_inside_tree():
		return 0.0
	var viewport: Viewport = get_viewport()
	if not targets.is_empty() and is_instance_valid(targets[0]) and targets[0].is_inside_tree():
		viewport = targets[0].get_viewport()
	return viewport.get_final_transform().get_scale().y
