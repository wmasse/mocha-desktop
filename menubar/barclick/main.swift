// barclick — small helper for the Mocha menu bar.
//
// Run with no arguments, it stays running and:
//   - closes the bar's menus when you click anywhere else (SketchyBar only
//     closes a menu when its button is clicked again)
//   - gives back Apple's menu bar on Control-Option-Command-M: the bar hides so
//     the real menu bar shows at the top, and comes back when you press it again
//     or once the pointer has left the top of the screen for a few seconds
// With an argument it does one quick job and exits:
//   barclick menubar                     same as Control-Option-Command-M
//   barclick hide | hide-others | quit   act on the app in front (no permission prompts)
//   barclick volume [+N|-N|=N]           print "<volume> <muted>", first changing it by N or to N%
//   barclick mute                        toggle mute, then print like volume
//   barclick strip <dir> <points>        cut the top of the current wallpaper, as macOS
//                                        draws it, into <dir>; print the PNG's path and
//                                        the image scale that maps it back to points
// Volume goes straight to Core Audio: AppleScript's volume commands take about
// a second each on macOS 27, which made the volume pill lag.

import AppKit
import AudioToolbox
import Carbon.HIToolbox
import CoreAudio

let env = ProcessInfo.processInfo.environment
let toggleMenuBarNote = Notification.Name("io.github.wmasse.mocha.menubar.toggle")
let configDir = env["CONFIG_DIR"] ?? NSHomeDirectory() + "/.config/sketchybar"
let barCommand = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/sketchybar"

@discardableResult
func run(_ path: String, _ args: [String]) -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return Data() }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return data
}

// ── Volume (default output device) ──
func outputDevice() -> AudioObjectID {
    var device = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
    return device
}

func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                               mElement: kAudioObjectPropertyElementMain)
}

func getProperty<T>(_ selector: AudioObjectPropertySelector, _ value: T) -> T {
    var address = outputAddress(selector), result = value
    var size = UInt32(MemoryLayout<T>.size)
    AudioObjectGetPropertyData(outputDevice(), &address, 0, nil, &size, &result)
    return result
}

func setProperty<T>(_ selector: AudioObjectPropertySelector, _ value: T) {
    var address = outputAddress(selector), newValue = value
    AudioObjectSetPropertyData(outputDevice(), &address, 0, nil, UInt32(MemoryLayout<T>.size), &newValue)
}

func printVolume() {
    let volume = getProperty(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0))
    let muted = getProperty(kAudioDevicePropertyMute, UInt32(0)) != 0
    print(Int((volume * 100).rounded()), muted)
}

// ── Wallpaper strip ──
/// Which image of a dynamic (time-of-day) wallpaper macOS is showing now
func currentImageIndex(_ source: CGImageSource) -> Int {
    guard CGImageSourceGetCount(source) > 1,
          let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
          let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "apple_desktop:h24" as CFString),
          let base64 = CGImageMetadataTagCopyValue(tag) as? String,
          let data = Data(base64Encoded: base64),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let times = plist["ti"] as? [[String: Any]] else { return 0 }
    // "t" is the fraction of the (local) day each image starts at
    let midnight = Calendar.current.startOfDay(for: Date())
    let dayFraction: Double = Date().timeIntervalSince(midnight) / 86400
    var starts: [(t: Double, i: Int)] = []
    for entry in times {
        guard let i = (entry["i"] as? NSNumber)?.intValue else { continue }
        let t = (entry["t"] as? NSNumber)?.doubleValue ?? Double(entry["t"] as? String ?? "")
        if let t { starts.append((t, i)) }
    }
    // The latest image that has started today; before the first one, last night's
    let started = starts.filter { $0.t <= dayFraction }
    let current = started.max { $0.t < $1.t } ?? starts.max { $0.t < $1.t }
    return current?.i ?? 0
}

/// The top `points` of the wallpaper as macOS fills the main screen with it
func wallpaperStrip(dir: String, points: CGFloat) -> String? {
    guard let screen = NSScreen.screens.first,
          let url = NSWorkspace.shared.desktopImageURL(for: screen),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let index = currentImageIndex(source)
    let scale = screen.backingScaleFactor
    let width = Int(screen.frame.width * scale), height = Int(screen.frame.height * scale)
    let stripHeight = Int(points * scale)
    let wallpaper = url.deletingPathExtension().lastPathComponent
        .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    let name = "strip-\(wallpaper)-\(index)-\(width)x\(stripHeight).png"
    let out = (dir as NSString).appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: out) { return out }

    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil),
          let context = CGContext(data: nil, width: width, height: stripHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // Fill the screen (scale up or down to cover it, centered), then keep the top rows.
    // CGContext's origin is bottom-left, so the screen's top edge lines up with stripHeight.
    let fill = max(Double(width) / Double(image.width), Double(height) / Double(image.height))
    let drawnWidth = Double(image.width) * fill, drawnHeight = Double(image.height) * fill
    let x = (Double(width) - drawnWidth) / 2
    let top = (Double(height) - drawnHeight) / 2          // distance of the image's top above the screen's top, negated
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: x, y: Double(stripHeight) - drawnHeight - top, width: drawnWidth, height: drawnHeight))

    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    guard let strip = context.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dest, strip, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    // Keep only this wallpaper's strips; older ones are no longer needed
    for file in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    where file.hasPrefix("strip-") && file != name { try? FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent(file)) }
    return out
}

// ── One-shot actions ──
let args = Array(CommandLine.arguments.dropFirst())
if let action = args.first {
    switch action {
    case "menubar":
        // The running helper owns the toggle (it also brings the bar back later)
        DistributedNotificationCenter.default().postNotificationName(toggleMenuBarNote, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
    case "hide", "hide-others", "quit":
        guard let app = NSWorkspace.shared.frontmostApplication else { exit(1) }
        if action == "hide" { app.hide() }
        if action == "quit" { app.terminate() }
        if action == "hide-others" {
            for other in NSWorkspace.shared.runningApplications
            where other != app && other.activationPolicy == .regular { other.hide() }
        }
    case "volume":
        if args.count > 1, args[1].hasPrefix("="), let level = Float32(args[1].dropFirst()) {
            // An exact level, from the volume menu's slider
            setProperty(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, min(1, max(0, level / 100)))
            if level > 0 { setProperty(kAudioDevicePropertyMute, UInt32(0)) }
        } else if args.count > 1, let step = Float32(args[1]) {
            let volume = getProperty(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0))
            let newVolume = min(1, max(0, volume + step / 100))
            setProperty(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, newVolume)
            if step > 0 { setProperty(kAudioDevicePropertyMute, UInt32(0)) }   // like the volume keys
        }
        printVolume()
    case "mute":
        let muted = getProperty(kAudioDevicePropertyMute, UInt32(0)) != 0
        setProperty(kAudioDevicePropertyMute, UInt32(muted ? 0 : 1))
        printVolume()
    case "strip":
        guard args.count > 2, let points = Double(args[2]),
              let path = wallpaperStrip(dir: args[1], points: CGFloat(points)) else { exit(1) }
        // The PNG has one pixel per screen pixel; SketchyBar needs the scale back to points
        print(path, 1 / (NSScreen.screens.first?.backingScaleFactor ?? 1))
    default: exit(2)
    }
    exit(0)
}

/// Frames of the menu bar's own windows that are on screen right now
func onScreenBarWindows() -> [CGRect] {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return windows.compactMap { w in
        guard w[kCGWindowOwnerName as String] as? String == "sketchybar",
              let bounds = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }
}

/// Close the bar's menus on a click that lands outside the bar and its menus
func closeMenusIfClickedOutside() {
    let mouse = NSEvent.mouseLocation
    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
    let point = CGPoint(x: mouse.x, y: mainHeight - mouse.y)   // window list uses top-left origin
    DispatchQueue.global(qos: .userInitiated).async {
        guard !onScreenBarWindows().contains(where: { $0.contains(point) }) else { return }
        run(barCommand, ["--set", "/.*/", "popup.drawing=off"])
    }
}

/// Hides the bar so Apple's menu bar can show, and brings it back
final class MenuBarToggle {
    static let shared = MenuBarToggle()
    private var hidden = false
    private var awayFor: TimeInterval = 0
    private let tick: TimeInterval = 0.25
    private let returnAfter: TimeInterval = 4   // seconds away from the top before the bar comes back

    func toggle() {
        hidden ? show() : hide()
    }

    private func hide() {
        hidden = true
        awayFor = 0
        run(barCommand, ["--set", "/.*/", "popup.drawing=off", "--bar", "hidden=on"])
        Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] timer in
            guard let self, self.hidden else { timer.invalidate(); return }
            self.check()
        }
    }

    private func show() {
        hidden = false
        run(barCommand, ["--bar", "hidden=off"])
    }

    /// Count time the pointer spends away from the top, but not while one of
    /// Apple's menus is open (you're reading it)
    private func check() {
        let fromTop = (NSScreen.screens.first?.frame.maxY ?? 0) - NSEvent.mouseLocation.y
        if fromTop < 40 || appleMenuIsOpen() {
            awayFor = 0
        } else {
            awayFor += tick
            if awayFor >= returnAfter { show() }
        }
    }

    private func appleMenuIsOpen() -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { w in
            guard (w[kCGWindowLayer as String] as? Int) == menuLevel,
                  let owner = w[kCGWindowOwnerName as String] as? String,
                  owner != "sketchybar", owner != "mochadock",   // the bars' own menus
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.minY > -1000   // hidden menus are parked far off screen
        }
    }
}

/// Control-Option-Command-M. A Carbon hot key needs no Accessibility or Input
/// Monitoring permission, unlike watching the keyboard.
func registerMenuBarHotKey() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        MenuBarToggle.shared.toggle()
        return noErr
    }, 1, &spec, nil, nil)
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x4D4F4341), id: 1)   // "MOCA"
    let status = RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey | cmdKey), id,
                                     GetApplicationEventTarget(), 0, &ref)
    if status != noErr {
        FileHandle.standardError.write("barclick: couldn't register Control-Option-Command-M (\(status))\n".data(using: .utf8)!)
    }
}

final class Helper: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        // Mouse-down monitoring needs no permissions (only keyboard monitoring does)
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            closeMenusIfClickedOutside()
        }
        registerMenuBarHotKey()
        DistributedNotificationCenter.default().addObserver(forName: toggleMenuBarNote, object: nil, queue: .main) { _ in
            MenuBarToggle.shared.toggle()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
let helper = Helper()
app.delegate = helper
app.run()
