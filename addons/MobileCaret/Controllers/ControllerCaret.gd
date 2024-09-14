extends Control
class_name ControllerCaret
@export var caret: TextureButton

func set_caret_texture(texture2D: Texture2D) -> void:
	caret.texture_normal = texture2D
	caret.texture_pressed = texture2D
	caret.texture_hover = texture2D
	caret.texture_disabled = texture2D
	caret.texture_focused = texture2D


func hide_caret() -> void:
	caret.hide()


func show_caret() -> void:
	caret.show()
