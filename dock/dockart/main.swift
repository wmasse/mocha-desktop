// dockart: draws the scenery behind the dock's tray for the themes that have it.
//   dockart <theme> <width> <out.png> [height [border-color width radius]]
//   exits 1 if the theme has no scenery. The border (0xAARRGGBB, points) is drawn
//   on top, since the scenery covers the tray's own outline.
// (height defaults to the 68pt tray; the theme gallery and menus draw smaller ones)
//
// The tiles cover most of the tray, so a scene is built in two layers:
//   - broad forms (gradients, glows, horizon and wave lines) that still read as one
//     scene when the tiles cover parts of them
//   - details placed where they stay whole: in the gaps between tiles, and in the
//     bands above and below them. DOCKART_GAPS lists the gap centers (points from
//     the left) and DOCKART_TILE the tile size; without them, gaps are assumed
//     every 60pt like the dock's.
// Heights are given as fractions (0 = top).
import AppKit

let args = CommandLine.arguments
guard args.count > 3, let width = Double(args[2]) else { exit(2) }
let W = width, H = args.count > 4 ? Double(args[4]) ?? 68 : 68.0, S = 2.0   // points
let env = ProcessInfo.processInfo.environment
let tile = Double(env["DOCKART_TILE"] ?? "") ?? H * 52 / 68
let gaps: [Double] = {
    let given = (env["DOCKART_GAPS"] ?? "").split(separator: ",").compactMap { Double($0) }
    if !given.isEmpty { return given }
    return Array(stride(from: 60.0, to: W - 30, by: 60))
}()
let band = max(0, (H - tile) / 2) / H   // the visible band above (and below) the tiles, as a fraction

func color(_ hex: String, _ alpha: Double = 1) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

/// A point at x points across and fraction y down (0 = top)
func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * S, y: (1 - y) * H * S) }

/// Same random numbers every time, so details don't move between redraws
struct Seeded {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 33) / Double(1 << 31)
    }
}

func vertical(_ ctx: CGContext, _ stops: [(Double, String)], alpha: Double = 1) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: stops.map { color($0.1, alpha) } as CFArray,
                       locations: stops.map { CGFloat($0.0) })!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H * S), end: CGPoint(x: 0, y: 0), options: [])
}

func horizontal(_ ctx: CGContext, _ stops: [(Double, String)], alpha: Double = 1) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: stops.map { color($0.1, alpha) } as CFArray,
                       locations: stops.map { CGFloat($0.0) })!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: W * S, y: 0), options: [])
}

func glow(_ ctx: CGContext, x: Double, y: Double, radius: Double, _ hex: String, _ alpha: Double) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(hex, alpha), color(hex, 0)] as CFArray,
                       locations: [0, 1])!
    let c = pt(x, y)
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius * S, options: [])
}

func fillBelow(_ ctx: CGContext, _ hex: String, _ alpha: Double, _ y: (Double) -> Double) {
    ctx.beginPath(); ctx.move(to: pt(0, 1))
    for x in stride(from: 0.0, through: W, by: 2) { ctx.addLine(to: pt(x, y(x))) }
    ctx.addLine(to: pt(W, 1)); ctx.closePath()
    ctx.setFillColor(color(hex, alpha)); ctx.fillPath()
}

func strokeLine(_ ctx: CGContext, _ hex: String, _ alpha: Double, width: Double, _ y: (Double) -> Double) {
    ctx.beginPath(); ctx.move(to: pt(0, y(0)))
    for x in stride(from: 2.0, through: W, by: 2) { ctx.addLine(to: pt(x, y(x))) }
    ctx.setStrokeColor(color(hex, alpha)); ctx.setLineWidth(width * S); ctx.setLineCap(.round); ctx.strokePath()
}

func dot(_ ctx: CGContext, x: Double, y: Double, r: Double, _ hex: String, _ alpha: Double) {
    ctx.setFillColor(color(hex, alpha))
    let c = pt(x, y)
    ctx.fillEllipse(in: CGRect(x: c.x - r * S, y: c.y - r * S, width: 2 * r * S, height: 2 * r * S))
}

/// An ellipse rotated by angle (radians), centered at x and fraction y; sizes in points
func petal(_ ctx: CGContext, x: Double, y: Double, w: Double, h: Double, angle: Double, _ hex: String, _ alpha: Double) {
    ctx.saveGState()
    let c = pt(x, y); ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: angle)
    ctx.setFillColor(color(hex, alpha))
    ctx.fillEllipse(in: CGRect(x: -w / 2 * S, y: -h / 2 * S, width: w * S, height: h * S))
    ctx.restoreGState()
}

/// A four-pointed sparkle, like the ✦ on the wallpaper
func sparkle(_ ctx: CGContext, x: Double, y: Double, r: Double, _ hex: String, _ alpha: Double) {
    let c = pt(x, y), k = r * S, t = k * 0.22
    ctx.beginPath()
    ctx.move(to: CGPoint(x: c.x, y: c.y + k))
    ctx.addQuadCurve(to: CGPoint(x: c.x + k, y: c.y), control: CGPoint(x: c.x + t, y: c.y + t))
    ctx.addQuadCurve(to: CGPoint(x: c.x, y: c.y - k), control: CGPoint(x: c.x + t, y: c.y - t))
    ctx.addQuadCurve(to: CGPoint(x: c.x - k, y: c.y), control: CGPoint(x: c.x - t, y: c.y - t))
    ctx.addQuadCurve(to: CGPoint(x: c.x, y: c.y + k), control: CGPoint(x: c.x - t, y: c.y + t))
    ctx.setFillColor(color(hex, alpha)); ctx.fillPath()
}

/// A vertical line in a gap, from fraction y0 to y1
func gapLine(_ ctx: CGContext, x: Double, _ y0: Double, _ y1: Double, width w: Double, _ hex: String, _ alpha: Double) {
    ctx.beginPath(); ctx.move(to: pt(x, y0)); ctx.addLine(to: pt(x, y1))
    ctx.setStrokeColor(color(hex, alpha)); ctx.setLineWidth(w * S); ctx.setLineCap(.round); ctx.strokePath()
}

let scenes: [String: (CGContext) -> Void] = [
    // Sunset over still water: violet cloud, a gold horizon through the middle,
    // dark water; in each gap the sun's reflection shimmers on the water
    "dusklake": { ctx in
        vertical(ctx, [(0, "2a2440"), (0.30, "5a3a52"), (0.46, "c8693a"), (0.50, "f2a24a"),
                       (0.54, "c8693a"), (0.70, "2c3a4a"), (1, "0e161e")])
        for x in stride(from: 120.0, to: W, by: 260) { glow(ctx, x: x, y: 0.5, radius: 160, "ffb347", 0.3) }
        for (i, x) in gaps.enumerated() {
            for k in 0..<3 {   // broken gold streaks below the horizon, shorter as they go down
                let y = 0.56 + Double(k) * 0.08 + (i % 2 == 0 ? 0 : 0.03)
                gapLine(ctx, x: x, y, y + 0.035 - Double(k) * 0.008, width: 1.6, "ffc66b", 0.75 - Double(k) * 0.2)
            }
        }
    },
    // Snow at dawn: rose sky into lavender, a low snowy ridge along the bottom band,
    // the first light at the right
    "alpenglow": { ctx in
        vertical(ctx, [(0, "f4c6d4"), (0.45, "e6c9e6"), (0.8, "d4dcef"), (1, "f6f4f8")])
        horizontal(ctx, [(0, "ffd6c2"), (0.5, "f4c6d4"), (1, "c9c6ef")], alpha: 0.45)
        glow(ctx, x: W - 30, y: 0.25, radius: 110, "fff1e6", 0.8)
        let ridge: (Double) -> Double = { x in 1 - band * 1.6 + band * 0.9 * abs(sin(x / 38)) }
        fillBelow(ctx, "c3b8df", 0.7) { ridge($0 + 20) - band * 0.5 }
        fillBelow(ctx, "fbf8fb", 0.95) { ridge($0) }
        for x in gaps { sparkle(ctx, x: x, y: 0.5, r: 2.2, "ffffff", 0.85) }   // frost glinting between tiles
    },
    // Autumn: warm wood, lamplight, and a leaf drifting down each gap
    "harvest": { ctx in
        vertical(ctx, [(0, "3b2618"), (0.5, "4a3020"), (1, "2b1b11")])
        for x in stride(from: 200.0, to: W, by: 420) { glow(ctx, x: x, y: 0.6, radius: 220, "d9773b", 0.18) }
        let leaves = ["d9773b", "b5432a", "d9a441", "8a8f4f"]
        for (i, x) in gaps.enumerated() {
            let y = 0.32 + 0.36 * Double((i * 5) % 7) / 6
            petal(ctx, x: x, y: y, w: 3.2, h: 7, angle: (i % 2 == 0 ? 0.5 : -0.5), leaves[i % leaves.count], 0.9)
        }
    },
    // Flowers after dark: a stem rises up each gap and blooms in the band above the tiles
    "nightgarden": { ctx in
        vertical(ctx, [(0, "040406"), (1, "0a0812")])
        let petals = ["ff5fa2", "3fd0c9", "a78bfa", "ff8a5c", "9be15d", "d16bff"]
        let top = band * 0.55
        for (i, x) in gaps.enumerated() {
            let c = petals[i % petals.count]
            gapLine(ctx, x: x, 1.02, top + 0.04, width: 1.3, "3f8a5f", 0.85)
            petal(ctx, x: x + 1.6, y: 0.62 + 0.08 * Double(i % 3), w: 2.2, h: 4.5, angle: -0.7, "3f8a5f", 0.85)   // a leaf
            glow(ctx, x: x, y: top, radius: 14, c, 0.6)
            dot(ctx, x: x, y: top, r: 2.6, c, 1)
        }
    },
    // Fuji in spring: pale sky into teal, the mountain as a faint broad form behind,
    // a blossom petal falling in each gap
    "sakura": { ctx in
        vertical(ctx, [(0, "eaf3f4"), (0.55, "bcd9dc"), (1, "8fbfc4")])
        horizontal(ctx, [(0, "f7c3d6"), (0.3, "f7c3d6"), (0.6, "bcd9dc")], alpha: 0.4)
        let peak = W * 0.7, half = W * 0.32
        ctx.beginPath(); ctx.move(to: pt(peak - half, 1.05)); ctx.addLine(to: pt(peak, 0.05)); ctx.addLine(to: pt(peak + half, 1.05))
        ctx.closePath(); ctx.setFillColor(color("7fb3b8", 0.35)); ctx.fillPath()
        for (i, x) in gaps.enumerated() {
            let y = 0.3 + 0.4 * Double((i * 3) % 5) / 4
            petal(ctx, x: x, y: y, w: 3.6, h: 5.2, angle: Double(i) * 0.9, "f28cb1", 0.9)
        }
    },
    // Northern lights: smooth curtains of green, teal and violet over navy; stars
    // only where the tiles leave sky showing
    "aurora": { ctx in
        vertical(ctx, [(0, "070b1c"), (0.6, "0b1630"), (1, "0a1a26")])
        let bands: [(String, Double, Double, Double)] = [("3dffa8", 0.40, 70, 0.0), ("2fd6d0", 0.50, 110, 1.7), ("9a7bff", 0.34, 160, 3.1)]
        for (hex, base, wave, phase) in bands {
            for k in 0..<5 {
                let off = Double(k) * 0.03
                let y: (Double) -> Double = { x in base + off + 0.12 * sin(x / wave + phase) }
                ctx.beginPath(); ctx.move(to: pt(0, y(0)))
                for x in stride(from: 2.0, through: W, by: 2) { ctx.addLine(to: pt(x, y(x))) }
                for x in stride(from: W, through: 0, by: -2) { ctx.addLine(to: pt(x, y(x) + 0.16)) }
                ctx.closePath(); ctx.setFillColor(color(hex, 0.08)); ctx.fillPath()
            }
        }
        var r = Seeded(state: 9)
        for x in gaps { for _ in 0..<2 { dot(ctx, x: x + (r.next() - 0.5) * 3, y: 0.2 + r.next() * 0.6, r: 0.6 + r.next() * 0.4, "ffffff", 0.8) } }
        for _ in 0..<Int(W / 12) { dot(ctx, x: r.next() * W, y: r.next() * band, r: 0.5, "ffffff", 0.7) }   // in the top band
    },
    // Desert dusk: broad dunes from pale sand to rust, a pale sun
    "dune": { ctx in
        vertical(ctx, [(0, "f6d9b8"), (0.6, "f0c49a"), (1, "e8b083")])
        glow(ctx, x: W - 40, y: 0.3, radius: 70, "fff4e0", 0.9)
        fillBelow(ctx, "e3a46f", 0.9) { x in 0.48 + 0.10 * sin(x / 160 + 0.5) }
        fillBelow(ctx, "cf7f4f", 0.9) { x in 0.66 + 0.08 * sin(x / 120 + 2.0) }
        fillBelow(ctx, "a9583a", 0.95) { x in 1 - band * 1.2 + band * 0.4 * sin(x / 90 + 4.0) }
    },
    // The sea: deep teal below, shallow aqua above, foam lines that run through the gaps
    "tide": { ctx in
        vertical(ctx, [(0, "9fe3e0"), (0.45, "3fb2b8"), (1, "0f5a6b")])
        for (k, base) in [0.32, 0.55, 0.78].enumerated() {
            let amp = 0.04 + Double(k) * 0.012
            fillBelow(ctx, "0f5a6b", 0.16) { x in base + amp * sin(x / 60 + Double(k) * 1.4) }
            strokeLine(ctx, "ffffff", 0.6, width: 1.1) { x in base + amp * sin(x / 60 + Double(k) * 1.4) }
        }
    },
    // Art deco: burgundy velvet framed by gold rules, a slim gold pillar between tiles
    "velvet": { ctx in
        vertical(ctx, [(0, "4a0f1f"), (1, "2a0812")])
        horizontal(ctx, [(0, "000000"), (0.5, "6a1830"), (1, "000000")], alpha: 0.35)
        strokeLine(ctx, "d4af6a", 0.75, width: 0.9) { _ in band * 0.5 }
        strokeLine(ctx, "d4af6a", 0.75, width: 0.9) { _ in 1 - band * 0.5 }
        for x in gaps {
            gapLine(ctx, x: x, band + 0.06, 1 - band - 0.06, width: 0.9, "d4af6a", 0.8)
            let c = pt(x, 0.5), d = 3.0 * S
            ctx.beginPath(); ctx.move(to: CGPoint(x: c.x, y: c.y + d)); ctx.addLine(to: CGPoint(x: c.x + d * 0.6, y: c.y))
            ctx.addLine(to: CGPoint(x: c.x, y: c.y - d)); ctx.addLine(to: CGPoint(x: c.x - d * 0.6, y: c.y)); ctx.closePath()
            ctx.setFillColor(color("d4af6a", 0.95)); ctx.fillPath()
        }
    },
    // A tea house: soft matcha paper, a bamboo stalk standing in each gap
    "matcha": { ctx in
        vertical(ctx, [(0, "e3ebd2"), (1, "cfdcb7")])
        for (i, x) in gaps.enumerated() {
            gapLine(ctx, x: x, -0.05, 1.05, width: 3.2, "8fae6a", 0.8)
            for k in 0..<2 {
                let ny = 0.28 + Double(k) * 0.4 + (i % 2 == 0 ? 0 : 0.1)
                ctx.beginPath(); ctx.move(to: pt(x - 2.4, ny)); ctx.addLine(to: pt(x + 2.4, ny))
                ctx.setStrokeColor(color("6c8c4c", 0.9)); ctx.setLineWidth(1.2 * S); ctx.strokePath()
            }
        }
    },
    // Deep space: violet, magenta and blue gas, a faint starfield, a bright star in each gap
    "nebula": { ctx in
        vertical(ctx, [(0, "0a0618"), (0.5, "120a2a"), (1, "07040f")])
        var r = Seeded(state: 21)
        let gas: [(String, Double)] = [("7b3fe4", 0.42), ("d0409a", 0.38), ("3a5bd9", 0.36), ("5a2a9e", 0.40), ("ff6fb5", 0.22)]
        for i in 0..<max(4, Int(W / 90)) {
            let (hex, a) = gas[i % gas.count]
            glow(ctx, x: r.next() * W, y: 0.2 + r.next() * 0.6, radius: 50 + r.next() * 90, hex, a * 1.15)
        }
        horizontal(ctx, [(0, "000000"), (0.5, "3d1f7a"), (1, "000000")], alpha: 0.18)
        for _ in 0..<Int(W * 0.5) {
            let b = r.next()
            dot(ctx, x: r.next() * W, y: r.next(), r: 0.25 + b * 0.35, "ffffff", 0.2 + b * 0.4)
        }
        for (i, x) in gaps.enumerated() where i % 2 == 0 {
            let y = 0.3 + r.next() * 0.4
            glow(ctx, x: x, y: y, radius: 8, "e8e0ff", 0.6)
            dot(ctx, x: x, y: y, r: 1.0, "ffffff", 1)
        }
    },
    // Orbit: made to sit with the Candy Orbit wallpaper rather than copy it. The
    // wallpaper's navy outline color as a deep night tray, a faint dotted orbit, and
    // a cream or peach sparkle in each gap, like the ✦ scattered over the desktop
    "orbit": { ctx in
        vertical(ctx, [(0, "22324f"), (1, "17233b")])
        glow(ctx, x: W - 26, y: 0.35, radius: 90, "f6a46b", 0.22)   // warm light from the sun's side
        glow(ctx, x: 30, y: 0.65, radius: 90, "8fd3f5", 0.14)       // sky blue at the other end
        strokeLine(ctx, "fff4e0", 0.22, width: 0.9) { x in 0.5 + 0.28 * sin(x / (W / 2.2) + 0.6) }   // one faint orbit
        let tones = ["fff4e0", "f6a46b", "fff4e0", "8fd3f5"]
        for (i, x) in gaps.enumerated() {
            let y = 0.32 + 0.36 * Double((i * 3) % 5) / 4
            sparkle(ctx, x: x, y: y, r: 3.2, tones[i % tones.count], 0.95)
        }
    },
]

guard let draw = scenes[args[1]] else { exit(1) }
let ctx = CGContext(data: nil, width: Int(W * S), height: Int(H * S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
draw(ctx)
// The tray's outline, on top of the scenery
if args.count > 7, let v = UInt32(args[5].replacingOccurrences(of: "0x", with: ""), radix: 16),
   let lw = Double(args[6]), lw > 0, let radius = Double(args[7]) {
    ctx.setStrokeColor(CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                               blue: CGFloat(v & 0xff) / 255, alpha: CGFloat(v >> 24) / 255))
    ctx.setLineWidth(lw * S)
    let inset = lw * S / 2, r = min(radius, H / 2) * S
    ctx.addPath(CGPath(roundedRect: CGRect(x: inset, y: inset, width: W * S - 2 * inset, height: H * S - 2 * inset),
                       cornerWidth: r - inset, cornerHeight: r - inset, transform: nil))
    ctx.strokePath()
}
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
