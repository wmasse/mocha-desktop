// The weather widget: sits on the desktop like Apple's widgets, drawn in the current
// dock theme (its menu colors, its tray's edge and corners, its typeface), with the
// weather symbols on little tiles shaped like the dock's own. Changes with the theme.
// Click it to open Weather, drag it anywhere, right-click for its size, city, units,
// or to hide it (the Trash's menu in the dock brings it back). Forecasts come from
// Open-Meteo (free, no account); the city you type is the only thing sent.

import AppKit

let widgetNote = Notification.Name("io.github.wmasse.mocha.dock.widget")

// MARK: - Settings and forecast (saved as JSON)

struct WidgetSettings: Codable {
    var city: String?, detail: String?, lat: Double?, lon: Double?
    var follow: Bool?, locatedAt: Double?               // follow: use where the Mac is (refreshed hourly)
    var medium: Bool?, hidden: Bool?, unit: String?   // unit: "F", "C" (nil: from your region)
    var x: Double?, y: Double?                         // bottom-left corner on screen

    static let path = configDir + "/widget.json"
    static func load() -> WidgetSettings {
        guard let data = FileManager.default.contents(atPath: path),
              let s = try? JSONDecoder().decode(WidgetSettings.self, from: data) else { return WidgetSettings() }
        return s
    }
    func save() {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        try? e.encode(self).write(to: URL(fileURLWithPath: WidgetSettings.path))
    }
    var fahrenheit: Bool { unit.map { $0 == "F" } ?? (Locale.current.measurementSystem == .us) }
}

struct Forecast: Codable {
    struct Hour: Codable { var label: String, temp: Double, code: Int, day: Bool, rain: Int }
    var city: String, temp: Double, code: Int, day: Bool, high: Double, low: Double
    var hours: [Hour], fetched: Date, fahrenheit: Bool

    static let path = configDir + "/cache/weather.json"
    static func load() -> Forecast? {
        FileManager.default.contents(atPath: path).flatMap { try? JSONDecoder().decode(Forecast.self, from: $0) }
    }
    func save() { try? JSONEncoder().encode(self).write(to: URL(fileURLWithPath: Forecast.path)) }
}

/// What WMO weather codes look like, and are called
enum Sky {
    static func name(_ code: Int, day: Bool) -> String {
        switch code {
        case 0: return day ? "Sunny" : "Clear"
        case 1: return day ? "Mostly Sunny" : "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61: return "Light Rain"
        case 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71: return "Light Snow"
        case 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80, 81: return "Showers"
        case 82: return "Heavy Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Hailstorms"
        default: return "—"
        }
    }

    /// The SF Symbol, and its layers' colors in the theme's palette
    static func symbol(_ code: Int, day: Bool, _ look: WidgetLook) -> (String, [NSColor]) {
        let cloud = look.subtext
        let result: (String, [NSColor])
        switch code {
        case 0: result = day ? ("sun.max.fill", [look.yellow]) : ("moon.stars.fill", [look.lavender, look.yellow])
        case 1, 2: result = day ? ("cloud.sun.fill", [cloud, look.yellow]) : ("cloud.moon.fill", [cloud, look.lavender])
        case 3: result = ("cloud.fill", [cloud])
        case 45, 48: result = ("cloud.fog.fill", [cloud, look.muted])
        case 51...57: result = ("cloud.drizzle.fill", [cloud, look.blue])
        case 65, 82: result = ("cloud.heavyrain.fill", [cloud, look.blue])
        case 61, 63, 80, 81: result = ("cloud.rain.fill", [cloud, look.blue])
        case 66, 67: result = ("cloud.sleet.fill", [cloud, look.teal])
        case 71...77, 85, 86: result = ("cloud.snow.fill", [cloud, look.teal])
        case 95...99: result = ("cloud.bolt.rain.fill", [cloud, look.yellow, look.blue])
        default: result = ("questionmark", [look.muted])
        }
        // mono themes draw every icon in one color, like their dock
        return look.mono ? (result.0, result.1.map { _ in look.text }) : result
    }
}

// MARK: - The theme's look

struct WidgetLook {
    var background = themeColor("0xff313244"), border = themeColor("0xff45475a"), borderWidth: CGFloat = 1
    var radius: CGFloat = 22
    var text = themeColor("0xffcdd6f4"), subtext = themeColor("0xffbac2de"), muted = themeColor("0xff9399b2")
    var tiles: [NSColor] = [themeColor("0xff45475a")], tileBorder = NSColor.clear, tileBorderWidth: CGFloat = 0
    var tileRadius: CGFloat = 15, ring = themeColor("0xffcdd6f4"), mono = false
    var yellow = themeColor("0xfff9e2af"), blue = themeColor("0xff89b4fa"), teal = themeColor("0xff94e2d5")
    var lavender = themeColor("0xffb4befe")
    var family = "Hack Nerd Font", boldStyle = "Bold", regularStyle = "Regular"

    /// A theme's look, read in a clean shell (the current theme with your custom colors, or any theme by key)
    static func load(_ key: String) -> WidgetLook {
        let script = """
            THEME_DIR="$2"; source "$2/themes/$1.sh"; [ -f "$2/custom-$1.sh" ] && source "$2/custom-$1.sh"; source "$2/style.sh"
            printf '%s\\n' "$MENU_COLOR" "$MENU_BORDER_COLOR" "$TRAY_COLOR" "$TRAY_BORDER_COLOR" "$TRAY_BORDER_WIDTH" "$TRAY_RADIUS" \
              "$TEXT" "$SUBTEXT" "$OVERLAY" "$TILE_IDLE_COLOR" "$TILE_IDLE_COLORS" "$TILE_BORDER_COLOR" "$TILE_BORDER_WIDTH" \
              "$THEME_TILE_RADIUS" "$FRONT_RING_COLOR" "$ICON_STYLE" "$YELLOW" "$BLUE" "$TEAL" "$LAVENDER" \
              "$LABEL_FONT" "$LABEL_BOLD" "$LABEL_REGULAR"
            """
        let out = String(data: run("/usr/bin/env", ["-i", "HOME=" + NSHomeDirectory(), "/bin/bash", "-c", script, "_", key, configDir]),
                         encoding: .utf8) ?? ""
        let f = out.components(separatedBy: "\n")
        var look = WidgetLook()
        guard f.count >= 23 else { return look }
        look.background = themeColor(f[0], look.background)
        // the tray's edge, when the theme has a solid tray with one; otherwise the menus' hairline
        let tray = themeColor(f[2], .clear), trayBorder = CGFloat(Double(f[4]) ?? 0)
        if tray.alphaComponent > 0.5, trayBorder > 0 {
            look.border = themeColor(f[3], look.border); look.borderWidth = min(4, trayBorder)
        } else {
            look.border = themeColor(f[1], look.border); look.borderWidth = 1
        }
        look.radius = max(0, min(26, CGFloat(Double(f[5]) ?? 22)))
        look.text = themeColor(f[6], look.text); look.subtext = themeColor(f[7], look.subtext); look.muted = themeColor(f[8], look.muted)
        let collage = f[10].split(separator: " ").map { themeColor(String($0)) }
        look.tiles = collage.isEmpty ? [themeColor(f[9], look.tiles[0])] : collage
        look.tileBorder = themeColor(f[11], .clear); look.tileBorderWidth = CGFloat(Double(f[12]) ?? 0)
        look.tileRadius = CGFloat(Double(f[13]) ?? 15)
        look.ring = themeColor(f[14], look.text); look.mono = f[15] == "mono"
        look.yellow = themeColor(f[16], look.yellow); look.blue = themeColor(f[17], look.blue)
        look.teal = themeColor(f[18], look.teal); look.lavender = themeColor(f[19], look.lavender)
        look.family = f[20].isEmpty ? look.family : f[20]
        look.boldStyle = f[21]; look.regularStyle = f[22]
        return look
    }

    /// The theme's typeface in its own bold or regular style
    func font(_ size: CGFloat, bold: Bool) -> NSFont {
        let style = bold ? boldStyle : regularStyle
        if let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
           let match = members.first(where: { ($0[1] as? String) == style }), let name = match[0] as? String,
           let font = NSFont(name: name, size: size) { return font }
        panelFamily = family
        return panelFont(size, bold: bold)
    }
}

// MARK: - Drawing

enum WidgetState { case needsCity, loading, failed, ready(Forecast) }

final class WidgetView: NSView {
    var look = WidgetLook() { didSet { needsDisplay = true } }
    var state = WidgetState.loading { didSet { needsDisplay = true } }
    var medium = false { didSet { needsDisplay = true } }
    var onClick: () -> Void = {}
    var menuProvider: () -> NSMenu? = { nil }
    private var pressed: NSPoint?, dragged = false

    static let smallSize = NSSize(width: 170, height: 170), mediumSize = NSSize(width: 364, height: 170)

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { pressed = event.locationInWindow; dragged = false }
    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let p = pressed, hypot(event.locationInWindow.x - p.x, event.locationInWindow.y - p.y) > 3 else { return }
        dragged = true
        window?.performDrag(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        if !dragged, pressed != nil { onClick() }
        pressed = nil
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menuProvider() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: look.borderWidth / 2, dy: look.borderWidth / 2)
        let shape = NSBezierPath(roundedRect: card, xRadius: look.radius, yRadius: look.radius)
        look.background.setFill(); shape.fill()
        if look.borderWidth > 0 { look.border.setStroke(); shape.lineWidth = look.borderWidth; shape.stroke() }

        let pad: CGFloat = 16, h = bounds.height
        // what the left column says
        var city = "Weather", temp = "--°", line1 = "", line2 = ""
        var symbol: (code: Int, day: Bool)?
        switch state {
        case .needsCity: line1 = "Click to choose"; line2 = "your city"
        case .loading: line1 = "Loading…"
        case .failed: line1 = "Can't reach the"; line2 = "weather right now"
        case .ready(let f):
            city = f.city; temp = "\(Int(f.temp.rounded()))°"
            line1 = Sky.name(f.code, day: f.day)
            line2 = "H:\(Int(f.high.rounded()))°  L:\(Int(f.low.rounded()))°"
            symbol = (f.code, f.day)
            if Date().timeIntervalSince(f.fetched) > 2 * 3600 {   // old: say when it's from
                let t = DateFormatter(); t.timeStyle = .short
                line2 = "Updated \(t.string(from: f.fetched))"
            }
        }

        let column: CGFloat = medium ? 150 : bounds.width
        // the sky now, on a tile up in the corner beside the city; the temperature gets the row below to itself
        let tileSide: CGFloat = 36
        let bigTile = NSRect(x: column - pad - tileSide + 2, y: 12, width: tileSide, height: tileSide)
        drawTile(bigTile, index: 0, now: false)
        if let symbol {
            drawSymbol(symbol.code, day: symbol.day, in: bigTile, size: 19)
        } else {
            drawSymbol(name: "location.fill", colors: [look.mono ? look.text : look.blue], in: bigTile, size: 16)
        }
        draw(city, font: look.font(13, bold: true), color: look.text,
             in: NSRect(x: pad, y: 20, width: bigTile.minX - pad - 6, height: 18))
        draw(temp, font: fitted(temp, size: 44, width: column - pad * 1.5), color: look.text,
             in: NSRect(x: pad - 2, y: 50, width: column - pad, height: 56))
        draw(line1, font: look.font(13, bold: true), color: look.text, in: NSRect(x: pad, y: h - pad - 36, width: column - pad * 1.5, height: 18))
        draw(line2, font: look.font(12, bold: false), color: look.subtext, in: NSRect(x: pad, y: h - pad - 17, width: column - pad * 1.5, height: 17))

        guard medium else { return }
        // the next five hours, each on a tile like the dock's; now has the front app's ring
        let rule = NSBezierPath(rect: NSRect(x: column + 4, y: 22, width: 1, height: h - 44))
        look.muted.withAlphaComponent(0.35).setFill(); rule.fill()
        guard case .ready(let f) = state, !f.hours.isEmpty else { return }
        let left = column + 20, width = bounds.width - left - pad, count = min(5, f.hours.count)
        let slot = width / CGFloat(count), tile: CGFloat = 32
        let top = (h - 92) / 2 + 2
        for (i, hour) in f.hours.prefix(count).enumerated() {
            let mid = left + slot * (CGFloat(i) + 0.5)
            draw(hour.label, font: look.font(11, bold: i == 0), color: i == 0 ? look.text : look.subtext,
                 in: NSRect(x: mid - slot / 2, y: top, width: slot, height: 15), center: true)
            let r = NSRect(x: mid - tile / 2, y: top + 20, width: tile, height: tile)
            drawTile(r, index: i + 1, now: i == 0)
            drawSymbol(hour.code, day: hour.day, in: r, size: 17)
            draw("\(Int(hour.temp.rounded()))°", font: look.font(13, bold: true), color: look.text,
                 in: NSRect(x: mid - slot / 2, y: top + 58, width: slot, height: 18), center: true)
            if hour.rain >= 20 {
                draw("\(hour.rain)%", font: look.font(10, bold: true), color: look.mono ? look.subtext : look.blue,
                     in: NSRect(x: mid - slot / 2, y: top + 76, width: slot, height: 14), center: true)
            }
        }
    }

    /// The theme's regular face at up to `size`, shrunk until the text fits `width`
    private func fitted(_ s: String, size: CGFloat, width: CGFloat) -> NSFont {
        var size = size
        while size > 24, (s as NSString).size(withAttributes: [.font: look.font(size, bold: false)]).width > width { size -= 2 }
        return look.font(size, bold: false)
    }

    private func drawTile(_ r: NSRect, index: Int, now: Bool) {
        let color = look.tiles.isEmpty ? look.background : look.tiles[index % look.tiles.count]
        let radius = min(r.width / 2, look.tileRadius * r.width / 52)
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        if color.alphaComponent > 0 { color.setFill(); path.fill() }
        if look.tileBorderWidth > 0 {
            look.tileBorder.setStroke(); path.lineWidth = min(2, look.tileBorderWidth); path.stroke()
        }
        if now {
            let ring = r.insetBy(dx: -3, dy: -3)
            let p = NSBezierPath(roundedRect: ring, xRadius: radius + 3, yRadius: radius + 3)
            look.ring.setStroke(); p.lineWidth = 1.5; p.stroke()
        }
    }

    private func drawSymbol(_ code: Int, day: Bool, in r: NSRect, size: CGFloat) {
        let (name, colors) = Sky.symbol(code, day: day, look)
        drawSymbol(name: name, colors: colors, in: r, size: size)
    }

    private func drawSymbol(name: String, colors: [NSColor], in r: NSRect, size: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: colors))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let s = image.size
        image.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func draw(_ s: String, font: NSFont, color: NSColor, in r: NSRect, center: Bool = false) {
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail; p.alignment = center ? .center : .left
        (s as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                             attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    }

    /// The widget as a picture (for previews), at 2x with its corners see-through
    func snapshot() -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: 0, y: bounds.height); ctx.scaleBy(x: 1, y: -1)   // the view draws top-down
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw(bounds)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}

// MARK: - The widget on the desktop

final class WeatherWidget: NSObject {
    private var settings = WidgetSettings.load()
    private var forecast = Forecast.load()
    private var window: NSWindow?
    private var view: WidgetView?
    private var themeStamp = 0.0
    private var fetching = false, failed = false
    private var picker: CityPicker?

    func start() {
        if !(settings.hidden ?? false) { show() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkTheme() }
        Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.fetch() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.fetch() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.place()
        }
        DistributedNotificationCenter.default().addObserver(forName: widgetNote, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            switch note.object as? String {
            case "show": self.setHidden(false)
            case "hide": self.setHidden(true)
            case "city": self.askCity()
            case "here": self.useLocation(asked: true)
            case "close-picker": self.picker?.close()
            default: self.setHidden(!(self.settings.hidden ?? false))
            }
        }
        fetch()
    }

    // MARK: window

    private func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: WidgetView.smallSize), styleMask: .borderless, backing: .buffered, defer: false)
            // with the desktop's own widgets: above the wallpaper and icons, under every app window
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
            w.backgroundColor = .clear; w.isOpaque = false; w.hasShadow = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            let v = WidgetView(frame: NSRect(origin: .zero, size: WidgetView.smallSize))
            v.onClick = { [weak self] in self?.clicked() }
            v.menuProvider = { [weak self] in self?.menu() }
            w.contentView = v
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak self] _ in
                guard let self, let w = self.window else { return }
                self.settings.x = Double(w.frame.minX); self.settings.y = Double(w.frame.minY); self.settings.save()
            }
            window = w; view = v
            themeStamp = 0; checkTheme()
        }
        refresh()
        place()
        window?.orderFrontRegardless()
    }

    /// Where it goes: where you left it (kept on screen), or the bottom-left corner beside the dock
    private func place() {
        guard let window, let screen = NSScreen.main else { return }
        let size = (settings.medium ?? false) ? WidgetView.mediumSize : WidgetView.smallSize
        let area = screen.visibleFrame
        var origin = NSPoint(x: settings.x ?? Double(area.minX + 16), y: settings.y ?? Double(screen.frame.minY + 16))
        if settings.x == nil, let taken = desktopWidgetFrame(near: NSRect(origin: origin, size: size), on: screen) {
            origin.y = taken.maxY + 12   // first time, with Apple's widget in that corner: just above it
        }
        origin.x = min(max(origin.x, screen.frame.minX), screen.frame.maxX - size.width)
        origin.y = min(max(origin.y, screen.frame.minY), area.maxY - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        view?.frame = NSRect(origin: .zero, size: size)
    }

    /// One of Apple's desktop widgets overlapping a spot, in screen coordinates (bottom-left origin)
    private func desktopWidgetFrame(near spot: NSRect, on screen: NSScreen) -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let level = Int(CGWindowLevelForKey(.desktopIconWindow))
        for w in list where (w["kCGWindowOwnerName"] as? String) == "Notification Center" {
            guard let l = w["kCGWindowLayer"] as? Int, l > level, l < level + 10,
                  let b = w["kCGWindowBounds"] as? [String: CGFloat], let x = b["X"], let y = b["Y"], let wd = b["Width"], let h = b["Height"] else { continue }
            let r = NSRect(x: x, y: screen.frame.height - y - h, width: wd, height: h)
            if r.intersects(spot) { return r }
        }
        return nil
    }

    private func setHidden(_ hidden: Bool) {
        settings.hidden = hidden; settings.save()
        if hidden { window?.orderOut(nil) } else { show(); fetch() }
    }

    private func refresh() {
        guard let view else { return }
        view.medium = settings.medium ?? false
        if settings.lat == nil { view.state = .needsCity }
        else if let forecast, forecast.fahrenheit == settings.fahrenheit { view.state = .ready(forecast) }
        else { view.state = failed ? .failed : .loading }
    }

    private func checkTheme() {
        guard view != nil else { return }
        let stamp = ["theme.txt", "custom-\(currentTheme()).sh", "style.sh"].map { name in
            (try? FileManager.default.attributesOfItem(atPath: configDir + "/" + name)[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? 0 }.reduce(0, +)
        guard stamp != themeStamp else { return }
        themeStamp = stamp
        let key = currentTheme()
        DispatchQueue.global().async {
            let look = WidgetLook.load(key)
            DispatchQueue.main.async { [weak self] in self?.view?.look = look }
        }
    }

    // MARK: actions

    private func clicked() {
        if settings.lat == nil { askCity(); return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Weather.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    private func menu() -> NSMenu {
        let m = NSMenu()
        func item(_ title: String, _ on: Bool = false, _ action: @escaping () -> Void) {
            let i = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
            let target = MenuAction(action); i.target = target; i.representedObject = target
            i.state = on ? .on : .off
            m.addItem(i)
        }
        let medium = settings.medium ?? false
        item("Small", !medium) { [weak self] in self?.setMedium(false) }
        item("Medium", medium) { [weak self] in self?.setMedium(true) }
        m.addItem(.separator())
        item("°F", settings.fahrenheit) { [weak self] in self?.setUnit("F") }
        item("°C", !settings.fahrenheit) { [weak self] in self?.setUnit("C") }
        m.addItem(.separator())
        item(settings.city == nil ? "Choose City…" : "Change City…") { [weak self] in self?.askCity() }
        item("Use My Location", settings.follow ?? false) { [weak self] in self?.useLocation(asked: true) }
        item("Refresh") { [weak self] in self?.fetch() }
        item("Open Weather") { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Weather.app"),
                                                                  configuration: NSWorkspace.OpenConfiguration()) }
        m.addItem(.separator())
        item("Hide Widget") { [weak self] in self?.setHidden(true) }
        return m
    }

    private func setMedium(_ on: Bool) { settings.medium = on; settings.save(); refresh(); place() }
    private func setUnit(_ unit: String) { settings.unit = unit; settings.save(); refresh(); fetch() }

    /// The map picker; one at a time
    private func askCity() {
        if let picker { picker.show(); return }
        let current = settings.lat.map { Place(name: settings.city ?? "", detail: settings.detail ?? "", lat: $0, lon: settings.lon ?? 0) }
        let p = CityPicker(current: current, followingLocation: settings.follow ?? false)
        p.onPick = { [weak self] place in self?.use(place, follow: false) }
        p.onUseLocation = { [weak self] in self?.useLocation(asked: true) }
        p.onClose = { [weak self] in self?.picker = nil }
        picker = p
        p.show()
    }

    private func use(_ place: Place, follow: Bool) {
        settings.city = place.name; settings.detail = place.detail
        settings.lat = place.lat; settings.lon = place.lon
        settings.follow = follow
        if follow { settings.locatedAt = Date().timeIntervalSince1970 }
        settings.save()
        forecast = nil; refresh(); fetch()
    }

    /// Weather where the Mac is. Asked: you chose it (say if it can't); otherwise the hourly refresh (quietly)
    private func useLocation(asked: Bool) {
        if asked, settings.lat == nil { view?.state = .loading }
        MacLocation.find { [weak self] result in
            guard let self else { return }
            switch result {
            case .found(let place):
                self.use(place, follow: true)
            case .denied:
                if asked || self.settings.follow == true {
                    self.settings.follow = false; self.settings.save()
                    MacLocation.explainDenied()
                }
                self.refresh()
            case .failed:
                if asked {
                    NSApp.activate(ignoringOtherApps: true)
                    let a = NSAlert(); a.messageText = "Couldn't find where you are"
                    a.informativeText = "Location Services didn't answer. Check that Wi-Fi is on, or pick a city instead."
                    a.runModal()
                }
                self.refresh()
            }
        }
    }

    // MARK: forecast

    private func fetch() {
        if settings.follow == true, Date().timeIntervalSince1970 - (settings.locatedAt ?? 0) > 3600, !fetching {
            settings.locatedAt = Date().timeIntervalSince1970   // don't ask again while this one runs
            useLocation(asked: false)   // finds the place, then fetches
            return
        }
        guard !fetching, !(settings.hidden ?? false), let lat = settings.lat, let lon = settings.lon else { return }
        fetching = true
        let fahrenheit = settings.fahrenheit, city = settings.city ?? ""
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [.init(name: "latitude", value: String(lat)), .init(name: "longitude", value: String(lon)),
                        .init(name: "current", value: "temperature_2m,weather_code,is_day"),
                        .init(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
                        .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                        .init(name: "forecast_days", value: "2"), .init(name: "timezone", value: "auto"),
                        .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius")]
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, _, _ in
            let parsed = data.flatMap { WeatherWidget.parse($0, city: city, fahrenheit: fahrenheit) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                if let parsed { parsed.save(); self.forecast = parsed; self.failed = false } else { self.failed = true }
                self.refresh()
            }
        }.resume()
    }

    static func parse(_ data: Data, city: String, fahrenheit: Bool) -> Forecast? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any], let hourly = json["hourly"] as? [String: Any],
              let daily = json["daily"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double, let code = current["weather_code"] as? Int,
              let now = current["time"] as? String,
              let times = hourly["time"] as? [String], let temps = hourly["temperature_2m"] as? [Double],
              let codes = hourly["weather_code"] as? [Int], let days = hourly["is_day"] as? [Int],
              let highs = daily["temperature_2m_max"] as? [Double], let lows = daily["temperature_2m_min"] as? [Double],
              !highs.isEmpty, !lows.isEmpty else { return nil }
        let rains = hourly["precipitation_probability"] as? [Int] ?? []
        // times are the city's local time; the hour now and the four after it
        let thisHour = String(now.prefix(13))
        let start = times.firstIndex { $0.hasPrefix(thisHour) } ?? 0
        let parse = DateFormatter(); parse.locale = Locale(identifier: "en_US_POSIX"); parse.dateFormat = "yyyy-MM-dd'T'HH:mm"
        parse.timeZone = TimeZone(identifier: "UTC")
        let label = DateFormatter(); label.timeZone = TimeZone(identifier: "UTC")
        label.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h a"
        var hours: [Forecast.Hour] = []
        for i in start..<min(times.count, temps.count, codes.count, days.count, start + 5) {
            let rain = i < rains.count ? rains[i] : 0
            if i == start {   // "Now" matches the big number
                hours.append(.init(label: "Now", temp: temp, code: code, day: (current["is_day"] as? Int ?? 1) == 1, rain: rain))
                continue
            }
            let text = parse.date(from: times[i]).map { label.string(from: $0) }?
                .components(separatedBy: .whitespaces).joined() ?? ""   // "4 PM" (a narrow space) → "4PM"
            hours.append(.init(label: text, temp: temps[i], code: codes[i], day: days[i] == 1, rain: rain))
        }
        return Forecast(city: city, temp: temp, code: code, day: (current["is_day"] as? Int ?? 1) == 1,
                        high: highs[0], low: lows[0], hours: hours, fetched: Date(), fahrenheit: fahrenheit)
    }
}

/// A closure as a menu item's target
final class MenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

/// dockdrop widget-preview <out.png> <theme> <small|medium>: the widget in a theme, with a sample forecast
func widgetPreview(_ args: [String]) {
    guard args.count >= 3 else { return }
    let view = WidgetView(frame: NSRect(origin: .zero, size: args.count > 3 && args[3] == "medium" ? WidgetView.mediumSize : WidgetView.smallSize))
    view.medium = args.count > 3 && args[3] == "medium"
    view.look = WidgetLook.load(args[2])
    let sample: [(String, Double, Int, Int)] = [("Now", 58, 2, 0), ("4PM", 59, 1, 0), ("5PM", 57, 3, 10), ("6PM", 54, 61, 40), ("7PM", 52, 63, 70)]
    view.state = .ready(Forecast(city: "Cupertino", temp: 58, code: 2, day: true, high: 63, low: 47,
                                 hours: sample.map { .init(label: $0.0, temp: $0.1, code: $0.2, day: true, rain: $0.3) },
                                 fetched: Date(), fahrenheit: true))
    if let rep = view.snapshot(), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: args[1]))
    }
}
