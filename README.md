<p align="center"><img src="docs/icon.png" width="128" alt=""></p>

<h1 align="center">Mocha Desktop</h1>

<p align="center">A pastel <a href="https://catppuccin.com">Catppuccin Mocha</a> menu bar and dock for macOS, built on <a href="https://github.com/FelixKratz/SketchyBar">SketchyBar</a>.</p>

<p align="center"><img src="docs/installer.png" width="520" alt="The Mocha Desktop installer"></p>

## What you get

**Menu bar**
- Pills for the Apple menu, current app, Amphetamine, Low Power Mode, Do Not Disturb, volume, Wi‑Fi, battery, and date and time, in the current theme's colors and typeface
- Click the battery for a menu with how much is left and, in minutes, how long it'll last, or how long until it's full while charging
- They sit on a strip cut from the top of your own wallpaper (it follows dynamic wallpapers through the day), so the bar blends into the desktop while covering Apple's menu bar
- The notch stays empty, so apps that live there aren't covered
- Click the current app to hide it, hide the others or quit it
- Click the clock for Calendar or battery for its settings
- Click Wi‑Fi for a menu to turn it off or on, or open its settings
- Click volume for a menu: what's playing in Spotify or Music (artwork, progress with time left, back, pause, next), a volume slider, mute, and your connected Bluetooth devices with their battery; scroll over the pill to change the volume
- If [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) is installed, click the cup to keep your Mac awake for a while or until you turn it off, and optionally with the lid closed
- Click the leaf to switch Low Power Mode (needs a one-time permission, which the installer explains); the battery pill turns amber whenever it's on. Click the moon for Do Not Disturb (needs a shortcut named "Mocha Do Not Disturb": Set Focus → Do Not Disturb → Toggle)
- The Apple menu has Settings, Activity Monitor, Reload bars, Lock screen and Sleep
- Need Apple's own menu bar (File, Edit…)? Press **Control‑Option‑Command‑M**, or pick **macOS Menu Bar** in the Apple menu. The Mocha bar steps aside and comes back once you're done
- Menus close when you click anywhere else

**Dock**
- Tiles built from the apps already in your Dock; open apps are marked in the theme's style (filled, inverted or outlined) and the app in front gets a ring
- Hover to see the app's name; the tile grows without moving the others, and keeps up however fast you move
- Right-click for Open or Quit, Show in Finder, Move left or right, Add app, Remove from Dock
- Drag files onto an app to open them with it, or onto the Trash to delete them
- Right-click the Trash to see every open app by its icon, with a button beside each to quit it
- Forty-eight themes in a gallery (right-click any tile → **Theme…**), each a full design: shapes, surfaces, how open apps look, and its own typeface. The menu bar follows the dock. The gallery has a tab for each set and opens on the one you're using
  - Classic: Catppuccin Mocha and Latte, Graphite, Paper, Nord Glass, Terminal
  - Scenes, with scenery drawn behind the tray: Harvest, Dusk Lake, Alpenglow, Night Garden, Sakura, Aurora, Dune, Tide, Velvet, Matcha, Nebula, Orbit. The scenery is laid out around the icons, with its details in the gaps between them
  - Candy Orbit, made to go with the Candy Orbit wallpaper's planets and skies: Sticker, Sherbet, Daybreak, Gas Giant, Ring, Rocket, Cumulus, Starlight, Red Planet, Moonlight
  - Styles, one for each design style: Broadsheet (brutalist editorial), Saddle (warm tactile analog), Swiss (high-contrast Swiss grid), Phosphor '77 (70s sci-fi terminal), Pop (neo-brutalist pop), Precision (precision industrial hardware), Obsidian (high-craft dark mode), Millennium (Y2K cyber-minimalism), Bento (Japanese bento and magazine editorial), Riso Zine (Risograph and indie zine print)
  - Effects, where the dock comes alive around the app you're on: Current (water flows over to it and swells up behind it), Claymation (stop-motion clay builds up around it), Ferrofluid (magnetic fluid spikes up around it), Pop-Up (a paper scene folds up out of a book behind it), Live Wire (a spark runs over and lights a neon outline), Hourglass (sand pours onto it and piles higher the longer you stay), Overgrowth (vines climb it and flower), Lava (a lava lamp rises around it), Campfire (a pixel fire burns under it), Jelly (its jelly block grows and wobbles). They react when you point at a tile too, and pause in Low Power Mode and while the screen sleeps
- A weather widget on the desktop, drawn in the current theme (its colors, typeface and tray edge, with the forecast on tiles shaped like the dock's). Click it to open Weather, drag it anywhere, right-click for small or medium, °F or °C, to pick your city on a map (or follow your location), or to hide it (the Trash's menu brings it back). Forecasts come from Open-Meteo, which is sent only the place's coordinates; Use My Location goes through a tiny app, Mocha Location, that asks macOS for permission the first time
- **Customize colors…** picks your own tray, tile, text and icon colors (saved per theme)
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
| Theme and colors | Right-click a tile → **Theme…**, or edit `~/.config/sketchybar-dock/themes/` (palettes and design) and `style.sh` (what each design setting does); scenery is drawn by `dock/dockart` |
| Menu bar items | `~/.config/sketchybar/sketchybarrc` |

After editing, use **Reload bars** in the Apple menu.

## Uninstall

Open the app and click **Uninstall**, or run `./uninstall.sh`. It brings back Apple's menu bar, Dock and window zoom, and moves your Mocha settings aside instead of deleting them.

## How it works

- **Menu bar:** a SketchyBar config in `menubar/`, started at login by a LaunchAgent.
  - **Above Apple's menu bar:** macOS slides its auto-hidden menu bar down whenever the pointer nears the top, and on macOS 27 it also keeps an invisible window there that takes clicks. Stock SketchyBar can only sit on the same layer, so the menu bar runs a copy built with a one-line change (`menubar/sketchybar/topmost.patch`, built by `scripts/build-sketchybar.sh`) that draws it two layers higher. The bar is a full-width strip, taller than Apple's, so Apple's bar never shows through.
  - **Menu helper:** `menubar/barclick` is a small native helper. It closes the bar's menus on outside clicks, gives back Apple's menu bar on Control‑Option‑Command‑M, hides or quits the current app, and cuts the wallpaper strip (picking the right image of a dynamic wallpaper for the time of day). It also reads and sets the volume through Core Audio, since AppleScript's volume commands take about a second each on macOS 27.
- **Dock:** a second SketchyBar instance in `dock/`, started at login by a LaunchAgent. SketchyBar names each instance after the file it starts from, so the dock runs through a link called `mochadock`.
- **Dock helper:** `dock/dockdrop` is a small native helper that runs alongside the dock.
  - **Hover:** SketchyBar runs a separate script for every mouse enter and exit, all at once, so quick back-and-forth movement made them land out of order and left the wrong tile grown or a name stuck. The helper checks where the pointer is 60 times a second and sends the dock one update, in order, only when the tile under it changes.
  - **Drag and drop:** SketchyBar can't receive drops, so the helper keeps an invisible window over the dock that only catches drops while a file drag is happening. Since macOS 27 that window isn't always told about the drop, so the helper also watches for the button coming up over a tile and handles the files itself.
  - **Menus:** it closes the dock's menus when you click elsewhere.
  - **Panels:** the open-apps panel and the theme gallery are native panels drawn in the current theme (`apps.swift`, `gallery.swift`).
  - **Weather widget:** a window at the desktop widgets' level, so app windows cover it (`widget.swift`). Your city and its spot are saved in `widget.json`.
  - **Effects:** for effect themes, the helper keeps a see-through window behind the tiles and animates it (`stage.swift`, `effects.swift`), following the app in front and the tile under the pointer. It only draws while something is moving, at each effect's own frame rate.
- **Scenery:** `dock/dockart` draws each scene theme's scenery (gradients and simple shapes) at the tray's exact width.
- **Installer app:** `app/` holds the installer app, which runs `install.sh` and shows its output.

## Build from source

```bash
scripts/build-app.sh 1.0.0
```

This produces `dist/Mocha Desktop.app` and `dist/Mocha-Desktop.zip` (universal, ad-hoc signed). It needs the Xcode Command Line Tools. The build works around a module-map bug in some Command Line Tools releases on its own.

## Credits

Colors from [Catppuccin](https://github.com/catppuccin/catppuccin) (MIT). Bars by [SketchyBar](https://github.com/FelixKratz/SketchyBar) (GPL-3.0; the menu bar uses a patched build, see `menubar/sketchybar/`). Window gaps by [Rectangle](https://github.com/rxhanson/Rectangle). Icons from [Nerd Fonts](https://www.nerdfonts.com).
