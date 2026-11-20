# Drift

Hold **⌘** and drag anywhere on a window to move it. Right-drag to resize from the nearest corner. Like Linux, on macOS.

A tiny native menu bar app: Swift, a global `CGEvent` tap, and the Accessibility API. The settings panel uses Liquid Glass. No dependencies, ~400 lines.

## Install

**Build it yourself** (cleanest, 10 seconds, needs Xcode 26+):

```sh
git clone https://github.com/xevrion/drift && cd drift
./build.sh && open build/Drift.app
```

**Or download** `Drift.zip` from [Releases](../../releases), unzip and move `Drift.app` to `/Applications`. Drift isn't notarized yet, so macOS blocks the first launch. Either:

- open it once, then go to System Settings → Privacy & Security and click **Open Anyway**, or
- run `xattr -dr com.apple.quarantine /Applications/Drift.app` and open it normally.

Requires macOS 26 or later.

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
