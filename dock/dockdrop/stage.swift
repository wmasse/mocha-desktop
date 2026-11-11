// The stage: an animated layer behind the dock's tiles, for effect themes (themes that
// set STAGE_EFFECT). It sits one window level below SketchyBar's dock windows, so the
// tiles and icons always draw on top of it, and it reaches above the tray so an effect
// can rise past the icons. It never takes the mouse. The effects themselves are in
// effects.swift; they react to the app you're on, the tile under the pointer, and
// which apps are open.
//
// Animation runs only as fast as the effect asks: 60fps while something is moving,
// slower or not at all once it settles, and nothing in Low Power Mode or while the
// screen sleeps.
import AppKit

let slideNote = Notification.Name("io.github.wmasse.mocha.dock.slide")

/// What an effect sees each frame. Points, y up, origin at the stage's bottom-left.
struct StageScene {
    var size: CGSize
    var tray: CGRect
    var tiles: [CGRect]          // every tile, the Trash last
    var front: Int?              // the tile of the app you're on
    var previous: Int?           // the one before
    var switched: Double         // when front last changed (stage time)
    var hover: Int?
    var hovered: Double          // when hover last changed
    var running: Set<Int>
    var time: Double             // seconds since the stage started
    var dt: Double               // seconds since the last frame
    var lowPower: Bool

    /// One "point" at the dock's own scale (the gallery's cards draw smaller)
    var u: CGFloat { tray.height / 68 }
    func center(_ i: Int?) -> CGFloat? {
        guard let i, i >= 0, i < tiles.count else { return nil }
        return tiles[i].midX
    }
    func tile(_ i: Int?) -> CGRect? {
        guard let i, i >= 0, i < tiles.count else { return nil }
        return tiles[i]
    }
    var sinceSwitch: Double { time - switched }
    var sinceHover: Double { time - hovered }
}

protocol StageEffect: AnyObject {
    func draw(_ ctx: CGContext, _ s: StageScene)
    /// Frames per second wanted now; 0 when nothing is moving
    func fps(_ s: StageScene) -> Double
}

final class StageView: NSView {
    var effect: StageEffect?
    var scene: StageScene?
    override var isFlipped: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        guard let effect, let scene, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        effect.draw(ctx, scene)
    }
}

final class Stage {
    private var window: NSWindow?
    private var view: StageView?
    private var effect: StageEffect?
    private var effectName = ""
    private var timer: Timer?
    private let started = Date()
    private var lastFrame = 0.0
    private var themeStamp = -1.0

    // Where the dock is (screen points; x from the left)
    private var trayMinX: CGFloat = 0, trayWidth: CGFloat = 0
    private var mids: [CGFloat] = []
    private var items: [String] = []
    private var tileSize: CGFloat = 52
    private var yOffset: CGFloat = 8, barHeight: CGFloat = 80, shown = false
    private var slidingUntil = 0.0
    private var barBottom: CGFloat?        // where the dock's window really is (bottom-left origin), and
    private var measuredAt: CGFloat = 8    // the y_offset it was measured at

    // What the dock is doing
    private var bundles: [String: String] = [:]   // bundle id → item
    private var front: Int?, previous: Int?, switchedAt = 0.0
    private var hover: Int?, hoveredAt = 0.0
    private var running: Set<Int> = []
    private var asleep = false
    private var fullScreenSpace = false   // the dock isn't on this space (a full-screen app), so neither is this

    private let margin: CGFloat = 40, headroom: CGFloat = 72, trayHeight: CGFloat = 68

    private var now: Double { Date().timeIntervalSince(started) }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.readApps() }
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.readApps() }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.readApps() }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.asleep = true }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = false; self?.kick()
        }
        // full-screen spaces have no dock; check after each space switch (they finish animating a moment later)
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            for delay in [0.0, 0.3, 1.0] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.checkSpace() } }
        }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.kick() }
        // fullscreen.sh slides the dock away and back; follow it
        DistributedNotificationCenter.default().addObserver(forName: slideNote, object: nil, queue: .main) { [weak self] note in
            let parts = (note.object as? String ?? "").split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else { return }
            self?.slide(to: CGFloat(parts[0]), over: parts[1])
        }
        // A theme switch rewrites theme.txt; checking its date once a second costs nothing
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkTheme()
            if self?.effect != nil { self?.checkSpace() }   // in case a space switch was missed
        }
        checkTheme()
        checkSpace()
    }

    /// From the hover's geometry reads (main thread)
    func update(spots: [(item: String, midX: CGFloat)], yOffset: CGFloat, height: CGFloat, shown: Bool, tile: CGFloat, gap: CGFloat) {
        var changed = false
        let newItems = spots.map(\.item), newMids = spots.map(\.midX)
        if newItems != items || newMids != mids { items = newItems; mids = newMids; changed = true; readBundles() }
        // the tray runs from the first tile to the Trash, padding included
        if let first = newMids.min(), let last = newMids.max() {
            let minX = first - tile / 2 - gap, width = last - first + tile + 2 * gap
            if minX != trayMinX || width != trayWidth { trayMinX = minX; trayWidth = width; changed = true }
        }
        if now > slidingUntil, yOffset != self.yOffset { self.yOffset = yOffset; changed = true }
        if height != barHeight || shown != self.shown || tile != tileSize { barHeight = height; self.shown = shown; tileSize = tile; changed = true }
        if changed { place(); readApps() }
    }

    func hoverChanged(_ item: String?) {
        let i = item.flatMap { items.firstIndex(of: $0) }
        guard i != hover else { return }
        hover = i; hoveredAt = now
        kick()
    }

    // MARK: theme

    private func checkTheme() {
        let stamp = ["theme.txt", "custom-\(currentTheme()).sh"].map { name in
            (try? FileManager.default.attributesOfItem(atPath: configDir + "/" + name)[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? 0 }.reduce(0, +)
        guard stamp != themeStamp else { return }
        themeStamp = stamp
        DispatchQueue.global().async {
            let out = run("/bin/bash", ["-c", "source \"$CONFIG_DIR/colors.sh\"; echo \"$STAGE_EFFECT\""])
            let name = (String(data: out, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { [weak self] in self?.use(name) }
        }
    }

    private func use(_ name: String) {
        guard name != effectName else { return }
        effectName = name
        effect = makeEffect(name)
        timer?.invalidate(); timer = nil
        if effect == nil { window?.orderOut(nil); return }
        if window == nil { makeWindow() }
        view?.effect = effect
        place()
        readApps()
    }

    // MARK: apps

    private func readBundles() {
        guard let text = try? String(contentsOfFile: configDir + "/apps.txt", encoding: .utf8) else { return }
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let f = line.split(separator: "|", omittingEmptySubsequences: false)
            if f.count >= 3 { map[String(f[2])] = "app." + f[0] }
        }
        bundles = map
    }

    private func readApps() {
        guard effect != nil else { return }
        if bundles.isEmpty { readBundles() }
        let open = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        running = Set(items.indices.filter { i in bundles.contains { $0.value == items[i] && open.contains($0.key) } })
        let frontItem = NSWorkspace.shared.frontmostApplication?.bundleIdentifier.flatMap { bundles[$0] }
        let f = frontItem.flatMap { items.firstIndex(of: $0) }
        if f != front { previous = front; front = f; switchedAt = now }
        kick()
    }

    // MARK: window

    private func makeWindow() {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = NSWindow.Level(rawValue: 2)   // just under SketchyBar's dock windows (level 3)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = true
        let v = StageView(frame: .zero)
        v.wantsLayer = true
        v.layerContentsRedrawPolicy = .onSetNeedsDisplay
        w.contentView = v
        window = w; view = v
    }

    private var frameRect: NSRect {
        let bottom = (barBottom ?? yOffset) + (yOffset - measuredAt)
        return NSRect(x: trayMinX - margin, y: bottom, width: trayWidth + 2 * margin, height: barHeight + headroom)
    }

    /// SketchyBar draws the tray in a window of its own; read where that window really sits,
    /// since the bar can end up a few points off its y_offset
    private func measureBar() {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let screenHeight = NSScreen.screens.first?.frame.height else { return }
        for w in list where (w["kCGWindowOwnerName"] as? String) == barCommand.split(separator: "/").last.map(String.init) {
            guard let b = w["kCGWindowBounds"] as? [String: CGFloat], let x = b["X"], let y = b["Y"], let width = b["Width"],
                  let height = b["Height"], abs(width - trayWidth) < 3, abs(x - trayMinX) < 3 else { continue }
            barBottom = screenHeight - (y + height)
            measuredAt = yOffset
            return
        }
    }

    /// Parked below the screen (a full-screen app is up): the dock is out of sight, so the effect goes too.
    /// Its window reaches higher than the dock, so moving it down with the dock would leave the top showing.
    private var parked: Bool { yOffset < 0 }

    /// Show only where SketchyBar is showing the dock
    private func checkSpace() {
        let away = !dockOnScreen()
        guard away != fullScreenSpace else { return }
        fullScreenSpace = away
        place()
    }

    private func place() {
        guard let window, effect != nil else { return }
        guard shown, !parked, !fullScreenSpace, trayWidth > 0, !mids.isEmpty else { window.orderOut(nil); return }
        if now <= slidingUntil { return }   // mid-slide: the slide puts it in place
        window.alphaValue = 1
        if now > slidingUntil { measureBar() }
        window.setFrame(frameRect, display: false)
        view?.frame = NSRect(origin: .zero, size: frameRect.size)
        window.orderFrontRegardless()
        kick()
    }

    /// Goes down with the dock, fading as it goes, and comes back up with it
    private func slide(to y: CGFloat, over seconds: Double) {
        let wasParked = parked
        yOffset = y
        guard let window, effect != nil, shown, !fullScreenSpace, trayWidth > 0, !mids.isEmpty else { return }
        if parked {
            guard window.isVisible else { return }
            slidingUntil = now + seconds + 0.6
            let target = frameRect
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = seconds
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().setFrame(target, display: true)
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.parked else { return }
                window.orderOut(nil); self.timer?.invalidate(); self.timer = nil
            })
        } else {
            let target = frameRect
            if wasParked || !window.isVisible {
                // start from where the dock is coming up from
                window.setFrame(target.offsetBy(dx: 0, dy: -96), display: false)
                view?.frame = NSRect(origin: .zero, size: target.size)
                window.alphaValue = 0
                window.orderFrontRegardless()
                kick()
            }
            slidingUntil = now + seconds + 0.6
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = seconds
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(target, display: true)
                window.animator().alphaValue = 1
            }, completionHandler: { [weak self] in
                self?.slidingUntil = 0; self?.place()
            })
        }
    }

    // MARK: frames

    private func scene() -> StageScene {
        let trayRect = CGRect(x: margin, y: (barHeight - trayHeight) / 2, width: trayWidth, height: trayHeight)
        let tiles = mids.map { mid in
            CGRect(x: mid - trayMinX + margin - tileSize / 2, y: trayRect.midY - tileSize / 2, width: tileSize, height: tileSize)
        }
        let t = now
        let dt = min(max(t - lastFrame, 1.0 / 240), 1.0 / 15)
        lastFrame = t
        return StageScene(size: frameRect.size, tray: trayRect, tiles: tiles, front: front, previous: previous,
                          switched: switchedAt, hover: hover, hovered: hoveredAt, running: running, time: t, dt: dt,
                          lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    /// Something changed: draw now, then keep drawing as long as the effect wants
    private func kick() {
        guard effect != nil, window?.isVisible == true, timer == nil else { return }
        lastFrame = now - 1.0 / 60
        frame()
    }

    private func frame() {
        timer = nil
        guard let effect, let view, let window, window.isVisible, !asleep else { return }
        let s = scene()
        view.scene = s
        view.display()
        let fps = min(effect.fps(s), 60)
        guard fps > 0 else { return }
        let t = Timer(timeInterval: 1 / fps, repeats: false) { [weak self] _ in self?.frame() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// A still of an effect, settled, for the theme gallery's cards
    static func preview(_ name: String, size: CGSize, tiles: [CGRect]) -> NSImage? {
        guard let effect = makeEffect(name) else { return nil }
        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        var s = StageScene(size: size, tray: CGRect(origin: .zero, size: size), tiles: tiles, front: 1, previous: nil,
                           switched: 0, hover: nil, hovered: -10, running: [0, 1], time: 0, dt: 1.0 / 30, lowPower: false)
        for f in 0...75 {   // run it for 2.5 seconds so it settles, keeping the last frame
            s.time = Double(f) / 30
            ctx.clear(CGRect(origin: .zero, size: size))
            effect.draw(ctx, s)
        }
        guard let image = ctx.makeImage() else { return nil }
        return NSImage(cgImage: image, size: size)
    }
}
