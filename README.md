# Mobile Caret for Godot 4 (WIP)

Godot 4 plugin for customizable, touch-friendly carets on mobile devices. Improves text input visibility and selection ease.

## Motivation

Godot's built-in caret can be challenging to see and interact with on smaller screens, particularly on mobile devices. This plugin aims to address that by providing a customizable solution for a more user-friendly caret experience.

## Features

* **Custom Caret:** Use any `TextureButton` as your text caret, providing greater visibility and touch target area.
* **Offset Control:** Fine-tune the position of the custom caret relative to the text for optimal placement.
* **Text Selection Support:** The plugin seamlessly handles text selection, allowing you to drag the custom caret to adjust the selection range.
* **Theme Compatibility:** Works with various themes and font sizes, ensuring visual consistency.

## Installation

1. Copy `addons/MobileCaret` into your project's `addons/` folder.
2. Enable **MobileCaret** in *Project Settings > Plugins*. This registers the `MobileCaret` autoload (or add `CaretsController/carets_controller.tscn` as an autoload yourself).

## Usage

* The controller watches GUI focus: whenever a `LineEdit` or `TextEdit` is focused, a handle appears under its caret.
* **No selection:** drag the handle to move the caret.
* **Selection:** two handles (start/end) appear; drag either to adjust the selection. They may cross.
* **Long-press** a word to select it.
* Handles never take focus from the text control. Touch input must be emulated as mouse input (Godot's default `emulate_mouse_from_touch`).
* While dragging, the handle follows your finger smoothly and the caret snaps to the nearest character.
* The single caret handle fades out after a period of inactivity (selection handles never fade). Tapping or moving the caret brings it back.
* Customize via the exported properties on the controller:
  * Look: `texture_caret`, `handle_size`, `handle_color`, `caret_texture_offset`, `hit_margin`
  * Gestures: `long_press_seconds`
  * Fade: `caret_fade_delay` (seconds idle; `0` disables), `caret_fade_duration`
  * Native caret: `hide_native_caret` (hide Godot's thin caret whenever a handle shows), `hide_native_caret_while_dragging` (hide it only during a drag, on by default). Any existing `caret_color` override on the control is restored exactly.

## Tests

```
godot --path <project> res://MobileCaret/tests/test_carets.tscn
```

Drives real input events against the example scene (exit code 0 = all pass).

## Important Notes

* **Work in Progress:** This plugin is actively being developed. There might be some edge cases or bugs that need to be addressed.
* **Feedback and Contributions:** Your feedback and contributions are highly valued! This plugin is a work in progress, pull requests are always welcome!
