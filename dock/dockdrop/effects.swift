// The effect themes' animations, drawn on the stage (stage.swift) behind the dock's
// tiles. Each one is its own medium with its own way of moving, and each one makes a
// fuss of the app you're on. Sizes are in u, one point at the dock's own scale, so the
// gallery's small cards draw the same scene smaller.
import AppKit

func makeEffect(_ name: String) -> StageEffect? {
    switch name {
    case "current": return CurrentEffect()
    case "claymation": return ClayEffect()
    case "ferrofluid": return FerroEffect()
    case "popup": return PopUpEffect()
    case "livewire": return LiveWireEffect()
    case "hourglass": return HourglassEffect()
    case "overgrowth": return OvergrowthEffect()
    case "lava": return LavaEffect()
    case "campfire": return CampfireEffect()
    case "jelly": return JellyEffect()
    default: return nil
    }
}

// MARK: - Helpers

func cg(_ hex: String, _ alpha: Double = 1) -> CGColor {
    let v = UInt32(hex, radix: 16) ?? 0
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: CGFloat(alpha))
}
/// The same color, darker (f < 1) or lighter (f > 1)
func shade(_ hex: String, _ f: Double, _ alpha: Double = 1) -> CGColor {
    let v = UInt32(hex, radix: 16) ?? 0
    func ch(_ x: UInt32) -> CGFloat { CGFloat(min(255, Double(x & 0xff) * f)) / 255 }
    return CGColor(srgbRed: ch(v >> 16), green: ch(v >> 8), blue: ch(v), alpha: CGFloat(alpha))
}
func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
func smooth(_ t: Double) -> Double { let x = clamp01(t); return x * x * (3 - 2 * x) }
func outBack(_ t: Double) -> Double { let x = clamp01(t) - 1, k = 1.70158; return 1 + x * x * ((k + 1) * x + k) }
func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

struct RNG {
    var s: UInt64
    init(_ seed: Int) { s = UInt64(bitPattern: Int64(seed)) &* 2654435761 &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double(s >> 33) / Double(UInt64(1) << 31)
    }
}
func hash01(_ i: Int, _ seed: Int = 0) -> Double { var r = RNG(i &* 73856093 ^ seed &* 19349663); _ = r.next(); return r.next() }
/// Smooth noise, -1…1
func vnoise(_ x: Double, _ seed: Int = 0) -> Double {
    let i = Int(floor(x)), f = x - floor(x), e = f * f * (3 - 2 * f)
    return (hash01(i, seed) * (1 - e) + hash01(i + 1, seed) * e) * 2 - 1
}

/// A damped spring
/// A background that never moves, drawn once at screen resolution and reused every frame
final class Backdrop {
    private var key = "", image: CGImage?
    func draw(_ ctx: CGContext, _ rect: CGRect, _ paint: (CGContext) -> Void) {
        let scale = max(1, ctx.userSpaceToDeviceSpaceTransform.a.magnitude)
        let k = "\(rect) \(scale)"
        if k != key || image == nil {
            key = k; image = nil
            let w = Int((rect.width * scale).rounded(.up)), h = Int((rect.height * scale).rounded(.up))
            guard w > 0, h > 0, let off = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            off.scaleBy(x: scale, y: scale); off.translateBy(x: -rect.minX, y: -rect.minY)
            paint(off); image = off.makeImage()
        }
        if let image { ctx.draw(image, in: CGRect(origin: rect.origin, size: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))) }
    }
}

struct Spring {
    var x: Double, v = 0.0
    mutating func step(to target: Double, k: Double, d: Double, dt: Double) {
        let steps = max(1, Int(ceil(dt / (1.0 / 240))))
        let h = dt / Double(steps)
        for _ in 0..<steps { v += ((target - x) * k - v * d) * h; x += v * h }
    }
    func resting(at target: Double) -> Bool { abs(v) < 0.004 && abs(x - target) < 0.002 }
}

extension CGContext {
    func paint(_ p: CGPath, _ c: CGColor) { addPath(p); setFillColor(c); fillPath() }
    func trace(_ p: CGPath, _ c: CGColor, _ w: CGFloat) {
        addPath(p); setStrokeColor(c); setLineWidth(w); setLineCap(.round); setLineJoin(.round); strokePath()
    }
    func gradient(in p: CGPath, from a: CGPoint, to b: CGPoint, _ stops: [(CGFloat, CGColor)]) {
        saveGState(); addPath(p); clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray,
                           locations: stops.map(\.0))!
        drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }
    func glow(at c: CGPoint, radius: CGFloat, _ hex: String, _ alpha: Double) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [cg(hex, alpha), cg(hex, 0)] as CFArray,
                           locations: [0, 1])!
        drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: max(radius, 0.1), options: [])
    }
    func disc(_ c: CGPoint, _ r: CGFloat, _ color: CGColor) {
        setFillColor(color); fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    let rad = min(radius, r.width / 2, r.height / 2)
    return CGPath(roundedRect: r, cornerWidth: max(rad, 0), cornerHeight: max(rad, 0), transform: nil)
}
func polyline(_ pts: [CGPoint]) -> CGPath { let p = CGMutablePath(); if !pts.isEmpty { p.addLines(between: pts) }; return p }

/// Points around a rounded rectangle (counter-clockwise), with their outward normals
func roundRectRim(_ r: CGRect, _ radius: CGFloat, step: CGFloat) -> [(CGPoint, CGVector)] {
    let rad = min(radius, r.width / 2, r.height / 2)
    var out: [(CGPoint, CGVector)] = []
    func edge(_ a: CGPoint, _ b: CGPoint, _ n: CGVector) {
        let len = hypot(b.x - a.x, b.y - a.y), k = max(1, Int(len / step))
        for i in 0..<k { let t = CGFloat(i) / CGFloat(k); out.append((CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), n)) }
    }
    func corner(_ c: CGPoint, _ a0: CGFloat) {
        let k = max(2, Int(rad * .pi / 2 / step))
        for i in 0..<k {
            let a = a0 + CGFloat(i) / CGFloat(k) * .pi / 2
            out.append((CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad), CGVector(dx: cos(a), dy: sin(a))))
        }
    }
    edge(CGPoint(x: r.minX + rad, y: r.minY), CGPoint(x: r.maxX - rad, y: r.minY), CGVector(dx: 0, dy: -1))
    corner(CGPoint(x: r.maxX - rad, y: r.minY + rad), -.pi / 2)
    edge(CGPoint(x: r.maxX, y: r.minY + rad), CGPoint(x: r.maxX, y: r.maxY - rad), CGVector(dx: 1, dy: 0))
    corner(CGPoint(x: r.maxX - rad, y: r.maxY - rad), 0)
    edge(CGPoint(x: r.maxX - rad, y: r.maxY), CGPoint(x: r.minX + rad, y: r.maxY), CGVector(dx: 0, dy: 1))
    corner(CGPoint(x: r.minX + rad, y: r.maxY - rad), .pi / 2)
    edge(CGPoint(x: r.minX, y: r.maxY - rad), CGPoint(x: r.minX, y: r.minY + rad), CGVector(dx: -1, dy: 0))
    corner(CGPoint(x: r.minX + rad, y: r.minY + rad), .pi)
    return out
}

/// A shape traced partway: the first `fraction` of a polyline
func partial(_ pts: [CGPoint], _ fraction: Double) -> [CGPoint] {
    guard pts.count > 1, fraction > 0 else { return [] }
    var lengths: [CGFloat] = [0]
    for i in 1..<pts.count { lengths.append(lengths[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
    let want = lengths.last! * CGFloat(clamp01(fraction))
    var out = [pts[0]]
    for i in 1..<pts.count {
        if lengths[i] <= want { out.append(pts[i]); continue }
        let seg = lengths[i] - lengths[i - 1], t = seg > 0 ? (want - lengths[i - 1]) / seg : 0
        out.append(CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t, y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t))
        break
    }
    return out
}
func bezier(_ a: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ b: CGPoint, steps: Int = 24) -> [CGPoint] {
    (0...steps).map { i in
        let t = CGFloat(i) / CGFloat(steps), m = 1 - t
        let x = m * m * m * a.x + 3 * m * m * t * c1.x + 3 * m * t * t * c2.x + t * t * t * b.x
        let y = m * m * m * a.y + 3 * m * m * t * c1.y + 3 * m * t * t * c2.y + t * t * t * b.y
        return CGPoint(x: x, y: y)
    }
}

// MARK: - 1. Current: water flows to the app you're on

final class CurrentEffect: StageEffect {
    private var h: [Double] = [], v: [Double] = []
    private var fromX = Double.nan, toX = Double.nan, moveStart = 0.0
    private var lastFront: Int?? = .none, lastHover: Int?? = .none
    private var drops: [(x: Double, y: Double, vx: Double, vy: Double)] = []
    private var energy = 1.0
    private var amp = 0.0

    func fps(_ s: StageScene) -> Double {
        if !drops.isEmpty || energy > 0.015 || s.sinceSwitch < 1.2 { return 60 }
        return s.lowPower ? 0 : 20
    }

    func draw(_ ctx: CGContext, _ s: StageScene) {
        let u = Double(s.u), tray = s.tray
        let spacing = 3 * u
        let n = Int(Double(tray.width) / spacing) + 2
        let rest = Double(tray.minY) + 7 * u
        if h.count != n { h = Array(repeating: rest, count: n); v = Array(repeating: 0, count: n) }
        func xAt(_ i: Int) -> Double { Double(tray.minX) + Double(i) * spacing }
        originX = Double(tray.minX)

        // The water gathers under the app you're on, and flows over when you switch
        if lastFront == .none || lastFront! != s.front {
            let target = s.center(s.front).map(Double.init) ?? Double(tray.midX)
            if fromX.isNaN { fromX = target; toX = target }
            else { fromX += (toX - fromX) * smooth((s.time - moveStart) / 0.9); toX = target; moveStart = s.time }
            if lastFront != .none, let fx = s.center(s.front) { splash(Double(fx), s); kick(Double(fx), 55 * u, spacing) }
            lastFront = .some(s.front)
        }
        if lastHover == .none || lastHover! != s.hover {
            if lastHover != .none, let hx = s.center(s.hover) { kick(Double(hx), 16 * u, spacing) }
            lastHover = .some(s.hover)
        }
        let travel = smooth((s.time - moveStart) / 0.9)
        let cx = fromX + (toX - fromX) * travel
        let wantAmp = s.front == nil ? 0.0 : 1.0
        amp += (wantAmp - amp) * min(1, s.dt * 3)
        let crest = Double(s.tile(s.front)?.maxY ?? tray.maxY) + 16 * u   // the swell stands up past the trough
        let peak = (crest - rest) * amp * (0.5 + 0.5 * abs(2 * travel - 1))
        let sigma = Double(s.tiles.first?.width ?? 52) * 0.5

        // Columns on springs, coupled to their neighbours so waves travel
        let steps = max(1, Int(ceil(s.dt / (1.0 / 180)))), dt = s.dt / Double(steps)
        for _ in 0..<steps {
            for i in 0..<n {
                let d = xAt(i) - cx
                let target = rest + peak * exp(-d * d / (2 * sigma * sigma))
                let left = h[max(i - 1, 0)], right = h[min(i + 1, n - 1)]
                v[i] += ((target - h[i]) * 40 - v[i] * 5 + (left + right - 2 * h[i]) * 260) * dt
            }
            for i in 0..<n { h[i] += v[i] * dt }
        }
        energy = v.reduce(0) { $0 + abs($1) } / Double(n) / u
        func surface(_ x: Double) -> Double {
            let f = (x - Double(tray.minX)) / spacing, i = max(0, min(n - 2, Int(f))), t = f - Double(i)
            return h[i] * (1 - t) + h[i + 1] * t
        }

        // The glass trough (drawn first, so the swell rises up in front of its rim)
        let glass = rounded(tray, 22 * s.u)
        ctx.paint(glass, cg("ffffff", 0.16))
        ctx.trace(glass, cg("ffffff", 0.6), 1.4 * s.u)
        ctx.trace(rounded(tray.insetBy(dx: 2 * s.u, dy: 2 * s.u), 20 * s.u), cg("ffffff", 0.18), 0.8 * s.u)
        // the water: kept inside the trough, except where it swells up past the rim
        let room = CGMutablePath()
        room.addPath(glass)
        room.addRect(CGRect(x: tray.minX + 22 * s.u, y: tray.midY, width: tray.width - 44 * s.u, height: s.size.height))
        ctx.saveGState(); ctx.addPath(room); ctx.clip()
        let water = CGMutablePath()
        water.move(to: CGPoint(x: tray.minX, y: tray.minY))
        for i in 0..<n { water.addLine(to: CGPoint(x: xAt(i), y: h[i])) }
        water.addLine(to: CGPoint(x: tray.maxX, y: tray.minY)); water.closeSubpath()
        ctx.gradient(in: water, from: CGPoint(x: 0, y: crest), to: CGPoint(x: 0, y: tray.minY),
                     [(0, cg("7ae8ec")), (0.35, cg("23aec4")), (1, cg("06506a"))])
        // light rippling up through the swell
        ctx.saveGState(); ctx.addPath(water); ctx.clip()
        for k in 0..<4 {
            let base = rest + (6 + Double(k) * 11) * u
            let line = (0...Int(Double(tray.width) / (4 * u))).map { j -> CGPoint in
                let x = Double(tray.minX) + Double(j) * 4 * u
                return CGPoint(x: x, y: base + 2 * u * sin(x / (14 * u) + s.time * (1.6 + Double(k) * 0.4) + Double(k)))
            }
            ctx.trace(polyline(line), cg("ffffff", 0.16), s.u)
        }
        ctx.restoreGState()
        // the surface, and streaks flowing along it toward your app
        ctx.trace(polyline((0..<n).map { CGPoint(x: xAt($0), y: h[$0]) }), cg("e8fdff", 0.9), 1.4 * s.u)
        if s.front != nil {
            for side in [-1.0, 1.0] {
                let edge = side < 0 ? Double(tray.minX) + 12 * u : Double(tray.maxX) - 12 * u
                let span = cx - edge
                for k in 0..<7 {
                    let f = (Double(k) / 7 + s.time * 0.3).truncatingRemainder(dividingBy: 1)
                    let x = edge + span * f, len = 11 * u * side * -1
                    let a = sin(.pi * f) * 0.85
                    let pts = [CGPoint(x: x, y: surface(x) - 2.6 * u), CGPoint(x: x - len, y: surface(x - len) - 2.6 * u)]
                    ctx.trace(polyline(pts), cg("ffffff", a), 1.3 * s.u)
                }
            }
        }
        ctx.restoreGState()

        // the splash
        var kept: [(x: Double, y: Double, vx: Double, vy: Double)] = []
        for var d in drops {
            d.vy -= 720 * u * s.dt; d.x += d.vx * s.dt; d.y += d.vy * s.dt
            if d.vy < 0, d.y <= surface(d.x) { kick(d.x, 6 * u, spacing); continue }
            kept.append(d)
            let stretch = CGFloat(min(3.0, abs(d.vy) / (140 * u)))
            ctx.saveGState()
            ctx.translateBy(x: d.x, y: d.y); ctx.rotate(by: atan2(d.vy, d.vx) - .pi / 2)
            ctx.setFillColor(cg("c8f6fa", 0.95))
            ctx.fillEllipse(in: CGRect(x: -2.3 * s.u, y: -2.3 * s.u * (1 + stretch * 0.5), width: 4.6 * s.u, height: 4.6 * s.u * (1 + stretch * 0.5)))
            ctx.restoreGState()
        }
        drops = kept
    }

    private func splash(_ x: Double, _ s: StageScene) {
        var r = RNG(Int(s.time * 1000))
        let u = Double(s.u), top = Double(s.tile(s.front)?.maxY ?? s.tray.maxY) + 8 * u
        for _ in 0..<24 {
            drops.append((x + (r.next() - 0.5) * 34 * u, top, (r.next() - 0.5) * 170 * u, (150 + r.next() * 210) * u))
        }
    }
    /// Push the surface up around x, so a wave runs out from there
    private func kick(_ x: Double, _ strength: Double, _ spacing: Double) {
        guard !v.isEmpty else { return }
        let column = (x - originX) / spacing
        for i in v.indices {
            let d = Double(i) - column
            v[i] += strength * 3 * exp(-d * d / 18)
        }
    }
    private var originX = 0.0
}

// MARK: - 2. Claymation: clay builds up around the app you're on, in stop motion

final class ClayEffect: StageEffect {
    private let colors = ["f2c14e", "3a9e9a", "f28482", "f6e7c1", "5b8bd0", "e07a5f", "9fd3c7", "c9b6e4", "f2c14e", "f28482"]
    // where each lump lands around a tile: across (tile widths from the middle), up (tile heights from the bottom), size
    private let lumps: [(CGFloat, CGFloat, CGFloat)] = [(-0.62, 0.08, 0.26), (0.62, 0.08, 0.26), (-0.6, 0.55, 0.25), (0.6, 0.55, 0.25),
                                                        (-0.4, 0.98, 0.27), (0.4, 0.98, 0.27), (0, 1.16, 0.31),
                                                        (-0.2, 1.42, 0.2), (0.22, 1.40, 0.19), (0.02, 1.62, 0.17)]

    func fps(_ s: StageScene) -> Double {
        if s.sinceSwitch < 1.6 || s.sinceHover < 0.6 { return 12 }
        return s.lowPower ? 0 : 4
    }

    func draw(_ ctx: CGContext, _ s: StageScene) {
        let moving = s.sinceSwitch < 1.6 || s.sinceHover < 0.6
        let t = floor(s.time * 12) / 12                       // stop motion: 12 frames a second
        let boil = Int(floor(s.time * (moving ? 12 : 4))) % 3 // and the clay never sits quite still
        let u = s.u, since = t - s.switched

        // The slab
        let slab = wobbly(s.tray, 22 * u, amp: 1.2 * u, seed: boil * 31)
        ctx.paint(slab, cg("e07a5f"))
        ctx.saveGState(); ctx.addPath(slab); ctx.clip()
        ctx.paint(wobbly(s.tray.offsetBy(dx: 0, dy: -s.tray.height * 0.72), 22 * u, amp: 2 * u, seed: boil * 7 + 3), cg("b85a44", 0.55))
        ctx.paint(wobbly(CGRect(x: s.tray.minX + 10 * u, y: s.tray.maxY - 6 * u, width: s.tray.width * 0.35, height: 3 * u), 2 * u,
                         amp: 0.6 * u, seed: boil), cg("ffffff", 0.18))
        // thumbprints, pressed in the bands
        for k in 0..<max(2, Int(s.tray.width / (150 * u))) {
            let x = s.tray.minX + (CGFloat(k) + 0.5) * s.tray.width / CGFloat(max(2, Int(s.tray.width / (150 * u))))
            let y = k % 2 == 0 ? s.tray.maxY - 4 * u : s.tray.minY + 4 * u
            for ring in 1...3 {
                let p = CGMutablePath()
                p.addArc(center: CGPoint(x: x, y: y), radius: CGFloat(ring) * 2.2 * u, startAngle: 0.3, endAngle: 2.6, clockwise: false)
                ctx.trace(p, cg("7a3626", 0.18), 0.6 * u)
            }
        }
        ctx.restoreGState()

        // A little clay pancake squashing under the tile you point at
        if let tile = s.tile(s.hover), s.hover != s.front {
            let k = clamp01((t - s.hovered) / 0.35)
            let squash = 1 + 0.35 * sin(k * .pi * 2) * (1 - k)
            let w = tile.width * 0.75 * CGFloat(squash), hgt = 7 * u / CGFloat(squash)
            ctx.paint(wobbly(CGRect(x: tile.midX - w / 2, y: tile.minY - hgt * 0.6, width: w, height: hgt), hgt / 2, amp: 0.5 * u, seed: boil + 9),
                      cg("f6e7c1"))
        }

        // The old crown melts back into the slab; the new one is built lump by lump
        if let old = s.tile(s.previous), s.previous != s.front, since < 0.9 {
            for (k, lump) in lumps.enumerated() {
                let tau = clamp01((since - 0.03 * Double(k)) / 0.6)
                guard tau < 1 else { continue }
                let c = landing(old, lump), r = old.width * lump.2
                let sunk = CGPoint(x: c.x, y: c.y - (c.y - s.tray.minY) * CGFloat(tau))
                drawLump(ctx, at: sunk, r: r * CGFloat(1 - tau * 0.8), sx: 1 + CGFloat(tau) * 0.5, sy: 1 - CGFloat(tau) * 0.6,
                         color: colors[k % colors.count], seed: boil * 11 + k, u: u)
            }
        }
        if let tile = s.tile(s.front) {
            for (k, lump) in lumps.enumerated() {
                let lands = 0.18 + 0.09 * Double(k)
                let c = landing(tile, lump), r = tile.width * lump.2
                if since < lands {
                    // still flying in from the slab beside the tile
                    let p = clamp01((since - (lands - 0.25)) / 0.25)
                    guard p > 0 else { continue }
                    let from = CGPoint(x: tile.midX + (k % 2 == 0 ? -1 : 1) * tile.width * 1.4, y: s.tray.minY + 6 * u)
                    let x = mix(from.x, c.x, p), y = mix(from.y, c.y, p) + CGFloat(sin(p * .pi)) * 26 * u
                    drawLump(ctx, at: CGPoint(x: x, y: y), r: r * 0.8, sx: 0.9, sy: 1.15, color: colors[k % colors.count], seed: boil * 5 + k, u: u)
                } else {
                    // landed: squash, then spring back round
                    let tau = since - lands
                    let wob = exp(-7 * tau) * cos(17 * tau)
                    drawLump(ctx, at: c, r: r, sx: 1 + 0.28 * CGFloat(wob), sy: 1 - 0.36 * CGFloat(wob),
                             color: colors[k % colors.count], seed: boil * 13 + k, u: u)
                }
            }
        }
    }

    private func landing(_ tile: CGRect, _ lump: (CGFloat, CGFloat, CGFloat)) -> CGPoint {
        CGPoint(x: tile.midX + lump.0 * tile.width, y: tile.minY + lump.1 * tile.height)
    }

    private func drawLump(_ ctx: CGContext, at c: CGPoint, r: CGFloat, sx: CGFloat, sy: CGFloat, color: String, seed: Int, u: CGFloat) {
        guard r > 0.5 else { return }
        func blob(_ rad: CGFloat, _ off: CGPoint) -> CGPath {
            let p = CGMutablePath()
            for i in 0..<16 {
                let a = CGFloat(i) / 16 * 2 * .pi
                let wob = 1 + 0.07 * CGFloat(vnoise(Double(i) * 0.9, seed))
                let pt = CGPoint(x: c.x + off.x + cos(a) * rad * sx * wob, y: c.y + off.y + sin(a) * rad * sy * wob)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath(); return p
        }
        ctx.paint(blob(r * 1.03, CGPoint(x: 0.6 * u, y: -1.4 * u)), cg("3b2a20", 0.22))     // its shadow
        ctx.paint(blob(r, .zero), shade(color, 0.78))
        ctx.paint(blob(r * 0.84, CGPoint(x: -r * 0.08, y: r * 0.1)), cg(color))
        ctx.paint(blob(r * 0.26, CGPoint(x: -r * 0.38, y: r * 0.4)), cg("ffffff", 0.32))
        let print = CGMutablePath()
        print.addArc(center: CGPoint(x: c.x + r * 0.2, y: c.y - r * 0.1), radius: r * 0.42, startAngle: 3.6, endAngle: 5.4, clockwise: false)
        ctx.trace(print, shade(color, 0.6, 0.35), 0.6 * u)
    }

    private func wobbly(_ r: CGRect, _ radius: CGFloat, amp: CGFloat, seed: Int) -> CGPath {
        let rim = roundRectRim(r, radius, step: 4 * max(amp, 0.3))
        let p = CGMutablePath()
        for (i, (pt, n)) in rim.enumerated() {
            let k = CGFloat(vnoise(Double(i) * 0.31, seed)) * amp
            let q = CGPoint(x: pt.x + n.dx * k, y: pt.y + n.dy * k)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath(); return p
    }
}

// MARK: - 3. Ferrofluid: black magnetic fluid spikes up around the app you're on

final class FerroEffect: StageEffect {
    private var amp: [Spring] = []
    private let backdrop = Backdrop()

    func fps(_ s: StageScene) -> Double {
        let moving = amp.indices.contains { !amp[$0].resting(at: target($0, s)) }
        if moving { return 60 }
        return s.lowPower ? 0 : 15
    }
    private func target(_ i: Int, _ s: StageScene) -> Double { i == s.front ? 1 : (i == s.hover ? 0.32 : 0) }

    func draw(_ ctx: CGContext, _ s: StageScene) {
        let u = s.u, tray = s.tray
        if amp.count != s.tiles.count { amp = s.tiles.indices.map { Spring(x: $0 == s.front ? 1 : 0) } }
        for i in amp.indices { amp[i].step(to: target(i, s), k: i == s.front ? 70 : 120, d: i == s.front ? 7 : 14, dt: s.dt) }

        // Brushed steel
        let plate = rounded(tray, 20 * u)
        backdrop.draw(ctx, tray) { ctx in
            ctx.gradient(in: plate, from: CGPoint(x: 0, y: tray.maxY), to: CGPoint(x: 0, y: tray.minY),
                         [(0, cg("3b3d43")), (0.5, cg("26272c")), (1, cg("141518"))])
            ctx.saveGState(); ctx.addPath(plate); ctx.clip()
            var r = RNG(4)
            for _ in 0..<Int(tray.height / (1.2 * u)) {
                let y = tray.minY + CGFloat(r.next()) * tray.height
                ctx.trace(polyline([CGPoint(x: tray.minX, y: y), CGPoint(x: tray.maxX, y: y)]), cg("ffffff", 0.035), 0.5 * u)
            }
            ctx.restoreGState()
        }
        ctx.saveGState(); ctx.addPath(plate); ctx.clip()
        // the pool along the bottom, heaped behind the tiles it's drawn to
        let base = tray.minY + 9 * u
        let pool = CGMutablePath()
        pool.move(to: CGPoint(x: tray.minX, y: tray.minY))
        var x = tray.minX
        while x <= tray.maxX {
            var y = base + 1.2 * u * CGFloat(sin(Double(x / (17 * u)) + s.time * 0.8))
            for (i, t) in s.tiles.enumerated() where amp[i].x > 0.01 {
                let d = Double((x - t.midX) / (t.width * 0.62))
                y += (t.maxY - 6 * u - base) * CGFloat(max(0, amp[i].x)) * CGFloat(exp(-d * d * 2))
            }
            pool.addLine(to: CGPoint(x: x, y: y)); x += 2 * u
        }
        pool.addLine(to: CGPoint(x: tray.maxX, y: tray.minY)); pool.closeSubpath()
        ctx.paint(pool, cg("060607"))
        ctx.gradient(in: pool, from: CGPoint(x: 0, y: tray.maxY), to: CGPoint(x: 0, y: base - 4 * u),
                     [(0, cg("9aa0aa", 0.28)), (0.4, cg("9aa0aa", 0.06)), (1, cg("000000", 0))])
        ctx.restoreGState()
        ctx.trace(plate, cg("a7adb6", 0.45), 1.1 * u)

        // The spikes, out of the fluid hugging the tile
        for (i, t) in s.tiles.enumerated() where amp[i].x > 0.02 {
            let a = CGFloat(max(0, amp[i].x))
            ctx.paint(rounded(t.insetBy(dx: -5 * u * a, dy: -5 * u * a), 14 * u), cg("060607"))
            let center = CGPoint(x: t.midX, y: t.midY), radius = t.width * 0.56 + 4 * u * a
            let count = 13
            for k in 0..<count {
                let theta = 0.12 * .pi + Double(k) / Double(count - 1) * 0.76 * .pi
                let bell = pow(sin(theta), 3)
                let breath = 1 + 0.07 * sin(s.time * 2.4 + Double(k) * 1.7)
                let len = (8 + 30 * bell) * Double(u) * Double(a) * breath
                let dir = CGVector(dx: cos(theta), dy: sin(theta))
                let foot = CGPoint(x: center.x + dir.dx * radius * 1.0, y: center.y + dir.dy * radius * 0.95)
                spike(ctx, foot: foot, dir: dir, len: CGFloat(len), half: (2.4 + 1.6 * CGFloat(bell)) * u * sqrt(a), u: u)
            }
            // and a few low ones along the pool on either side
            for side in [-1.0, 1.0] {
                for k in 0..<3 {
                    let fx = t.midX + CGFloat(side) * (t.width * (0.62 + 0.18 * CGFloat(k)))
                    let len = (9 - 2.5 * CGFloat(k)) * u * a * CGFloat(1 + 0.08 * sin(s.time * 3 + Double(k)))
                    spike(ctx, foot: CGPoint(x: fx, y: t.minY + 2 * u), dir: CGVector(dx: CGFloat(side) * 0.25, dy: 0.97), len: len,
                          half: 2.2 * u * sqrt(a), u: u)
                }
            }
        }
    }

    private func spike(_ ctx: CGContext, foot: CGPoint, dir: CGVector, len: CGFloat, half: CGFloat, u: CGFloat) {
        guard len > 0.5 else { return }
        let n = CGVector(dx: -dir.dy, dy: dir.dx)
        let tip = CGPoint(x: foot.x + dir.dx * len, y: foot.y + dir.dy * len)
        let l = CGPoint(x: foot.x + n.dx * half, y: foot.y + n.dy * half), r = CGPoint(x: foot.x - n.dx * half, y: foot.y - n.dy * half)
        let mid = CGPoint(x: foot.x + dir.dx * len * 0.45, y: foot.y + dir.dy * len * 0.45)
        let p = CGMutablePath()
        p.move(to: l)
        p.addQuadCurve(to: tip, control: CGPoint(x: mid.x + n.dx * half * 0.35, y: mid.y + n.dy * half * 0.35))
        p.addQuadCurve(to: r, control: CGPoint(x: mid.x - n.dx * half * 0.35, y: mid.y - n.dy * half * 0.35))
        p.closeSubpath()
        ctx.paint(p, cg("060607"))
        ctx.trace(polyline([CGPoint(x: l.x + dir.dx * len * 0.15, y: l.y + dir.dy * len * 0.15),
                            CGPoint(x: mid.x + n.dx * half * 0.3, y: mid.y + n.dy * half * 0.3), tip]), cg("b9c0cc", 0.55), 0.6 * u)
        ctx.disc(CGPoint(x: tip.x - dir.dx * 1.2 * u, y: tip.y - dir.dy * 1.2 * u), 0.5 * u, cg("ffffff", 0.7))
    }
}

// MARK: - 4. Pop-Up: a paper scene folds up out of the book behind the app you're on

final class PopUpEffect: StageEffect {
    private var lift: [Spring] = []

    func fps(_ s: StageScene) -> Double {
        lift.indices.contains { !lift[$0].resting(at: target($0, s)) } ? 60 : 0
    }
    private func target(_ i: Int, _ s: StageScene) -> Double { i == s.front ? 1 : (i == s.hover ? 0.22 : 0) }

    func draw(_ ctx: CGContext, _ s: StageScene) {
        let u = s.u, tray = s.tray
        if lift.count != s.tiles.count { lift = s.tiles.indices.map { Spring(x: $0 == s.front ? 1 : 0) } }
        for i in lift.indices { lift[i].step(to: target(i, s), k: 110, d: i == s.front ? 9 : 16, dt: s.dt) }

        // The open book: its cloth cover, the pages, the shadow in the gutter
        ctx.paint(rounded(tray, 12 * u), cg("1f5c63"))
        let pages = tray.insetBy(dx: 4 * u, dy: 4 * u)
        let paper = rounded(pages, 8 * u)
        ctx.paint(paper, cg("f6eedc"))
        ctx.gradient(in: paper, from: CGPoint(x: pages.midX - 22 * u, y: 0), to: CGPoint(x: pages.midX + 22 * u, y: 0),
                     [(0, cg("000000", 0)), (0.5, cg("5a4a2a", 0.22)), (1, cg("000000", 0))])
        for k in 0..<3 {
            let y = pages.minY + (1.4 + CGFloat(k) * 1.5) * u
            ctx.trace(polyline([CGPoint(x: pages.minX + 6 * u, y: y), CGPoint(x: pages.maxX - 6 * u, y: y)]), cg("cbbb98", 0.8), 0.5 * u)
        }

        // Back to front, so a tall scene stands behind its neighbours' small tabs
        let order = s.tiles.indices.sorted { lift[$0].x < lift[$1].x }
        let base = pages.minY + 8 * u
        ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: base, width: s.size.width, height: s.size.height))   // stands on the page
        for i in order where lift[i].x > 0.01 { scene(ctx, s.tiles[i], CGFloat(lift[i].x), base: base, u: u) }
        ctx.restoreGState()
    }

    /// Three paper layers, each folding up a beat after the one behind it
    private func scene(_ ctx: CGContext, _ t: CGRect, _ p: CGFloat, base: CGFloat, u: CGFloat) {
        func layer(_ delay: CGFloat, _ build: (CGMutablePath) -> Void, fill: String, edge: String? = nil) {
            let q = min(1.15, max(0, (p - delay) / (1 - delay)))
            guard q > 0.01 else { return }
            let path = CGMutablePath(); build(path)
            let shear = 0.3 * (1 - min(q, 1))
            let m = CGAffineTransform(translationX: t.midX, y: base).scaledBy(x: 1, y: q).concatenating(.identity)
            var tr = CGAffineTransform(a: 1, b: 0, c: shear, d: 1, tx: 0, ty: 0).concatenating(m)
            guard let placed = path.copy(using: &tr) else { return }
            var drop = CGAffineTransform(translationX: 2 * u, y: -2 * u)
            if let shadow = placed.copy(using: &drop) { ctx.paint(shadow, cg("2b1f10", 0.22 * Double(min(q, 1)))) }
            ctx.paint(placed, cg(fill))
            if let edge { ctx.trace(placed, cg(edge, 0.55), 0.7 * u) }
        }
        let w = t.width, top = t.maxY - base
        func dome(_ p: CGMutablePath, _ cx: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
            p.move(to: CGPoint(x: cx - rx, y: 0))
            p.addCurve(to: CGPoint(x: cx, y: ry), control1: CGPoint(x: cx - rx, y: ry * 0.56), control2: CGPoint(x: cx - rx * 0.56, y: ry))
            p.addCurve(to: CGPoint(x: cx + rx, y: 0), control1: CGPoint(x: cx + rx * 0.56, y: ry), control2: CGPoint(x: cx + rx, y: ry * 0.56))
            p.closeSubpath()
        }
        // a sunburst behind everything, with its sun
        layer(0, { p in
            let rx = w * 1.3, ry = top + 46 * u
            for k in stride(from: 0, to: 16, by: 2) {
                let a0 = CGFloat(k) / 16 * .pi, a1 = CGFloat(k + 1) / 16 * .pi
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: cos(a0) * rx, y: sin(a0) * ry)); p.addLine(to: CGPoint(x: cos(a1) * rx, y: sin(a1) * ry))
                p.closeSubpath()
            }
        }, fill: "e8b13a")
        layer(0.04, { p in
            p.addEllipse(in: CGRect(x: -w * 0.36, y: top + 6 * u, width: w * 0.72, height: w * 0.72))
        }, fill: "fbf3dc", edge: "c9a13a")
        // rolling hills
        layer(0.14, { p in dome(p, -w * 0.62, w * 0.78, top + 14 * u); dome(p, w * 0.66, w * 0.74, top + 20 * u) }, fill: "2a8c82", edge: "1d6159")
        layer(0.24, { p in dome(p, -w * 0.15, w * 1.05, top + 4 * u) }, fill: "e86a50", edge: "b04a35")
        // a pennant on a stick, last
        layer(0.36, { p in
            let x = w * 0.34, y0 = top, y1 = top + 30 * u
            p.addRect(CGRect(x: x - 0.9 * u, y: y0, width: 1.8 * u, height: y1 - y0))
            p.move(to: CGPoint(x: x + 0.9 * u, y: y1)); p.addLine(to: CGPoint(x: x + 17 * u, y: y1 - 5.5 * u))
            p.addLine(to: CGPoint(x: x + 0.9 * u, y: y1 - 11 * u)); p.closeSubpath()
        }, fill: "c9413a")
    }
}

// MARK: - 5. Live Wire: a neon tube that sparks over to the app you're on and lights up around it

final class LiveWireEffect: StageEffect {
    private let pink = "ff2e88", core = "ffd6e8", cyan = "00e5ff"

    private func nextFlicker(after t: Double) -> Double {
        var k = Int(t / 7)
        while true {
            let at = Double(k) * 7 + 2 + hash01(k, 5) * 4
            if at + 0.2 > t { return at }
            k += 1
        }
    }

    func fps(_ s: StageScene) -> Double {
        if s.sinceSwitch < 1.3 || s.sinceHover < 0.25 { return 60 }
        if s.lowPower || s.front == nil { return 0 }
        let next = nextFlicker(after: s.time)
        if s.time >= next { return 30 }
        return max(0.3, 1 / max(next - s.time, 0.05))
    }

    func draw(_ ctx: CGContext, _ s: StageScene) {
        let u = s.u, tray = s.tray, since = s.sinceSwitch
        // A dark wall, bricked along the top
        let wall = rounded(tray, 16 * u)
        ctx.paint(wall, cg("17151a"))
        ctx.saveGState(); ctx.addPath(wall); ctx.clip()
        var r = RNG(3)
        for _ in 0..<Int(tray.width * 0.8 / u) { ctx.disc(CGPoint(x: tray.minX + CGFloat(r.next()) * tray.width, y: tray.minY + CGFloat(r.next()) * tray.height), 0.35 * u, cg("ffffff", 0.04)) }
        let course = tray.maxY - (tray.height - (s.tiles.first?.height ?? 52)) / 2
        ctx.trace(polyline([CGPoint(x: tray.minX, y: course), CGPoint(x: tray.maxX, y: course)]), cg("2c2832"), 0.8 * u)
        var bx = tray.minX + 6 * u, row = 0
        while bx < tray.maxX {
            ctx.trace(polyline([CGPoint(x: bx, y: course), CGPoint(x: bx, y: tray.maxY)]), cg("2c2832"), 0.8 * u)
            bx += 24 * u; row += 1
        }
        if let t = s.tile(s.front) { ctx.glow(at: CGPoint(x: t.midX, y: t.midY), radius: 70 * u, pink, 0.16 * smooth((since - 0.7) / 0.4)) }
        ctx.restoreGState()

        // The tube along the bottom
        let ty = tray.minY + 4.2 * u
        let tube = polyline([CGPoint(x: tray.minX + 14 * u, y: ty), CGPoint(x: tray.maxX - 14 * u, y: ty)])
        ctx.trace(tube, cg("4a2038"), 2.4 * u)
        let lit = s.front != nil && since > 0.75
        if lit { neon(ctx, tube, u, strength: 0.45) }
        ctx.trace(polyline([CGPoint(x: tray.minX + 14 * u, y: ty + 0.6 * u), CGPoint(x: tray.maxX - 14 * u, y: ty + 0.6 * u)]), cg("ffffff", 0.12), 0.5 * u)

        // under the tile you point at, the tube runs cyan
        if let t = s.tile(s.hover), s.hover != s.front {
            let a = smooth(s.sinceHover / 0.15)
            let seg = polyline([CGPoint(x: t.minX + 4 * u, y: ty), CGPoint(x: t.maxX - 4 * u, y: ty)])
            for (w, al) in [(9.0, 0.12), (5.0, 0.25), (2.4, 0.9)] { ctx.trace(seg, cg(cyan, al * a), CGFloat(w) * u) }
        }

        // The old sign switches off with a stutter
        if let old = s.tile(s.previous), s.previous != s.front, since < 0.14, Int(since * 60) % 2 == 0 {
            neon(ctx, sign(old, ty, u), u, strength: 0.5)
            neon(ctx, polyline(arrow(old, u)), u, strength: 0.5)
        }
        guard let t = s.tile(s.front) else { return }
        // a spark runs along the tube, the outline traces itself, then it catches
        let from = s.center(s.previous) ?? tray.minX + 14 * u
        if since < 0.4 {
            let x = mix(from, t.midX, smooth(since / 0.35))
            let trail = polyline([CGPoint(x: from, y: ty), CGPoint(x: x, y: ty)])
            ctx.trace(trail, cg(pink, 0.35), 2.4 * u)
            ctx.glow(at: CGPoint(x: x, y: ty), radius: 16 * u, pink, 0.9)
            ctx.disc(CGPoint(x: x, y: ty), 2.2 * u, cg("ffffff"))
        }
        let outline = sign(t, ty, u)
        if since >= 0.35 && since < 0.8 {
            let q = smooth((since - 0.35) / 0.4)
            let pts = signPoints(t, ty, u)
            neon(ctx, polyline(partial(pts, q)), u, strength: 0.8)
        } else if since >= 0.8 {
            // ignition stutter, then steady, with the odd buzz later on
            let pattern: [Double] = [1, 0, 1, 1, 0.3, 1]
            var level = since < 1.1 ? pattern[min(pattern.count - 1, Int((since - 0.8) / 0.05))] : 1
            let next = nextFlicker(after: s.time)
            if s.time >= next && s.time < next + 0.2 { level = 0.35 + 0.65 * (vnoise(s.time * 60, 9) > 0 ? 1 : 0) }
            if level > 0 {
                neon(ctx, outline, u, strength: level)
                neon(ctx, polyline(partial(arrow(t, u), smooth((since - 0.8) / 0.3))), u, strength: level)
            }
        }
    }

    private func signPoints(_ t: CGRect, _ ty: CGFloat, _ u: CGFloat) -> [CGPoint] {
        let r = t.insetBy(dx: -5 * u, dy: -5 * u)
        var pts = [CGPoint(x: r.minX + 9 * u, y: ty)]
        let rim = roundRectRim(r, 14 * u, step: 2 * u)
        // start at the bottom-left of the frame and go all the way round
        if let start = rim.indices.min(by: { hypot(rim[$0].0.x - (r.minX + 9 * u), rim[$0].0.y - r.minY) <
                                             hypot(rim[$1].0.x - (r.minX + 9 * u), rim[$1].0.y - r.minY) }) {
            let ordered = Array(rim[start...] + rim[..<start]).map(\.0).reversed()
            pts += ordered
            pts.append(ordered.first!)
        }
        pts.append(CGPoint(x: r.maxX - 9 * u, y: r.minY)); pts.append(CGPoint(x: r.maxX - 9 * u, y: ty))
        return pts
    }
    private func sign(_ t: CGRect, _ ty: CGFloat, _ u: CGFloat) -> CGPath { polyline(signPoints(t, ty, u)) }

    private func neon(_ ctx: CGContext, _ path: CGPath, _ u: CGFloat, strength: Double) {
        for (w, a) in [(20.0, 0.07), (12.0, 0.14), (6.0, 0.32), (3.2, 0.6)] { ctx.trace(path, cg(pink, a * strength), CGFloat(w) * u) }
        ctx.trace(path, cg(core, strength), 1.6 * u)
    }
    /// A neon arrow above the tile, pointing down at it
    private func arrow(_ t: CGRect, _ u: CGFloat) -> [CGPoint] {
        let x = t.midX, y = t.maxY + 14 * u
        return [CGPoint(x: x, y: y + 24 * u), CGPoint(x: x, y: y), CGPoint(x: x - 8 * u, y: y + 9 * u),
                CGPoint(x: x, y: y), CGPoint(x: x + 8 * u, y: y + 9 * u)]
    }
}

// MARK: - 6. Hourglass: sand pours onto the app you're on, and piles higher the longer you stay

final class HourglassEffect: StageEffect {
    private let backdrop = Backdrop()
    private var piles: [Double] = []      // 0…1 of a full dune
    private var spread: [Double] = []     // how far a pile has slumped
    private var streamX = Double.nan, streamFrom = 0.0, streamMove = -10.0
    private var lastFront: Int?? = .none

    func fps(_ s: StageScene) -> Double {
        if s.sinceSwitch < 1.6 { return 60 }
        return s.lowPower ? 0 : 15
    }

    func draw(_ ctx: CGContext, _ s: StageScene) {
        let u = s.u, tray = s.tray
        if piles.count != s.tiles.count { piles = Array(repeating: 0, count: s.tiles.count); spread = piles }
        if lastFront == .none || lastFront! != s.front {
            if let x = s.center(s.front) {
                streamFrom = streamX.isNaN ? Double(x) : streamX; streamMove = s.time
                if streamX.isNaN { streamX = Double(x) }
            }
            lastFront = .some(s.front)
        }
        if let x = s.center(s.front) { streamX = streamFrom + (Double(x) - streamFrom) * smooth((s.time - streamMove) / 0.5) }

        // Dunes: yours grows (a full dune after ten minutes there), the others slump away
        for i in piles.indices {
            if i == s.front {
                let want = min(1, 0.42 + max(0, s.sinceSwitch - 0.5) / 600 * 0.58)
                piles[i] = min(want, piles[i] + s.dt * 0.5); spread[i] = max(0, spread[i] - s.dt)
            } else if piles[i] > 0 {
                piles[i] = max(0, piles[i] - s.dt * 0.55); spread[i] = min(1, spread[i] + s.dt * 0.9)
            }
        }

        // Sandstone
        let stone = rounded(tray, 18 * u)
        backdrop.draw(ctx, tray.insetBy(dx: -u, dy: -u)) { ctx in
            ctx.paint(stone, cg("f3e6c9"))
            ctx.saveGState(); ctx.addPath(stone); ctx.clip()
            ctx.gradient(in: stone, from: CGPoint(x: 0, y: tray.maxY), to: CGPoint(x: 0, y: tray.minY), [(0, cg("ffffff", 0.18)), (1, cg("8a6234", 0.22))])
            for k in 0..<4 {
                let base = tray.minY + tray.height * (0.18 + 0.2 * CGFloat(k))
                let line = stride(from: tray.minX, through: tray.maxX, by: 4 * u).map { x in
                    CGPoint(x: x, y: base + 1.5 * u * CGFloat(sin(Double(x / (40 * u)) + Double(k))))
                }
                ctx.trace(polyline(line), cg("c9a46b", 0.35), 0.8 * u)
            }
            ctx.restoreGState()
            ctx.trace(stone, cg("b08850", 0.7), 1 * u)
        }
        ctx.saveGState(); ctx.clip(to: CGRect(x: tray.minX + 6 * u, y: tray.minY + 1 * u, width: tray.width - 12 * u, height: s.size.height))
        for (i, t) in s.tiles.enumerated() where piles[i] > 0.005 { dune(ctx, t, piles[i], spread[i], tray, u) }
        ctx.restoreGState()

        // The stream, falling from a little hourglass above
        guard let t = s.tile(s.front), !s.lowPower || s.sinceSwitch < 1.6 else { return }
        let x = CGFloat(streamX)
        let topY = s.size.height - 4 * u
        let glassH = 20 * u, glassW = 17 * u
        let neckY = topY - glassH
        let pileTop = tray.minY + (t.maxY + 12 * u - tray.minY) * CGFloat(piles[s.front!])
        let fallTop = neckY
        ctx.trace(polyline([CGPoint(x: x, y: fallTop), CGPoint(x: x, y: pileTop)]), cg("c79a55", 0.7), 1.6 * u)
        let len = Double(fallTop - pileTop)
        if len > 0 {
            for k in 0..<22 {
                let y = Double(fallTop) - (s.time * 150 * Double(u) + Double(k) * len / 22).truncatingRemainder(dividingBy: len)
                ctx.disc(CGPoint(x: x + CGFloat(vnoise(Double(k) + s.time * 3, 2)) * 1.1 * u, y: CGFloat(y)), 1.0 * u, cg("a87a3e"))
            }
        }
        for k in 0..<3 {   // grains bouncing off the top of the dune
            let ph = (s.time * 2.2 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let dx = CGFloat(ph) * CGFloat(k % 2 == 0 ? 1 : -1) * 7 * u
            ctx.disc(CGPoint(x: x + dx, y: pileTop + CGFloat(sin(ph * .pi)) * 4 * u), 0.7 * u, cg("b8894a"))
        }
        let bulb = CGMutablePath()
        bulb.move(to: CGPoint(x: x - glassW / 2, y: topY)); bulb.addLine(to: CGPoint(x: x + glassW / 2, y: topY))
        bulb.addQuadCurve(to: CGPoint(x: x + 0.8 * u, y: neckY), control: CGPoint(x: x + glassW / 2, y: neckY + 2 * u))
        bulb.addLine(to: CGPoint(x: x - 0.8 * u, y: neckY))
        bulb.addQuadCurve(to: CGPoint(x: x - glassW / 2, y: topY), control: CGPoint(x: x - glassW / 2, y: neckY + 2 * u))
        ctx.paint(bulb, cg("ffffff", 0.45))
        let sand = CGMutablePath()
        sand.move(to: CGPoint(x: x - glassW * 0.3, y: neckY + glassH * 0.5)); sand.addLine(to: CGPoint(x: x + glassW * 0.3, y: neckY + glassH * 0.5))
        sand.addLine(to: CGPoint(x: x, y: neckY + 1 * u)); sand.closeSubpath()
        ctx.paint(sand, cg("d9b26f"))
        ctx.trace(bulb, cg("6b4a2a", 0.7), 0.8 * u)
        ctx.trace(polyline([CGPoint(x: x - glassW / 2 - 1.5 * u, y: topY), CGPoint(x: x + glassW / 2 + 1.5 * u, y: topY)]), cg("6b4a2a"), 1.6 * u)
    }

    private func dune(_ ctx: CGContext, _ t: CGRect, _ height: Double, _ spread: Double, _ tray: CGRect, _ u: CGFloat) {
        let peak = (t.maxY + 12 * u - tray.minY) * CGFloat(height)   // a full dune heaps up past the tile
        let half = t.width * CGFloat(1.15 + 0.7 * spread)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: t.midX - half, y: tray.minY))
        for k in 0...40 {
            let z = CGFloat(k) / 20 - 1
            let y = tray.minY + peak * pow(cos(z * .pi / 2), 2)
            p.addLine(to: CGPoint(x: t.midX + z * half, y: y))
        }
        p.closeSubpath()
        ctx.gradient(in: p, from: CGPoint(x: t.midX - half, y: 0), to: CGPoint(x: t.midX + half, y: 0),
                     [(0, cg("e2b064")), (0.5, cg("c98f3e")), (1, cg("9c6a2c"))])
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        var r = RNG(Int(t.midX))
        for _ in 0..<Int(half * peak / (10 * u * u) + 4) {
            ctx.disc(CGPoint(x: t.midX + CGFloat(r.next() * 2 - 1) * half, y: tray.minY + CGFloat(r.next()) * peak), 0.4 * u, cg("7a5428", 0.3))
        }
        ctx.restoreGState()
    }
}

// MARK: - 7. Overgrowth: vines grow along the dock, climb the app you're on and flower

final class OvergrowthEffect: StageEffect {
    private let backdrop = Backdrop()
    private let speed: CGFloat = 520

    func fps(_ s: StageScene) -> Double {
        if s.sinceSwitch < 2.6 || s.sinceHover < 0.4 { return 60 }
        return s.lowPower ? 0 : 10
    }

    func draw(_ ctx: CGContext, _ s: StageScene) {
        let u = s.u, tray = s.tray
        let moss = rounded(tray, 18 * u)
        backdrop.draw(ctx, tray.insetBy(dx: -u, dy: -u)) { ctx in
            ctx.gradient(in: moss, from: CGPoint(x: 0, y: tray.maxY), to: CGPoint(x: 0, y: tray.minY), [(0, cg("2e4d37")), (1, cg("172a1e"))])
            ctx.saveGState(); ctx.addPath(moss); ctx.clip()
            var r = RNG(12)
            for _ in 0..<Int(tray.width / (14 * u)) {   // leaf shadows along the bottom
                let x = tray.minX + CGFloat(r.next()) * tray.width
                self.leaf(ctx, at: CGPoint(x: x, y: tray.minY + 3 * u), angle: CGFloat(r.next() - 0.5) * 1.6, size: (5 + CGFloat(r.next()) * 4) * u, color: cg("0f1f14", 0.55))
            }
            ctx.restoreGState()
            ctx.trace(moss, cg("5e8a66", 0.55), 1 * u)
        }

        let band = tray.maxY - max(3 * u, (tray.height - (s.tiles.first?.height ?? 52)) / 4)
        // The last flower drops its petals and its vines fade
        if let old = s.tile(s.previous), s.previous != s.front, s.sinceSwitch < 1.3 {
            let fade = 1 - clamp01(s.sinceSwitch / 0.8)
            if fade > 0 { vines(ctx, s, old, band, grown: 10, alpha: fade, u: u) }
            fallingPetals(ctx, old, s.sinceSwitch, u)
        }
        // A bud on the tile you point at
        if let t = s.tile(s.hover), s.hover != s.front {
            let k = outBack(s.sinceHover / 0.3)
            let c = CGPoint(x: t.midX, y: t.maxY + 5 * u)
            ctx.trace(polyline([CGPoint(x: t.midX, y: t.maxY - 2 * u), c]), cg("8fb98a"), 1.4 * u)
            ctx.saveGState(); ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: CGFloat(k), y: CGFloat(k))
            ctx.setFillColor(cg("a7d49b")); ctx.fillEllipse(in: CGRect(x: -2.4 * u, y: -1 * u, width: 4.8 * u, height: 7 * u))
            ctx.restoreGState()
        }
        guard let t = s.tile(s.front) else { return }
        vines(ctx, s, t, band, grown: s.sinceSwitch, alpha: 1, u: u)
    }

    /// Two vines from the ends of the dock to the tile, up its sides, and the flower on top
    private func vines(_ ctx: CGContext, _ s: StageScene, _ t: CGRect, _ band: CGFloat, grown: Double, alpha: Double, u: CGFloat) {
        let tray = s.tray
        let sway = s.lowPower ? 0 : CGFloat(sin(s.time * 1.3)) * 2 * u
        let bloomAt = CGPoint(x: t.midX + sway, y: t.maxY + 30 * u)
        var reach = 0.0
        for side in [-1.0, 1.0] {
            let startX = side < 0 ? tray.minX + 10 * u : tray.maxX - 10 * u
            let endX = side < 0 ? t.minX - 5 * u : t.maxX + 5 * u
            let run = stride(from: startX, through: endX, by: side < 0 ? 3 * u : -3 * u).map { x in
                CGPoint(x: x, y: band + 1.6 * u * CGFloat(sin(Double(x / (13 * u)))))
            }
            let along = Double(abs(endX - startX) / (speed * u))
            reach = max(reach, along)
            let g = clamp01(grown / max(along, 0.01))
            let shown = partial(run, g)
            ctx.trace(polyline(shown), cg("8fb98a", alpha), 1.5 * u)
            // leaves come out as the stem passes
            for (k, p) in shown.enumerated() where k % 7 == 3 {
                let age = grown - Double(k) / Double(run.count) * along
                let sz = 4.5 * u * CGFloat(outBack(age / 0.2))
                leaf(ctx, at: p, angle: (k % 14 == 3 ? 0.9 : -0.9) + (side < 0 ? 0 : .pi), size: sz, color: cg("6fa86a", alpha))
            }
            // then up the side of the tile, curling in over the top
            let climb = bezier(run.last ?? CGPoint(x: endX, y: band), CGPoint(x: endX + CGFloat(side) * 6 * u, y: t.maxY + 6 * u),
                               CGPoint(x: t.midX + CGFloat(side) * 12 * u, y: t.maxY + 26 * u),
                               CGPoint(x: bloomAt.x + CGFloat(side) * 2 * u, y: bloomAt.y - 3 * u))
            let c = clamp01((grown - along) / 0.35)
            if c > 0 {
                let up = partial(climb, c)
                ctx.trace(polyline(up), cg("8fb98a", alpha), 1.5 * u)
                if c > 0.5, let mid = up.dropLast(up.count / 3).last {
                    leaf(ctx, at: mid, angle: side < 0 ? 2.4 : 0.7, size: 5 * u * CGFloat(outBack((c - 0.5) * 3)), color: cg("6fa86a", alpha))
                }
            }
        }
        let open = outBack((grown - reach - 0.3) / 0.5)
        if open > 0.01 { flower(ctx, at: bloomAt, open: CGFloat(open), spin: CGFloat(sin(s.time * 0.9)) * 0.06, alpha: alpha, u: u) }
    }

    private func flower(_ ctx: CGContext, at c: CGPoint, open: CGFloat, spin: CGFloat, alpha: Double, u: CGFloat) {
        ctx.saveGState(); ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: spin); ctx.scaleBy(x: open, y: open)
        ctx.glow(at: .zero, radius: 32 * u, "f2836b", 0.25 * alpha)
        for k in 0..<6 {
            ctx.saveGState(); ctx.rotate(by: CGFloat(k) / 6 * 2 * .pi)
            ctx.setFillColor(cg(k % 2 == 0 ? "f2836b" : "f7b2bd", alpha))
            ctx.fillEllipse(in: CGRect(x: -5 * u, y: 2 * u, width: 10 * u, height: 16 * u))
            ctx.restoreGState()
        }
        ctx.disc(.zero, 5 * u, cg("f2c14e", alpha))
        ctx.disc(CGPoint(x: -1.4 * u, y: 1.4 * u), 1.6 * u, cg("fff4c8", alpha))
        ctx.restoreGState()
    }

    private func fallingPetals(_ ctx: CGContext, _ t: CGRect, _ tau: Double, _ u: CGFloat) {
        for k in 0..<6 {
            let a = CGFloat(k) / 6 * 2 * .pi
            let x = t.midX + cos(a) * 8 * u + CGFloat(sin(tau * 4 + Double(k))) * 6 * u * CGFloat(tau)
            let y = t.maxY + 30 * u + sin(a) * 10 * u - CGFloat(tau) * 22 * u - CGFloat(tau * tau) * 40 * u
            ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: a + CGFloat(tau) * 3)
            ctx.setFillColor(cg(k % 2 == 0 ? "f2836b" : "f7b2bd", 1 - clamp01(tau / 1.2)))
            ctx.fillEllipse(in: CGRect(x: -3 * u, y: -5 * u, width: 6 * u, height: 10 * u))
            ctx.restoreGState()
        }
    }

    private func leaf(_ ctx: CGContext, at p: CGPoint, angle: CGFloat, size: CGFloat, color: CGColor) {
        guard size > 0.3 else { return }
        ctx.saveGState(); ctx.translateBy(x: p.x, y: p.y); ctx.rotate(by: angle)
        let l = CGMutablePath()
        l.move(to: .zero)
        l.addQuadCurve(to: CGPoint(x: size * 1.6, y: 0), control: CGPoint(x: size * 0.8, y: size * 0.7))
        l.addQuadCurve(to: .zero, control: CGPoint(x: size * 0.8, y: -size * 0.7))
        ctx.paint(l, color)
        ctx.restoreGState()
    }
}

// MARK: - 8. Lava: wax drifts toward the app you're on, and a little lamp bubbles on top of it

final class LavaEffect: StageEffect {
    private struct Blob { var x: Double; var home: Double; var phase: Double; var period: Double; var r: Double; var drawn: Bool }
    private var blobs: [Blob] = []
    private var lamps: [Spring] = []

    func fps(_ s: StageScene) -> Double {
        if lamps.indices.contains(where: { !lamps[$0].resting(at: $0 == s.front ? 1 : 0) }) { return 60 }
        return s.lowPower ? 0 : 24
    }

    func draw(_ ctx: CGContext, _ s: StageScene) {
        let u = Double(s.u), tray = s.tray
        if blobs.isEmpty || blobs.count != max(6, Int(Double(tray.width) / (60 * u))) {
            var r = RNG(8)
            blobs = (0..<max(6, Int(Double(tray.width) / (60 * u)))).map { k in
                let home = Double(tray.minX) + (Double(k) + r.next()) / Double(max(6, Int(Double(tray.width) / (60 * u)))) * Double(tray.width)
                return Blob(x: home, home: home, phase: r.next() * 6.3, period: 7 + r.next() * 6, r: (6 + r.next() * 5) * u, drawn: k % 3 != 2)
            }
        }
        if lamps.count != s.tiles.count { lamps = s.tiles.indices.map { Spring(x: $0 == s.front ? 1 : 0) } }
        for i in lamps.indices { lamps[i].step(to: i == s.front ? 1 : 0, k: 60, d: 11, dt: s.dt) }

        // The lamp's liquid
        let glass = rounded(tray, 24 * s.u)
        ctx.gradient(in: glass, from: CGPoint(x: 0, y: tray.maxY), to: CGPoint(x: 0, y: tray.minY), [(0, cg("12463d")), (1, cg("061b18"))])
        ctx.saveGState(); ctx.addPath(glass); ctx.clip()
        let fx = s.center(s.front).map(Double.init)
        var centers: [(CGPoint, CGFloat)] = []
        for k in blobs.indices {
            // most of the wax drifts over to your app; some stays put
            let want = (blobs[k].drawn ? fx : nil).map { $0 + (blobs[k].home - Double(tray.midX)) * 0.12 } ?? blobs[k].home
            blobs[k].x += (want - blobs[k].x) * (1 - exp(-s.dt * 0.9))
            let lo = Double(tray.minY) + blobs[k].r + 3 * u, hi = Double(tray.maxY) - blobs[k].r - 3 * u
            let y = lo + (hi - lo) * (0.5 + 0.5 * sin(s.time * 2 * .pi / blobs[k].period + blobs[k].phase))
            centers.append((CGPoint(x: blobs[k].x, y: y), CGFloat(blobs[k].r)))
        }
        wax(ctx, centers, s.u)
        ctx.restoreGState()
        ctx.gradient(in: rounded(CGRect(x: tray.minX + 14 * s.u, y: tray.maxY - 7 * s.u, width: tray.width - 28 * s.u, height: 3 * s.u), 1.5 * s.u),
                     from: CGPoint(x: tray.minX, y: 0), to: CGPoint(x: tray.maxX, y: 0),
                     [(0, cg("ffffff", 0)), (0.5, cg("ffffff", 0.16)), (1, cg("ffffff", 0))])
        ctx.trace(glass, cg("7fd3c2", 0.35), 1.2 * s.u)

        // A glass lamp standing up out of your app, its wax rising and falling
        for (i, t) in s.tiles.enumerated() where lamps[i].x > 0.02 {
            let a = CGFloat(lamps[i].x)
            let w = t.width * 0.95, top = t.maxY + 58 * s.u * a
            let body = CGRect(x: t.midX - w / 2, y: t.maxY - 10 * s.u, width: w, height: top - (t.maxY - 10 * s.u))
            guard body.height > 2 else { continue }
            let lamp = rounded(body, w / 2)
            ctx.paint(lamp, cg("0a2d28", 0.92))
            ctx.saveGState(); ctx.addPath(lamp); ctx.clip()
            let rise = 0.5 + 0.5 * sin(s.time * 1.1)
            let r1 = w * 0.28, r2 = w * 0.2
            let c1 = CGPoint(x: t.midX, y: body.minY + r1 + (body.height - 2 * r1) * CGFloat(rise))
            let c2 = CGPoint(x: t.midX + 2 * s.u, y: body.minY + r2 + (body.height - 2 * r2) * CGFloat(1 - rise))
            wax(ctx, [(c1, r1), (c2, r2), (CGPoint(x: t.midX, y: body.minY), w * 0.42)], s.u)
            ctx.restoreGState()
            ctx.trace(lamp, cg("bff3e6", 0.6), 1.2 * s.u)
            ctx.trace(polyline([CGPoint(x: body.minX + w * 0.22, y: body.minY + 8 * s.u), CGPoint(x: body.minX + w * 0.22, y: body.maxY - w * 0.35)]),
                      cg("ffffff", 0.35), 1.2 * s.u)
            let cap = CGRect(x: t.midX - w * 0.32, y: body.maxY - 1 * s.u, width: w * 0.64, height: 5 * s.u * a)
            ctx.paint(rounded(cap, 2 * s.u), cg("c9cdd2"))
        }
    }

    /// Blobs of wax, joined by necks where they come close, with a hot glow
    private func wax(_ ctx: CGContext, _ blobs: [(CGPoint, CGFloat)], _ u: CGFloat) {
        for (c, r) in blobs { ctx.glow(at: c, radius: r * 2.2, "ff4f8b", 0.18) }
        ctx.setFillColor(cg("f0457a"))
        for i in blobs.indices {
            for j in blobs.indices where j > i {
                let (a, ra) = blobs[i], (b, rb) = blobs[j]
                let d = hypot(a.x - b.x, a.y - b.y)
                guard d < (ra + rb) * 1.35 else { continue }
                let w = min(ra, rb) * (1.6 - d / (ra + rb)) * 1.1
                guard w > 0.5 else { continue }
                ctx.trace(polyline([a, b]), cg("f0457a"), w)
            }
        }
        for (c, r) in blobs {
            let p = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
            ctx.gradient(in: p, from: CGPoint(x: c.x - r * 0.4, y: c.y + r * 0.5), to: CGPoint(x: c.x + r * 0.5, y: c.y - r),
                         [(0, cg("ff9ab8")), (0.5, cg("f0457a")), (1, cg("c22a5c"))])
        }
    }
}

// MARK: - 9. Campfire: 8-bit fire roars behind the app you're on; open apps keep a pilot flame

final class CampfireEffect: StageEffect {
    private let backdrop = Backdrop()
    private var heat: [UInt8] = []
    private var cols = 0, rows = 0
    private var acc = 0.0
    private var rng = RNG(77)
    private var embers: [(x: Double, y: Double, born: Double)] = []
    private var packed: [UInt32] = []     // the fire's colors as premultiplied RGBA pixels
    private var pixels: [UInt32] = []

    init() {
        let keys: [(Int, String)] = [(0, "1a0606"), (4, "5a1607"), (9, "8f2707"), (14, "b74707"), (19, "d9670f"),
                                     (24, "ef8f17"), (28, "f7b733"), (32, "fbd96b"), (36, "fff8e0")]
        for v in 0...36 {
            let hi = keys.firstIndex { $0.0 >= v } ?? keys.count - 1, lo = max(0, hi - 1)
            let (a, ca) = keys[lo], (b, cb) = keys[hi]
            let t = b == a ? 0 : Double(v - a) / Double(b - a)
            let x = UInt32(ca, radix: 16)!, y = UInt32(cb, radix: 16)!
            func ch(_ s: UInt32) -> CGFloat { CGFloat(Double((x >> s) & 0xff) * (1 - t) + Double((y >> s) & 0xff) * t) / 255 }
            let alpha: CGFloat = v == 0 ? 0 : (v < 4 ? CGFloat(v) / 4 * 0.8 : 1)
            func byte(_ x: CGFloat) -> UInt32 { UInt32(max(0, min(255, (x * alpha * 255).rounded()))) }
            packed.append((byte(ch(16)) << 24) | (byte(ch(8)) << 16) | (byte(ch(0)) << 8) | UInt32((alpha * 255).rounded()))
        }
    }

    func fps(_ s: StageScene) -> Double { s.lowPower ? 6 : 15 }

    func draw(_ ctx: CGContext, _ s: StageScene) {
        let u = s.u, tray = s.tray, px = 3 * u
        let c = Int(tray.width / px), r = Int((s.size.height - tray.minY) / px)
        if c != cols || r != rows { cols = c; rows = r; heat = Array(repeating: 0, count: c * r) }

        // The night: pixel sky, pixel grass, stepped corners
        let ground = steppedRect(tray, px)
        backdrop.draw(ctx, tray) { ctx in
            ctx.paint(ground, cg("1d1a33"))
            ctx.saveGState(); ctx.addPath(ground); ctx.clip()
            for col in 0..<c {
                let hgt = 2 + Int(hash01(col, 4) * 2.5)
                for k in 0..<hgt {
                    ctx.setFillColor(cg(k == hgt - 1 ? "4f9a45" : (k == 0 ? "254a25" : "35702f")))
                    ctx.fill(CGRect(x: tray.minX + CGFloat(col) * px, y: tray.minY + CGFloat(k) * px, width: px, height: px))
                }
            }
            ctx.restoreGState()
        }
        ctx.saveGState(); ctx.addPath(ground); ctx.clip()
        var sr = RNG(31)
        for _ in 0..<Int(tray.width / (24 * u)) {
            let x = tray.minX + (CGFloat(Int(sr.next() * Double(c)))) * px
            let y = tray.maxY - px * CGFloat(1 + Int(sr.next() * 2))
            let twinkle = s.lowPower ? 1 : (Int(s.time * 2 + sr.next() * 10) % 5 == 0 ? 0.35 : 1)
            ctx.setFillColor(cg("fff3c4", twinkle)); ctx.fill(CGRect(x: x, y: y, width: px, height: px))
        }
        ctx.restoreGState()

        // Feed the bottom row: big under your app, small under open ones
        var source = [UInt8](repeating: 0, count: c)
        for (i, t) in s.tiles.enumerated() {
            let level: UInt8 = i == s.front ? 36 : (i == s.hover ? 16 : (s.running.contains(i) ? 10 : 0))
            guard level > 0 else { continue }
            let a = max(0, Int((t.minX - 5 * u - tray.minX) / px)), b = min(c - 1, Int((t.maxX + 5 * u - tray.minX) / px))
            if a <= b { for x in a...b { source[x] = max(source[x], level) } }
        }
        acc += s.dt
        let steps = min(4, Int(acc * 15)); acc -= Double(steps) / 15
        for _ in 0..<steps { spread(source) }

        // Draw the fire: one pixel per cell into a small bitmap, scaled up crisp in one go
        if pixels.count != c * r { pixels = Array(repeating: 0, count: c * r) }
        for y in 0..<r {
            let row = (r - 1 - y) * c   // bitmaps run top-down
            for x in 0..<c { pixels[row + x] = packed[Int(heat[y * c + x])] }
        }
        let image: CGImage? = pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: c, height: r, bitsPerComponent: 8, bytesPerRow: c * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage()
        }
        if let image {
            ctx.saveGState(); ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: tray.minX, y: tray.minY + px, width: CGFloat(c) * px, height: CGFloat(r) * px))
            ctx.restoreGState()
        }

        // Embers off the big fire
        if let t = s.tile(s.front), !s.lowPower, rng.next() < s.dt * 6 {
            embers.append((Double(t.midX) + (rng.next() - 0.5) * Double(t.width), Double(t.maxY + 20 * u), s.time))
        }
        embers = embers.filter { s.time - $0.born < 1.4 }
        for e in embers {
            let age = s.time - e.born
            let x = e.x + sin(age * 5 + e.x) * Double(4 * u), y = e.y + age * Double(30 * u)
            let snapX = (CGFloat(x) / px).rounded() * px, snapY = (CGFloat(y) / px).rounded() * px
            ctx.setFillColor(cg(age < 0.7 ? "ffb347" : "d94f1e", 1 - age / 1.4))
            ctx.fill(CGRect(x: snapX, y: snapY, width: px, height: px))
        }
    }

    /// The classic fire spread: each cell takes the one below it, cooled a little and blown sideways
    private func spread(_ source: [UInt8]) {
        for x in 0..<cols { heat[x] = source[x] }
        for y in 1..<rows {
            for x in 0..<cols {
                let below = heat[(y - 1) * cols + x]
                let roll = rng.next()
                let cool = UInt8(roll < 0.22 ? 0 : (roll < 0.55 ? 1 : 2))
                let dx = Int(rng.next() * 3) - 1
                let to = min(cols - 1, max(0, x + dx))
                heat[y * cols + to] = below > cool ? below - cool : 0
            }
        }
    }

    private func steppedRect(_ r: CGRect, _ px: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let pts: [CGPoint] = [
            CGPoint(x: r.minX + 2 * px, y: r.minY), CGPoint(x: r.maxX - 2 * px, y: r.minY), CGPoint(x: r.maxX - 2 * px, y: r.minY + px),
            CGPoint(x: r.maxX - px, y: r.minY + px), CGPoint(x: r.maxX - px, y: r.minY + 2 * px), CGPoint(x: r.maxX, y: r.minY + 2 * px),
            CGPoint(x: r.maxX, y: r.maxY - 2 * px), CGPoint(x: r.maxX - px, y: r.maxY - 2 * px), CGPoint(x: r.maxX - px, y: r.maxY - px),
            CGPoint(x: r.maxX - 2 * px, y: r.maxY - px), CGPoint(x: r.maxX - 2 * px, y: r.maxY), CGPoint(x: r.minX + 2 * px, y: r.maxY),
            CGPoint(x: r.minX + 2 * px, y: r.maxY - px), CGPoint(x: r.minX + px, y: r.maxY - px), CGPoint(x: r.minX + px, y: r.maxY - 2 * px),
            CGPoint(x: r.minX, y: r.maxY - 2 * px), CGPoint(x: r.minX, y: r.minY + 2 * px), CGPoint(x: r.minX + px, y: r.minY + 2 * px),
            CGPoint(x: r.minX + px, y: r.minY + px), CGPoint(x: r.minX + 2 * px, y: r.minY + px)]
        p.addLines(between: pts); p.closeSubpath()
        return p
    }
}

// MARK: - 10. Jelly: a jelly behind every app; yours bounces up big and the jolt runs down the line

final class JellyEffect: StageEffect {
    private let flavors = ["e8336f", "8ad13b", "ff9a2e", "8e4fd1", "f5d33a", "3b6fe0", "18b6a6"]
    private var grow: [Spring] = [], squash: [Spring] = [], lean: [Spring] = []
    private var kicks: [(at: Double, i: Int, squash: Double, lean: Double)] = []
    private var lastFront: Int?? = .none, lastHover: Int?? = .none

    func fps(_ s: StageScene) -> Double {
        let moving = grow.indices.contains { !grow[$0].resting(at: $0 == s.front ? 1.42 : 1) || !squash[$0].resting(at: 0) || !lean[$0].resting(at: 0) }
        return moving || !kicks.isEmpty ? 60 : 0
    }

    func draw(_ ctx: CGContext, _ s: StageScene) {
        let u = s.u, tray = s.tray
        let n = s.tiles.count
        if grow.count != n {
            grow = (0..<n).map { Spring(x: $0 == s.front ? 1.42 : 1) }
            squash = Array(repeating: Spring(x: 0), count: n); lean = squash
        }
        if lastFront == .none || lastFront! != s.front {
            if lastFront != .none, let f = s.front {
                // the new one lands hard; the jolt travels out to the neighbours
                kicks.append((s.time, f, 4.5, 0))
                for d in 1...4 {
                    for side in [-1, 1] where f + d * side >= 0 && f + d * side < n {
                        kicks.append((s.time + 0.06 * Double(d), f + d * side, 1.6 / Double(d), Double(side) * 3.2 / Double(d)))
                    }
                }
            }
            lastFront = .some(s.front)
        }
        if lastHover == .none || lastHover! != s.hover {
            if lastHover != .none, let h = s.hover { kicks.append((s.time, h, 1.8, 0)) }
            lastHover = .some(s.hover)
        }
        kicks = kicks.filter { k in
            guard k.at <= s.time, k.i < n else { return true }
            squash[k.i].v += k.squash; lean[k.i].v += k.lean
            return false
        }
        for i in 0..<n {
            grow[i].step(to: i == s.front ? 1.42 : 1, k: 150, d: 8, dt: s.dt)
            squash[i].step(to: 0, k: 260, d: 9, dt: s.dt)
            lean[i].step(to: 0, k: 200, d: 6, dt: s.dt)
        }

        // A china plate
        let plate = rounded(tray, 30 * u)
        ctx.paint(plate, cg("f7f4ee"))
        ctx.gradient(in: plate, from: CGPoint(x: 0, y: tray.maxY), to: CGPoint(x: 0, y: tray.minY), [(0, cg("ffffff", 0.5)), (1, cg("b9b2a4", 0.35))])
        ctx.trace(rounded(tray.insetBy(dx: 4 * u, dy: 4 * u), 26 * u), cg("3a6fb0", 0.5), 1.1 * u)
        ctx.trace(rounded(tray.insetBy(dx: 6 * u, dy: 6 * u), 24 * u), cg("3a6fb0", 0.2), 0.6 * u)
        ctx.trace(plate, cg("cfc6b4"), 1 * u)

        // Smaller jellies first, so the big one stands in front of its neighbours
        for i in (0..<n).sorted(by: { grow[$0].x < grow[$1].x }) {
            jelly(ctx, s.tiles[i], i == n - 1 ? "aab2bc" : flavors[i % flavors.count],
                  grow: CGFloat(grow[i].x), squash: CGFloat(squash[i].x), lean: CGFloat(lean[i].x), u: u, seed: i)
        }
    }

    private func jelly(_ ctx: CGContext, _ t: CGRect, _ flavor: String, grow: CGFloat, squash: CGFloat, lean: CGFloat, u: CGFloat, seed: Int) {
        let w = t.width + 10 * u, h = t.height + 10 * u
        let sx = (1 + (grow - 1) * 0.55) * (1 + squash * 0.06), sy = grow * (1 - squash * 0.06)
        let base = CGPoint(x: t.midX, y: t.minY - 5 * u)
        ctx.setFillColor(cg("6a5a40", 0.16))
        ctx.fillEllipse(in: CGRect(x: base.x - w * sx * 0.55, y: base.y - 2.5 * u, width: w * sx * 1.1, height: 5 * u))
        ctx.saveGState()
        ctx.translateBy(x: base.x, y: base.y)
        ctx.concatenate(CGAffineTransform(a: sx, b: 0, c: lean * 0.05, d: sy, tx: 0, ty: 0))
        let body = rounded(CGRect(x: -w / 2, y: 0, width: w, height: h), 15 * u)
        ctx.paint(body, cg(flavor, 0.9))
        ctx.gradient(in: body, from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: 0), [(0, cg("ffffff", 0.22)), (0.6, cg("ffffff", 0)), (1, shade(flavor, 0.55, 0.55))])
        let shine = CGMutablePath()
        shine.addArc(center: CGPoint(x: -w * 0.08, y: h * 0.42), radius: w * 0.38, startAngle: 1.9, endAngle: 2.8, clockwise: false)
        ctx.trace(shine, cg("ffffff", 0.7), 2.2 * u)
        var r = RNG(seed)
        for _ in 0..<3 {
            ctx.disc(CGPoint(x: (CGFloat(r.next()) - 0.5) * w * 0.7, y: CGFloat(r.next()) * h * 0.25 + 3 * u), (0.6 + CGFloat(r.next())) * u, cg("ffffff", 0.35))
        }
        ctx.trace(body, shade(flavor, 0.7, 0.6), 0.8 * u)
        ctx.restoreGState()
    }
}
