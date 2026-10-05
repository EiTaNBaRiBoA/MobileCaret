# Shows draggable caret handles for the focused LineEdit/TextEdit/CodeEdit.
#
#  * No selection: one handle under the caret. Dragging it moves the caret.
#  * Selection:    two handles (start/end). Dragging one moves that end of the selection;
#                  the handles may cross.
#  * Long-press on the text selects the word under the finger.
#  * A TextEdit with several carets gets handles for every caret.
#
# Add the scene as an autoload (the plugin does this) and it works for every text control, in the
# main window and in any other Window or SubViewport. The handles live on a high CanvasLayer inside
# the control's own viewport and never take focus from the text control.
class_name carets_controller extends CanvasLayer

# Emitted when a handle is tapped without being dragged. Optional listeners (such as the floating
# toolbar) can use it to show their UI; nothing depends on it.
signal handle_tapped(control: Control)

# Optional custom handle texture. Leave empty to draw the default teardrop.
@export var texture_caret: Texture2D
# Extra offset applied to the handles, in pixels.
@export var caret_texture_offset: Vector2 = Vector2.ZERO
# Physical size of a handle in millimeters. The handle keeps this size on screen whatever the
# resolution, aspect ratio, stretch mode or DPI, so it stays easy to grab. Set to (0, 0) to use
# `handle_size` (logical pixels) instead.
@export var handle_size_mm: Vector2 = Vector2(7.0, 8.0)
# Size of a handle in logical pixels. Used when `handle_size_mm` is (0, 0); otherwise it is
# only the reference that `hit_margin` is relative to.
@export var handle_size: Vector2 = Vector2(48.0, 56.0)
@export var handle_color: Color = Color(0.2, 0.5, 1.0)
# Extra pixels around a handle that still count as touching it (at `handle_size`; scaled together
# with the handle when `handle_size_mm` is used).
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

# How far a press may move and still count as a long-press (at `handle_size`; scaled with the handle).
const LONG_PRESS_TOLERANCE: float = 12.0
# The drag only takes effect once the pointer has moved this far (viewport pixels) from the press,
# so touching a handle without moving never changes the caret or starts edge-scrolling.
const DRAG_THRESHOLD: float = 6.0
# Longest frame time used for edge-scrolling, so one slow frame can't make the caret leap.
const MAX_DRAG_DELTA: float = 0.05
const HANDLES_LAYER_NAME: String = "MobileCaretHandles"


# The handles of one viewport. The main window's overlay is this node itself; other viewports
# get a caret_viewport_layer child that also receives their input.
class _Overlay extends RefCounted:
	var viewport: Viewport
	var layer: CanvasLayer
	var root: Control
	var handles: Array[caret_indicator] = []
	# Handle size (logical pixels of this viewport) and its factor relative to `handle_size`.
	var logical_size: Vector2 = Vector2.ZERO
	var ui_scale: float = 1.0


var _overlays: Dictionary = {}
var _active: _Overlay = null

var _adapter: caret_text_adapter = null
# The handle currently being dragged, the caret it belongs to, and whether the drag adjusts a
# selection (then `_drag_anchor` is the fixed end).
var _drag_handle: caret_indicator = null
var _drag_caret: int = 0
var _drag_has_anchor: bool = false
var _drag_anchor: Vector2i = Vector2i.ZERO
# Where the dragged handle's tip should be (viewport space).
var _drag_tip: Vector2 = Vector2.ZERO
var _drag_press_pointer: Vector2 = Vector2.ZERO
var _drag_moved: bool = false
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
var _last_carets: PackedInt32Array = PackedInt32Array()

# Saved state of the control's caret_color override while the native caret is hidden.
var _hidden_caret_control: Control = null
var _had_caret_override: bool = false
var _saved_caret_color: Color = Color.WHITE


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Lets optional companions (like the toolbar) find this controller wherever it is.
	add_to_group(&"mobile_caret_controller")

	var overlay: _Overlay = _Overlay.new()
	overlay.viewport = get_viewport()
	overlay.layer = self
	overlay.root = _make_handles_root()
	add_child(overlay.root)
	_overlays[get_viewport().get_instance_id()] = overlay
	_ensure_handles(overlay, 2)

	# Follow focus in every viewport: the main window, other Windows and SubViewports.
	var tracker: caret_focus_tracker = caret_focus_tracker.new()
	tracker.name = "FocusTracker"
	add_child(tracker)
	tracker.focus_changed.connect(_on_focus_changed)
	_on_focus_changed(get_viewport().gui_get_focus_owner())


func _process(delta: float) -> void:
	if _adapter == null:
		return
	if not _adapter.is_valid() or not _adapter.control.is_visible_in_tree() or not _adapter.control.has_focus():
		_set_control(null)
		return
	if _adapter.control.get_viewport() != _active.viewport:
		# The control moved to another viewport: continue there.
		_set_control(_adapter.control)
		if _adapter == null:
			return
	_update_appearance(_active)
	_adapter.ui_scale = _active.ui_scale
	_update_long_press(delta)
	if _drag_handle != null:
		_step_drag(delta)
	if _adapter == null:
		return
	_update_fade(delta)
	_update_handles()
	_update_native_caret()


func _exit_tree() -> void:
	_set_native_caret_hidden(false)


#region Overlays and viewports

func _make_handles_root() -> Control:
	var root: Control = Control.new()
	root.name = "Handles"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.focus_mode = Control.FOCUS_NONE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	return root

# The overlay for a viewport, created (inside that viewport) on first use.
func _overlay_for(viewport: Viewport) -> _Overlay:
	var id: int = viewport.get_instance_id()
	if _overlays.has(id):
		return _overlays[id]
	_purge_dead_overlays()
	var overlay: _Overlay = _Overlay.new()
	overlay.viewport = viewport
	var layer_node: caret_viewport_layer = caret_viewport_layer.get_or_create(viewport, HANDLES_LAYER_NAME, 128)
	overlay.layer = layer_node
	overlay.root = _make_handles_root()
	layer_node.add_child(overlay.root)
	layer_node.input_received.connect(_handle_input.bind(viewport))
	_overlays[id] = overlay
	_ensure_handles(overlay, 2)
	return overlay

# Forgets overlays whose viewport has been freed.
func _purge_dead_overlays() -> void:
	for key: Variant in _overlays.keys():
		if not is_instance_valid((_overlays[key] as _Overlay).viewport):
			_overlays.erase(key)

func _ensure_handles(overlay: _Overlay, count: int) -> void:
	while overlay.handles.size() < count:
		var handle: caret_indicator = caret_indicator.new()
		handle.name = "Handle%d" % (overlay.handles.size() + 1)
		overlay.root.add_child(handle)
		overlay.handles.append(handle)
		_apply_appearance(overlay, handle)

# Handle size in logical pixels of a viewport: either the configured physical size or the plain
# `handle_size`.
func _compute_handle_size(viewport: Viewport) -> Vector2:
	if handle_size_mm.x <= 0.0 or handle_size_mm.y <= 0.0:
		return handle_size
	var size_now: Vector2 = Vector2(caret_screen.mm_to_logical(viewport, handle_size_mm.x), caret_screen.mm_to_logical(viewport, handle_size_mm.y))
	return size_now.clamp(Vector2(16.0, 16.0), Vector2(400.0, 400.0))

func _apply_appearance(overlay: _Overlay, handle: caret_indicator) -> void:
	if overlay.logical_size == Vector2.ZERO:
		overlay.logical_size = _compute_handle_size(overlay.viewport)
		overlay.ui_scale = overlay.logical_size.x / maxf(handle_size.x, 1.0)
	handle.texture = texture_caret
	handle.handle_color = handle_color
	handle.set_handle_size(overlay.logical_size)

# Keeps texture, color and size of the handles in sync with the exported properties and the
# screen, so changes at runtime (or a resized window) take effect.
func _update_appearance(overlay: _Overlay) -> void:
	var size_now: Vector2 = _compute_handle_size(overlay.viewport)
	var stale: bool = not size_now.is_equal_approx(overlay.logical_size)
	if not stale and not overlay.handles.is_empty():
		stale = overlay.handles[0].texture != texture_caret or overlay.handles[0].handle_color != handle_color
	if not stale:
		return
	overlay.logical_size = size_now
	overlay.ui_scale = size_now.x / maxf(handle_size.x, 1.0)
	for handle: caret_indicator in overlay.handles:
		handle.texture = texture_caret
		handle.handle_color = handle_color
		handle.set_handle_size(size_now)

#endregion


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
	_active = null
	_drag_handle = null
	_pressing = false
	_mark_active()
	_hide_handles()
	if not is_instance_valid(new_control) or not new_control.is_inside_tree():
		return
	_adapter = caret_text_adapter.for_control(new_control)
	if _adapter != null:
		_active = _overlay_for(new_control.get_viewport())
		_update_appearance(_active)
		_adapter.ui_scale = _active.ui_scale
		new_control.gui_input.connect(_on_control_gui_input)
		_update_handles()

#endregion


#region Handle placement

func _hide_handles() -> void:
	for key: Variant in _overlays.keys():
		var overlay: _Overlay = _overlays[key]
		if not is_instance_valid(overlay.viewport):
			# Its viewport (and the handles in it) was freed.
			_overlays.erase(key)
			continue
		for handle: Variant in overlay.handles:
			if is_instance_valid(handle):
				(handle as caret_indicator).hide()

# Handles come in pairs per caret: [2k] is the caret / selection start, [2k+1] the selection end.
func _update_handles() -> void:
	var count: int = _adapter.get_caret_count()
	_ensure_handles(_active, count * 2)
	var handles: Array[caret_indicator] = _active.handles
	for index: int in handles.size():
		if index >= count * 2:
			handles[index].hide()
	for caret_index: int in count:
		var first: caret_indicator = handles[caret_index * 2]
		var second: caret_indicator = handles[caret_index * 2 + 1]
		if _drag_handle != null and _drag_caret == caret_index:
			# While dragging, the dragged handle sits at the native caret and its partner at the anchor.
			var other: caret_indicator = second if _drag_handle == first else first
			var caret: Vector2i = _adapter.get_caret(caret_index)
			if _drag_has_anchor:
				var dragged_style: caret_indicator.Style = _style_for(caret, _drag_anchor)
				_place(_drag_handle, caret, dragged_style, true)
				_place(other, _drag_anchor, _opposite(dragged_style))
			else:
				_place(_drag_handle, caret, caret_indicator.Style.CARET, true)
				other.hide()
		elif _adapter.has_selection(caret_index):
			_mark_active()
			var from: Vector2i = _adapter.get_selection_from(caret_index)
			var to: Vector2i = _adapter.get_selection_to(caret_index)
			var first_style: caret_indicator.Style = _style_for(from, to)
			_place(first, from, first_style)
			_place(second, to, _opposite(first_style))
		else:
			# Also for empty text: a tap in an empty field still shows the caret handle (and,
			# with the toolbar, Paste).
			_place(first, _adapter.get_caret(caret_index), caret_indicator.Style.CARET)
			second.hide()

# Positions a handle at a text position, hiding it if that position is scrolled out of view.
# A dragged handle (`dragging`) is never hidden: it follows the finger horizontally while the
# caret itself snaps to characters (like Android), and it stays inside the control vertically,
# following the finger while the caret row is scrolled or clipped at an edge.
func _place(handle: caret_indicator, pos: Vector2i, handle_style: caret_indicator.Style, dragging: bool = false) -> void:
	var pos_visible: bool = _adapter.is_pos_visible(pos)
	if not dragging and (not pos_visible or _adapter.is_pos_clipped(pos)):
		handle.hide()
		return
	handle.style = handle_style
	var tip: Vector2 = _drag_tip
	if pos_visible:
		# Text-control space -> viewport space (same space as the handle layer).
		tip = _adapter.control.get_global_transform_with_canvas() * _adapter.get_tip_local(pos)
		tip += caret_texture_offset
	if dragging:
		var bounds: Rect2 = _adapter.control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _adapter.control.size)
		# Follow the finger sideways, but never past the end of the text on this row (or the control).
		var to_viewport: Transform2D = _adapter.control.get_global_transform_with_canvas()
		var low: float = bounds.position.x
		var high: float = bounds.end.x
		if pos_visible:
			var row_y: float = _adapter.get_tip_local(pos).y - _adapter.get_line_height() * 0.5
			var extent: Vector2 = _adapter.get_row_x_extent(row_y)
			if not is_inf(extent.x):
				low = maxf(low, (to_viewport * Vector2(extent.x, row_y)).x + caret_texture_offset.x)
			if not is_inf(extent.y):
				high = minf(high, (to_viewport * Vector2(extent.y, row_y)).x + caret_texture_offset.x)
		tip.x = clampf(_drag_tip.x, minf(low, high), high)
		tip.y = clampf(tip.y, bounds.position.y + _adapter.get_line_height(), bounds.end.y)
	handle.set_tip(tip)
	handle.modulate.a = _caret_alpha if handle_style == caret_indicator.Style.CARET else 1.0
	handle.show()

# Style (left- or right-leaning) of the handle at `pos` whose partner is at `other`, by their
# order on screen (rows first), so it is right for right-to-left text as well.
func _style_for(pos: Vector2i, other: Vector2i) -> caret_indicator.Style:
	var to_viewport: Transform2D = _adapter.control.get_global_transform_with_canvas()
	var a: Vector2 = to_viewport * _adapter.get_tip_local(pos)
	var b: Vector2 = to_viewport * _adapter.get_tip_local(other)
	var row_gap: float = _adapter.get_line_height() * 0.5
	var before: bool
	if absf(a.y - b.y) > row_gap:
		before = a.y < b.y
	elif not is_equal_approx(a.x, b.x):
		before = a.x < b.x
	else:
		before = _is_before(pos, other)
	return caret_indicator.Style.LEFT if before else caret_indicator.Style.RIGHT

static func _opposite(handle_style: caret_indicator.Style) -> caret_indicator.Style:
	return caret_indicator.Style.RIGHT if handle_style == caret_indicator.Style.LEFT else caret_indicator.Style.LEFT

static func _is_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)

#endregion


#region Dragging

# The main window's input arrives here; other viewports forward theirs from their own layer.
func _input(event: InputEvent) -> void:
	_handle_input(event, get_viewport())

# Handles are hit-tested here instead of through the GUI: a press that reaches the GUI on
# a non-text control would make the text control lose focus (and its selection).
func _handle_input(event: InputEvent, event_viewport: Viewport) -> void:
	if _adapter == null or _active == null or event_viewport != _active.viewport:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			var handle: caret_indicator = _handle_at(button.position)
			if handle != null:
				_begin_drag(handle, button.position)
				event_viewport.set_input_as_handled()
		elif _drag_handle != null:
			_end_drag()
			event_viewport.set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_handle != null:
		var motion: InputEventMouseMotion = event
		_drag_tip = motion.position + _drag_grab_offset
		if not _drag_moved and motion.position.distance_to(_drag_press_pointer) > DRAG_THRESHOLD * _active.ui_scale:
			_drag_moved = true
		event_viewport.set_input_as_handled()

# The visible handle under a viewport-space point (the closest one if several overlap).
func _handle_at(point: Vector2) -> caret_indicator:
	var best: caret_indicator = null
	var best_distance: float = INF
	for handle: caret_indicator in _active.handles:
		if handle.hits(point, hit_margin * _active.ui_scale):
			var distance: float = handle.get_tip().distance_to(point)
			if distance < best_distance:
				best = handle
				best_distance = distance
	return best

func _begin_drag(handle: caret_indicator, pointer: Vector2) -> void:
	var index: int = _active.handles.find(handle)
	_drag_handle = handle
	_drag_caret = index / 2
	_drag_press_pointer = pointer
	_drag_moved = false
	_drag_grab_offset = handle.get_tip() - pointer
	_drag_tip = handle.get_tip()
	_pressing = false
	_drag_has_anchor = _adapter.has_selection(_drag_caret)
	if _drag_has_anchor:
		# The end that is not being dragged stays fixed: the first handle of a pair is the
		# selection start, the second one its end.
		_drag_anchor = _adapter.get_selection_to(_drag_caret) if index % 2 == 0 else _adapter.get_selection_from(_drag_caret)

func _end_drag() -> void:
	var tapped: bool = _drag_handle != null and not _drag_moved
	_drag_handle = null
	if _adapter != null:
		# Carets dragged onto each other become one.
		_adapter.merge_carets()
		_update_handles()
		if tapped:
			handle_tapped.emit(_adapter.control)

# Applies the drag every frame, so edge-scrolling continues while the finger rests still.
func _step_drag(delta: float) -> void:
	if not _drag_moved:
		return
	if _drag_caret >= _adapter.get_caret_count():
		# Carets merged while dragging.
		_drag_handle = null
		return
	delta = minf(delta, MAX_DRAG_DELTA)
	var control: Control = _adapter.control
	# The tip is at the bottom of the caret; aim at the middle of that line.
	var to_local: Transform2D = control.get_global_transform_with_canvas().affine_inverse()
	var local: Vector2 = to_local * (_drag_tip - caret_texture_offset)
	local.y -= _adapter.get_line_height() * 0.5
	var target: Vector2i = _adapter.get_drag_target(local, _adapter.get_caret(_drag_caret), delta)
	if _drag_has_anchor:
		_adapter.select(_drag_anchor, target, _drag_caret)
	else:
		_adapter.set_caret(target, _drag_caret)

#endregion


#region Fade and native caret

func _mark_active() -> void:
	_idle_time = 0.0

# Fades the single caret handle out after `caret_fade_delay` seconds of inactivity.
func _update_fade(delta: float) -> void:
	var carets: PackedInt32Array = PackedInt32Array()
	for i: int in _adapter.get_caret_count():
		var caret: Vector2i = _adapter.get_caret(i)
		carets.append(caret.x)
		carets.append(caret.y)
	if carets != _last_carets or _drag_handle != null or _adapter.has_any_selection():
		_mark_active()
	_last_carets = carets
	_idle_time += delta
	var faded: bool = caret_fade_delay > 0.0 and _idle_time >= caret_fade_delay
	_caret_alpha = move_toward(_caret_alpha, 0.0 if faded else 1.0, delta / maxf(caret_fade_duration, 0.001))

# True when at least one handle is visibly shown (not hidden and not faded out).
func _handles_showing() -> bool:
	for handle: caret_indicator in _active.handles:
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
		if motion.position.distance_to(_press_position) > LONG_PRESS_TOLERANCE * _active.ui_scale:
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
