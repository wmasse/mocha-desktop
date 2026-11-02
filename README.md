<p align="center"><img src="docs/icon.png" width="128" alt=""></p>

<h1 align="center">Mocha Desktop</h1>

<p align="center">A pastel <a href="https://catppuccin.com">Catppuccin Mocha</a> menu bar and dock for macOS, built on <a href="https://github.com/FelixKratz/SketchyBar">SketchyBar</a>.</p>

<p align="center"><img src="docs/installer.png" width="520" alt="The Mocha Desktop installer"></p>

## What you get

**Menu bar**
- Floating pills: Apple menu, current app, volume, Wi‑Fi, battery, and date and time
- The notch stays empty, so apps that live there aren't covered
- Click the clock for Calendar, battery or Wi‑Fi for their settings
- Click volume to mute; scroll over it to change the volume
- The Apple menu has Settings, Activity Monitor, Reload bars, Lock screen and Sleep, and closes when you click anywhere else

**Dock**
- Squircle tiles in pastel colors, built from the apps already in your Dock
- Running apps fill in with color; the app in front gets a ring
- Hover to see the app's name; the tile grows without moving the others, and keeps up however fast you move
- Right-click for Open or Quit, Show in Finder, Move left or right, Add app, Remove from Dock
- Drag files onto an app to open them with it, or onto the Trash to delete them
- Slides out of the way for full-screen apps and back when you leave

**Window gaps**
- Double-click a window's title bar to fill the space between the menu bar and dock, with an even 8pt gap all around (uses [Rectangle](https://rectangleapp.com))

**Wallpaper**
- A solid Mocha background

## Install

You need macOS 13 or later and [Homebrew](https://brew.sh).

1. Download **Mocha-Desktop.zip** from the [latest release](../../releases/latest), unzip it and move **Mocha Desktop** to Applications.
2. Open it. The app isn't notarized, so the first time macOS will block it: go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. Pick the parts you want and click **Install**.
4. Finish up:
   - Set **System Settings → Control Center → Automatically hide and show the menu bar** to **Always**, if Apple's menu bar still shows.
   - If you installed window gaps, allow **Rectangle** in **Privacy & Security → Accessibility** and turn on **Launch on login** in its settings.

Prefer the terminal? Clone the repo and run `./install.sh` (or `./install.sh menubar dock` for only some parts).

The installer trusts SketchyBar's official Homebrew tap (`felixkratz/formulae`), installs SketchyBar, the Hack Nerd Font and, for window gaps, Rectangle. Anything it replaces in `~/.config` is kept as a `.backup` copy.

## Make it yours

| What | Where |
|---|---|
| Dock apps, order, icons and colors | Right-click a tile, or edit `~/.config/sketchybar-dock/apps.txt` |
| Tile and hover size | `~/.config/sketchybar-dock/sizes.sh` |
| Colors | `colors.sh` in either config folder |
| Menu bar items | `~/.config/sketchybar/sketchybarrc` |

After editing, use **Reload bars** in the Apple menu.

## Uninstall

Open the app and click **Uninstall**, or run `./uninstall.sh`. It brings back Apple's menu bar, Dock and window zoom, and moves your Mocha settings aside instead of deleting them.

## How it works

- **Menu bar:** a SketchyBar config in `menubar/`.
- **Dock:** a second SketchyBar instance in `dock/`, started at login by a LaunchAgent. SketchyBar names each instance after the file it starts from, so the dock runs through a link called `mochadock`.
- **Dock helper:** `dock/dockdrop` is a small native helper that runs alongside the dock.
  - **Hover:** SketchyBar runs a separate script for every mouse enter and exit, all at once, so quick back-and-forth movement made them land out of order and left the wrong tile grown or a name stuck. The helper checks where the pointer is 60 times a second and sends the dock one update, in order, only when the tile under it changes.
  - **Drag and drop:** SketchyBar can't receive drops, so the helper keeps an invisible window over the dock that only catches drops while a file drag is happening.
  - **Menus:** it closes the bars' menus when you click elsewhere.
- **Installer app:** `app/` holds the installer app, which runs `install.sh` and shows its output.

## Build from source

```bash
scripts/build-app.sh 1.0.0
```

This produces `dist/Mocha Desktop.app` and `dist/Mocha-Desktop.zip` (universal, ad-hoc signed). It needs the Xcode Command Line Tools. The build works around a module-map bug in some Command Line Tools releases on its own.

## Credits

Colors from [Catppuccin](https://github.com/catppuccin/catppuccin) (MIT). Bars by [SketchyBar](https://github.com/FelixKratz/SketchyBar). Window gaps by [Rectangle](https://github.com/rxhanson/Rectangle). Icons from [Nerd Fonts](https://www.nerdfonts.com).
