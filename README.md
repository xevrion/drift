# Drift

Hold **⌘** and drag anywhere on a window to move it. Right-drag to resize from the nearest corner. Like Linux, on macOS.

A tiny native menu bar app: Swift, a global `CGEvent` tap, and the Accessibility API. The settings panel uses Liquid Glass. No dependencies, ~400 lines.

## Install

Grab `Drift.zip` from [Releases](../../releases), unzip, move `Drift.app` to `/Applications` and open it. It's ad-hoc signed, so the first time right-click → **Open**.

Or build it yourself (macOS 26+, Xcode 26+):

```sh
./build.sh
open build/Drift.app
```

Grant **Accessibility** when asked (System Settings → Privacy & Security → Accessibility). Drift starts by itself once it's allowed.

## Use

| Gesture | Does |
| --- | --- |
| ⌘ + drag | Move the window under the cursor |
| ⌘ + right-drag | Resize from the nearest corner |

The modifier can be ⌘, ⌥, ⌃ or ⌃⌥, picked from the menu bar panel. Modifier matching is exact, so ⌘⇧-click and friends still reach the app.

## How it's fast

- The event tap only decides and swallows events; window writes happen on a separate queue, latest frame wins, so a slow app never lags the cursor.
- `AXEnhancedUserInterface` is switched off during a drag. Chrome and Electron apps otherwise animate every frame change.
- The window is found once on mouse down, never during the drag.

## License

MIT
