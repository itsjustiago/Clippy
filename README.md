# Clippy 📋

A clipboard history for macOS — the equivalent of Windows' **Win + V**.
Global shortcut: **`⌥V`** (Option + V).

A native Swift/SwiftUI menu-bar app that keeps everything you copy (text and
images) and lets you paste older items with a global shortcut.

## ⬇️ Install

**[⬇️ Download Clippy (.dmg)](https://github.com/itsjustiago/Clippy/releases/latest/download/Clippy.dmg)**

1. Open the downloaded **Clippy.dmg**.
2. Drag **Clippy.app** onto the **Applications** folder.
3. Open Clippy from Applications. The first time, **right-click the app → Open → Open**
   (macOS asks this once because the app isn't from the App Store — no Terminal needed).
4. A welcome screen appears with a button to turn on auto-paste. Then just press **`⌥V`**.

That's it — no commands, no setup.

## Features

- **Global shortcut `⌥V`** — opens a floating panel in any app.
- **Instant search** — type to filter the history.
- **Keyboard navigation** — `↑`/`↓` to move, `↵` to paste, `esc` to close.
- **Auto-paste** — the chosen item is pasted into the app you were in (needs Accessibility).
- **Quick paste** — `⌘1`…`⌘9` paste the first items directly.
- **Pin favourites** (`⌘P`) — kept at the top, never auto-removed.
- **Delete** (`⌘⌫`) single items, or clear the unpinned history.
- **Text and images** — images stored on disk with a thumbnail.
- **Source app** — shows which app each copy came from.
- **Privacy** — ignores content marked sensitive by password managers.
- **Custom shortcut** — set your own key combo in Settings.
- **Update check** — Clippy checks GitHub for newer releases and offers a one-click update in the menu.
- **Menu bar** — recent items, clear history, launch at login, settings.
- **Welcome screen** — first-run onboarding with a one-click Accessibility button.
- No Dock icon. History stored locally (up to 200 items).

## Panel shortcuts

| Key | Action |
|-----|--------|
| `⌥V` | Open / close the panel |
| type | Search |
| `↑` `↓` | Navigate |
| `↵` | Paste the selected item |
| `⌘1`–`⌘9` | Paste item N |
| `⌘P` | Pin / unpin |
| `⌘⌫` | Delete the selected item |
| `esc` | Close |

`⌥V` is the default — change it any time in **Settings** (menu bar 📋 → *Definições…*).

## Updates

Clippy checks GitHub for a newer release on launch (toggle in Settings). When one is
available, the menu bar shows **⤓ Update to vX.Y.Z…**. Click it (or *Update now* in
Settings) and Clippy **downloads, installs and restarts itself** — no dragging, no
Terminal. Your history, settings and Accessibility permission are kept.

## The "unidentified developer" prompt

Clippy is signed with a self-signed certificate and isn't notarised by Apple
(that needs a paid Apple Developer account). So the **first** launch needs a
right-click → Open; after that it opens normally. There's nothing to type.

## Build from source

For developers who'd rather build it themselves:

```bash
./build.sh    # compiles, signs, installs to /Applications and launches
```

The first run creates a self-signed certificate (`./setup-signing.sh`) in a
dedicated keychain. It gives the app a **stable identity** so the Accessibility
permission sticks and isn't re-requested on every rebuild.

Requirements: macOS 14+ and the Command Line Tools (`swift`).

- Regenerate the icon: `swift make-icon.swift && iconutil -c icns Clippy.iconset -o Clippy.icns`
- Package the DMG: `./make-dmg.sh`

### Releasing a new version

1. Bump `CFBundleShortVersionString` in `Info.plist`.
2. `./build.sh && ./make-dmg.sh`
3. `gh release create vX.Y.Z Clippy.dmg Clippy.zip --title "Clippy X.Y.Z" --notes "…"`

Both assets matter: **Clippy.dmg** for the website download, **Clippy.zip** for the
in-app updater. Installed copies detect the new release on next launch and update in one click.

## Project layout

```
Sources/Clippy/
  main.swift              — entry point (menu-bar app)
  AppDelegate.swift       — menu, global shortcut, lifecycle
  HistoryStore.swift      — model + persistence + images
  ClipboardManager.swift  — clipboard monitoring
  HotKey.swift            — global shortcut (Carbon)
  PanelController.swift   — floating panel + keyboard + paste
  PasteHelper.swift       — simulate ⌘V (Accessibility)
  ContentView.swift       — SwiftUI panel UI
  Onboarding.swift        — first-run welcome window
```

## Notes

- While Clippy is running, `⌥V` no longer types the `√` character.
  To change the shortcut, edit `AppDelegate.applicationDidFinishLaunching`.
- Data is stored in `~/Library/Application Support/Clippy/`.
