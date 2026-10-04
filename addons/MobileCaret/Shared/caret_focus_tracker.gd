# Reports focus changes from every viewport: the main window, other Windows and SubViewports
# (GUI focus is tracked per viewport, so listening to the root alone would miss them).
class_name caret_focus_tracker extends Node

# Emitted when a control gains GUI focus in any viewport.
signal focus_changed(control: Control)

var _hooked: Dictionary = {}


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_hook(get_tree().root)
	_scan(get_tree().root)

func _hook(viewport: Viewport) -> void:
	var id: int = viewport.get_instance_id()
	if _hooked.has(id):
		return
	_hooked[id] = true
	viewport.gui_focus_changed.connect(_on_gui_focus_changed)

func _on_gui_focus_changed(control: Control) -> void:
	focus_changed.emit(control)

func _on_node_added(node: Node) -> void:
	if node is Viewport:
		_hook(node)

func _scan(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Viewport:
			_hook(child)
		_scan(child)