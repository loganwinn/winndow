# Winndow

A free, tiny menu-bar window manager for macOS that works like [Spectacle](https://github.com/eczarny/spectacle), which is no longer maintained (its last code change was November 2019 and the project is archived). Same keyboard shortcuts, same behavior, rebuilt in Swift for current macOS (13 Ventura and later, Apple silicon and Intel).

## Install

1. Download `Winndow.zip` from the [latest release](../../releases/latest) and unzip it.
2. Drag **Winndow.app** into **Applications**.
3. The first time, **right-click Winndow.app → Open → Open**. (It isn't notarized by Apple yet, so a normal double-click shows a warning.)
4. When asked, allow Winndow under **System Settings → Privacy & Security → Accessibility**. That's what lets it move windows.
5. Coming from Spectacle? Quit Spectacle first, because both apps use the same shortcuts.

Turn on **Launch at Login** from the Winndow menu-bar icon. If you keep Winndow in the Dock, clicking its icon while it's running opens the shortcuts editor.

## Shortcuts

| Action | Shortcut |
|---|---|
| Center | ⌥⌘C |
| Fullscreen | ⌥⌘F |
| Left / Right half | ⌥⌘← / ⌥⌘→ |
| Top / Bottom half | ⌥⌘↑ / ⌥⌘↓ |
| Upper left / Lower left | ⌃⌘← / ⌃⇧⌘← |
| Upper right / Lower right | ⌃⌘→ / ⌃⇧⌘→ |
| Next / Previous display | ⌃⌥⌘→ / ⌃⌥⌘← |
| Next / Previous third | ⌃⌥→ / ⌃⌥← |
| Make larger / smaller | ⌃⌥⇧→ / ⌃⌥⇧← |
| Undo / Redo | ⌥⌘Z / ⌥⇧⌘Z |

Press a half or corner shortcut again to cycle its width (or height): ½ → ⅔ → ⅓ → ½, just like Spectacle.

### Change a shortcut

Choose **Edit Shortcuts…** from the menu-bar icon, click the shortcut you want to change, and press the new keys (for example ⌘3 for Next Third). Delete removes a shortcut, Esc cancels, and **Restore Spectacle Defaults** puts them all back. A shortcut needs at least one of ⌘, ⌥ or ⌃, and while Winndow owns a combo, other apps stop receiving it.

## Build from source

Needs only the Xcode Command Line Tools (`xcode-select --install`), not full Xcode.

```bash
./build.sh test   # geometry self-check
./build.sh        # build/Winndow.app and build/Winndow.zip
osascript -l JavaScript Tests/live-test.js   # presses every default shortcut on a real window
osascript -l JavaScript Tests/rebind-test.js # checks a Next Third rebound to ⌘3
```

Pushing a tag like `v1.0.0` builds the app on GitHub Actions and attaches `Winndow.zip` to a release.

## Credits

The window-position math follows Spectacle's published calculations (MIT, © Eric Czarny). Winndow is written from scratch in Swift and is also MIT licensed.
