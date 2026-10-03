@tool
# Registers the carets controller as the "MobileCaret" autoload while the plugin is enabled.
extends EditorPlugin

const AUTOLOAD_NAME: String = "MobileCaret"


func _enable_plugin() -> void:
	var dir: String = (get_script() as Script).resource_path.get_base_dir()
	add_autoload_singleton(AUTOLOAD_NAME, dir.path_join("CaretsController/carets_controller.tscn"))

func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
