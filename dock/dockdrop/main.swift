// dockdrop — lets you drop files onto the Mocha dock like the real Dock.
//
// SketchyBar can't receive drag-and-drop, so this helper keeps an invisible
// window over the dock. The window lets every click through, and only starts
// catching drops while a file drag is in progress. Dropping on an app tile
// opens the files with that app; dropping on the trash moves them to the Trash.
//
// It also closes the bars' menus (the Apple menu and the dock's right-click
// menus) when you click anywhere outside the bars, like a normal menu.

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

final class DropView: NSView {
    var tiles: [Tile] = []
    private var highlighted: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func tile(at info: NSDraggingInfo) -> Tile? {
        let x = info.draggingLocation.x + (window?.frame.minX ?? 0)
        return tiles.first { x >= $0.minX && x <= $0.maxX }
    }

    /// Reuse the dock's own hover so the tile under the drag grows like on mouse-over
    private func highlight(_ item: String?) {
        guard item != highlighted else { return }
        let hover = configDir + "/plugins/tile.sh"
        if let old = highlighted { run("/bin/bash", [hover], extraEnv: ["NAME": old, "SENDER": "mouse.exited"]) }
        if let new = item { run("/bin/bash", [hover], extraEnv: ["NAME": new, "SENDER": "mouse.entered"]) }
        highlighted = item
    }

    private func operation(for info: NSDraggingInfo) -> NSDragOperation {
        guard let t = tile(at: info) else { highlight(nil); return [] }
        highlight(t.item)
        return t.app == nil ? .move : .copy
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        log("drag entered the dock")
        return operation(for: info)
    }
    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation { operation(for: info) }
    override func draggingExited(_ info: NSDraggingInfo?) { highlight(nil) }
    override func draggingEnded(_ info: NSDraggingInfo) { highlight(nil) }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        defer { highlight(nil) }
        guard let t = tile(at: info),
              let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }

        log("dropped \(urls.count) file(s) on \(t.item)")
        if let app = t.app {
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            for url in urls { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        }
        return true
    }
}

final class Helper: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var view: DropView!
    private let dragBoard = NSPasteboard(name: .drag)
    private var restingChangeCount = 0
    private var catching = false

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
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            closeMenusIfClickedOutside()
        }

        // Watch for file drags 20 times a second; this is cheap and needs no permissions
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        if !buttonDown {
            if catching { stopCatching() }
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

    private func startCatching() {
        let tiles = loadTiles()
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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
let helper = Helper()
app.delegate = helper
app.run()
