// Mocha Desktop — installer app. Runs the bundled install.sh / uninstall.sh
// (in Contents/Resources/payload) and shows their output as it happens.

import SwiftUI
import AppKit

// MARK: - Palette (Catppuccin Mocha)

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

enum Mocha {
    static let crust = Color(hex: 0x11111b)
    static let base = Color(hex: 0x1e1e2e)
    static let surface0 = Color(hex: 0x313244)
    static let surface1 = Color(hex: 0x45475a)
    static let overlay = Color(hex: 0x9399b2)
    static let subtext = Color(hex: 0xa6adc8)
    static let text = Color(hex: 0xcdd6f4)
    static let pink = Color(hex: 0xf5c2e7)
    static let peach = Color(hex: 0xfab387)
    static let yellow = Color(hex: 0xf9e2af)
    static let green = Color(hex: 0xa6e3a1)
    static let teal = Color(hex: 0x94e2d5)
    static let blue = Color(hex: 0x89b4fa)
    static let lavender = Color(hex: 0xb4befe)
    static let mauve = Color(hex: 0xcba6f7)
    static let red = Color(hex: 0xf38ba8)
}

// MARK: - What can be installed

enum Part: String, CaseIterable, Identifiable {
    case menubar, dock, gaps, wallpaper
    var id: String { rawValue }

    var title: String {
        switch self {
        case .menubar: return "Menu bar"
        case .dock: return "Dock"
        case .gaps: return "Window gaps"
        case .wallpaper: return "Wallpaper"
        }
    }

    var detail: String {
        switch self {
        case .menubar: return "Floating pastel pills. The notch stays clear."
        case .dock: return "Squircle tiles from your current Dock, with drag and drop."
        case .gaps: return "Double-click a title bar to fill the space between the bars."
        case .wallpaper: return "A solid Mocha background to match."
        }
    }

    var symbol: String {
        switch self {
        case .menubar: return "menubar.rectangle"
        case .dock: return "dock.rectangle"
        case .gaps: return "macwindow"
        case .wallpaper: return "photo"
        }
    }

    var tint: Color {
        switch self {
        case .menubar: return Mocha.pink
        case .dock: return Mocha.blue
        case .gaps: return Mocha.green
        case .wallpaper: return Mocha.peach
        }
    }
}

// MARK: - Running the scripts

@MainActor
final class Runner: ObservableObject {
    @Published var log = ""
    @Published var running = false
    @Published var status: String?
    @Published var succeeded = false
    @Published var needsHomebrew = false

    private var payload: URL? { Bundle.main.resourceURL?.appendingPathComponent("payload") }

    func run(_ script: String, _ args: [String], doing: String) {
        guard let payload, !running else { return }
        log = ""
        status = doing
        succeeded = false
        needsHomebrew = false
        running = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [payload.appendingPathComponent(script).path] + args
        process.currentDirectoryURL = payload
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["NONINTERACTIVE"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self.log += text
                if text.contains("Homebrew is needed") { self.needsHomebrew = true }
            }
        }
        process.terminationHandler = { proc in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                self.running = false
                self.succeeded = proc.terminationStatus == 0
                self.status = self.succeeded ? "Done" : "Stopped with an error. The log below shows where."
            }
        }

        do {
            try process.run()
        } catch {
            running = false
            status = "Couldn't start the installer: \(error.localizedDescription)"
        }
    }
}

// MARK: - Views

/// A little picture of the design: menu bar pills on top, dock at the bottom
struct Preview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x24243a), Mocha.base],
                                     startPoint: .top, endPoint: .bottom))
            VStack {
                HStack(spacing: 6) {
                    pill(Mocha.pink, width: 22)
                    pill(Mocha.surface0, width: 54)
                    Spacer()
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Mocha.crust).frame(width: 70, height: 16)   // the notch, left clear
                    Spacer()
                    pill(Mocha.surface0, width: 34, dot: Mocha.blue)
                    pill(Mocha.surface0, width: 22, dot: Mocha.green)
                    pill(Mocha.surface0, width: 34, dot: Mocha.yellow)
                    pill(Mocha.surface0, width: 70, dot: Mocha.peach)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                Spacer()

                HStack(spacing: 6) {
                    ForEach([Mocha.blue, Mocha.green, Mocha.yellow, Mocha.teal, Mocha.mauve,
                             Mocha.pink, Mocha.peach, Mocha.lavender, Mocha.red], id: \.self) { color in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(color).frame(width: 24, height: 24)
                    }
                    Rectangle().fill(Mocha.surface1).frame(width: 1.5, height: 16).padding(.horizontal, 2)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Mocha.surface1).frame(width: 24, height: 24)
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Mocha.surface0))
                .padding(.bottom, 10)
            }
        }
        .frame(height: 170)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Mocha.surface1, lineWidth: 1))
    }

    private func pill(_ color: Color, width: CGFloat, dot: Color? = nil) -> some View {
        Capsule().fill(color).frame(width: width, height: 14)
            .overlay(alignment: .leading) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6).padding(.leading, 5) }
            }
    }
}

struct PartRow: View {
    let part: Part
    @Binding var on: Bool

    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: part.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Mocha.base)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(part.tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Mocha.text)
                    Text(part.detail).font(.system(size: 11.5)).foregroundStyle(Mocha.subtext)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(on ? part.tint : Mocha.surface1)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? Mocha.surface0 : Mocha.surface0.opacity(0.45)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MochaButton: ButtonStyle {
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filled ? Mocha.base : Mocha.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(filled ? Mocha.pink : Mocha.surface0))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct ContentView: View {
    @StateObject private var runner = Runner()
    @State private var selected = Set(Part.allCases)
    @State private var confirmUninstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mocha Desktop")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Mocha.text)
                Text("A pastel Catppuccin Mocha menu bar and dock for your Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(Mocha.subtext)
            }

            Preview()

            VStack(spacing: 8) {
                ForEach(Part.allCases) { part in
                    PartRow(part: part, on: Binding(
                        get: { selected.contains(part) },
                        set: { if $0 { selected.insert(part) } else { selected.remove(part) } }))
                }
            }
            .disabled(runner.running)

            HStack(spacing: 10) {
                Button("Install") {
                    runner.run("install.sh", Part.allCases.filter(selected.contains).map(\.rawValue),
                               doing: "Installing…")
                }
                .buttonStyle(MochaButton(filled: true))
                .disabled(runner.running || selected.isEmpty)

                Button("Uninstall") { confirmUninstall = true }
                    .buttonStyle(MochaButton(filled: false))
                    .disabled(runner.running)

                if runner.running { ProgressView().controlSize(.small).padding(.leading, 4) }
                if let status = runner.status {
                    Text(status).font(.system(size: 12))
                        .foregroundStyle(runner.running ? Mocha.subtext : (runner.succeeded ? Mocha.green : Mocha.red))
                }
                Spacer()
                if runner.needsHomebrew {
                    Button("Get Homebrew") { NSWorkspace.shared.open(URL(string: "https://brew.sh")!) }
                        .buttonStyle(MochaButton(filled: false))
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(runner.log.isEmpty ? "Needs Homebrew (brew.sh). Output from the installer shows up here." : runner.log)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(runner.log.isEmpty ? Mocha.overlay : Mocha.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(height: 130)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Mocha.crust))
                .onChange(of: runner.log) { _ in proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(Mocha.base)
        .alert("Remove Mocha Desktop?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) {
                runner.run("uninstall.sh", [], doing: "Uninstalling…")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This brings back Apple's menu bar, Dock and window zoom. Your Mocha settings are moved aside, not deleted.")
        }
    }
}

@main
struct MochaDesktopApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
