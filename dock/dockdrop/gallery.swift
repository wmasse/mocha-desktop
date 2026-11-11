// The theme gallery: a card per theme, each a tiny dock drawn in that theme (its
// scenery or tray, a few tiles in its style, its name in its own typeface).
// Click a card to switch; the gallery stays open (and takes on the new theme) so
// you can try a few. Opened from Theme… in the dock's menus.

import AppKit

let toggleGalleryNote = Notification.Name("io.github.wmasse.mocha.dock.themes")

/// What a card needs from a theme file (read in a clean shell, so themes can't leak into each other)
struct ThemeCard {
    let key: String
    var name = "", font = "Hack Nerd Font"
    var menu = NSColor.darkGray, border = NSColor.gray, text = NSColor.white, base = NSColor.black
    var accent = NSColor.systemPink, tray = NSColor.darkGray, trayBorder = NSColor.gray
    var trayRadius: CGFloat = 24, tileRadius: CGFloat = 15
    var idle: [NSColor] = [], running = "fill", runningColor: NSColor?, mono = false
    var appColors: [NSColor] = []
    var scenery: NSImage?

    static func load(key: String) -> ThemeCard {
        var card = ThemeCard(key: key)
        let script = """
            source "$1"; THEME_DIR="$2"; source "$2/style.sh"
            printf '%s\\n' "$THEME_NAME" "$LABEL_FONT" "$MENU_COLOR" "$MENU_BORDER_COLOR" "$TEXT" "$BASE" "$APPLE_COLOR" \
              "$TRAY_COLOR" "$TRAY_BORDER_COLOR" "$TRAY_RADIUS" "$THEME_TILE_RADIUS" "$TILE_IDLE_COLOR" \
              "$TILE_IDLE_COLORS" "$RUNNING_STYLE" "$RUNNING_COLOR" "$ICON_STYLE" "$BLUE" "$GREEN" "$PEACH" "$MAUVE"
            """
        let out = String(data: run("/usr/bin/env", ["-i", "HOME=" + NSHomeDirectory(), "/bin/bash", "-c", script, "_",
                                                     configDir + "/themes/\(key).sh", configDir]), encoding: .utf8) ?? ""
        let f = out.components(separatedBy: "\n")
        guard f.count >= 20 else { return card }
        card.name = f[0]; card.font = f[1]
        card.menu = themeColor(f[2]); card.border = themeColor(f[3]); card.text = themeColor(f[4])
        card.base = themeColor(f[5]); card.accent = themeColor(f[6]); card.tray = themeColor(f[7])
        card.trayBorder = themeColor(f[8]); card.trayRadius = CGFloat(Double(f[9]) ?? 24)
        card.tileRadius = CGFloat(Double(f[10]) ?? 15)
        let collage = f[12].split(separator: " ").map { themeColor(String($0)) }
        card.idle = collage.isEmpty ? [themeColor(f[11])] : collage
        card.running = f[13]; card.runningColor = f[14].isEmpty ? nil : themeColor(f[14]); card.mono = f[15] == "mono"
        card.appColors = [themeColor(f[16]), themeColor(f[17]), themeColor(f[18]), themeColor(f[19])]
        // The scenery strip, if the theme has one (cached like the dock's)
        let preview = configDir + "/cache/card-\(key).png"
        if !FileManager.default.fileExists(atPath: preview) {
            // the card's own layout: four 24pt tiles, 6pt apart, centered in a 134pt tray
            run(configDir + "/bin/dockart", [key, "134", preview, "44"],
                extraEnv: ["DOCKART_GAPS": "37,67,97", "DOCKART_TILE": "24"])
        }
        card.scenery = NSImage(contentsOfFile: preview)
        return card
    }
}

/// One card: a tiny dock in the theme, and its name
final class CardView: HoverView {
    let card: ThemeCard, current: Bool, look: PanelLook
    var onPick: () -> Void = {}
    init(card: ThemeCard, current: Bool, look: PanelLook, frame: NSRect) {
        self.card = card; self.current = current; self.look = look
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 2, dy: 2)
        let shape = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
        card.menu.setFill(); shape.fill()
        (current ? card.accent : (hovering ? look.text.withAlphaComponent(0.5) : card.border)).setStroke()
        shape.lineWidth = current ? 2.5 : 1; shape.stroke()

        // The tray, with its scenery
        let tray = NSRect(x: box.minX + 10, y: box.minY + 10, width: box.width - 20, height: 44)
        let r = min(card.trayRadius * 44 / 68, 18)
        let trayShape = NSBezierPath(roundedRect: tray, xRadius: r, yRadius: r)
        card.tray.setFill(); trayShape.fill()
        if let img = card.scenery {
            NSGraphicsContext.saveGraphicsState(); trayShape.addClip()
            img.draw(in: tray); NSGraphicsContext.restoreGraphicsState()
        }
        card.trayBorder.setStroke(); trayShape.lineWidth = 1; trayShape.stroke()

        // Four tiles: two open (in the theme's style), two not
        let tile: CGFloat = 24, gap: CGFloat = 6
        let startX = tray.midX - (4 * tile + 3 * gap) / 2
        for i in 0..<4 {
            let rect = NSRect(x: startX + CGFloat(i) * (tile + gap), y: tray.midY - tile / 2, width: tile, height: tile)
            let tr = min(card.tileRadius * tile / 52, tile / 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: tr, yRadius: tr)
            let appColor = card.appColors[i % card.appColors.count]
            let iconColor = card.mono ? card.text : appColor
            var fill = card.idle[i % card.idle.count], glyph = iconColor, outline: NSColor?
            if i < 2 {
                switch card.running {
                case "invert": fill = card.text; glyph = card.base
                case "outline": outline = iconColor
                default: fill = card.runningColor ?? appColor; glyph = card.base
                }
            }
            fill.setFill(); path.fill()
            if let outline { outline.setStroke(); path.lineWidth = 1.5; path.stroke() }
            glyph.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 7.5, dy: 7.5), xRadius: 2.5, yRadius: 2.5).fill()
        }

        // Accent dot and the name, in the theme's typeface
        let nameFont = NSFontManager.shared.font(withFamily: card.font, traits: .boldFontMask, weight: 9, size: 12)
            ?? panelFont(12, bold: true)
        card.accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: box.minX + 12, y: tray.maxY + 13, width: 8, height: 8)).fill()
        (card.name as NSString).draw(at: NSPoint(x: box.minX + 26, y: tray.maxY + 8),
                                     withAttributes: [.font: nameFont, .foregroundColor: card.text])
    }
    override func mouseUp(with event: NSEvent) { onPick() }
}

final class ThemeGallery {
    private var panel: NSPanel?
    private var anchorMidX: CGFloat = 0, trayTop: CGFloat = 0
    private var lastClosed = Date.distantPast
    private var cards: [String: ThemeCard] = [:]   // drawn once per session; themes rarely change

    var isOpen: Bool { panel?.isVisible ?? false }

    func toggle(midX: CGFloat, trayTop: CGFloat) {
        if isOpen { close(); return }
        if Date().timeIntervalSince(lastClosed) < 0.35 { return }
        anchorMidX = midX; self.trayTop = trayTop
        build()
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil); lastClosed = Date()
    }

    func clickedAt(_ point: NSPoint) {
        guard let panel, panel.isVisible, !panel.frame.contains(point) else { return }
        close()
    }

    private func build() {
        let look = PanelLook.current()
        let current = currentTheme()
        let classic = ["mocha", "latte", "graphite", "paper", "nord", "terminal"]
        let scenes = ["harvest", "dusklake", "alpenglow", "nightgarden", "sakura", "aurora", "dune", "tide", "velvet", "matcha", "nebula", "orbit"]
        let all = ((try? FileManager.default.contentsOfDirectory(atPath: configDir + "/themes")) ?? [])
            .filter { $0.hasSuffix(".sh") }.map { String($0.dropLast(3)) }
        let sections: [(String, [String])] = [
            ("CLASSIC", classic.filter(all.contains) + all.filter { !classic.contains($0) && !scenes.contains($0) }.sorted()),
            ("SCENES", scenes.filter(all.contains)),
        ]
        for key in all where cards[key] == nil { cards[key] = ThemeCard.load(key: key) }

        let cols = 4, cardW: CGFloat = 158, cardH: CGFloat = 92, gap: CGFloat = 12, pad: CGFloat = 22
        let header: CGFloat = 58, label: CGFloat = 28, footer: CGFloat = 54
        let width = pad * 2 + CGFloat(cols) * cardW + CGFloat(cols - 1) * gap
        var height = header + footer
        for (_, keys) in sections where !keys.isEmpty {
            height += label + CGFloat((keys.count + cols - 1) / cols) * (cardH + gap)
        }

        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        content.layer?.backgroundColor = look.background.cgColor
        content.layer?.cornerRadius = look.radius
        content.layer?.borderWidth = 1; content.layer?.borderColor = look.border.cgColor
        content.layer?.masksToBounds = true

        let title = NSTextField(labelWithString: "Themes")
        title.font = panelFont(13, bold: true); title.textColor = look.text
        title.frame = NSRect(x: pad, y: 16, width: 200, height: 18); content.addSubview(title)
        let sub = NSTextField(labelWithString: "Click a theme to switch · the dock and top bar change together")
        sub.font = panelFont(11); sub.textColor = look.muted
        sub.frame = NSRect(x: pad, y: 35, width: width - pad * 2, height: 15); content.addSubview(sub)

        var y = header
        for (name, keys) in sections where !keys.isEmpty {
            let l = NSTextField(labelWithString: name)
            l.font = panelFont(10.5, bold: true); l.textColor = look.muted
            l.frame = NSRect(x: pad + 2, y: y + 6, width: 200, height: 14); content.addSubview(l)
            y += label
            for (i, key) in keys.enumerated() {
                guard let card = cards[key] else { continue }
                let x = pad + CGFloat(i % cols) * (cardW + gap), cy = y + CGFloat(i / cols) * (cardH + gap)
                let v = CardView(card: card, current: key == current, look: look,
                                 frame: NSRect(x: x, y: cy, width: cardW, height: cardH))
                v.onPick = { [weak self] in self?.pick(key) }
                content.addSubview(v)
            }
            y += CGFloat((keys.count + cols - 1) / cols) * (cardH + gap)
        }

        let line = NSView(frame: NSRect(x: pad, y: height - footer, width: width - pad * 2, height: 1))
        line.wantsLayer = true; line.layer?.backgroundColor = look.border.cgColor; content.addSubview(line)
        let customize = FooterButton(title: "Customize colors…", look: look,
                                     frame: NSRect(x: pad, y: height - footer + 12, width: 200, height: 30)) { [weak self] in
            self?.close()
            let menu = configDir + "/plugins/menu.sh"
            DispatchQueue.global().async {
                run("/bin/bash", ["-c", "MENU_ONLY=1 \"$0\" show trash && \"$0\" customize trash", menu])
            }
        }
        content.addSubview(customize)

        let screen = NSScreen.screens.first?.frame ?? .zero
        let x = min(max(anchorMidX - width / 2, screen.minX + 8), screen.maxX - width - 8)
        let py = max(screen.maxY - trayTop + 10, screen.minY)
        let p = panel ?? makePanel()
        p.setContentSize(NSSize(width: width, height: height))
        p.setFrameOrigin(NSPoint(x: x, y: min(py, screen.maxY - height - 44)))
        p.contentView = content
        p.orderFrontRegardless()
        panel = p
    }

    /// Switch theme (menu.sh writes theme.txt and reloads both bars), then redraw in it
    private func pick(_ key: String) {
        let menu = configDir + "/plugins/menu.sh"
        DispatchQueue.global().async {
            run("/bin/bash", [menu, "theme-\(key)", "trash"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.isOpen == true { self?.build() }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.hidesOnDeactivate = false; p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return p
    }
}
