# A CanvasLayer that the handles/toolbar put into a Window or SubViewport so they can draw there
# and receive that viewport's input (a node only gets `_input` for the viewport it lives in).
class_name caret_viewport_layer extends CanvasLayer

# Emitted for every input event the viewport receives.
signal input_received(event: InputEvent)


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	input_received.emit(event)


# Returns the layer named `layer_name` in `viewport`, creating it on first use.
static func get_or_create(viewport: Viewport, layer_name: String, layer_index: int) -> caret_viewport_layer:
	var existing: Node = viewport.get_node_or_null(layer_name)
	if existing is caret_viewport_layer:
		return existing
	var layer: caret_viewport_layer = caret_viewport_layer.new()
	layer.name = layer_name
	layer.layer = layer_index
	viewport.add_child(layer)
	return layer
