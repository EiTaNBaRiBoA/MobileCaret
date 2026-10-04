@tool
# Registers the carets controller ("MobileCaret") and the optional floating toolbar
# ("MobileCaretToolbar") as autoloads while the plugin is enabled. They are independent of each
# other: use `MobileCaretToolbar.enabled = false` (or remove its autoload) to run without a toolbar.
extends EditorPlugin

const AUTOLOAD_NAME: String = "MobileCaret"
const TOOLBAR_AUTOLOAD_NAME: String = "MobileCaretToolbar"


func _enable_plugin() -> void:
	var dir: String = (get_script() as Script).resource_path.get_base_dir()
	add_autoload_singleton(AUTOLOAD_NAME, dir.path_join("CaretsController/carets_controller.tscn"))
	add_autoload_singleton(TOOLBAR_AUTOLOAD_NAME, dir.path_join("Toolbar/caret_toolbar.tscn"))

func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	remove_autoload_singleton(TOOLBAR_AUTOLOAD_NAME)
