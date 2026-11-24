# Floating Cut / Copy / Paste / Select all toolbar for the focused LineEdit, TextEdit, CodeEdit,
# selectable RichTextLabel or custom control (see caret_text_adapter), in the style of Android's
# text selection toolbar, with an overflow menu (Undo / Redo / Share).
#
# It is independent of the carets controller:
#  * Add it as an autoload (the plugin does) or as a node anywhere in the tree.
#  * Switch it on and off from code with `enabled`, or call `show_for_caret()` / `hide_toolbar()`.
#  * If a carets controller exists it also listens to its `handle_tapped` signal (tapping a handle
#    without dragging shows or re-shows the toolbar); without one everything else still works.
#  * It works for controls in the main window and in any other Window or SubViewport.
#
# Its buttons are hit-tested in `_input` instead of through the GUI: a press that reaches the GUI
# on a non-text control would make the text control lose focus (and its selection).
class_name caret_toolbar extends CanvasLayer

# Emitted after an action ran. `action` is "cut", "copy", "paste", "select_all", "undo", "redo"
# or "share".
signal action_pressed(action: StringName)
# Emitted when a custom item (see add_item) is pressed, with the control it was pressed for.
signal item_pressed(id: StringName, control: Control)
# Emitted by the Share button with the selected text. The toolbar cannot share by itself (that is
# platform specific); connect this to your share code. The button only shows when `show_share` is on.
signal share_requested(text: String)

const ACTION_CUT: StringName = &"cut"
const ACTION_COPY: StringName = &"copy"
const ACTION_PASTE: StringName = &"paste"
const ACTION_SELECT_ALL: StringName = &"select_all"
const ACTION_UNDO: StringName = &"undo"
const ACTION_REDO: StringName = &"redo"
const ACTION_SHARE: StringName = &"share"
const ACTION_DELETE: StringName = &"delete"
const ACTION_COPY_IMAGE: StringName = &"copy_image"
# Buttons that only open and close the overflow menu (no action_pressed signal).
const ITEM_MORE: StringName = &"more"
const ITEM_BACK: StringName = &"back"
# Buttons that move between the pages of a menu too long for the screen.
const ITEM_PAGE_NEXT: StringName = &"page_next"
const ITEM_PAGE_PREV: StringName = &"page_prev"
const PANEL_LAYER_NAME: String = "MobileCaretToolbar"
const CONTROLLER_GROUP: StringName = &"mobile_caret_controller"
# A press that moves less than this (in millimeters) and ends within TAP_SECONDS is a tap.
const TAP_MOVE_MM: float = 2.0
const TAP_SECONDS: float = 0.45
# Seconds between looks for a carets controller to link to.
const RELINK_INTERVAL: float = 0.5
# Seconds between looks at the system clipboard while the toolbar shows (for the Paste button). On
# a phone each look is a call to another process, too slow to make on every frame.
const CLIPBOARD_CHECK_SECONDS: float = 0.5

# Master switch. When false the toolbar is hidden and never shows.
@export var enabled: bool = true:
	set(value):
		enabled = value
		if not is_node_ready():
			return
		# Switching it off hides it; switching it back on starts from a clean state.
		_reset_interaction()
		_caret_mode = false
		_dismissed = false
		_overflow_open = false
		_stable_time = 0.0
		if not enabled:
			_hide_panels()

@export_group("Buttons")
@export var show_cut: bool = true
@export var show_copy: bool = true
@export var show_paste: bool = true
@export var show_select_all: bool = true
@export var text_cut: String = "Cut"
@export var text_copy: String = "Copy"
@export var text_paste: String = "Paste"
@export var text_select_all: String = "Select all"
## Delete: removes the selected text without copying it. Off by default (like Share).
@export var show_delete: bool = false
@export var text_delete: String = "Delete"
## Copy image, in the menu of an image (caret_image_menu), where the system clipboard can take an image.
@export var show_copy_image: bool = true
@export var text_copy_image: String = "Copy image"

@export_group("Overflow menu")
# The "more" button that opens Undo / Redo / Share.
@export var show_overflow: bool = true
@export var show_undo: bool = true
@export var show_redo: bool = true
# Off by default: the Share button does nothing until you connect `share_requested`.
@export var show_share: bool = false
@export var text_undo: String = "Undo"
@export var text_redo: String = "Redo"
@export var text_share: String = "Share"
@export var text_more: String = "···"
# Back to the menu above. Its own sign: ‹ and › move between the pages of a long menu.
@export var text_back: String = "↩"
@export var text_page_prev: String = "‹"
@export var text_page_next: String = "›"

@export_group("Look")
# Height of the bar in millimeters. Like the caret handles, it keeps this physical size on screen
# whatever the resolution, aspect ratio, stretch mode or DPI. A menu too long for the screen is a
# grid and pages instead (it only shrinks when a single button is wider than the viewport).
@export var height_mm: float = 7.5
# Gap between the toolbar and the selection, in millimeters.
@export var gap_mm: float = 2.0
# What a menu too wide for the window does. PAGES: it is laid out at full size, in rows of cells
# (up to submenu_rows or main_rows), and what still does not fit goes to further pages with ‹ and ›.
# SHRINK: it stays one row and the whole bar gets smaller (down to min_shrink).
enum TooWideMenu { PAGES, SHRINK }
@export var too_wide_menu: TooWideMenu = TooWideMenu.PAGES
# Rows a page of a submenu may take (PAGES). 1: pages of one row.
@export_range(1, 8) var submenu_rows: int = 2
# Rows a page of the main row and of the ··· menu may take (PAGES).
@export_range(1, 8) var main_rows: int = 1
# The smallest the bar gets (a share of its size) with SHRINK, and when a single button is wider
# than the window.
@export_range(0.1, 1.0) var min_shrink: float = 0.4
@export var background_color: Color = Color(0.13, 0.14, 0.17, 0.97)
@export var text_color: Color = Color.WHITE
@export var pressed_color: Color = Color(1.0, 1.0, 1.0, 0.18)

@export_group("Behavior")
# Seconds the selection must stay unchanged, with no mouse button held, before the toolbar shows.
# This keeps it out of the way while handles are being dragged.
@export var show_delay: float = 0.2
# Tapping inside an existing selection keeps the selection and shows or hides the toolbar (like
# Android). Turn it off to let such taps collapse the selection as usual.
@export var tap_selection_toggles_toolbar: bool = true

# The panel of the viewport that holds the focused control, and every panel by viewport.
var _panel: caret_toolbar_panel
var _panels: Dictionary = {}
var _adapter: caret_text_adapter = null
var _focused: Control = null
# State used to hide the toolbar when the selection/caret/text changes.
var _signature: String = ""
var _stable_time: float = 0.0
# True after show_for_caret(): the toolbar is shown for the bare caret (Paste / Select all).
var _caret_mode: bool = false
# Signature at the moment show_for_caret() was called.
var _caret_signature: String = ""
# Set after Copy (or a tap on the selection): hidden until the selection changes.
var _dismissed: bool = false
# True while the overflow menu (Undo / Redo / Share) replaces the main buttons.
var _overflow_open: bool = false
var _pressed_action: StringName = &""
var _linked_controller: Node = null
var _relink_wait: float = 0.0
# Whether a mouse button is down in a viewport other than the main window (Input only knows
# about the main one).
var _viewport_pressed: bool = false
# What the panel was last laid out for: bar height and available width (to re-fit on change).
var _built_bar: float = 0.0
var _built_available: float = 0.0
var _built_layout: String = ""
# A possible tap on the selection: where it started, when, and the selection to keep.
var _tap_start: Vector2 = Vector2.ZERO
var _tap_time: int = 0
var _tap_active: bool = false
var _tap_selection: Array[Vector2i] = []
var _tap_caret: int = 0
# Whether the toolbar was showing when the press started (it hides while the mouse is down).
var _tap_was_showing: bool = false
# For a selectable label the press is held back (it would start a new selection); it is replayed
# if the gesture turns out to be a drag.
var _tap_swallowed: bool = false
var _tap_event: InputEventMouseButton = null
var _replaying: bool = false
# Custom items added with add_item(), and the open submenus: the ids from the main row down to
# the one shown (empty when the main row shows). A submenu's items may open submenus too.
var _custom_items: Array[Dictionary] = []
var _submenu_path: Array[StringName] = []
# The page shown of a menu too long for the screen, and the menu it belongs to.
var _page: int = 0
var _page_key: String = ""
# Whether the system clipboard has text, as last read (see _clipboard_has), and how long ago.
var _clipboard_known: bool = false
var _clipboard_full: bool = false
var _clipboard_age: float = 0.0
# How many times the system clipboard was read (for the tests).
var _clipboard_reads: int = 0


func _ready() -> void:
	layer = 129
	# Taps on the toolbar keep the text control's focus (see the carets controller).
	add_to_group(&"mobile_caret_overlay")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = _make_panel()
	add_child(_panel)
	_panels[get_viewport().get_instance_id()] = _panel
	var tracker: caret_focus_tracker = caret_focus_tracker.new()
	tracker.name = "FocusTracker"
	add_child(tracker)
	tracker.focus_changed.connect(_on_focus_changed)
	_on_focus_changed(get_viewport().gui_get_focus_owner())


func _process(delta: float) -> void:
	_try_connect_controller(delta)
	if not enabled:
		_hide_panels()
		return
	_validate_focus()
	if _adapter == null:
		_hide_panels()
		return
	# Follow the control if it moved to another viewport.
	var panel: caret_toolbar_panel = _panel_for(_adapter.control.get_viewport())
	if panel != _panel:
		_hide_panels()
		_panel = panel

	# Anything that changes the selection, the caret or the text restarts the delay.
	var signature: String = _make_signature()
	if signature != _signature:
		_signature = signature
		_stable_time = 0.0
		_dismissed = false
		_overflow_open = false
		_submenu_path.clear()
		# The bare-caret toolbar goes away as soon as the caret moves or the text changes.
		if _caret_mode and signature != _caret_signature:
			_caret_mode = false
	_stable_time += delta
	if _is_pointer_down() and _pressed_action == &"":
		_stable_time = 0.0

	var wanted: bool = (_adapter.has_any_selection() or _caret_mode) and not _dismissed and _stable_time >= show_delay and _adapter.menu_enabled()
	if not wanted:
		# Read the clipboard afresh the next time the toolbar shows.
		_clipboard_known = false
		_hide_panels()
		return
	_clipboard_age += delta
	if not _rebuild_items():
		_hide_panels()
		return
	_place()


#region Public API

# Shows the toolbar at the caret of the focused control (Paste / Select all), for example after
# the user taps the caret handle. It hides again as soon as the caret moves or text changes.
func show_for_caret() -> void:
	if not enabled or _adapter == null:
		return
	_validate_focus()
	if _adapter == null or not _adapter.supports_handles():
		return
	_caret_mode = true
	_dismissed = false
	_signature = _make_signature()
	_caret_signature = _signature
	_stable_time = show_delay

# The menu of one control. Settings are kept on the control (caret_menu_settings), so they work for
# any control and go away with it.

# Shows (true) or never shows (false) the menu for this control.
func set_control_menu(control: Control, enabled: bool) -> void:
	caret_menu_settings.set_menu_enabled(control, enabled)

func is_control_menu_enabled(control: Control) -> bool:
	return caret_menu_settings.is_menu_enabled(control)

# The built-in buttons this control may have, for example [&"copy"] for a read-only note, or
# [&"copy", &"cut", &"delete"]: cut, copy, paste, select_all, delete, undo, redo, share. Cut, Paste
# and Delete still need text that can be edited, and the toolbar's own show_* switches still apply.
func set_control_actions(control: Control, actions: Array) -> void:
	caret_menu_settings.set_actions(control, actions)

# The buttons set for this control; empty when none are set (it may have all of them).
func get_control_actions(control: Control) -> Array:
	return caret_menu_settings.get_actions(control)

# Back to the defaults for this control: menu on, every button.
func clear_control_settings(control: Control) -> void:
	caret_menu_settings.clear(control)

# Hides the toolbar until the selection or caret changes.
func hide_toolbar() -> void:
	_caret_mode = false
	_overflow_open = false
	_hide_panels()
	_dismissed = true

func is_showing() -> bool:
	return _panel != null and _panel.visible

# Adds a button for every control.
#  * `index`: its place in the main row, 0 being the leftmost (the built-in buttons move right);
#    -1 puts it last, before the ··· button. Items with the same index keep the order they were
#    added in.
#  * `callback`: called with the focused control when the button is pressed (item_pressed is
#    emitted too).
#  * `children`: Dictionaries of the same kind ({"id", "text", "callback", "items", ...}); the
#    button then opens them as a submenu with a ‹ button to go back.
#  * `when`: "always", "selection" (only with a selection) or "caret" (only without one).
#  * `font` / `icon`: an optional Font for the label and a Texture2D icon.
# Adding an id again replaces the old item.
func add_item(id: StringName, text: String, index: int = -1, callback: Callable = Callable(), children: Array = [], when: String = "always", font: Font = null, icon: Texture2D = null) -> void:
	add_item_spec({"id": id, "text": text, "index": index, "callback": callback, "items": children, "when": when, "font": font, "icon": icon})

# Same as add_item() with the fields in one Dictionary.
func add_item_spec(spec: Dictionary) -> void:
	remove_item(StringName(spec.get("id", &"")))
	_custom_items.append(spec)

func remove_item(id: StringName) -> void:
	for i: int in range(_custom_items.size() - 1, -1, -1):
		if StringName(_custom_items[i].get("id", &"")) == id:
			_custom_items.remove_at(i)

func clear_items() -> void:
	_custom_items.clear()
	_submenu_path.clear()

# The custom items added with add_item().
func get_items() -> Array[Dictionary]:
	return _custom_items.duplicate()

# Opens the submenu of a custom item (as if it was pressed), one level deeper than the one shown.
# &"" closes all submenus.
func open_submenu(id: StringName) -> void:
	if id == &"":
		_submenu_path.clear()
	else:
		_submenu_path.append(id)
	_overflow_open = false

# The ids of the open submenus, from the main row down (empty when none is open).
func get_open_submenus() -> Array[StringName]:
	return _submenu_path.duplicate()

# Rectangle (viewport space) of one button, or an empty Rect2 if it is not shown.
func get_button_rect(action: StringName) -> Rect2:
	if not is_showing():
		return Rect2()
	for item: Dictionary in _panel.items:
		if item["id"] == action:
			return _panel.get_global_transform() * (item["rect"] as Rect2)
	return Rect2()

# Whether the toolbar is shown over a viewport-space point of `viewport`.
func covers_point(point: Vector2, viewport: Viewport) -> bool:
	var found: Variant = _panels.get(viewport.get_instance_id())
	if not is_instance_valid(found):
		return false
	var panel: caret_toolbar_panel = found as caret_toolbar_panel
	if panel == null or not panel.visible:
		return false
	return (panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.size)).has_point(point)

# Rectangle (viewport space) of the whole toolbar, or an empty Rect2 if hidden.
func get_toolbar_rect() -> Rect2:
	if not is_showing():
		return Rect2()
	return Rect2(_panel.global_position, _panel.size)

#endregion


#region Panels, focus and state

func _make_panel() -> caret_toolbar_panel:
	var panel: caret_toolbar_panel = caret_toolbar_panel.new()
	panel.name = "Panel"
	panel.hide()
	return panel

# The panel that lives in `viewport` (created, with a layer that receives that viewport's input,
# on first use).
func _panel_for(viewport: Viewport) -> caret_toolbar_panel:
	var id: int = viewport.get_instance_id()
	if _panels.has(id) and is_instance_valid(_panels[id]):
		return _panels[id] as caret_toolbar_panel
	var layer_node: caret_viewport_layer = caret_viewport_layer.get_or_create(viewport, PANEL_LAYER_NAME, 129)
	var panel: caret_toolbar_panel = _make_panel()
	layer_node.add_child(panel)
	layer_node.input_received.connect(_handle_input.bind(viewport))
	_panels[id] = panel
	return panel

# Hides every panel. A button that was held down is released, since its panel is gone.
func _hide_panels() -> void:
	_pressed_action = &""
	for key: Variant in _panels.keys():
		var panel: Variant = _panels[key]
		if is_instance_valid(panel):
			(panel as caret_toolbar_panel).hide()
			(panel as caret_toolbar_panel).pressed_index = -1
		else:
			# Its viewport was freed.
			_panels.erase(key)

# Forgets any press/tap in progress (when the toolbar is switched off or its control changes).
func _reset_interaction() -> void:
	_pressed_action = &""
	_tap_active = false
	_tap_swallowed = false
	_tap_event = null
	_viewport_pressed = false

func _on_focus_changed(control: Control) -> void:
	_focused = control

# Keeps the adapter in step with the focused control (and drops it when that is hidden or gone,
# or stops being usable, e.g. a label that is no longer selectable).
func _validate_focus() -> void:
	var current: Control = _adapter.control if _adapter != null and _adapter.is_valid() else null
	var target: Control = _focused if is_instance_valid(_focused) and _focused.is_visible_in_tree() and _focused.has_focus() else null
	if target == current and (_adapter == null or (_adapter.is_valid() and _adapter.is_usable())):
		return
	_clear_adapter()
	if target != null:
		_adapter = caret_text_adapter.for_toolbar(target)

func _clear_adapter() -> void:
	_adapter = null
	_submenu_path.clear()
	_caret_mode = false
	_dismissed = false
	_overflow_open = false
	_signature = ""
	_reset_interaction()
	_hide_panels()

func _make_signature() -> String:
	# Something that changes whenever the text does.
	var version: int = _adapter.get_text_version()
	if _adapter.has_any_selection():
		var index: int = maxi(_adapter.get_selection_caret(), 0)
		return "s%s-%s-%d-%d" % [str(_adapter.get_selection_from(index)), str(_adapter.get_selection_to(index)), version, _adapter.get_caret_count()]
	return "c%s-%d-%d" % [str(_adapter.get_caret()), version, _adapter.get_caret_count()]

func _is_pointer_down() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _viewport_pressed

# Links to a carets controller (found through its group, wherever it is in the tree) so that
# tapping a handle shows the toolbar. Looks again if the controller goes away or is replaced.
func _try_connect_controller(delta: float) -> void:
	if is_instance_valid(_linked_controller):
		return
	_linked_controller = null
	_relink_wait -= delta
	if _relink_wait > 0.0:
		return
	_relink_wait = RELINK_INTERVAL
	for node: Node in get_tree().get_nodes_in_group(CONTROLLER_GROUP):
		if node != self and node.has_signal(&"handle_tapped"):
			node.connect(&"handle_tapped", _on_handle_tapped)
			_linked_controller = node
			return

# How far the selection handles reach below a caret, in logical pixels: asked from the linked
# controller, or 9 mm (room for a large handle) when there is none.
func _handle_reach(viewport: Viewport) -> float:
	if is_instance_valid(_linked_controller) and _linked_controller.has_method(&"get_handle_reach"):
		return float(_linked_controller.call(&"get_handle_reach", viewport))
	return caret_screen.mm_to_logical(viewport, 9.0)

func _on_handle_tapped(control: Control) -> void:
	if not enabled or _adapter == null or control != _adapter.control:
		return
	if _adapter.has_any_selection():
		_dismissed = false
		_stable_time = show_delay
	else:
		show_for_caret()

#endregion


#region Buttons and placement

func _is_everything_selected() -> bool:
	return _adapter.has_any_selection() and _adapter.is_everything_selected()

func _entry(id: StringName, text: String) -> Dictionary:
	return {"id": id, "text": text, "rect": Rect2()}

func _custom_entry(spec: Dictionary) -> Dictionary:
	var entry: Dictionary = _entry(StringName(spec.get("id", &"")), str(spec.get("text", "")))
	entry["font"] = spec.get("font")
	entry["icon"] = spec.get("icon")
	entry["custom"] = true
	return entry

# The custom items that apply now: the toolbar's own and the focused control's.
func _custom_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var has_selection: bool = _adapter.has_any_selection()
	var all: Array = []
	all.append_array(_custom_items)
	all.append_array(_adapter.get_toolbar_items())
	for spec: Variant in all:
		if not (spec is Dictionary):
			continue
		var when: String = str((spec as Dictionary).get("when", "always"))
		if (when == "selection" and not has_selection) or (when == "caret" and has_selection):
			continue
		specs.append(spec as Dictionary)
	return specs

# A custom item by id, searched through the submenus too.
static func _find_spec(id: StringName, specs: Array) -> Dictionary:
	for spec: Variant in specs:
		if not (spec is Dictionary):
			continue
		if StringName((spec as Dictionary).get("id", &"")) == id:
			return spec as Dictionary
		var found: Dictionary = _find_spec(id, (spec as Dictionary).get("items", []) as Array)
		if not found.is_empty():
			return found
	return {}

# The buttons of the main row and the overflow menu that apply right now.
func _build_entries() -> Array[Dictionary]:
	# The engine refuses to copy or cut a password field, so nothing here may leak its text.
	var secret: bool = _adapter.is_secret()
	var has_selection: bool = _adapter.has_any_selection()
	var copyable: bool = has_selection and not secret
	var editable: bool = _adapter.is_text_editable()
	var main_row: Array[Dictionary] = []
	# the control's own settings come on top of the toolbar's switches (set_control_actions)
	var allows: Callable = _adapter.allows_action
	if show_copy_image and _adapter.can_copy_image() and allows.call(ACTION_COPY_IMAGE):
		main_row.append(_entry(ACTION_COPY_IMAGE, text_copy_image))
	if show_cut and copyable and editable and allows.call(ACTION_CUT):
		main_row.append(_entry(ACTION_CUT, text_cut))
	if show_delete and has_selection and editable and _adapter.can_delete() and allows.call(ACTION_DELETE):
		main_row.append(_entry(ACTION_DELETE, text_delete))
	if show_copy and copyable and allows.call(ACTION_COPY):
		main_row.append(_entry(ACTION_COPY, text_copy))
	if show_paste and editable and allows.call(ACTION_PASTE) and _clipboard_has():
		main_row.append(_entry(ACTION_PASTE, text_paste))
	if show_select_all and not _adapter.is_empty() and not _is_everything_selected() and allows.call(ACTION_SELECT_ALL):
		main_row.append(_entry(ACTION_SELECT_ALL, text_select_all))

	var overflow: Array[Dictionary] = []
	if show_overflow:
		if editable and show_undo and _adapter.has_undo() and allows.call(ACTION_UNDO):
			overflow.append(_entry(ACTION_UNDO, text_undo))
		if editable and show_redo and _adapter.has_redo() and allows.call(ACTION_REDO):
			overflow.append(_entry(ACTION_REDO, text_redo))
		if show_share and copyable and allows.call(ACTION_SHARE):
			overflow.append(_entry(ACTION_SHARE, text_share))

	var specs: Array[Dictionary] = _custom_specs()
	if not _submenu_path.is_empty():
		var open: Dictionary = _find_spec(_submenu_path[_submenu_path.size() - 1], specs)
		var children: Array = open.get("items", []) as Array
		if not children.is_empty():
			var page: Array[Dictionary] = [_entry(ITEM_BACK, text_back)]
			for child: Variant in children:
				if child is Dictionary:
					page.append(_custom_entry(child as Dictionary))
			return page
		_submenu_path.clear()

	if _overflow_open and not overflow.is_empty():
		var menu: Array[Dictionary] = [_entry(ITEM_BACK, text_back)]
		menu.append_array(overflow)
		return menu
	_overflow_open = false
	# Custom items go to their index (0 = leftmost), lowest index first.
	var ordered: Array[Dictionary] = specs.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _sort_index(a) < _sort_index(b))
	var last: Array[Dictionary] = []
	for spec: Dictionary in ordered:
		var index: int = int(spec.get("index", -1))
		if index < 0:
			last.append(_custom_entry(spec))
		else:
			main_row.insert(mini(index, main_row.size()), _custom_entry(spec))
	main_row.append_array(last)
	if not overflow.is_empty():
		main_row.append(_entry(ITEM_MORE, text_more))
	return main_row

# Whether the system clipboard has text: read when the toolbar shows, then at most every
# CLIPBOARD_CHECK_SECONDS (so text copied in another app shows Paste within that time).
func _clipboard_has() -> bool:
	if not _clipboard_known or _clipboard_age >= CLIPBOARD_CHECK_SECONDS:
		_clipboard_full = DisplayServer.clipboard_has()
		_clipboard_known = true
		_clipboard_age = 0.0
		_clipboard_reads += 1
	return _clipboard_full

static func _sort_index(spec: Dictionary) -> int:
	var index: int = int(spec.get("index", -1))
	return index if index >= 0 else 1 << 30

# Builds the list of buttons that apply right now. Returns false if there are none.
func _rebuild_items() -> bool:
	var entries: Array[Dictionary] = _build_entries()
	if entries.is_empty():
		return false
	var viewport: Viewport = _adapter.control.get_viewport()
	var desired_bar: float = caret_screen.mm_to_logical(viewport, height_mm)
	var available: float = viewport.get_visible_rect().size.x - 2.0 * caret_screen.mm_to_logical(viewport, gap_mm)
	# Colors can change at any time.
	_panel.background_color = background_color
	_panel.text_color = text_color
	_panel.pressed_color = pressed_color
	# Full size: a menu that does not fit is laid out in rows and pages (_page_of), unless the
	# too_wide_menu setting asks for the smaller bar.
	_panel.bar_height = desired_bar
	_panel.font_size = maxi(int(desired_bar * 0.42), 8)
	var rows: int = _rows_allowed()
	entries = _page_of(entries, available, rows)
	var layout: String = "%d/%d/%.3f" % [too_wide_menu, rows, min_shrink]
	# Only rebuild (and re-measure) when the buttons, the sizes or the layout settings changed.
	var same: bool = _panel.items.size() == entries.size() and is_equal_approx(_built_bar, desired_bar) and is_equal_approx(_built_available, available) and layout == _built_layout
	if same:
		for i: int in entries.size():
			if _panel.items[i]["id"] != entries[i]["id"] or _panel.items[i]["text"] != entries[i]["text"]:
				same = false
				break
	if not same:
		_built_bar = desired_bar
		_built_available = available
		_built_layout = layout
		# A page allowed more than one row that does not fit in one is a grid (caret_toolbar_panel).
		_panel.max_width = available if rows > 1 else 0.0
		_panel.set_items(entries)
		# Shrink: with SHRINK, or when a single button is wider than the viewport (a tiny window).
		if available > 0.0 and _panel.size.x > available:
			var factor: float = maxf(available / _panel.size.x, min_shrink)
			_panel.bar_height = desired_bar * factor
			_panel.font_size = maxi(int(desired_bar * factor * 0.42), 6)
			_panel.relayout()
	return true

# The buttons of the page shown now. A submenu takes up to submenu_rows rows of cells (a grid), the
# main row and the ··· menu up to main_rows (one row by default). What does not fit goes to further
# pages, with ‹ and › to move between them, and back stays first on every page. Nothing is cut off
# by the screen's edge, and nothing gets smaller: only a single button wider than the screen still
# shrinks the bar (and every menu does with too_wide_menu SHRINK).
# Rows a page of the menu shown now may take (PAGES; 1 with SHRINK).
func _rows_allowed() -> int:
	if too_wide_menu == TooWideMenu.SHRINK:
		return 1
	return maxi(1, submenu_rows if not _submenu_path.is_empty() else main_rows)

func _page_of(entries: Array[Dictionary], available: float, rows: int) -> Array[Dictionary]:
	var key: String = str(_submenu_path) + ("+more" if _overflow_open else "")
	if key != _page_key:
		_page_key = key
		_page = 0
	if available <= 0.0 or too_wide_menu == TooWideMenu.SHRINK:
		return entries
	var fixed: Array[Dictionary] = []
	var rest: Array[Dictionary] = entries.duplicate()
	if not rest.is_empty() and rest[0]["id"] == ITEM_BACK:
		fixed.append(rest.pop_front())
	var prev: Dictionary = _entry(ITEM_PAGE_PREV, text_page_prev)
	var next: Dictionary = _entry(ITEM_PAGE_NEXT, text_page_next)
	var pages: Array = []
	if rows > 1:
		# Cells of one width, as many across as fit, `rows` rows a page.
		var cell: float = maxf(_panel.cell_width(prev), _panel.cell_width(next))
		for entry: Dictionary in entries:
			cell = maxf(cell, _panel.cell_width(entry))
		var capacity: int = maxi(1, int(available / cell)) * rows
		if entries.size() <= capacity:
			return entries
		var i: int = 0
		while i < rest.size():
			var slots: int = capacity - fixed.size() - (1 if not pages.is_empty() else 0)
			var take: int = slots if rest.size() - i <= slots else slots - 1
			take = maxi(1, take)
			pages.append(rest.slice(i, i + take))
			i += take
	else:
		var total: float = 0.0
		for entry: Dictionary in entries:
			total += _panel.button_width(entry)
		if total <= available:
			return entries
		# One row a page, filled by the buttons' own widths.
		var fixed_width: float = 0.0
		for entry: Dictionary in fixed:
			fixed_width += _panel.button_width(entry)
		var i: int = 0
		while i < rest.size():
			var room: float = available - fixed_width - (_panel.button_width(prev) if not pages.is_empty() else 0.0)
			var page: Array[Dictionary] = []
			var used: float = 0.0
			while i < rest.size():
				var width: float = _panel.button_width(rest[i])
				var reserve: float = _panel.button_width(next) if i + 1 < rest.size() else 0.0
				if not page.is_empty() and used + width + reserve > room:
					break
				page.append(rest[i])
				used += width
				i += 1
			pages.append(page)
	_page = clampi(_page, 0, pages.size() - 1)
	var shown: Array[Dictionary] = fixed.duplicate()
	if _page > 0:
		shown.append(prev)
	for entry: Dictionary in pages[_page]:
		shown.append(entry)
	if _page < pages.size() - 1:
		shown.append(next)
	return shown

# Positions the toolbar above the selection (or caret), below it when there is no room above.
func _place() -> void:
	var control: Control = _adapter.control
	var viewport: Viewport = control.get_viewport()
	var to_viewport: Transform2D = control.get_global_transform_with_canvas()
	var caret_index: int = maxi(_adapter.get_selection_caret(), 0)
	var from_pos: Vector2i = _adapter.get_selection_from(caret_index) if _adapter.has_any_selection() else _adapter.get_caret()
	var to_pos: Vector2i = _adapter.get_selection_to(caret_index) if _adapter.has_any_selection() else from_pos
	# A position that is scrolled out of view, or clipped by a scroll container, doesn't count.
	var from_visible: bool = _adapter.is_pos_visible(from_pos) and not _adapter.is_pos_clipped(from_pos)
	var to_visible: bool = _adapter.is_pos_visible(to_pos) and not _adapter.is_pos_clipped(to_pos)
	if not from_visible and not to_visible:
		_hide_panels()
		return
	if not from_visible:
		from_pos = to_pos
	if not to_visible:
		to_pos = from_pos
	var line_height: float = to_viewport.basis_xform(Vector2(0.0, _adapter.get_line_height())).y
	var from_tip: Vector2 = to_viewport * _adapter.get_tip_local(from_pos)
	var to_tip: Vector2 = to_viewport * _adapter.get_tip_local(to_pos)
	var gap: float = caret_screen.mm_to_logical(viewport, gap_mm)
	var bounds: Rect2 = viewport.get_visible_rect()
	var panel_size: Vector2 = _panel.size

	var center_x: float = (from_tip.x + to_tip.x) * 0.5
	if absf(from_tip.y - to_tip.y) > line_height * 0.5:
		# A selection over several rows: center on the control instead.
		center_x = (to_viewport * Vector2(control.size.x * 0.5, 0.0)).x
	var top: float = from_tip.y - line_height - gap - panel_size.y
	if top < bounds.position.y + gap:
		# No room above: go below the selection, clear of the selection handles and their grab area.
		top = to_tip.y + _handle_reach(viewport) + gap
	var left: float = clampf(center_x - panel_size.x * 0.5, bounds.position.x + gap, maxf(bounds.end.x - panel_size.x - gap, bounds.position.x + gap))
	top = clampf(top, bounds.position.y + gap, maxf(bounds.end.y - panel_size.y - gap, bounds.position.y + gap))
	_panel.global_position = Vector2(left, top)
	_panel.show()

#endregion


#region Input and actions

# The main window's input arrives here; other viewports forward theirs from their own layer.
func _input(event: InputEvent) -> void:
	_handle_input(event, get_viewport())

func _handle_input(event: InputEvent, event_viewport: Viewport) -> void:
	# Input only knows about the main window's mouse, so remember presses in other viewports.
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and event_viewport != get_viewport():
		_viewport_pressed = (event as InputEventMouseButton).pressed
	if _replaying or _adapter == null or not enabled:
		return
	if event_viewport != _adapter.control.get_viewport():
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if _handle_toolbar_input(event, event_viewport):
		return
	_handle_selection_tap(event, event_viewport)

# Presses and releases on the toolbar's buttons. Returns true if the event was consumed.
func _handle_toolbar_input(event: InputEvent, event_viewport: Viewport) -> bool:
	if _panel == null or not _panel.visible or not (event is InputEventMouseButton):
		return false
	var button: InputEventMouseButton = event
	if button.button_index != MOUSE_BUTTON_LEFT:
		return false
	var local: Vector2 = _panel.get_global_transform().affine_inverse() * button.position
	var index: int = _panel.item_at(local)
	if button.pressed:
		if index >= 0:
			_pressed_action = _panel.items[index]["id"]
			_panel.pressed_index = index
			event_viewport.set_input_as_handled()
			return true
	elif _pressed_action != &"":
		var action: StringName = _pressed_action
		_pressed_action = &""
		_panel.pressed_index = -1
		event_viewport.set_input_as_handled()
		if index >= 0 and _panel.items[index]["id"] == action:
			_perform(action)
		return true
	return false

# A short tap inside an existing selection keeps the selection and shows or hides the toolbar.
func _handle_selection_tap(event: InputEvent, event_viewport: Viewport) -> void:
	if not tap_selection_toggles_toolbar:
		return
	var move_limit: float = caret_screen.mm_to_logical(event_viewport, TAP_MOVE_MM)
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button: InputEventMouseButton = event
		if button.pressed:
			_tap_active = false
			# A double click is meant to select a word, not to toggle the toolbar.
			if not button.double_click and _adapter.has_any_selection() and _is_inside_selection(button.position):
				_tap_active = true
				_tap_was_showing = is_showing()
				_tap_start = button.position
				_tap_time = Time.get_ticks_msec()
				_tap_caret = maxi(_adapter.get_selection_caret(), 0)
				_tap_selection = [_adapter.get_selection_from(_tap_caret), _adapter.get_selection_to(_tap_caret)]
				# A selectable label starts a new selection on press, so the press is held back
				# (and replayed if this turns out to be a drag). The other controls only collapse
				# the selection on release, which is undone afterwards.
				_tap_swallowed = not _adapter.supports_handles()
				if _tap_swallowed:
					_tap_event = button.duplicate() as InputEventMouseButton
					event_viewport.set_input_as_handled()
		elif _tap_active:
			_tap_active = false
			if _tap_swallowed:
				# The label never saw the press, so it must not see the release either.
				event_viewport.set_input_as_handled()
				_toggle_for_tap()
			elif Time.get_ticks_msec() - _tap_time <= int(TAP_SECONDS * 1000.0) and button.position.distance_to(_tap_start) <= move_limit:
				_restore_selection.call_deferred(_tap_selection[0], _tap_selection[1], _tap_caret)
				_toggle_for_tap()
	elif event is InputEventMouseMotion and _tap_active:
		if (event as InputEventMouseMotion).position.distance_to(_tap_start) > move_limit:
			_tap_active = false
			if _tap_swallowed and _tap_event != null:
				# Not a tap but a drag that started inside the selection: let the label have its press.
				_replay_press.call_deferred(event_viewport, _tap_event)

func _replay_press(viewport: Viewport, press: InputEventMouseButton) -> void:
	if not is_instance_valid(viewport):
		return
	_replaying = true
	viewport.push_input(press, true)
	_replaying = false

# The control's own release handling collapses the selection; put it back. The collapse and
# the restore both look like selection changes, so the outcome of the tap is applied again after.
func _restore_selection(from: Vector2i, to: Vector2i, caret_index: int) -> void:
	if _adapter == null or not _adapter.is_valid() or not _adapter.supports_handles():
		return
	if not _adapter.has_any_selection():
		_adapter.select(from, to, caret_index)
	_signature = _make_signature()
	_toggle_for_tap()

# Whether a viewport-space point is over the text of the current selection.
func _is_inside_selection(point: Vector2) -> bool:
	var control: Control = _adapter.control
	var local: Vector2 = control.get_global_transform_with_canvas().affine_inverse() * point
	if not Rect2(Vector2.ZERO, control.size).has_point(local):
		return false
	if not _adapter.supports_handles():
		# A selectable label has no text positions: any tap on the label counts.
		return true
	var pos: Vector2i = _adapter.get_pos_at_local(local)
	var line_height: float = _adapter.get_line_height()
	var row_middle: float = _adapter.get_tip_local(pos).y - line_height * 0.5
	if absf(local.y - row_middle) > line_height * 0.5:
		return false
	for index: int in _adapter.get_caret_count():
		if not _adapter.has_selection(index):
			continue
		var from: Vector2i = _adapter.get_selection_from(index)
		var to: Vector2i = _adapter.get_selection_to(index)
		var after_start: bool = pos.y > from.y or (pos.y == from.y and pos.x >= from.x)
		var before_end: bool = pos.y < to.y or (pos.y == to.y and pos.x <= to.x)
		if not (after_start and before_end):
			continue
		# On a single row the tap must also be between the two ends on screen.
		if from.y == to.y:
			var x_from: float = _adapter.get_tip_local(from).x
			var x_to: float = _adapter.get_tip_local(to).x
			if local.x < minf(x_from, x_to) - 2.0 or local.x > maxf(x_from, x_to) + 2.0:
				continue
		return true
	return false

func _toggle_for_tap() -> void:
	if _tap_was_showing:
		_dismissed = true
		_overflow_open = false
		_hide_panels()
	else:
		_dismissed = false
		_stable_time = show_delay

func _perform(action: StringName) -> void:
	if _adapter == null or not _adapter.is_valid():
		return
	if action != ITEM_BACK and action != ITEM_MORE and action != ITEM_PAGE_NEXT and action != ITEM_PAGE_PREV:
		var custom: Dictionary = _find_spec(action, _custom_specs())
		if not custom.is_empty():
			_perform_custom(action, custom)
			return
	match action:
		ITEM_MORE:
			_overflow_open = true
			return
		ITEM_PAGE_NEXT:
			_page += 1
			return
		ITEM_PAGE_PREV:
			_page = maxi(0, _page - 1)
			return
		ITEM_BACK:
			# One level up: from a submenu to the one it was opened from, or to the main row.
			if not _submenu_path.is_empty():
				_submenu_path.pop_back()
			else:
				_overflow_open = false
			return
		ACTION_CUT:
			_adapter.cut()
		ACTION_DELETE:
			_adapter.delete_selection()
		ACTION_COPY_IMAGE:
			_adapter.copy_image()
		ACTION_COPY:
			_adapter.copy()
			# Like Android: the selection stays, the toolbar goes away until it changes.
			_dismissed = true
			_caret_mode = false
		ACTION_PASTE:
			_adapter.paste()
		ACTION_SELECT_ALL:
			_adapter.select_all()
		ACTION_UNDO:
			_adapter.undo()
			_overflow_open = false
		ACTION_REDO:
			_adapter.redo()
			_overflow_open = false
		ACTION_SHARE:
			if not _adapter.is_secret():
				share_requested.emit(_adapter.get_selected_text())
			_overflow_open = false
	# Cut, Copy and the control's own actions may have changed the clipboard.
	_clipboard_known = false
	_stable_time = 0.0
	action_pressed.emit(action)

func _perform_custom(id: StringName, spec: Dictionary) -> void:
	var children: Array = spec.get("items", []) as Array
	if not children.is_empty():
		open_submenu(id)
		return
	var control: Control = _adapter.control
	_submenu_path.clear()
	var callback: Variant = spec.get("callback")
	if callback is Callable and (callback as Callable).is_valid():
		(callback as Callable).call(control)
	if _adapter != null and _adapter.is_valid():
		_adapter.toolbar_item_pressed(id)
	_clipboard_known = false
	_stable_time = 0.0
	item_pressed.emit(id, control)
	action_pressed.emit(id)

#endregion
