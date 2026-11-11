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
/// Each tile's left and right edge in points (DOCKART_TILES "l-r,l-r,…", the Trash included);
/// without it, worked out from the gaps
let tiles: [(Double, Double)] = {
    let given = (env["DOCKART_TILES"] ?? "").split(separator: ",").compactMap { pair -> (Double, Double)? in
        let p = pair.split(separator: "-").compactMap { Double($0) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }
    if !given.isEmpty { return given }
    guard let first = gaps.first else { return [] }
    let pitch = gaps.count > 1 ? gaps[1] - gaps[0] : 60
    return ([first - pitch / 2] + gaps.map { $0 + pitch / 2 }).map { ($0 - tile / 2, $0 + tile / 2) }
}()
/// A rectangle from x0 to x1 points across and fractions y0 to y1 down
func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
    CGRect(x: x0 * S, y: (1 - y1) * H * S, width: (x1 - x0) * S, height: (y1 - y0) * H * S)
}
func fillRect(_ ctx: CGContext, _ r: CGRect, _ hex: String, _ alpha: Double) { ctx.setFillColor(color(hex, alpha)); ctx.fill(r) }
func dashes(_ ctx: CGContext, y: Double, from x0: Double, to x1: Double, dash: Double, gap: Double, width w: Double, _ hex: String, _ alpha: Double) {
    ctx.saveGState()
    ctx.beginPath(); ctx.move(to: pt(x0, y)); ctx.addLine(to: pt(x1, y))
    ctx.setStrokeColor(color(hex, alpha)); ctx.setLineWidth(w * S); ctx.setLineDash(phase: 0, lengths: [dash * S, gap * S])
    ctx.strokePath(); ctx.restoreGState()
}

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

    // ---- Made to go with the Candy Orbit wallpaper (its colors are sampled from it) ----

    // Daybreak: the wallpaper's whole day in one ribbon, left to right: night, dawn
    // magenta, morning peach, noon blue, the gold afternoon, dusk, night again. It shows
    // in the bands around the tiles; the sun sits in the noon gap, stars at night
    "daybreak": { ctx in
        horizontal(ctx, [(0, "211158"), (0.11, "963e89"), (0.22, "ffaaad"), (0.34, "fecf99"), (0.46, "d4e5d8"),
                         (0.56, "9addfe"), (0.68, "fcc56d"), (0.79, "ba454b"), (0.89, "612975"), (1, "211158")])
        vertical(ctx, [(0, "ffffff"), (0.5, "ffffff"), (1, "000000")], alpha: 0.10)
        let noon = gaps.min(by: { abs($0 - W * 0.53) < abs($1 - W * 0.53) }) ?? W / 2
        for x in gaps {
            let t = x / W
            if x == noon { glow(ctx, x: x, y: 0.5, radius: 22, "fff6cf", 0.9); dot(ctx, x: x, y: 0.5, r: 2.8, "fffbea", 1) }
            else if t < 0.16 || t > 0.84 { sparkle(ctx, x: x, y: 0.5, r: 2.6, "fff4e0", 0.95) }
        }
    },
    // Gas Giant: the big striped planet's bands, cream, orange and terracotta, tilted
    // like the planet in the corner, with its soft highlight
    "gasgiant": { ctx in
        vertical(ctx, [(0, "f6e2b4"), (1, "f2d4a1")])
        let tilt: (Double) -> Double = { x in 0.07 * (x / W - 0.5) }
        let bands: [(String, Double)] = [("f0a860", 0.14), ("f6e2b4", 0.30), ("c67357", 0.44), ("e98f64", 0.56),
                                          ("f2d4a1", 0.66), ("f0a860", 0.80), ("c67357", 0.93)]
        for (hex, y) in bands { fillBelow(ctx, hex, 1) { y + tilt($0) } }
        glow(ctx, x: W * 0.12, y: 0.32, radius: 60, "fffbea", 0.45)
    },
    // Ring: the planet's ring as the tray, its cream and tan bands running the length
    "ring": { ctx in
        vertical(ctx, [(0, "e2cfa3"), (0.16, "e7d5b0"), (0.17, "f3ecd6"), (0.36, "f3ecd6"), (0.37, "e2cfa3"),
                       (0.63, "e2cfa3"), (0.64, "f3ecd6"), (0.83, "f3ecd6"), (0.84, "e7d5b0"), (1, "e2cfa3")])
        for y in [0.365, 0.635] { strokeLine(ctx, "c9b080", 0.55, width: 0.8) { _ in y } }
    },
    // Rocket: the rocket's white hull, softly rounded, rivets along the top band and its
    // pink stripe along the bottom one
    "rocket": { ctx in
        vertical(ctx, [(0, "eceaf4"), (0.35, "fdfcff"), (0.7, "f6f5fa"), (1, "e4e2ee")])
        for x in stride(from: 18.0, to: W - 12, by: 15) { dot(ctx, x: x, y: band * 0.5, r: 0.8, "b9b6c8", 0.9) }
        strokeLine(ctx, "e84a7e", 1, width: 2.6) { _ in 1 - band * 0.5 }
    },
    // Cumulus: the daytime sky, with the wallpaper's outlined cream clouds billowing in
    // along the top and bottom edges, around the tiles rather than behind them
    "cumulus": { ctx in
        vertical(ctx, [(0, "a9d3e6"), (1, "cfe6e2")])
        glow(ctx, x: W - 70, y: 0.25, radius: 130, "fff6cf", 0.55)
        var r = Seeded(state: 5)
        func bank(top: Bool) {
            var puffs: [(Double, Double)] = []
            var x = -6.0
            while x < W + 10 { puffs.append((x, 6.5 + r.next() * 3.5)); x += 11 + r.next() * 7 }
            let yc = top ? -3.5 / H : 1 + 3.5 / H
            for (x, rad) in puffs { dot(ctx, x: x, y: yc, r: rad + 1.1, "1e2340", 0.75) }   // outline first,
            for (x, rad) in puffs { dot(ctx, x: x, y: yc, r: rad, "fffaf0", 1) }            // then the cream over it
        }
        bank(top: true); bank(top: false)
        for (i, x) in gaps.enumerated() where i % 3 == 1 { sparkle(ctx, x: x, y: 0.5, r: 2.4, "ffffff", 0.8) }
    },
    // Starlight: the wallpaper's night: indigo, the soft diagonal beam, dotted orbit
    // tracks in the bands, and white and lime sparkles between tiles
    "starlight": { ctx in
        vertical(ctx, [(0, "2a166b"), (1, "1b0f4e")])
        for (w, a) in [(150.0, 0.16), (70.0, 0.14)] {   // the beam, rising to the right
            ctx.beginPath(); ctx.move(to: pt(W * 0.25, 1.1)); ctx.addLine(to: pt(W * 0.25 + w, 1.1))
            ctx.addLine(to: pt(W * 0.75 + w, -0.1)); ctx.addLine(to: pt(W * 0.75, -0.1)); ctx.closePath()
            ctx.setFillColor(color("8a7ad0", a)); ctx.fillPath()
        }
        for y in [band * 0.5, 1 - band * 0.5] {
            for x in stride(from: 10.0, to: W - 8, by: 6) { dot(ctx, x: x, y: y, r: 0.55, "c9c0f0", 0.55) }
        }
        for (i, x) in gaps.enumerated() {
            let y = 0.34 + 0.32 * Double((i * 3) % 5) / 4
            if i % 2 == 0 { sparkle(ctx, x: x, y: y, r: 3.2, "f7f2ff", 1) } else { sparkle(ctx, x: x, y: y, r: 2.2, "c8f05a", 1) }
        }
    },
    // Red Planet: the little red planet's dusty rust, darker patches, and a crater in each gap
    "redplanet": { ctx in
        vertical(ctx, [(0, "e07a5a"), (0.5, "c8553e"), (1, "a5402f")])
        var r = Seeded(state: 13)
        for _ in 0..<max(3, Int(W / 140)) { glow(ctx, x: r.next() * W, y: 0.3 + r.next() * 0.4, radius: 50 + r.next() * 60, "8a464a", 0.35) }
        glow(ctx, x: W * 0.2, y: 0.2, radius: 120, "f2956e", 0.35)
        for (i, x) in gaps.enumerated() {
            let y = 0.3 + 0.4 * Double((i * 5) % 7) / 6, s = 1.7 + Double(i % 3) * 0.45
            dot(ctx, x: x + 0.5, y: y + 0.6 / H, r: s + 0.6, "f2956e", 0.55)   // the lit rim
            dot(ctx, x: x, y: y, r: s, "7a3436", 0.75)
        }
    },
    // Phosphor '77: an amber CRT in a dark room. Scanlines over warm black, an instrument
    // ruler along the top band, a stream of data and a cursor along the bottom. The gaps
    // stay empty: the icons float on the glass
    "phosphor": { ctx in
        vertical(ctx, [(0, "160d04"), (1, "0b0602")])
        glow(ctx, x: W / 2, y: 0.5, radius: W * 0.45, "ffb000", 0.07)
        ctx.setFillColor(color("000000", 0.32))
        for y in stride(from: 0.0, to: H, by: 2) { ctx.fill(CGRect(x: 0, y: y * S, width: W * S, height: S * 0.9)) }
        for (i, x) in stride(from: 14.0, to: W - 12, by: 6).enumerated() {   // the ruler
            gapLine(ctx, x: x, 0.0, (i % 5 == 0 ? band * 0.75 : band * 0.35), width: 0.8, "ffb000", i % 5 == 0 ? 0.7 : 0.4)
        }
        let y = 1 - band * 0.5
        ctx.setFillColor(color("ffb000", 0.95)); ctx.fill(CGRect(origin: pt(12, y + 0.04), size: CGSize(width: 4 * S, height: 5 * S)))   // cursor
        var r = Seeded(state: 77), x = 22.0
        while x < W - 16 {
            let len = 2 + r.next() * 12
            ctx.setFillColor(color("ffb000", 0.25 + r.next() * 0.3)); ctx.fill(CGRect(origin: pt(x, y + 0.012), size: CGSize(width: min(len, W - 16 - x) * S, height: 1.4 * S)))
            x += len + 3 + r.next() * 4
        }
    },
    // Riso Zine: newsprint, two inks overprinted and slightly out of register: a big
    // fluorescent pink sun and a yellow slab that turn orange where they cross, a blue
    // frame printed a hair off, a halftone fade along the top. Most of the page stays bare
    "riso": { ctx in
        vertical(ctx, [(0, "f2ece0"), (1, "f2ece0")])
        var r = Seeded(state: 3)
        for _ in 0..<Int(W * 2.5) { dot(ctx, x: r.next() * W, y: r.next(), r: 0.3, "2a2418", 0.10) }   // paper grain
        ctx.setBlendMode(.multiply)
        dot(ctx, x: W * 0.16, y: 0.95, r: 58, "ff48b0", 0.9)          // the pink sun, sinking off the bottom
        ctx.beginPath(); ctx.move(to: pt(W * 0.30, -0.1)); ctx.addLine(to: pt(W * 0.30 + 46, -0.1))
        ctx.addLine(to: pt(W * 0.30 - 10, 1.1)); ctx.addLine(to: pt(W * 0.30 - 56, 1.1)); ctx.closePath()
        ctx.setFillColor(color("ffe800", 0.95)); ctx.fillPath()       // the yellow slab, crossing it
        ctx.beginPath(); ctx.move(to: pt(W * 0.74, -0.1)); ctx.addLine(to: pt(W * 0.74 + 18, -0.1))
        ctx.addLine(to: pt(W * 0.74 - 4, 1.1)); ctx.addLine(to: pt(W * 0.74 - 22, 1.1)); ctx.closePath()
        ctx.setFillColor(color("ff48b0", 0.85)); ctx.fillPath()       // and a thin pink one far right
        for (i, x) in stride(from: W * 0.42, to: W - 10, by: 5).enumerated() {   // halftone, fading out
            let s = max(0, 1.4 - Double(i) * 0.02)
            if s > 0.15 { dot(ctx, x: x, y: band * 0.5, r: s, "3255a4", 0.9) }
        }
        ctx.setBlendMode(.normal)
        ctx.setStrokeColor(color("3255a4", 0.9)); ctx.setLineWidth(2 * S)   // the blue frame, printed 2pt off
        ctx.stroke(CGRect(x: 3.5 * S, y: 1.5 * S, width: (W - 5) * S, height: (H - 4.5) * S))
    },
    // ---- Styles ----

    // Broadsheet (brutalist editorial): newsprint under a solid black masthead rule with a
    // red issue block, column rules standing in the gaps, a double rule at the foot
    "broadsheet": { ctx in
        fillRect(ctx, rect(0, 0, W, 1), "f1efe9", 1)
        var r = Seeded(state: 8)
        for _ in 0..<Int(W * 1.5) { dot(ctx, x: r.next() * W, y: r.next(), r: 0.3, "000000", 0.06) }
        fillRect(ctx, rect(0, 0, W, band * 0.62), "111111", 1)
        fillRect(ctx, rect(W - 74, 0, W - 22, band * 0.62), "ff2a00", 1)
        for x in gaps { gapLine(ctx, x: x, band + 0.04, 1 - band - 0.04, width: 0.9, "111111", 0.9) }
        fillRect(ctx, rect(0, 1 - band * 0.55, W, 1 - band * 0.55 + 1.6 / H), "111111", 1)
        fillRect(ctx, rect(0, 1 - band * 0.2, W, 1 - band * 0.2 + 0.6 / H), "111111", 1)
    },
    // Saddle (warm tactile analog): cognac leather with its grain, saddle-stitched along
    // both edges in cream thread. Nothing in the gaps; the leather is the point
    "saddle": { ctx in
        vertical(ctx, [(0, "a0602f"), (0.5, "8f5228"), (1, "74401f")])
        horizontal(ctx, [(0, "000000"), (0.12, "000000"), (0.5, "ffffff"), (0.88, "000000"), (1, "000000")], alpha: 0.07)
        var r = Seeded(state: 4)
        for _ in 0..<Int(W * 3) { dot(ctx, x: r.next() * W, y: r.next(), r: 0.35, r.next() < 0.5 ? "3a1f0c" : "e8c49a", 0.09) }
        for y in [band * 0.48, 1 - band * 0.48] {
            dashes(ctx, y: y + 0.6 / H, from: 10, to: W - 10, dash: 3.6, gap: 2.4, width: 1.2, "3a1f0c", 0.45)   // the stitch holes' shadow
            dashes(ctx, y: y, from: 10, to: W - 10, dash: 3.6, gap: 2.4, width: 1.1, "f3e3c4", 0.9)
        }
    },
    // Swiss: white, one red field taking the first columns, a heavy black bar at the
    // foot, a hairline and grid ticks along the top, everything else left empty
    "swiss": { ctx in
        fillRect(ctx, rect(0, 0, W, 1), "ffffff", 1)
        let edge = gaps.count > 1 ? gaps[1] : W * 0.15
        fillRect(ctx, rect(0, 0, edge, 1), "ff1a1a", 1)
        fillRect(ctx, rect(0, 1 - band * 0.62, W, 1), "111111", 1)
        fillRect(ctx, rect(edge, band * 0.45, W, band * 0.45 + 0.7 / H), "111111", 1)
        for (l, _) in tiles where l > edge { fillRect(ctx, rect(l, band * 0.45 - 2.4 / H, l + 0.8, band * 0.45), "111111", 1) }
    },
    // Pop (neo-brutalist): sunflower yellow, and a hard black shadow knocked out behind
    // every tile, offset down and right like a sticker on a page
    "pop": { ctx in
        fillRect(ctx, rect(0, 0, W, 1), "ffc900", 1)
        let top = band, bottom = 1 - band, d = 3.5 * tile / 52, round = 8 * tile / 52
        for (l, rr) in tiles {
            let box = rect(l + d, top + d / H, rr + d, bottom + d / H)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: round * S, cornerHeight: round * S, transform: nil))
            ctx.setFillColor(color("111111", 1)); ctx.fillPath()
        }
    },
    // Precision (industrial, after the ten principles): warm grey enamel, a speaker grille
    // of fine perforations in the top-right corner only, one orange power light
    "precision": { ctx in
        vertical(ctx, [(0, "eceae5"), (1, "dddad3")])
        for row in 0..<2 {
            for x in stride(from: W * 0.62, to: W - 16, by: 4) {
                dot(ctx, x: x + Double(row) * 2, y: band * (0.3 + Double(row) * 0.38), r: 0.65, "4a4844", 0.55)
            }
        }
        glow(ctx, x: 18, y: band * 0.5, radius: 6, "ff6a13", 0.5)
        dot(ctx, x: 18, y: band * 0.5, r: 1.6, "ff6a13", 1)
    },
    // Obsidian (high-craft dark): near-black with a fine grain, one warm light from above,
    // and a hairline of light along the top edge, like a machined bevel
    "obsidian": { ctx in
        fillRect(ctx, rect(0, 0, W, 1), "0c0d0f", 1)
        var r = Seeded(state: 2)
        for _ in 0..<Int(W * 2) { dot(ctx, x: r.next() * W, y: r.next(), r: 0.3, "ffffff", 0.035) }
        glow(ctx, x: W * 0.5, y: -0.6, radius: W * 0.32, "ff6363", 0.16)
        glow(ctx, x: W * 0.5, y: -0.6, radius: W * 0.12, "ffd2c2", 0.10)
        let edge = rect(24, 0.012, W - 24, 0.012 + 0.6 / H)
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [color("ffffff", 0), color("ffffff", 0.22), color("ffffff", 0)] as CFArray, locations: [0, 0.5, 1])!
        ctx.saveGState(); ctx.clip(to: edge)
        ctx.drawLinearGradient(g, start: CGPoint(x: edge.minX, y: 0), end: CGPoint(x: edge.maxX, y: 0), options: [])
        ctx.restoreGState()
    },
    // Millennium (Y2K): brushed chrome, acid-lime sparkles in some gaps, and a
    // segmented loading bar along the bottom, stuck at 62%
    "millennium": { ctx in
        vertical(ctx, [(0, "d9dde0"), (0.16, "ffffff"), (0.46, "c8cdd2"), (0.56, "aab0b6"), (0.82, "eceef0"), (1, "c2c7cc")])
        for (i, x) in gaps.enumerated() where i % 3 == 1 { sparkle(ctx, x: x, y: 0.5, r: 3.4, "b8f000", 1) }
        let y0 = 1 - band * 0.78, y1 = 1 - band * 0.22
        var x = 16.0
        while x + 4 < W - 16 {
            let done = x < (W - 32) * 0.62 + 16
            let box = rect(x, y0, x + 4, y1)
            if done { fillRect(ctx, box, "b8f000", 1); ctx.setStrokeColor(color("5a7000", 0.7)) }
            else { fillRect(ctx, box, "ffffff", 0.5); ctx.setStrokeColor(color("6a7178", 0.5)) }
            ctx.setLineWidth(0.5 * S); ctx.stroke(box)
            x += 5.5
        }
    },
    // Bento (Japanese bento and magazine editorial): washi paper divided like a bento
    // box: ink rules above and below, a divider in every gap, a vermilion seal in the corner
    "bento": { ctx in
        fillRect(ctx, rect(0, 0, W, 1), "f4efe4", 1)
        var r = Seeded(state: 11)
        for _ in 0..<Int(W * 0.8) {   // paper fibres
            let x = r.next() * W, y = r.next(), a = r.next() * 3.1
            ctx.beginPath(); ctx.move(to: pt(x, y)); ctx.addLine(to: pt(x + cos(a) * 3, y + sin(a) * 3 / H))
            ctx.setStrokeColor(color("b8a888", 0.18)); ctx.setLineWidth(0.4 * S); ctx.strokePath()
        }
        let t = band * 0.5, b = 1 - band * 0.5
        for y in [t, b] { fillRect(ctx, rect(8, y - 0.6 / H, W - 8, y + 0.6 / H), "1c1c1c", 0.9) }
        for x in gaps { gapLine(ctx, x: x, t, b, width: 1.2, "1c1c1c", 0.9) }
        fillRect(ctx, rect(W - 26, t - 3.2 / H, W - 18.5, t + 4.3 / H), "e34234", 1)   // the seal, over the rule
        ctx.setStrokeColor(color("f4efe4", 0.8)); ctx.setLineWidth(0.5 * S); ctx.stroke(rect(W - 24.8, t - 2.0 / H, W - 19.7, t + 3.1 / H))
    },
    // Moonlight: the half-lit moon, pale grey into its shadow along the dock, with a
    // crater in each gap, lighter or darker with the side it is on
    "moonlight": { ctx in
        horizontal(ctx, [(0, "e6e0d4"), (0.42, "d2cbbd"), (0.58, "7d7984"), (1, "4a4756")])
        vertical(ctx, [(0, "ffffff"), (1, "000000")], alpha: 0.08)
        for (i, x) in gaps.enumerated() {
            let lit = x / W < 0.5, y = 0.32 + 0.36 * Double((i * 3) % 5) / 4, s = 1.8 + Double(i % 3) * 0.5
            dot(ctx, x: x - 0.4, y: y - 0.5 / H, r: s + 0.5, lit ? "f4f0e8" : "9a96a4", 0.7)
            dot(ctx, x: x, y: y, r: s, lit ? "b3ab9b" : "3e3b48", 0.8)
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
