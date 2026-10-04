# Screen-size helpers shared by the handles and the toolbar: how many real screen pixels one
# logical pixel of a viewport covers, and millimeter-to-pixel conversion for it.
class_name caret_screen extends RefCounted


# Screen pixels per logical pixel of `viewport`: stretch mode, aspect, content scale factor,
# and, for embedded windows or a SubViewport shown through a container, the parent's scale too.
static func viewport_scale(viewport: Viewport) -> float:
	if viewport is Window:
		var window: Window = viewport
		var window_scale: float = maxf(window.get_final_transform().get_scale().x, 0.01)
		if window.is_embedded() and window.get_parent() != null:
			window_scale *= viewport_scale(window.get_parent().get_viewport())
		return window_scale
	if viewport is SubViewport:
		var sub_viewport: SubViewport = viewport
		var container: SubViewportContainer = sub_viewport.get_parent() as SubViewportContainer
		if container != null:
			var ratio: float = 1.0
			if container.stretch and sub_viewport.size.x > 0:
				ratio = container.size.x / float(sub_viewport.size.x)
			return maxf(ratio * container.get_global_transform_with_canvas().get_scale().x * viewport_scale(container.get_viewport()), 0.01)
	return 1.0

# Dots per inch of the screen `viewport` is shown on (96 if the platform doesn't report one).
static func dpi(viewport: Viewport) -> float:
	var screen: int = DisplayServer.SCREEN_OF_MAIN_WINDOW
	if viewport is Window:
		screen = (viewport as Window).current_screen
	var value: float = float(DisplayServer.screen_get_dpi(screen))
	return value if value > 0.0 else 96.0

# Millimeters as logical pixels of `viewport`, so the size on screen stays constant.
static func mm_to_logical(viewport: Viewport, millimeters: float) -> float:
	return millimeters * dpi(viewport) / 25.4 / viewport_scale(viewport)
