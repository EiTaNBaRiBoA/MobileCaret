# Shows draggable caret handles for the focused LineEdit/TextEdit.
#
#  * No selection: one handle under the caret. Dragging it moves the caret.
#  * Selection:    two handles (start/end). Dragging one moves that end of the selection;
#                  the handles may cross.
#  * Long-press on the text selects the word under the finger.
#
# Add the scene as an autoload (the plugin does this) and it works for every text control.
# The handles live on a high CanvasLayer and never take focus from the text control.
class_name carets_controller extends CanvasLayer

# Optional custom handle texture. Leave empty to draw the default teardrop.
@export var texture_caret: Texture2D
# Extra offset applied to the handles, in pixels.
@export var caret_texture_offset: Vector2 = Vector2.ZERO
# Touch size of a handle, in pixels.
@export var handle_size: Vector2 = Vector2(48.0, 56.0)
@export var handle_color: Color = Color(0.2, 0.5, 1.0)
# Extra pixels around a handle that still count as touching it.
@export var hit_margin: float = 8.0
# Seconds a press must be held (without moving) to select a word. 0 disables long-press.
@export var long_press_seconds: float = 0.5
# Hide Godot's own thin caret whenever a handle is showing (pure Android look).
@export var hide_native_caret: bool = false
# Hide Godot's own thin caret only while a handle is being dragged.
@export var hide_native_caret_while_dragging: bool = true
# Seconds without activity before the single caret handle fades out. 0 or less never fades it.
# Selection handles never fade. Any caret move, tap or drag brings the handle back.
@export var caret_fade_delay: float = 4.0
# Seconds the fade-out/fade-in takes.
@export var caret_fade_duration: float = 0.25

# How far (in pixels) a press may move and still count as a long-press.
const LONG_PRESS_TOLERANCE: float = 12.0

var _root: Control
var _handles: Array[caret_indicator] = []

var _adapter: caret_text_adapter = null
# The handle currently being dragged, if any.
var _drag_handle: caret_indicator = null
# True when the drag adjusts a selection; `_drag_anchor` is then the fixed end.
var _drag_has_anchor: bool = false
var _drag_anchor: Vector2i = Vector2i.ZERO
# Where the dragged handle's tip should be (viewport space).
var _drag_tip: Vector2 = Vector2.ZERO
# Pointer-to-tip offset at the start of the drag, so the handle doesn't jump under the finger.
var _drag_grab_offset: Vector2 = Vector2.ZERO

var _pressing: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _long_press_fired: bool = false
var _long_press_pos: Vector2i = Vector2i.ZERO

# Idle tracking for the caret handle fade.
var _idle_time: float = 0.0
var _caret_alpha: float = 1.0
var _last_caret: Vector2i = Vector2i.ZERO

# Saved state of the control's caret_color override while the native caret is hidden.
var _hidden_caret_control: Control = null
var _had_caret_override: bool = false
var _saved_caret_color: Color = Color.WHITE


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.name = "Handles"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.focus_mode = Control.FOCUS_NONE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	for i: int in 2:
		var handle: caret_indicator = caret_indicator.new()
		handle.name = "Handle%d" % (i + 1)
		_root.add_child(handle)
		_handles.append(handle)
	_apply_appearance()

	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_on_focus_changed(get_viewport().gui_get_focus_owner())


func _process(delta: float) -> void:
	if _adapter == null:
		return
	if not _adapter.is_valid() or not _adapter.control.is_visible_in_tree() or not _adapter.control.has_focus():
		_set_control(null)
		return
	_update_long_press(delta)
	if _drag_handle != null:
		_step_drag(delta)
	_update_fade(delta)
	_update_handles()
	_update_native_caret()


func _exit_tree() -> void:
	_set_native_caret_hidden(false)


# Re-applies texture/size/color, e.g. after changing the exported properties at runtime.
func _apply_appearance() -> void:
	for handle: caret_indicator in _handles:
		handle.texture = texture_caret
		handle.handle_color = handle_color
		handle.set_handle_size(handle_size)


#region Focus tracking

func _on_focus_changed(focused: Control) -> void:
	if focused == (_adapter.control if _adapter != null else null):
		return
	_set_control(focused)

func _set_control(new_control: Control) -> void:
	_set_native_caret_hidden(false)
	if _adapter != null and _adapter.is_valid():
		var old: Control = _adapter.control
		if old.gui_input.is_connected(_on_control_gui_input):
			old.gui_input.disconnect(_on_control_gui_input)
	_adapter = null
	_drag_handle = null
	_pressing = false
	_mark_active()
	_hide_handles()
	if not is_instance_valid(new_control):
		return
	_adapter = caret_text_adapter.for_control(new_control)
	if _adapter != null:
		new_control.gui_input.connect(_on_control_gui_input)
		_update_handles()

#endregion


#region Handle placement

func _hide_handles() -> void:
	for handle: caret_indicator in _handles:
		handle.hide()

func _update_handles() -> void:
	var first: caret_indicator = _handles[0]
	var second: caret_indicator = _handles[1]

	if _drag_handle != null:
		# While dragging, the dragged handle sits at the native caret and the other at the anchor.
		var other: caret_indicator = second if _drag_handle == first else first
		var caret: Vector2i = _adapter.get_caret()
		if _drag_has_anchor:
			var dragged_style: caret_indicator.Style = caret_indicator.Style.LEFT if _is_before(caret, _drag_anchor) else caret_indicator.Style.RIGHT
			var other_style: caret_indicator.Style = caret_indicator.Style.RIGHT if dragged_style == caret_indicator.Style.LEFT else caret_indicator.Style.LEFT
			_place(_drag_handle, caret, dragged_style, _smooth_drag_x())
			_place(other, _drag_anchor, other_style)
		else:
			_place(_drag_handle, caret, caret_indicator.Style.CARET, _smooth_drag_x())
			other.hide()
	elif _adapter.has_selection():
		_mark_active()
		_place(first, _adapter.get_selection_from(), caret_indicator.Style.LEFT)
		_place(second, _adapter.get_selection_to(), caret_indicator.Style.RIGHT)
	elif _adapter.is_empty():
		_hide_handles()
	else:
		_place(first, _adapter.get_caret(), caret_indicator.Style.CARET)
		second.hide()

# Positions a handle at a text position, hiding it if that position is scrolled out of view.
# `smooth_x` (viewport space, NaN for none) lets a dragged handle follow the finger
# horizontally while the caret itself snaps to characters, like Android.
func _place(handle: caret_indicator, pos: Vector2i, handle_style: caret_indicator.Style, smooth_x: float = NAN) -> void:
	if not _adapter.is_pos_visible(pos):
		handle.hide()
		return
	handle.style = handle_style
	# Text-control space -> viewport space (same space as the handle layer).
	var tip: Vector2 = _adapter.control.get_global_transform_with_canvas() * _adapter.get_tip_local(pos)
	tip += caret_texture_offset
	if not is_nan(smooth_x):
		tip.x = smooth_x
	handle.set_tip(tip)
	handle.modulate.a = _caret_alpha if handle_style == caret_indicator.Style.CARET else 1.0
	handle.show()

# Horizontal position of the dragged handle: the finger's x, kept inside the control.
func _smooth_drag_x() -> float:
	var bounds: Rect2 = _adapter.control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _adapter.control.size)
	return clampf(_drag_tip.x, bounds.position.x, bounds.end.x)

static func _is_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)

#endregion


#region Dragging

# Handles are hit-tested here instead of through the GUI: a press that reaches the GUI on
# a non-text control would make the text control lose focus (and its selection).
func _input(event: InputEvent) -> void:
	if _adapter == null:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			var handle: caret_indicator = _handle_at(button.position)
			if handle != null:
				_begin_drag(handle, button.position)
				get_viewport().set_input_as_handled()
		elif _drag_handle != null:
			_end_drag()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_handle != null:
		var motion: InputEventMouseMotion = event
		_drag_tip = motion.position + _drag_grab_offset
		get_viewport().set_input_as_handled()

# The visible handle under a viewport-space point (the closest one if both overlap).
func _handle_at(point: Vector2) -> caret_indicator:
	var best: caret_indicator = null
	var best_distance: float = INF
	for handle: caret_indicator in _handles:
		if handle.hits(point, hit_margin):
			var distance: float = handle.get_tip().distance_to(point)
			if distance < best_distance:
				best = handle
				best_distance = distance
	return best

func _begin_drag(handle: caret_indicator, pointer: Vector2) -> void:
	_drag_handle = handle
	_drag_grab_offset = handle.get_tip() - pointer
	_drag_tip = handle.get_tip()
	_pressing = false
	_drag_has_anchor = _adapter.has_selection()
	if _drag_has_anchor:
		# The end that is not being dragged stays fixed.
		_drag_anchor = _adapter.get_selection_to() if handle.style == caret_indicator.Style.LEFT else _adapter.get_selection_from()

func _end_drag() -> void:
	_drag_handle = null
	if _adapter != null:
		_update_handles()

# Applies the drag every frame, so edge-scrolling continues while the finger rests still.
func _step_drag(delta: float) -> void:
	var control: Control = _adapter.control
	# The tip is at the bottom of the caret; aim at the middle of that line.
	var to_local: Transform2D = control.get_global_transform_with_canvas().affine_inverse()
	var local: Vector2 = to_local * (_drag_tip - caret_texture_offset)
	local.y -= _adapter.get_line_height() * 0.5
	var target: Vector2i = _adapter.get_drag_target(local, _adapter.get_caret(), delta)
	if _drag_has_anchor:
		_adapter.select(_drag_anchor, target)
	else:
		_adapter.set_caret(target)

#endregion


#region Fade and native caret

func _mark_active() -> void:
	_idle_time = 0.0

# Fades the single caret handle out after `caret_fade_delay` seconds of inactivity.
func _update_fade(delta: float) -> void:
	var caret: Vector2i = _adapter.get_caret()
	if caret != _last_caret or _drag_handle != null or _adapter.has_selection():
		_mark_active()
	_last_caret = caret
	_idle_time += delta
	var faded: bool = caret_fade_delay > 0.0 and _idle_time >= caret_fade_delay
	_caret_alpha = move_toward(_caret_alpha, 0.0 if faded else 1.0, delta / maxf(caret_fade_duration, 0.001))

# True when at least one handle is visibly shown (not hidden and not faded out).
func _handles_showing() -> bool:
	for handle: caret_indicator in _handles:
		if handle.visible and handle.modulate.a > 0.5:
			return true
	return false

func _update_native_caret() -> void:
	var hide_it: bool = _handles_showing() and (hide_native_caret or (hide_native_caret_while_dragging and _drag_handle != null))
	_set_native_caret_hidden(hide_it)

# Makes the control's own caret transparent, remembering any existing override to restore it.
func _set_native_caret_hidden(hidden: bool) -> void:
	if hidden:
		if _hidden_caret_control != null or _adapter == null:
			return
		_hidden_caret_control = _adapter.control
		_had_caret_override = _hidden_caret_control.has_theme_color_override("caret_color")
		_saved_caret_color = _hidden_caret_control.get_theme_color("caret_color")
		var transparent: Color = _saved_caret_color
		transparent.a = 0.0
		_hidden_caret_control.add_theme_color_override("caret_color", transparent)
	elif _hidden_caret_control != null:
		if is_instance_valid(_hidden_caret_control):
			if _had_caret_override:
				_hidden_caret_control.add_theme_color_override("caret_color", _saved_caret_color)
			else:
				_hidden_caret_control.remove_theme_color_override("caret_color")
		_hidden_caret_control = null

#endregion


#region Long press

func _on_control_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if not button.pressed and _long_press_fired:
			# The control's own release handling (which runs after this signal) would
			# collapse the selection, so apply it again once that is done.
			_reapply_long_press_selection.call_deferred()
		_pressing = button.pressed
		_press_position = button.position
		_mark_active()
		if button.pressed:
			# Resolve the text position now: the control may scroll while the press is held.
			_long_press_pos = _adapter.get_pos_at_local(button.position)
		_press_time = 0.0
		_long_press_fired = false
	elif event is InputEventMouseMotion and _pressing:
		var motion: InputEventMouseMotion = event
		if motion.position.distance_to(_press_position) > LONG_PRESS_TOLERANCE:
			_pressing = false

func _update_long_press(delta: float) -> void:
	if not _pressing or _long_press_fired or long_press_seconds <= 0.0 or _drag_handle != null:
		return
	_press_time += delta
	if _press_time >= long_press_seconds:
		_long_press_fired = true
		_adapter.select_word_at(_long_press_pos)

func _reapply_long_press_selection() -> void:
	if _adapter != null and _adapter.is_valid() and _drag_handle == null:
		_adapter.select_word_at(_long_press_pos)

#endregion
