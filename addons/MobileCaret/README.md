# Mobile Caret for Godot 4

Touch-friendly text carets and selection handles for Godot 4, in the style of Android. Drop it into your project and every `LineEdit` and `TextEdit` gets draggable handles, with no per-scene setup.

## Motivation

Godot's built-in caret is a thin line that is hard to see and almost impossible to place precisely with a finger. This plugin adds large, easy-to-grab handles so editing text on a phone feels natural.

## Features

* **Draggable caret handle:** a handle appears under the caret; drag it to move the caret.
* **Selection handles:** when text is selected, two handles mark the start and end. Drag either one to adjust the selection, and they can cross over each other.
* **Long-press to select a word.**
* **Smooth dragging:** the handle follows your finger while the caret snaps to the nearest character. Dragging past the edge of a control scrolls it.
* **Auto-fading caret handle:** the single caret handle fades out after a few seconds of inactivity and returns when you tap or move the caret. Selection handles stay visible.
* **Native caret hiding:** optionally hide Godot's own thin caret while a handle is shown, or only while dragging.
* **Works with what you already have:** supports `LineEdit` and `TextEdit` (including wrapped text, scrolling, alignment, secret fields and different font sizes) without changing your scenes. The text control keeps focus, so the on-screen keyboard stays up while you drag.
* **Customizable:** use your own handle texture, size and color.

## Installation

1. Download the repository (or use the Asset Library) and copy `addons/MobileCaret` into your project's `addons/` folder.
2. Open *Project Settings > Plugins* and enable **MobileCaret**. This registers a `MobileCaret` autoload.

That's it. Run your project and focus any `LineEdit` or `TextEdit`.

If you prefer not to use the plugin, add `addons/MobileCaret/CaretsController/carets_controller.tscn` as an autoload yourself.

An example scene is included at `addons/MobileCaret/Examples/example_scene.tscn`.

## Usage

* **Move the caret:** drag the handle under the caret.
* **Select text:** long-press a word (or double-tap). Two handles appear; drag them to adjust the selection.
* **Replace or collapse a selection:** just type, or tap elsewhere, as usual.

### Settings

Select the `MobileCaret` autoload (or `carets_controller` node) and adjust its exported properties, or set them from code, for example `MobileCaret.handle_color = Color.ORANGE`.

#### Look

| Property | Description |
| --- | --- |
| `texture_caret` | Optional custom handle texture. Leave empty for the default teardrop. |
| `handle_size_mm` | Physical size of a handle in millimeters (default 7 × 8). The handle keeps this size on screen whatever the resolution, aspect ratio, stretch mode or screen DPI, and the hit margin, drag threshold and edge-scroll zones scale with it. Set to `(0, 0)` to use `handle_size` instead. |
| `handle_size` | Size of a handle in logical pixels. Used when `handle_size_mm` is `(0, 0)`. |
| `handle_color` | Color of the default teardrop. |
| `caret_texture_offset` | Extra offset applied to the handles. |
| `hit_margin` | Extra pixels around a handle that still count as touching it. |

#### Gestures

| Property | Description |
| --- | --- |
| `long_press_seconds` | How long to press to select a word. `0` disables long-press. |

#### Fade

| Property | Description |
| --- | --- |
| `caret_fade_delay` | Seconds of inactivity before the caret handle fades out. `0` or less disables fading. |
| `caret_fade_duration` | How long the fade takes, in seconds. |

#### Native caret

| Property | Description |
| --- | --- |
| `hide_native_caret` | Hide Godot's thin caret whenever a handle is shown. |
| `hide_native_caret_while_dragging` | Hide it only while a handle is being dragged (on by default). |

If a control already has its own `caret_color` override, it is restored exactly when the native caret is shown again.

## Feedback and Contributions

Bug reports, ideas and pull requests are welcome.

## License

Released under the MIT License. See [LICENSE](LICENSE).
