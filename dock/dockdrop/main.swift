// dockdrop — lets you drop files onto the Mocha dock like the real Dock.
//
// SketchyBar can't receive drag-and-drop, so this helper keeps an invisible
// window over the dock. The window lets every click through, and only starts
// catching drops while a file drag is in progress. Dropping on an app tile
// opens the files with that app; dropping on the trash moves them to the Trash.
//
// Right-clicking the trash opens the open-apps panel (apps.swift); Theme… opens the
// theme gallery (gallery.swift).
//
// It also closes the bars' menus (the Apple menu and the dock's right-click
// menus) when you click anywhere outside the bars, like a normal menu.
//
// And it runs the dock's hover. SketchyBar starts a separate script for every
// mouse enter/exit and runs them side by side, so moving quickly back and
// forth made them land out of order and left the wrong tile grown or a name
// stuck on screen. Instead, this helper checks where the pointer is 60 times
// a second and, only when the tile under it changes, sends the dock one
// update, in order, from this one process.

import AppKit

let env = ProcessInfo.processInfo.environment
let configDir = env["CONFIG_DIR"] ?? NSHomeDirectory() + "/.config/sketchybar-dock"
let barCommand = configDir + "/bin/mochadock"
let dockHeight: CGFloat = 96   // covers the 80pt bar plus its 8pt offset, with room to spare
let logURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/dockdrop.log")

/// Short trail of what happened during drags, for troubleshooting
func log(_ message: String) {
    let line = "\(Date()) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

struct Tile {
    let item: String      // SketchyBar item name, e.g. "app.photos" or "trash"
    let app: URL?         // nil for the trash
    let minX: CGFloat
    let maxX: CGFloat
}

@discardableResult
func run(_ path: String, _ args: [String], extraEnv: [String: String] = [:]) -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    var e = env
    e["CONFIG_DIR"] = configDir
    e["PATH"] = configDir + "/bin:/opt/homebrew/bin:/usr/bin:/bin"
    extraEnv.forEach { e[$0] = $1 }
    p.environment = e
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return Data() }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return data
}

/// Where each tile currently sits on screen, read from SketchyBar.
/// Whether SketchyBar is drawing the dock on this space. On a full-screen space it parks the dock's windows
/// far off screen (-9999), and that happens even when the space doesn't look full screen to plugins/fullscreen.js
func dockOnScreen() -> Bool {
    guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return true }
    let owner = barCommand.split(separator: "/").last.map(String.init)
    return list.contains { w in
        guard (w["kCGWindowOwnerName"] as? String) == owner, let b = w["kCGWindowBounds"] as? [String: CGFloat] else { return false }
        return (b["X"] ?? -9999) > -1000 && (b["Height"] ?? 0) >= 40
    }
}

func loadTiles() -> [Tile] {
    guard let text = try? String(contentsOfFile: configDir + "/apps.txt", encoding: .utf8) else { return [] }
    var entries: [(String, URL?)] = text.split(separator: "\n").compactMap { line in
        guard !line.hasPrefix("#") else { return nil }
        let fields = line.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count >= 2 else { return nil }
        return ("app." + fields[0], URL(fileURLWithPath: String(fields[1])))
    }
    entries.append(("trash", nil))

    return entries.compactMap { item, app in
        let data = run(barCommand, ["--query", item])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rects = json["bounding_rects"] as? [String: Any],
              let rect = rects.values.first as? [String: Any],
              let origin = rect["origin"] as? [Double], let size = rect["size"] as? [Double],
              origin[0] > -1000 else { return nil }
        // Include the padding between tiles so there are no dead gaps
        return Tile(item: item, app: app, minX: origin[0] - 4, maxX: origin[0] + size[0] + 4)
    }
}

/// SketchyBar only closes a menu when its button is clicked again. Close every
/// bar menu on a click that lands outside both bars and their menus.
func closeMenusIfClickedOutside() {
    let mouse = NSEvent.mouseLocation
    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
    let point = CGPoint(x: mouse.x, y: mainHeight - mouse.y)   // window list uses top-left origin

    DispatchQueue.global(qos: .userInitiated).async {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] ?? []
        let onABar = windows.contains { w in
            guard let owner = w[kCGWindowOwnerName as String] as? String,
                  owner == "sketchybar" || owner == "mochadock",
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.contains(point)
        }
        guard !onABar else { return }
        run("/opt/homebrew/bin/sketchybar", ["--set", "apple", "popup.drawing=off"])
        run(barCommand, ["--set", "/app\\..*/", "popup.drawing=off", "--set", "trash", "popup.drawing=off",
                         "--remove", "/menu\\..*/"])
        try? FileManager.default.removeItem(atPath: "/tmp/mochadock-\(NSUserName())/menu-open")
    }
}

/// Open files with a tile's app, or move them to the Trash for the trash tile
func drop(_ urls: [URL], on tile: Tile, how: String) {
    log("dropped \(urls.count) file(s) on \(tile.item) (\(how))")
    if let app = tile.app {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    } else {
        for url in urls { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }
}

final class DropView: NSView {
    var tiles: [Tile] = []
    var handled = false   // the drop for the current drag already happened
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func tile(at info: NSDraggingInfo) -> Tile? {
        let x = info.draggingLocation.x + (window?.frame.minX ?? 0)
        return tiles.first { x >= $0.minX && x <= $0.maxX }
    }

    // The tile under the drag grows through the normal hover, which follows the pointer
    private func operation(for info: NSDraggingInfo) -> NSDragOperation {
        guard let t = tile(at: info) else { return [] }
        return t.app == nil ? .move : .copy
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        log("drag entered the dock")
        return operation(for: info)
    }
    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation { operation(for: info) }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        guard !handled, let t = tile(at: info),
              let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        handled = true
        drop(urls, on: t, how: "drop")
        return true
    }
}

func currentTheme() -> String {
    (try? String(contentsOfFile: configDir + "/theme.txt", encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "mocha"
}

/// Grows the tile under the pointer and shows its name; every other tile rests
/// with its name hidden. A hovered tile grows into its own padding, so the
/// tiles next to it don't move.
final class Hover {
    private struct Sizes { var tile = 52, gap = 4, radius = 15 }
    private struct Spot { let item: String; let midX: CGFloat }

    private var spots: [Spot] = []
    private var sizes = Sizes()
    private var barTop: CGFloat = 0, barBottom: CGFloat = 0, barShown = false
    private var signature = ""        // what the tile positions were read for
    private var settle = false        // read positions once more after a change
    private var wanted: String?       // tile under the pointer (main thread)
    private var latest: String?       // newest tile asked for (under lock)
    private var allItems: [String] = []   // every tile, for redrawing one by one (under lock)
    private var applied: String?? = .none   // what the dock last showed; .none = unknown

    private let geometryQueue = DispatchQueue(label: "hover.geometry")
    private let applyQueue = DispatchQueue(label: "hover.apply")
    private let lock = NSLock()
    private var pending = false

    /// For the stage (effect themes): where the tiles are, and which tile is under the pointer
    var onGeometry: ((_ spots: [(item: String, midX: CGFloat)], _ yOffset: CGFloat, _ height: CGFloat, _ shown: Bool,
                      _ tile: CGFloat, _ gap: CGFloat) -> Void)?
    var onHover: ((String?) -> Void)?

    func start() {
        refreshGeometry()
        // Positions only change on a reload, an app move, or the full-screen slide
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshGeometry() }
        let poll = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(poll, forMode: .common)   // keep running during drags and menus
    }

    /// Where a tile's center is, and the top of the tray (top-left origin), for the open-apps panel
    func anchor(for item: String) -> (midX: CGFloat, trayTop: CGFloat)? {
        guard let spot = spots.first(where: { $0.item == item }) else { return nil }
        return (spot.midX, barTop + 6)   // the 68pt tray sits centered in the 80pt bar
    }

    /// Where each tile sits now, padding included (main thread)
    func currentSpots() -> [(item: String, minX: CGFloat, maxX: CGFloat)] {
        lock.lock(); let s = sizes; lock.unlock()
        let half = CGFloat(s.tile / 2 + s.gap)
        return spots.map { ($0.item, $0.midX - half, $0.midX + half) }
    }

    private func refreshGeometry() {
        geometryQueue.async { [self] in
            guard let bar = try? JSONSerialization.jsonObject(with: run(barCommand, ["--query", "bar"])) as? [String: Any],
                  let height = bar["height"] as? Int, let yOffset = bar["y_offset"] as? Int else { return }
            let items = (bar["items"] as? [String] ?? []).joined(separator: ",")
            let appsDate = (try? FileManager.default.attributesOfItem(atPath: configDir + "/apps.txt")[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? 0
            // A theme or color change reloads the dock and can change the tile corners
            let lookDate = ["theme.txt", "custom-\(currentTheme()).sh"].map { name in
                (try? FileManager.default.attributesOfItem(atPath: configDir + "/" + name)[.modificationDate] as? Date)?
                    .timeIntervalSince1970 ?? 0 }
            // away (a full-screen space, or parked below the screen), SketchyBar reports no positions: read them again when it's back
            let sig = "\(items)|\(bar["margin"] ?? "")|\(appsDate)|\(lookDate)|\(yOffset >= 0)|\(dockOnScreen())"

            var newSpots: [Spot]?
            var newSizes: Sizes?
            if sig != signature || settle {
                settle = sig != signature
                signature = sig
                newSpots = loadTiles().map { Spot(item: $0.item, midX: ($0.minX + $0.maxX) / 2) }
                newSizes = readSizes()
            }
            let screenHeight = NSScreen.screens.first?.frame.height ?? 0
            let shown = (bar["hidden"] as? String) != "on" && (bar["drawing"] as? String) != "off"
            DispatchQueue.main.async { [self] in
                barBottom = screenHeight - CGFloat(yOffset)   // top-left origin, like the tile positions
                barTop = barBottom - CGFloat(height)
                barShown = shown
                if let newSpots {
                    spots = newSpots
                    lock.lock()
                    allItems = newSpots.map(\.item)
                    if let newSizes { sizes = newSizes }
                    applied = .none   // the dock may have reloaded: redraw it
                    lock.unlock()
                    request(wanted)
                }
                onGeometry?(spots.map { ($0.item, $0.midX) }, CGFloat(yOffset), CGFloat(height), shown, CGFloat(sizes.tile), CGFloat(sizes.gap))
            }
        }
    }

    private func readSizes() -> Sizes {
        let out = run("/bin/bash", ["-c", "source \"$CONFIG_DIR/colors.sh\"; source \"$CONFIG_DIR/sizes.sh\"; echo $TILE $TILE_GAP $TILE_RADIUS"])
        let n = (String(data: out, encoding: .utf8) ?? "").split(separator: " ").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard n.count == 3 else { return Sizes() }
        return Sizes(tile: n[0], gap: n[1], radius: n[2])
    }

    private func poll() {
        let mouse = NSEvent.mouseLocation
        let y = (NSScreen.screens.first?.frame.height ?? 0) - mouse.y
        var item: String?
        if barShown && y >= barTop && y <= barBottom {
            let half = CGFloat(sizes.tile / 2 + sizes.gap)   // a tile plus its padding: no dead gaps
            item = spots.first { abs(mouse.x - $0.midX) <= half }?.item
        }
        guard item != wanted else { return }
        wanted = item
        request(item)
        onHover?(item)
    }

    /// Updates go out one at a time; while one is running, only the newest wish is kept
    private func request(_ item: String?) {
        lock.lock()
        latest = item
        let start = !pending
        pending = true
        lock.unlock()
        if start { applyQueue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            let target = latest
            if case .some(let shown) = applied, shown == target { pending = false; lock.unlock(); return }
            let s = sizes
            lock.unlock()
            show(target, s)
            lock.lock(); applied = .some(target); lock.unlock()
        }
    }

    private func size(_ step: Int, _ s: Sizes) -> [String] {
        let size = s.tile + 2 * step, pad = s.gap - step
        return ["icon.width=\(size)", "padding_left=\(pad)", "padding_right=\(pad)",
                "background.height=\(size)", "background.corner_radius=\(s.radius * size / s.tile)"]   // corners grow with the tile, so circles stay round
    }

    private func show(_ item: String?, _ s: Sizes) {
        let menuFile = "/tmp/mochadock-\(NSUserName())/menu-open"
        var openMenu = (try? String(contentsOfFile: menuFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var args: [String] = []
        // Hovering another tile closes an open right-click menu
        if !openMenu.isEmpty, let item, item != openMenu {
            args += ["--set", openMenu, "popup.drawing=off", "--remove", "/menu\\..*/"]
            try? FileManager.default.removeItem(atPath: menuFile)
            openMenu = ""
        }
        lock.lock(); let tiles = allItems; lock.unlock()
        // Tile by tile, so an open menu is never switched off and back on (that
        // made it flicker whenever the pointer moved toward it)
        for tile in tiles.isEmpty ? ["/app\\..*/", "trash"] : tiles {
            if tile == item {
                args += ["--set", tile] + size(s.gap, s) + ["popup.drawing=on"]
            } else if tile == openMenu {
                args += ["--set", tile] + size(0, s)   // its menu stays up for the pointer to reach
            } else {
                args += ["--set", tile] + size(0, s) + ["popup.drawing=off"]
            }
        }
        if tiles.isEmpty, let item { args += ["--set", item] + size(s.gap, s) + ["popup.drawing=on"] }
        run(barCommand, args)
    }
}

final class Helper: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var view: DropView!
    private let dragBoard = NSPasteboard(name: .drag)
    private var restingChangeCount = 0
    private var catching = false
    private let hover = Hover()
    private let appsPanel = AppsPanel()
    private let gallery = ThemeGallery()
    private let stage = Stage()
    private let widget = WeatherWidget()

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        // macOS lets drags fall through fully transparent pixels, and anything under
        // ~0.4% alpha rounds to transparent, so use 2%: still invisible over the tray
        window.backgroundColor = NSColor(white: 0, alpha: 0.02)
        window.hasShadow = false
        window.level = .popUpMenu                                  // above SketchyBar's window
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        view = DropView(frame: .zero)
        window.contentView = view
        restingChangeCount = dragBoard.changeCount

        // Mouse-down monitoring needs no permissions (only keyboard monitoring does)
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            closeMenusIfClickedOutside()
            self?.appsPanel.clickedAt(NSEvent.mouseLocation)
            self?.gallery.clickedAt(NSEvent.mouseLocation)
        }

        // Theme… (plugins/menu.sh) asks for the theme gallery, centered over the dock
        DistributedNotificationCenter.default().addObserver(forName: toggleGalleryNote, object: nil, queue: .main) { [weak self] _ in
            guard let self, let spot = self.hover.anchor(for: "trash") else { return }
            self.appsPanel.close()
            self.gallery.toggle(midX: NSScreen.screens.first?.frame.midX ?? spot.midX, trayTop: spot.trayTop)
        }

        // Right-clicking the trash (plugins/menu.sh) asks for the open-apps panel
        DistributedNotificationCenter.default().addObserver(forName: toggleAppsNote, object: nil, queue: .main) { [weak self] _ in
            guard let self, let spot = self.hover.anchor(for: "trash") else { return }
            self.appsPanel.toggle(midX: spot.midX, trayTop: spot.trayTop)
        }

        // Effect themes animate on a stage behind the tiles (stage.swift)
        hover.onGeometry = { [weak self] in self?.stage.update(spots: $0, yOffset: $1, height: $2, shown: $3, tile: $4, gap: $5) }
        hover.onHover = { [weak self] in self?.stage.hoverChanged($0) }
        stage.start()
        widget.start()
        hover.start()

        // Watch for file drags 20 times a second; this is cheap and needs no permissions
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        if !buttonDown {
            if catching {
                dropWherePointerIs()
                stopCatching()
            }
            restingChangeCount = dragBoard.changeCount
            return
        }
        // The drag pasteboard changes when something starts being dragged
        if !catching && dragBoard.changeCount != restingChangeCount {
            let types = dragBoard.types ?? []
            log("drag started, types: \(types.map(\.rawValue).joined(separator: ", "))")
            restingChangeCount = dragBoard.changeCount
            if types.contains(.fileURL) { startCatching() }
        }
    }

    /// Backup for the drop itself: since macOS 27 the drop window isn't always told
    /// about the drag, so when the button comes up over a tile, read the dragged
    /// files and act on them here. Does nothing if the real drop already happened.
    private func dropWherePointerIs() {
        guard !view.handled else { return }
        let mouse = NSEvent.mouseLocation
        guard window.frame.contains(mouse),
              let tile = view.tiles.first(where: { mouse.x >= $0.minX && mouse.x <= $0.maxX }),
              let urls = dragBoard.readObjects(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return }
        view.handled = true
        drop(urls, on: tile, how: "release over tile")
    }

    /// Tile positions from the hover (kept current, so this is instant), with each
    /// tile's app from apps.txt; asks SketchyBar only if the hover has none yet
    private func currentTiles() -> [Tile] {
        let spots = hover.currentSpots()
        guard !spots.isEmpty,
              let text = try? String(contentsOfFile: configDir + "/apps.txt", encoding: .utf8) else { return loadTiles() }
        var apps: [String: URL] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            if fields.count >= 2 { apps["app." + fields[0]] = URL(fileURLWithPath: String(fields[1])) }
        }
        return spots.map { Tile(item: $0.item, app: apps[$0.item], minX: $0.minX, maxX: $0.maxX) }
    }

    private func startCatching() {
        let tiles = currentTiles()
        view.handled = false
        guard let screen = NSScreen.main, let first = tiles.first, let last = tiles.last else {
            log("no tile positions from SketchyBar; not catching")
            return
        }
        view.tiles = tiles
        let minX = tiles.map(\.minX).min() ?? first.minX
        let maxX = tiles.map(\.maxX).max() ?? last.maxX
        window.setFrame(NSRect(x: minX, y: screen.frame.minY, width: maxX - minX, height: dockHeight), display: false)
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
        catching = true
        log("catching drops over x \(Int(minX))–\(Int(maxX)) for \(tiles.count) tiles")
    }

    private func stopCatching() {
        catching = false
        // Give the drop a moment to land before letting clicks through again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.catching else { return }
            self.window.ignoresMouseEvents = true
            self.window.orderOut(nil)
        }
    }
}

// dockdrop slide <y_offset> <seconds>: fullscreen.sh is sliding the dock; the stage follows it
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "slide" {
    DistributedNotificationCenter.default().postNotificationName(slideNote, object: "\(CommandLine.arguments[2]),\(CommandLine.arguments[3])",
                                                                 userInfo: nil, deliverImmediately: true)
    exit(0)
}

// dockdrop widget [show|hide|toggle]: the weather widget in the running helper
if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "widget" {
    DistributedNotificationCenter.default().postNotificationName(widgetNote, object: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "toggle",
                                                                 userInfo: nil, deliverImmediately: true)
    exit(0)
}
// dockdrop widget-preview <out.png> <theme> [medium]: a picture of the widget in a theme
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "widget-preview" {
    _ = NSApplication.shared
    widgetPreview(Array(CommandLine.arguments.dropFirst()))
    exit(0)
}

// dockdrop apps | themes: open or close the open-apps panel or the theme gallery in the running helper
if let command = CommandLine.arguments.dropFirst().first, command == "apps" || command == "themes" {
    DistributedNotificationCenter.default().postNotificationName(command == "apps" ? toggleAppsNote : toggleGalleryNote,
                                                                 object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
let helper = Helper()
app.delegate = helper
app.run()
