# Puts an image on the system clipboard. Godot can only read an image from the clipboard
# (DisplayServer.clipboard_get_image), so this goes through the system itself, from GDScript only:
# - Android: Godot's Java bridge (JavaClassWrapper, the AndroidRuntime singleton). Android's
#   clipboard holds a link to an image, not the image, so the image is first added to the phone's
#   pictures (Pictures/<app name>). Only the latest copy is kept: the one before is deleted.
# - Windows: a PowerShell command (System.Windows.Forms.Clipboard).
# Other systems: not supported (supported() is false).
class_name caret_image_clipboard extends RefCounted

# Android: the link of the latest copy, deleted from the pictures by the next one.
const LAST_COPY: String = "user://mobile_caret_last_image_copy.txt"

# True once the last copy() went through to the end. A call into Java that Godot refuses stops the
# function with a script error and an empty result, which must not read as success.
static var finished: bool = false


# The pictures folder copies go to: the app's name.
static func _folder() -> String:
	var name: String = str(ProjectSettings.get_setting("application/config/name", "MobileCaret")).validate_filename()
	return name if not name.is_empty() else "MobileCaret"


# Copies the image and then calls `done` with "" or what went wrong, on the main thread. On Windows
# the PowerShell call (a third of a second, seconds on its first start) runs off the main thread,
# so the app does not freeze.
static func copy_later(image: Image, done: Callable) -> void:
	if OS.get_name() == "Windows":
		WorkerThreadPool.add_task(func() -> void:
			var err: String = copy(image)
			if err.is_empty() and not finished:
				err = "stopped"
			done.call_deferred(err))
		return
	var result: String = copy(image)
	if result.is_empty() and not finished:
		result = "stopped"
	done.call(result)


static func supported() -> bool:
	match OS.get_name():
		"Android":
			return Engine.has_singleton("AndroidRuntime")
		"Windows":
			return true
	return false


# Copies the image. Returns "" or what went wrong.
static func copy(image: Image) -> String:
	finished = false
	if image == null or image.is_empty():
		return "no image"
	if image.is_compressed():
		image = image.duplicate()
		image.decompress()
	match OS.get_name():
		"Android":
			return _copy_android(image.save_png_to_buffer())
		"Windows":
			return _copy_windows(image)
	return "not supported here"


static func _copy_android(png: PackedByteArray) -> String:
	if not Engine.has_singleton("AndroidRuntime"):
		return "no AndroidRuntime"
	var runtime: Variant = Engine.get_singleton("AndroidRuntime")
	var context: Variant = runtime.getApplicationContext()
	var resolver: Variant = context.getContentResolver()
	var ContentValues: Variant = JavaClassWrapper.wrap("android.content.ContentValues")
	var Media: Variant = JavaClassWrapper.wrap("android.provider.MediaStore$Images$Media")
	var Uri: Variant = JavaClassWrapper.wrap("android.net.Uri")
	var ClipData: Variant = JavaClassWrapper.wrap("android.content.ClipData")
	# the copy before this one is no longer on the clipboard: remove it from the pictures
	if FileAccess.file_exists(LAST_COPY):
		var last: String = FileAccess.get_file_as_string(LAST_COPY).strip_edges()
		if not last.is_empty():
			# (no selection: "" and an empty list; Godot cannot pass null for them)
			resolver.delete(Uri.parse(last), "", PackedStringArray())
			JavaClassWrapper.get_exception()   # a copy already gone is not an error
	var values: Variant = ContentValues.ContentValues()
	values.put("_display_name", "copy-%d.png" % Time.get_unix_time_from_system())
	values.put("mime_type", "image/png")
	values.put("relative_path", "Pictures/" + _folder())
	var image_uri: Variant = resolver.insert(Media.getContentUri("external"), values)
	if image_uri == null:
		return _java_error("could not add the image to the pictures")
	var out: Variant = resolver.openOutputStream(image_uri)
	if out == null:
		return _java_error("could not write the image")
	out.write(png)
	out.close()
	var f: FileAccess = FileAccess.open(LAST_COPY, FileAccess.WRITE)
	if f != null:
		f.store_string(str(image_uri.toString()))
		f.close()
	# Android wants the clipboard set on its UI thread
	var activity: Variant = runtime.getActivity()
	var set_clip: Callable = func() -> void:
		var clipboard: Variant = context.getSystemService("clipboard")
		clipboard.setPrimaryClip(ClipData.newUri(resolver, "Image", image_uri))
	activity.runOnUiThread(runtime.createRunnableFromGodotCallable(set_clip))
	var err: String = _java_error("")
	finished = err.is_empty()
	return err


# What the Java bridge reports went wrong, if anything.
static func _java_error(fallback: String) -> String:
	var e: Variant = JavaClassWrapper.get_exception()
	if e != null:
		return str(e.toString())
	return fallback


static func _copy_windows(image: Image) -> String:
	var path: String = ProjectSettings.globalize_path("user://mobile_caret_image_copy.png")
	if image.save_png(path) != OK:
		return "could not write the image"
	var script: String = "Add-Type -AssemblyName System.Windows.Forms, System.Drawing; " \
		+ "$img = [System.Drawing.Image]::FromFile('%s'); " % path.replace("'", "''") \
		+ "[System.Windows.Forms.Clipboard]::SetImage($img); $img.Dispose()"
	var output: Array = []
	var code: int = OS.execute("powershell", ["-NoProfile", "-STA", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", script], output, true)
	finished = code == 0
	return "" if code == 0 else "powershell %d: %s" % [code, "".join(output).strip_edges().left(200)]
