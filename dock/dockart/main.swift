// dockart: draws the scenery behind the dock's tray for the themes that have it.
//   dockart <theme> <width> <out.png> [height]   exits 1 if the theme has no scenery
// (height defaults to the 68pt tray; the theme gallery and menus draw smaller ones)
// Each scene is gradients and a few simple shapes after the picture or place the
// theme is based on, kept soft so the tiles read clearly on top. It's drawn at the
// tray's exact width (2x pixels for Retina) so its rounded ends line up; the dock
// redraws it whenever its width changes. Heights are given as fractions (0 = top).
import AppKit

let args = CommandLine.arguments
guard args.count > 3, let width = Double(args[2]) else { exit(2) }
let W = width, H = args.count > 4 ? Double(args[4]) ?? 68 : 68.0, S = 2.0   // points

func color(_ hex: String, _ alpha: Double = 1) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

/// A point at x points across and fraction y down (0 = top)
func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * S, y: (1 - y) * H * S) }

/// Same random numbers every time, so petals and stars don't move between redraws
struct Seeded {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 33) / Double(1 << 31)
    }
}

/// stops: (fraction from the top, color)
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

/// A soft round glow centered at x points and fraction y, radius in points
func glow(_ ctx: CGContext, x: Double, y: Double, radius: Double, _ hex: String, _ alpha: Double) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(hex, alpha), color(hex, 0)] as CFArray,
                       locations: [0, 1])!
    let c = pt(x, y)
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius * S, options: [])
}

/// Fill the area under a wavy line: y(x) is a fraction; down to the bottom edge
func fillBelow(_ ctx: CGContext, _ hex: String, _ alpha: Double, _ y: (Double) -> Double) {
    ctx.beginPath()
    ctx.move(to: pt(0, 1))
    for x in stride(from: 0.0, through: W, by: 2) { ctx.addLine(to: pt(x, y(x))) }
    ctx.addLine(to: pt(W, 1)); ctx.closePath()
    ctx.setFillColor(color(hex, alpha)); ctx.fillPath()
}

/// Stroke a wavy line
func strokeLine(_ ctx: CGContext, _ hex: String, _ alpha: Double, width: Double, _ y: (Double) -> Double) {
    ctx.beginPath()
    ctx.move(to: pt(0, y(0)))
    for x in stride(from: 2.0, through: W, by: 2) { ctx.addLine(to: pt(x, y(x))) }
    ctx.setStrokeColor(color(hex, alpha)); ctx.setLineWidth(width * S); ctx.setLineCap(.round); ctx.strokePath()
}

func dot(_ ctx: CGContext, x: Double, y: Double, r: Double, _ hex: String, _ alpha: Double) {
    ctx.setFillColor(color(hex, alpha))
    let c = pt(x, y)
    ctx.fillEllipse(in: CGRect(x: c.x - r * S, y: c.y - r * S, width: 2 * r * S, height: 2 * r * S))
}

func triangle(_ ctx: CGContext, x: Double, base: Double, top: Double, half: Double, _ hex: String, _ alpha: Double) {
    ctx.beginPath()
    ctx.move(to: pt(x - half, base)); ctx.addLine(to: pt(x, top)); ctx.addLine(to: pt(x + half, base)); ctx.closePath()
    ctx.setFillColor(color(hex, alpha)); ctx.fillPath()
}

let scenes: [String: (CGContext) -> Void] = [
    // Sunset over still water: violet cloud, a gold horizon, pines on the shore and
    // their reflection, dark water
    "dusklake": { ctx in
        vertical(ctx, [(0, "2a2440"), (0.30, "5a3a52"), (0.46, "c8693a"), (0.50, "f2a24a"),
                       (0.54, "c8693a"), (0.70, "2c3a4a"), (1, "0e161e")])
        for x in stride(from: 120.0, to: W, by: 260) { glow(ctx, x: x, y: 0.5, radius: 160, "ffb347", 0.35) }
        var r = Seeded(state: 7)
        for x in stride(from: 4.0, to: W, by: 9) {
            // pines thin out toward the middle, like a far shore
            let edge = min(x, W - x) / (W / 2)
            guard r.next() > edge * 0.85 else { continue }
            let h = 0.10 + r.next() * 0.12 * (1 - edge * 0.6)
            triangle(ctx, x: x, base: 0.5, top: 0.5 - h, half: 3.2, "141b24", 0.75)
            triangle(ctx, x: x, base: 0.5, top: 0.5 + h, half: 3.2, "141b24", 0.35)   // reflection
        }
    },
    // Snow at dawn: rose sky into lavender, a snowy ridge with lavender shadows
    "alpenglow": { ctx in
        vertical(ctx, [(0, "f4c6d4"), (0.45, "e6c9e6"), (0.8, "d4dcef"), (1, "f6f4f8")])
        horizontal(ctx, [(0, "ffd6c2"), (0.5, "f4c6d4"), (1, "c9c6ef")], alpha: 0.45)
        glow(ctx, x: W * 0.78, y: 0.2, radius: 120, "ffe3d3", 0.6)
        let ridge: (Double) -> Double = { x in
            0.58 - 0.16 * abs(sin(x / 95)) - 0.08 * abs(sin(x / 37 + 1.3))
        }
        fillBelow(ctx, "b9b0d8", 0.55) { ridge($0) + 0.03 }          // shadowed far range
        fillBelow(ctx, "fbf7fb", 0.85) { ridge($0 + 40) + 0.12 }     // sunlit snow in front
    },
    // Autumn: warm wood-brown, lamplight, fallen leaves along the bottom
    "harvest": { ctx in
        vertical(ctx, [(0, "3b2618"), (0.5, "4a3020"), (1, "2b1b11")])
        for x in stride(from: 200.0, to: W, by: 420) { glow(ctx, x: x, y: 0.6, radius: 220, "d9773b", 0.18) }
        var r = Seeded(state: 11)
        let leaves = ["d9773b", "b5432a", "d9a441", "8a8f4f"]
        for x in stride(from: 6.0, to: W, by: 11) {
            let y = 0.86 + r.next() * 0.12
            dot(ctx, x: x + r.next() * 6, y: y, r: 1.6 + r.next() * 1.6, leaves[Int(r.next() * 4) % 4], 0.55)
        }
    },
    // Flowers after dark: black, stems rising from the bottom, blooms glowing on top
    "nightgarden": { ctx in
        vertical(ctx, [(0, "040406"), (1, "0a0812")])
        let petals = ["ff5fa2", "3fd0c9", "a78bfa", "ff8a5c", "9be15d", "d16bff"]
        var r = Seeded(state: 3)
        for (i, x) in stride(from: 30.0, to: W, by: 46).enumerated() {
            let top = 0.35 + r.next() * 0.35, sway = (r.next() - 0.5) * 10
            ctx.beginPath()
            ctx.move(to: pt(x, 1.0))
            ctx.addQuadCurve(to: pt(x + sway, top), control: pt(x - sway, (1 + top) / 2))
            ctx.setStrokeColor(color("2f6b4f", 0.6)); ctx.setLineWidth(1.2 * S); ctx.strokePath()
            let c = petals[i % petals.count]
            glow(ctx, x: x + sway, y: top, radius: 22, c, 0.55)
            dot(ctx, x: x + sway, y: top, r: 2.6, c, 0.9)
        }
    },
    // Fuji in spring: pale sky into the mountain's teal, the snowcapped peak,
    // blossom drifting across
    "sakura": { ctx in
        vertical(ctx, [(0, "eaf3f4"), (0.55, "bcd9dc"), (1, "8fbfc4")])
        horizontal(ctx, [(0, "f7c3d6"), (0.25, "f7c3d6"), (0.5, "bcd9dc")], alpha: 0.35)
        let peak = W * 0.72, half = min(W * 0.16, 120.0)
        triangle(ctx, x: peak, base: 1.05, top: 0.06, half: half, "6fa9ae", 0.6)
        // the snowcap follows the slope: same peak, a third of the way down
        triangle(ctx, x: peak, base: 0.39, top: 0.06, half: half * 0.33 / 0.99, "fbfaf6", 0.92)
        var r = Seeded(state: 5)
        for _ in 0..<Int(W / 14) {
            dot(ctx, x: r.next() * W * 0.6, y: r.next(), r: 1.4 + r.next() * 1.4, "f28cb1", 0.5 + r.next() * 0.3)
        }
    },
    // Northern lights: navy night, stars, curtains of green, teal and violet
    "aurora": { ctx in
        vertical(ctx, [(0, "070b1c"), (0.6, "0b1630"), (1, "0a1a26")])
        var r = Seeded(state: 9)
        for _ in 0..<Int(W / 9) { dot(ctx, x: r.next() * W, y: r.next() * 0.9, r: 0.4 + r.next() * 0.6, "ffffff", 0.3 + r.next() * 0.5) }
        let bands: [(String, Double, Double, Double)] = [("3dffa8", 0.42, 70, 0.0), ("2fd6d0", 0.52, 110, 1.7), ("9a7bff", 0.36, 160, 3.1)]
        for (hex, base, wave, phase) in bands {
            for k in 0..<5 {   // thin bands stacked with a little offset make a soft curtain
                let off = Double(k) * 0.03
                let y: (Double) -> Double = { x in base + off + 0.12 * sin(x / wave + phase) }
                ctx.beginPath()
                ctx.move(to: pt(0, y(0)))
                for x in stride(from: 2.0, through: W, by: 2) { ctx.addLine(to: pt(x, y(x))) }
                for x in stride(from: W, through: 0, by: -2) { ctx.addLine(to: pt(x, y(x) + 0.16)) }
                ctx.closePath()
                ctx.setFillColor(color(hex, 0.07)); ctx.fillPath()
            }
        }
        fillBelow(ctx, "06101a", 0.85) { x in 0.9 - 0.06 * abs(sin(x / 120)) }   // dark hills
    },
    // Desert dusk: layered dunes from pale sand to deep rust under a pale sun
    "dune": { ctx in
        vertical(ctx, [(0, "f6d9b8"), (0.6, "f0c49a"), (1, "e8b083")])
        glow(ctx, x: W * 0.25, y: 0.3, radius: 60, "fff4e0", 0.9)
        fillBelow(ctx, "e3a46f", 0.9) { x in 0.48 + 0.10 * sin(x / 140 + 0.5) }
        fillBelow(ctx, "cf7f4f", 0.9) { x in 0.64 + 0.09 * sin(x / 100 + 2.0) }
        fillBelow(ctx, "a9583a", 0.95) { x in 0.80 + 0.07 * sin(x / 75 + 4.0) }
    },
    // The sea: deep teal below, shallow aqua above, white foam lines
    "tide": { ctx in
        vertical(ctx, [(0, "9fe3e0"), (0.45, "3fb2b8"), (1, "0f5a6b")])
        for (k, base) in [0.32, 0.55, 0.78].enumerated() {
            let amp = 0.05 + Double(k) * 0.015
            fillBelow(ctx, "0f5a6b", 0.18) { x in base + amp * sin(x / 48 + Double(k) * 1.4) }
            strokeLine(ctx, "ffffff", 0.55, width: 1.1) { x in base + amp * sin(x / 48 + Double(k) * 1.4) }
        }
    },
    // Art deco: deep burgundy velvet with fine gold fans
    "velvet": { ctx in
        vertical(ctx, [(0, "4a0f1f"), (1, "2a0812")])
        let step = 46.0
        for (i, x) in stride(from: 0.0, through: W + step, by: step).enumerated() {
            let cy = i % 2 == 0 ? 1.0 : 0.0
            for k in 1...4 {
                let rr = Double(k) * 8.5
                ctx.beginPath()
                ctx.addArc(center: pt(x, cy), radius: rr * S, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.setStrokeColor(color("d4af6a", 0.32)); ctx.setLineWidth(0.8 * S); ctx.strokePath()
            }
        }
        strokeLine(ctx, "d4af6a", 0.6, width: 1) { _ in 0.06 }
        strokeLine(ctx, "d4af6a", 0.6, width: 1) { _ in 0.94 }
    },
    // A tea house: soft matcha paper with bamboo stalks and their nodes
    "matcha": { ctx in
        vertical(ctx, [(0, "e3ebd2"), (1, "cfdcb7")])
        var r = Seeded(state: 13)
        for x in stride(from: 10.0, to: W, by: 26) {
            let w = 4.0 + r.next() * 3
            ctx.setFillColor(color("9fb67a", 0.35))
            ctx.fill(CGRect(x: x * S, y: 0, width: w * S, height: H * S))
            for _ in 0..<2 {
                let ny = 0.15 + r.next() * 0.7
                ctx.setFillColor(color("7f9a5c", 0.55))
                ctx.fill(CGRect(x: (x - 1) * S, y: (1 - ny) * H * S, width: (w + 2) * S, height: 1.4 * S))
            }
        }
    },
]

guard let draw = scenes[args[1]] else { exit(1) }
let ctx = CGContext(data: nil, width: Int(W * S), height: Int(H * S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
draw(ctx)
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
