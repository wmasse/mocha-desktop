// The open-apps panel: right-click the trash to see every open app as its icon,
// each with a small ✕ beside it to quit it. Clicking an icon switches to that
// app; hovering one shows its name in the header. The footer keeps the trash's
// own actions. Colors, corners and fonts come from the current dock theme.

import AppKit

let toggleAppsNote = Notification.Name("io.github.wmasse.mocha.dock.apps")

/// "0xAARRGGBB" → NSColor
func themeColor(_ value: String, _ fallback: NSColor = .gray) -> NSColor {
    let hex = value.hasPrefix("0x") ? String(value.dropFirst(2)) : value
    guard hex.count == 8, let v = UInt32(hex, radix: 16) else { return fallback }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: CGFloat(v >> 24) / 255)
}

/// The theme's menu look, read from colors.sh each time the panel opens
struct PanelLook {
    var background = themeColor("0xff313244"), border = themeColor("0xff45475a")
    var text = themeColor("0xffcdd6f4"), subtext = themeColor("0xffbac2de"), muted = themeColor("0xff9399b2")
    var red = themeColor("0xfff38ba8"), hover = themeColor("0xff45475a")
    var radius: CGFloat = 14

    static func current() -> PanelLook {
        let script = "source \"$CONFIG_DIR/colors.sh\"; echo $MENU_COLOR $MENU_BORDER_COLOR $TEXT $SUBTEXT $OVERLAY $RED $PILL_HOVER_COLOR $MENU_RADIUS $LABEL_FONT"
        let words = (String(data: run("/bin/bash", ["-c", script]), encoding: .utf8) ?? "")
            .split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        var look = PanelLook()
        guard words.count >= 8 else { return look }
        look.background = themeColor(words[0], look.background)
        look.border = themeColor(words[1], look.border)
        look.text = themeColor(words[2], look.text)
        look.subtext = themeColor(words[3], look.subtext)
        look.muted = themeColor(words[4], look.muted)
        look.red = themeColor(words[5], look.red)
        look.hover = themeColor(words[6], look.hover)
        look.radius = min(18, CGFloat(Double(words[7]) ?? 14))
        if words.count > 8 { panelFamily = words[8...].joined(separator: " ") }   // family names can have spaces
        return look
    }
}

/// The theme's typeface (LABEL_FONT), set each time the panel opens
var panelFamily = "Hack Nerd Font"

func panelFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
    NSFontManager.shared.font(withFamily: panelFamily, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: size)
        ?? NSFont(name: bold ? "Hack Nerd Font Bold" : "Hack Nerd Font", size: size)
        ?? (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
}

/// A view that tracks the pointer and draws a rounded highlight under it
class HoverView: NSView {
    var highlight: NSColor = .clear
    var cornerRadius: CGFloat = 10
    var hovering = false { didSet { if oldValue != hovering { needsDisplay = true; hoverChanged() } } }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        highlight.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }
    func hoverChanged() {}
}

/// The small ✕ beside an icon; turns red under the pointer
final class QuitBadge: HoverView {
    var look = PanelLook()
    var onQuit: () -> Void = {}
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        (hovering ? look.red : look.background).setFill(); circle.fill()
        (hovering ? look.red : look.border).setStroke(); circle.lineWidth = 1; circle.stroke()
        let cross = NSBezierPath()
        let inset = bounds.width * 0.32
        cross.move(to: NSPoint(x: inset, y: inset)); cross.line(to: NSPoint(x: bounds.maxX - inset, y: bounds.maxY - inset))
        cross.move(to: NSPoint(x: bounds.maxX - inset, y: inset)); cross.line(to: NSPoint(x: inset, y: bounds.maxY - inset))
        cross.lineWidth = 1.6; cross.lineCapStyle = .round
        (hovering ? look.background : look.muted).setStroke(); cross.stroke()
    }
    override func mouseUp(with event: NSEvent) { onQuit() }
}

/// One open app: its icon (click to switch to it) with the ✕ beside it
final class AppCell: HoverView {
    let app: NSRunningApplication
    var onHover: (NSRunningApplication?) -> Void = { _ in }
    var onPick: () -> Void = {}
    init(app: NSRunningApplication, look: PanelLook, frame: NSRect) {
        self.app = app
        super.init(frame: frame)
        highlight = look.hover
        let icon = NSImageView(frame: NSRect(x: 10, y: 12, width: 44, height: 44))
        icon.image = app.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hoverChanged() { onHover(hovering ? app : nil) }
    override func mouseUp(with event: NSEvent) { onPick() }
}

/// A text button in the footer
final class FooterButton: HoverView {
    let title: String, color: NSColor, action: () -> Void
    init(title: String, look: PanelLook, frame: NSRect, action: @escaping () -> Void) {
        self.title = title; self.color = look.subtext; self.action = action
        super.init(frame: frame)
        highlight = look.hover; cornerRadius = 8
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let attrs: [NSAttributedString.Key: Any] = [.font: panelFont(11.5, bold: true), .foregroundColor: color]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                 withAttributes: attrs)
    }
    override func mouseUp(with event: NSEvent) { action() }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class AppsPanel {
    private var panel: NSPanel?
    private var anchor: (midX: CGFloat, trayTop: CGFloat) = (0, 0)
    private var lastClosed = Date.distantPast
    private var subtitle: NSTextField?

    var isOpen: Bool { panel?.isVisible ?? false }

    /// Right-clicking the trash again closes it. The click itself first lands as an
    /// outside click and closes the panel, so a toggle right after that stays closed.
    func toggle(midX: CGFloat, trayTop: CGFloat) {
        log("apps panel: toggle (open: \(isOpen), anchor x \(Int(midX)) top \(Int(trayTop)))")
        if isOpen { close(); return }
        if Date().timeIntervalSince(lastClosed) < 0.35 { return }
        anchor = (midX, trayTop)
        build()
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        log("apps panel: closed")
        panel.orderOut(nil)
        lastClosed = Date()
    }

    /// Close on a click anywhere outside the panel
    func clickedAt(_ point: NSPoint) {
        guard let panel, panel.isVisible, !panel.frame.contains(point) else { return }
        close()
    }

    private func openApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid() }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func build() {
        let look = PanelLook.current()
        let apps = openApps()
        let cell: CGFloat = 64, gap: CGFloat = 10, pad: CGFloat = 22, badge: CGFloat = 18
        let cols = max(4, min(6, apps.count))
        let rows = max(1, Int(ceil(Double(apps.count) / Double(cols))))
        let gridWidth = CGFloat(cols) * (cell + badge / 2) + CGFloat(cols - 1) * gap
        let width = max(300, gridWidth + pad * 2)
        let header: CGFloat = 58, footer: CGFloat = 54
        let height = header + CGFloat(rows) * (cell + gap) - gap + 10 + footer

        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        content.layer?.backgroundColor = look.background.cgColor
        content.layer?.cornerRadius = look.radius
        content.layer?.borderWidth = 1
        content.layer?.borderColor = look.border.cgColor
        content.layer?.masksToBounds = true

        // Header: title, count, and the hovered app's name
        let title = NSTextField(labelWithString: "Open Apps")
        title.font = panelFont(13, bold: true); title.textColor = look.text
        title.frame = NSRect(x: pad, y: 16, width: 160, height: 18)
        content.addSubview(title)
        let count = NSTextField(labelWithString: "\(apps.count)")
        count.font = panelFont(11, bold: true); count.textColor = look.muted; count.alignment = .right
        count.frame = NSRect(x: width - pad - 40, y: 17, width: 40, height: 16)
        content.addSubview(count)
        let sub = NSTextField(labelWithString: "Click to switch · ✕ to quit")
        sub.font = panelFont(11); sub.textColor = look.muted; sub.lineBreakMode = .byTruncatingTail
        sub.frame = NSRect(x: pad, y: 35, width: width - pad * 2, height: 15)
        content.addSubview(sub)
        subtitle = sub

        // The grid, centered
        let startX = (width - gridWidth) / 2
        for (i, app) in apps.enumerated() {
            let col = CGFloat(i % cols), row = CGFloat(i / cols)
            let x = startX + col * (cell + badge / 2 + gap), y = header + row * (cell + gap)
            let c = AppCell(app: app, look: look, frame: NSRect(x: x, y: y, width: cell, height: cell))
            c.cornerRadius = min(14, look.radius)
            c.onHover = { [weak self] hovered in
                self?.subtitle?.stringValue = hovered?.localizedName ?? "Click to switch · ✕ to quit"
                self?.subtitle?.textColor = hovered == nil ? look.muted : look.text
            }
            c.onPick = { [weak self] in app.activate(); self?.close() }
            content.addSubview(c)
            let q = QuitBadge(frame: NSRect(x: x + cell - badge / 2 - 4, y: y + 2, width: badge, height: badge))
            q.look = look
            q.onQuit = { [weak self] in
                app.terminate()
                // Rebuild once it's gone (an app asking to save stays until you answer)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if self?.isOpen == true { self?.build() } }
            }
            content.addSubview(q)
        }
        if apps.isEmpty {
            let none = NSTextField(labelWithString: "No apps open")
            none.font = panelFont(12); none.textColor = look.muted
            none.frame = NSRect(x: pad, y: header + 20, width: width - pad * 2, height: 18)
            content.addSubview(none)
        }

        // Footer: the trash's own actions
        let line = NSView(frame: NSRect(x: pad, y: height - footer, width: width - pad * 2, height: 1))
        line.wantsLayer = true; line.layer?.backgroundColor = look.border.cgColor
        content.addSubview(line)
        let menuScript = configDir + "/plugins/menu.sh"
        let actions: [(String, () -> Void)] = [
            ("Open Trash", { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")) }),
            ("Add App", { DispatchQueue.global().async { run("/bin/bash", [menuScript, "add", "trash"]) } }),
            ("Theme", { DistributedNotificationCenter.default().postNotificationName(toggleGalleryNote, object: nil,
                                                                                     userInfo: nil, deliverImmediately: true) }),
        ]
        let buttonWidth = (width - pad * 2 - 8) / CGFloat(actions.count)
        for (i, (name, act)) in actions.enumerated() {
            let b = FooterButton(title: name, look: look,
                                 frame: NSRect(x: pad + CGFloat(i) * (buttonWidth + 4), y: height - footer + 12,
                                               width: buttonWidth, height: 30)) { [weak self] in
                self?.close(); act()
            }
            content.addSubview(b)
        }

        // Above the trash, clamped to the screen
        let screen = NSScreen.screens.first?.frame ?? .zero
        let x = min(max(anchor.midX - width / 2, screen.minX + 8), screen.maxX - width - 8)
        let y = screen.maxY - anchor.trayTop + 10   // trayTop uses a top-left origin

        let p = panel ?? makePanel()
        p.setContentSize(NSSize(width: width, height: height))
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.contentView = content
        p.orderFrontRegardless()
        panel = p
        log("apps panel: shown \(apps.count) apps at \(p.frame), visible \(p.isVisible)")
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return p
    }
}
