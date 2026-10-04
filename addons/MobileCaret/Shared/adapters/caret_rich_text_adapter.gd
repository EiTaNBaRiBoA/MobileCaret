# Adapter for a selectable RichTextLabel. Only the toolbar uses it: a RichTextLabel's selection can
# be read, copied and cleared but not set from code, so there are no caret handles for it.
# Text positions are (character index, 0); the geometry is approximate (the toolbar is centered
# over the label at the height of the selection's first line).
class_name caret_rich_text_adapter extends caret_text_adapter


var _cached_frame: int = -1
var _cached_selection: String = ""

func _label() -> RichTextLabel:
	return control as RichTextLabel

# The selected text, read at most once per frame (it is rebuilt from the content each call).
func _selected_text() -> String:
	var frame: int = Engine.get_process_frames()
	if frame != _cached_frame:
		_cached_frame = frame
		_cached_selection = _label().get_selected_text()
	return _cached_selection

func is_usable() -> bool:
	return is_instance_valid(control) and _label().selection_enabled

func supports_handles() -> bool:
	return false

func is_empty() -> bool:
	return _label().get_parsed_text().is_empty()

func has_selection(_caret_index: int = 0) -> bool:
	return _label().selection_enabled and not _selected_text().is_empty()

func has_any_selection() -> bool:
	return has_selection()

func get_caret(_caret_index: int = 0) -> Vector2i:
	# Nothing selected: there is no caret, so use the start of the text.
	return Vector2i(maxi(_label().get_selection_to(), 0), 0)

func get_selection_from(_caret_index: int = 0) -> Vector2i:
	return Vector2i(maxi(_label().get_selection_from(), 0), 0)

func get_selection_to(_caret_index: int = 0) -> Vector2i:
	return Vector2i(maxi(_label().get_selection_to(), 0), 0)

func deselect() -> void:
	_label().deselect()

func get_line_height() -> float:
	var label: RichTextLabel = _label()
	return label.get_theme_font("normal_font").get_height(label.get_theme_font_size("normal_font_size"))

# Bottom of the line that holds the character, at the horizontal middle of the label.
func get_tip_local(pos: Vector2i) -> Vector2:
	var label: RichTextLabel = _label()
	var line: int = label.get_character_line(pos.x)
	var top: float = label.get_line_offset(line)
	var bottom: float = label.get_line_offset(line + 1) if line + 1 < label.get_line_count() else float(label.get_content_height())
	var scroll: float = label.get_v_scroll_bar().value if label.scroll_active else 0.0
	return Vector2(label.size.x * 0.5, bottom - scroll)

func is_pos_visible(pos: Vector2i) -> bool:
	var y: float = get_tip_local(pos).y
	return y > 0.0 and y - get_line_height() < _label().size.y
