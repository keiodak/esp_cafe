// FAFoursesBoard.swift — Fourses (k.odk)
// (in coco duo: the Fourses app as it is, inside FA — iOS · FOURSES)
// The board: TARPTERGE's and ARPSERGE's touch nodes (44 each, Blasser's glyphs), INTERSEXON's (eight sample & holds,
// eight current cells) and the terminals lie on it as icons, over the whole screen.
// DRAW: a drag draws a shape (circle · triangle · square · line · ◌ an unsteady one · ◉ one hung from a point, moved
//   by gravity) — every icon inside a shape is joined (a wire, 2K), shapes that overlap join their icons too; an empty
//   shape lying on a joined one pulls it toward a voltage its size sets. A tap on a shape takes it away.
// EDIT: the icons (and the shapes) are moved by dragging them. RANDOM throws the icons across the board.
// PLAY: a finger joins what it covers — lightly (a tip, ~10M) or flat (~20K) — and the body hums.
// The pots and the rest are sliders above and below it (ContentView).

import AVFoundation
import SwiftUI
import UIKit

extension FA {
enum FrBoard {
    /// 0 capacitor · 1 buffer · 2 pulse · 3 threshold · 4 gate · 5 gate, inverted · 6 / 7 bounds · 8 / 9 / 10 the rate ladder
    static let role: [Int] = [4, 3, 2, 1, 0, 7, 9, 10, 8, 5, 6, 4, 3, 2, 1, 0, 9, 10, 8, 7, 5, 6, 4, 3, 2, 1, 0, 7, 9, 10, 8, 5, 6, 4, 3, 2, 1, 0, 9, 10, 8, 7, 5, 6]
    static let horse: [Int] = [0, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0]
    // ---- the colours: paper, ink, and four plain colours
    static let paper = Color(hex: 0xEAE4D8)                      // (paper, a little warm)
    static let ink = Color(hex: 0x1D1C1A)
    static let red = Color(hex: 0xE2432D)
    static let yellow = Color(hex: 0xE8BC3F)
    static let blue = Color(hex: 0x2F5C9C)
    static let green = Color(hex: 0x3E8A6B)
    static let gray = Color(hex: 0x8D8C87)
    /// a board's ink: TARPTERGE black, ARPSERGE blue
    static func boardInk(_ n: Int) -> Color { n >= 200 && n < 244 ? blue : ink }
    /// an icon's frame: TARPTERGE black · ARPSERGE blue · INTERSEXON yellow
    static func frameInk(_ n: Int) -> Color {
        if n >= 200 && n < 244 { return blue }
        if n >= 300 && n < 346 { return Color(hex: 0xD9A627) }
        return ink
    }
    /// the terminals, each its own colour: OUT L red · OUT R orange · DUB A green · DUB B violet
    static func termInk(_ n: Int) -> Color {
        switch n {
        case 46: return red
        case 47: return Color(hex: 0xEE8A2E)
        case 80, 81: return green
        case 90: return Color(hex: 0x8A5A3C)                     // CAFE A: coffee
        case 91: return Color(hex: 0xB4875C)                     // CAFE B: café au lait
        default: return Color(hex: 0x7A5BA6)
        }
    }
    /// each shape its own colour, in turn
    /// (a graphic score's: ink, vermilion, teal, orange, slate blue, magenta, mustard)
    static let shapeColors: [Color] = [ink, Color(hex: 0xE34A2B), Color(hex: 0x1F968D), Color(hex: 0xEF8C2E),
                                       Color(hex: 0x3F78A0), Color(hex: 0xE0387C), Color(hex: 0xE8B63C)]
    /// 0 … 1 through DRAW's colours, cold to warm: slate blue · teal · mustard · orange · vermilion · magenta (the meters')
    static func ramp(_ a: Double) -> Color {
        let stops: [(Double, Double, Double)] = [(0x3F, 0x78, 0xA0), (0x1F, 0x96, 0x8D), (0xE8, 0xB6, 0x3C),
                                                 (0xEF, 0x8C, 0x2E), (0xE3, 0x4A, 0x2B), (0xE0, 0x38, 0x7C)]
        let x: Double = min(1, max(0, a)) * Double(stops.count - 1)
        let i: Int = min(stops.count - 2, Int(x))
        let f: Double = x - Double(i)
        let p = stops[i], q = stops[i + 1]
        let r: Double = (p.0 + (q.0 - p.0) * f) / 255
        let g: Double = (p.1 + (q.1 - p.1) * f) / 255
        let b: Double = (p.2 + (q.2 - p.2) * f) / 255
        return Color(red: r, green: g, blue: b)
    }
    static func shapeInk(_ k: Int) -> Color { shapeColors[k % shapeColors.count] }
    /// the icons are these nodes: TARPTERGE (0…43), ARPSERGE (200…243), INTERSEXON (300… S&H IN · 310… GATE · 320… OUT ·
    /// 330… the current cells' SOURCE △ / SINK ▽), OUT L / R (46, 47), the filters' CV (80…83)
    static let nodes: [Int] = Array(0..<44) + Array(200..<244) + Array(300..<308) + Array(310..<318) + Array(320..<328)
        + Array(330..<346) + [46, 47] + Array(80..<84) + [90, 91]
    static let outputs: Set<Int> = [46, 47, 90, 91]
    /// CAFE A / B (90, 91): a linked Cafe's ASH — off the board (parked) while that Cafe is not linked
    static func cafeNode(_ k: Int) -> Int { 90 + k }
    static let parked: [Double] = [-5, -5]
    static let count = nodes.count
    /// what an icon is: < 11 a glyph (role) · 11 S&H IN · 12 S&H GATE · 13 S&H OUT · 14 SOURCE · 15 SINK ·
    /// 16 an input terminal (the filters' CV) · 17 an output (OUT L / R)
    static func kind(_ i: Int) -> Int {
        let n = nodes[i]
        if n < 44 { return role[n] }
        if n >= 200 && n < 244 { return role[n - 200] }
        if outputs.contains(n) { return 17 }
        if n >= 80 && n < 84 { return 16 }
        if n < 310 { return 11 }; if n < 320 { return 12 }; if n < 330 { return 13 }
        return (n - 330) % 2 == 0 ? 14 : 15
    }
    static func label(_ i: Int) -> String {
        let n = nodes[i]
        if n == 46 { return "OUT L" }; if n == 47 { return "OUT R" }; if n == 90 { return "CAFE A" }; if n == 91 { return "CAFE B" }
        if n >= 80 && n < 84 { return ["DUB A−", "DUB A+", "DUB B−", "DUB B+"][n - 80] }
        return ""
    }
    static let shapeNames = ["○", "△", "□", "／", "✎"]
    /// a line's and a free stroke's reach either side (in heights): the four widths DRAW offers
    static let lineWidths = [0.005, 0.012, 0.03, 0.06]
    /// a straight line's dashes (0 none · 1 long · 2 short), kept at index 8
    static func dash(_ s: [Double]) -> Int { Int(s[0]) == 3 && s.count > 8 ? Int(s[8]) : 0 }
    /// its stroke, dashed as it is (lw: its width in points)
    static func strokeStyle(_ s: [Double], _ lw: CGFloat) -> StrokeStyle { strokeStyle(dash: dash(s), lw) }
    static func strokeStyle(dash: Int, _ lw: CGFloat) -> StrokeStyle {
        switch dash {
        case 1: return StrokeStyle(lineWidth: lw, lineCap: .butt, lineJoin: .round, dash: [lw * 4, lw * 2.5])
        case 2: return StrokeStyle(lineWidth: lw, lineCap: .butt, lineJoin: .round, dash: [lw * 1.2, lw * 1.4])
        default: return StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
        }
    }
    // a shape is [kind, x, y, r, 0, flicker, sway] (a line: [3, x1, y1, x2, y2, flicker, sway, width]; a free stroke:
    // [6, x, y, 0, 0, flicker, sway, width, x1, y1, x2, y2, …] — x, y its first point); the older ◌ / ◉ kinds 4 / 5 read
    // as a circle that flickers irregularly / one that tilts
    static let flickNames = ["—", "SLOW", "FAST", "IRREG", "DRUNK"]
    static let swayNames = ["—", "SLOW", "FAST", "IRREG", "DRUNK", "TILT"]
    static func flickKind(_ s: [Double]) -> Int { s.count >= 7 ? Int(s[5]) : (s.count >= 4 && Int(s[0]) == 4 ? 3 : 0) }
    static func swayKind(_ s: [Double]) -> Int { s.count >= 7 ? Int(s[6]) : (s.count >= 4 && Int(s[0]) == 5 ? 5 : 0) }
    /// its outline (○ △ □ ／)
    static func geometry(_ s: [Double]) -> Int { let t = Int(s[0]); return t == 4 || t == 5 ? 0 : t }
    /// a line or a free stroke
    static func isStroke(_ s: [Double]) -> Bool { let t = Int(s[0]); return (t == 3 && s.count >= 5) || (t == 6 && s.count >= 10) }
    /// its reach either side (in heights)
    static func width(_ s: [Double]) -> Double { s.count >= 8 && s[7] > 0 ? s[7] : (Int(s[0]) == 6 ? 0.025 : 0.035) }
    /// its points (x, y)
    static func polyline(_ s: [Double]) -> [(Double, Double)] {
        if Int(s[0]) == 3 { return [(s[1], s[2]), (s[3], s[4])] }
        var p: [(Double, Double)] = []
        var i = 8
        while i + 1 < s.count { p.append((s[i], s[i + 1])); i += 2 }
        return p
    }
    /// moved as a whole by (dx, dy)
    static func shifted(_ s: [Double], _ dx: Double, _ dy: Double) -> [Double] {
        var t = s
        t[1] += dx; t[2] += dy
        if Int(s[0]) == 3 && t.count >= 5 { t[3] += dx; t[4] += dy }
        if Int(s[0]) == 6 { var i = 8; while i + 1 < t.count { t[i] += dx; t[i + 1] += dy; i += 2 } }
        return t
    }
    /// a stroke's path in a view of this size
    static func strokePath(_ s: [Double], _ size: CGSize) -> Path {
        var p = Path()
        let pts = polyline(s)
        guard let f = pts.first else { return p }
        p.move(to: CGPoint(x: f.0 * size.width, y: f.1 * size.height))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0 * size.width, y: q.1 * size.height)) }
        return p
    }
    /// an unsteady supply (◌, type 4): a circle whose contact comes and goes — each shape's state now (1 whole ·
    /// less: it reaches less far · 0: gone for a moment), set by the Director
    /// ◉ (type 5): a circle hung from where it was drawn, nudged a little by gravity (its offset now, set by the Director)
    static func flickered(_ shapes: [[Double]], _ f: [Double], _ g: [[Double]] = []) -> [[Double]] {
        shapes.enumerated().map { k, s in
            guard s.count >= 4 else { return s }
            var t = s
            t[0] = Double(geometry(s))
            let stroke = isStroke(t)
            if swayKind(s) > 0, k < g.count, g[k].count >= 2 { t = shifted(t, g[k][0], g[k][1]) }   // (swayed: moved as a whole)
            if flickKind(s) > 0 {                                                 // (flickering: it reaches less far, or is gone)
                let v = k < f.count ? f[k] : 1
                if v <= 0 { return [] }
                if stroke {
                    while t.count < 8 { t.append(0) }
                    t[7] = width(s) * v
                } else { t[3] = s[3] * v }
            }
            return t
        }
    }
    /// SORT: ARPSERGE on the left, TARPTERGE on the right (a row a horse, the top horse above), INTERSEXON along the
    /// bottom (each hold with its cell), the terminals between the two boards
    static func sorted(aspect: Double) -> [[Double]] {
        var out = [[Double]](repeating: [0.5, 0.5], count: count)
        let rowY = [0.66, 0.51, 0.36, 0.21]                                  // (horse 0 at the bottom of its stack; a little more room)
        for i in 0..<count {
            let n = nodes[i]
            if n < 44 || (n >= 200 && n < 244) {
                let b = n < 44 ? n : n - 200, arp = n >= 200
                let h = horse[b], r = role[b]
                let x0 = arp ? 0.02 : 0.585, x1 = arp ? 0.415 : 0.98
                out[i] = [x0 + (x1 - x0) * (Double(r) + 0.5) / 11, rowY[h]]
            }
        }
        // INTERSEXON: eight groups (IN · GATE · OUT · SOURCE · SINK), four to a row, in the middle
        let step = 0.036, pitch = 5 * step + 0.025                                  // (as close as ARP / TARP's icons)
        let x0 = 0.5 - (3 * pitch + 4 * step) / 2
        for k in 0..<8 {
            let ids = [300 + k, 310 + k, 320 + k, 330 + 2 * k, 331 + 2 * k]
            let row = k / 4, col = k % 4
            for (j, n) in ids.enumerated() {
                out[icon(ofNode: n)] = [x0 + Double(col) * pitch + Double(j) * step, row == 0 ? 0.785 : 0.905]
            }
        }
        // the terminals: down the middle
        for (j, n) in [46, 47, 80, 81, 82, 83, 90, 91].enumerated() {
            out[icon(ofNode: n)] = [0.5, 0.15 + Double(j) * 0.085]
        }
        _ = aspect
        return out
    }
    /// the free field (the sliders take the bottom)
    static let yMax = 1.0
    static func buf(_ h: Int) -> Int { (0..<44).first { role[$0] == 1 && horse[$0] == h } ?? 0 }
    /// ARPSERGE's buffer (its icon)
    static func bufArp(_ h: Int) -> Int { icon(ofNode: 200 + buf(h)) }
    static func icon(ofNode n: Int) -> Int { nodes.firstIndex(of: n) ?? 0 }

    /// the icons thrown across the board, none on another (their boxes kept apart, in heights: aspect = width / height)
    static func scatter(seed: UInt64? = nil, aspect: Double = 2.5) -> [[Double]] {
        var s = seed ?? UInt64.random(in: 1...UInt64.max)
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
        let a = max(0.5, aspect)
        func ok(_ c: [Double]) -> Bool { !keepOut.contains { c[0] > $0[0] - 0.06 && c[0] < $0[1] + 0.06 && c[1] < $0[2] + 0.06 } }   // (the corners: DRAW, the mode)
        var out: [[Double]] = []
        for i in 0..<count {
            var best = [0.5, 0.4], bestD = -1.0
            for _ in 0..<40 {                                            // (the candidate farthest from the others)
                let c = [0.05 + rnd() * 0.90, 0.07 + rnd() * (yMax - 0.12)]
                if !ok(c) { continue }
                let d = out.map { hypot(($0[0] - c[0]) * a, $0[1] - c[1]) }.min() ?? 1
                if d > bestD { bestD = d; best = c }
            }
            _ = i
            out.append(best)
        }
        return relax(out, aspect: a)
    }
    /// the corners the icons keep out of: DRAW's shapes and passes (top left), the mode (top right) — [x0, x1, y bottom]
    static let keepOut: [[Double]] = []                                   // (the tools sit above the board now)
    /// pushed apart until no two icons' boxes overlap
    static func relax(_ o: [[Double]], aspect: Double = 2.5) -> [[Double]] {
        var out = o
        let a = max(0.5, aspect)
        func half(_ i: Int) -> (Double, Double) { (0.040, 0.040) }
        for _ in 0..<120 {
            var moved = false
            for i in 0..<count {
                for j in (i + 1)..<count {
                    let (hwi, hhi) = half(i), (hwj, hhj) = half(j)
                    let dx = (out[j][0] - out[i][0]) * a, dy = out[j][1] - out[i][1]
                    let ox = hwi + hwj + 0.012 - abs(dx), oy = hhi + hhj + 0.012 - abs(dy)
                    guard ox > 0 && oy > 0 else { continue }
                    moved = true
                    if ox / a < oy {                                     // (along the shorter way out)
                        let m = ox / a / 2 * (dx >= 0 ? 1 : -1)
                        out[i][0] -= m; out[j][0] += m
                    } else {
                        let m = oy / 2 * (dy >= 0 ? 1 : -1)
                        out[i][1] -= m; out[j][1] += m
                    }
                }
            }
            for i in 0..<count {                                         // (kept on the board)
                out[i][0] = min(0.97, max(0.03, out[i][0])); out[i][1] = min(yMax - 0.05, max(0.05, out[i][1]))
            }
            for i in 0..<count {                                         // (and out of the corners: DRAW's shapes, the mode)
                let (hw, hh) = half(i), hx = hw / a
                for z in keepOut {                                       // [x0, x1, y1]: from the top
                    guard out[i][0] + hx > z[0], out[i][0] - hx < z[1], out[i][1] - hh < z[2] else { continue }
                    moved = true
                    let down = z[2] + hh + 0.01 - out[i][1]
                    let side = z[0] <= 0 ? z[1] + hx + 0.01 - out[i][0] : out[i][0] - (z[0] - hx - 0.01)
                    if down < side * a { out[i][1] += down }                // (the shorter way out: across, in heights)
                    else if z[0] <= 0 { out[i][0] += side } else { out[i][0] -= side }
                }
            }
            if !moved { break }
        }
        return out
    }
    /// the first board: scattered, OUT L beside TARPTERGE's first buffer and OUT R beside ARPSERGE's, each in a circle
    static func defaultLayout() -> (icons: [[Double]], shapes: [[Double]]) {
        var ic = scatter(seed: 7)
        let b0 = ic[buf(0)], b2 = ic[bufArp(0)]
        ic[icon(ofNode: 46)] = [min(0.95, b0[0] + 0.05), max(0.05, b0[1] - 0.05)]
        ic[icon(ofNode: 47)] = [min(0.95, b2[0] + 0.05), max(0.05, b2[1] - 0.05)]
        ic = relax(ic)
        // a circle round each buffer and its two outputs (after they were pushed apart)
        func ring(_ m: [Int]) -> [Double] {
            let p = m.map { ic[$0] }
            let cx = p.map { $0[0] }.reduce(0, +) / Double(p.count), cy = p.map { $0[1] }.reduce(0, +) / Double(p.count)
            let r = p.map { hypot(($0[0] - cx) * 2.5, $0[1] - cy) }.max() ?? 0.1
            return [0, cx, cy, r + 0.04]
        }
        let sh = [ring([buf(0), icon(ofNode: 46)]), ring([bufArp(0), icon(ofNode: 47)])]
        return (ic, sh)
    }

    /// is (x, y) inside a shape [type, cx, cy, r]? (x scaled by the board's aspect: r is in heights)
    static func inside(_ x: Double, _ y: Double, _ s: [Double], aspect: Double) -> Bool {
        if isStroke(s) {                                                 // a line or a free stroke: near it
            let w = width(s), pts = polyline(s), px = x * aspect
            if pts.count == 1 { return hypot(px - pts[0].0 * aspect, y - pts[0].1) <= w }
            for j in 1..<max(1, pts.count) {
                let ax = pts[j - 1].0 * aspect, ay = pts[j - 1].1, bx = pts[j].0 * aspect, by = pts[j].1
                let vx = bx - ax, vy = by - ay, L = vx * vx + vy * vy
                let t = L > 0 ? max(0, min(1, ((px - ax) * vx + (y - ay) * vy) / L)) : 0
                if hypot(px - (ax + vx * t), y - (ay + vy * t)) <= w { return true }
            }
            return false
        }
        let dx = (x - s[1]) * aspect, dy = y - s[2], r = s[3]
        switch Int(s[0]) {
        case 1:                                                          // a triangle, point up (y grows down)
            let a = (0.0, -r), b = (r * 0.866, r * 0.5), c = (-r * 0.866, r * 0.5)
            func side(_ p: (Double, Double), _ q: (Double, Double)) -> Double { (q.0 - p.0) * (dy - p.1) - (q.1 - p.1) * (dx - p.0) }
            let s1 = side(a, b), s2 = side(b, c), s3 = side(c, a)
            return (s1 >= 0 && s2 >= 0 && s3 >= 0) || (s1 <= 0 && s2 <= 0 && s3 <= 0)
        case 2: return abs(dx) <= r && abs(dy) <= r
        default: return dx * dx + dy * dy <= r * r
        }
    }
    /// a shape's box (x0, x1, y0, y1) in the field's own units
    static func bounds(_ s: [Double], aspect: Double) -> (Double, Double, Double, Double) {
        if isStroke(s) {
            let pts = polyline(s), w = width(s)
            guard let f = pts.first else { return (0, 0, 0, 0) }
            var b = (f.0, f.0, f.1, f.1)
            for q in pts { b.0 = min(b.0, q.0); b.1 = max(b.1, q.0); b.2 = min(b.2, q.1); b.3 = max(b.3, q.1) }
            return (b.0 - w / aspect, b.1 + w / aspect, b.2 - w, b.3 + w)
        }
        let r = s[3]
        return (s[1] - r / aspect, s[1] + r / aspect, s[2] - r, s[2] + r)
    }
    /// points on a shape (for overlaps): a line along its length, the others their centre and outline
    static func samples(_ s: [Double], aspect: Double) -> [(Double, Double)] {
        if isStroke(s) {                                                  // along it
            let pts = polyline(s)
            if Int(s[0]) == 3 { return (0...12).map { k in let t = Double(k) / 12; return (s[1] + (s[3] - s[1]) * t, s[2] + (s[4] - s[2]) * t) } }
            let step = max(1, pts.count / 24)
            return stride(from: 0, to: pts.count, by: step).map { pts[$0] }
        }
        var p = [(s[1], s[2])]
        for k in 0..<12 { let a = Double(k) * .pi / 6; p.append((s[1] + cos(a) * s[3] * 0.97 / aspect, s[2] + sin(a) * s[3] * 0.97)) }
        return p.filter { inside($0.0, $0.1, s, aspect: aspect) }
    }
    /// the wires the shapes make, as node pairs
    static func links(icons: [[Double]], shapes: [[Double]], aspect: Double, light: Bool = false,
                      drifted: (volts: [Int: Int], links: [[Int]])? = nil) -> [[Int]] {
        var out = iconLinks(icons: icons, shapes: shapes.filter { $0.count >= 4 }, aspect: aspect).map { [min(nodes[$0[0]], nodes[$0[1]]), max(nodes[$0[0]], nodes[$0[1]]), $0[2]] }
        if light {                                                       // CAMERA: each shape's light (node 100 + k) on what it covers
            for (k, s) in shapes.prefix(16).enumerated() where s.count >= 4 {
                for i in 0..<min(count, icons.count) {
                    let c = cover(i, icons[i], s, aspect: aspect)
                    if c > 0 { out.append([nodes[i], 100 + k, Int(150 + 850 * c)]) }
                }
            }
        } else {
            out += (drifted ?? drift(icons: icons, shapes: shapes, aspect: aspect)).links     // an empty shape on a joined one: its pull (node 100 + k)
        }
        return out
    }
    /// a shape that covers no icon but lies on a shape that does: it pulls that shape's icons (through its own node,
    /// 100 + k) toward a voltage its size sets — a small one a little under the middle (4.2 V), a big one down to 0 V;
    /// how much of it lies on the other sets how hard. [k: 0…500 as sent (×8.4 mV)] and the links
    static func drift(icons: [[Double]], shapes: [[Double]], aspect: Double) -> (volts: [Int: Int], links: [[Int]]) {
        let n = min(count, icons.count)
        let covered: [[Int]] = shapes.map { s in s.count >= 4 ? (0..<n).filter { cover($0, icons[$0], s, aspect: aspect) > 0 } : [] }
        var volts: [Int: Int] = [:], out: [[Int]] = []
        for (k, s) in shapes.prefix(16).enumerated() where s.count >= 4 && covered[k].isEmpty {
            let mine = samples(s, aspect: aspect)
            var group = Set<Int>(), f = 0.0
            for (j, t) in shapes.enumerated() where j != k && t.count >= 4 && !covered[j].isEmpty {
                let a = mine.isEmpty ? 0 : Double(mine.filter { inside($0.0, $0.1, t, aspect: aspect) }.count) / Double(mine.count)
                let theirs = samples(t, aspect: aspect)
                let b = theirs.isEmpty ? 0 : Double(theirs.filter { inside($0.0, $0.1, s, aspect: aspect) }.count) / Double(theirs.count)
                let o = max(a, b)
                if o > 0 { group.formUnion(covered[j]); f = max(f, o) }
            }
            guard !group.isEmpty else { continue }
            let area: Double = {                                                   // (of the field: 1 = all of it)
                switch Int(s[0]) {
                case 3, 6:
                    let pts = polyline(s)
                    var len = 0.0
                    for j in 1..<max(1, pts.count) { len += hypot((pts[j].0 - pts[j - 1].0) * aspect, pts[j].1 - pts[j - 1].1) }
                    return len * width(s) * 2 / aspect
                case 2: return 4 * s[3] * s[3] / aspect
                case 1: return 1.3 * s[3] * s[3] / aspect
                default: return .pi * s[3] * s[3] / aspect
                }
            }()
            volts[k] = Int((500 * (1 - min(1, area / 0.12))).rounded())            // (4.2 V → 0 V as it grows to an eighth of the field)
            let v = Int(200 + 600 * f)
            for i in group { out.append([nodes[i], 100 + k, v]) }
        }
        return (volts, out)
    }
    /// the icons in each shape joined; overlapping shapes joined (a star from the first)
    /// how bright the camera is inside a shape (the 8 × 16 mosaic over the field; 0…1)
    static func light(_ s: [Double], grid: [[Double]], aspect: Double) -> Double {
        guard grid.count >= 8, grid[0].count >= 16 else { return 0.5 }
        var sum = 0.0, n = 0
        let bx = bounds(s, aspect: aspect)                                  // (only the cells within its box)
        let r0 = max(0, Int(bx.2 * 8)), r1 = min(7, Int(bx.3 * 8)), c0 = max(0, Int(bx.0 * 16)), c1 = min(15, Int(bx.1 * 16))
        if r0 <= r1 && c0 <= c1 {
            for r in r0...r1 { for c in c0...c1 where inside((Double(c) + 0.5) / 16, (Double(r) + 0.5) / 8, s, aspect: aspect) { sum += grid[r][c]; n += 1 } }
        }
        if n > 0 { return sum / Double(n) }
        let r = min(7, max(0, Int(s[2] * 8))), c = min(15, max(0, Int(s[1] * 16)))   // (smaller than a cell: the one under it)
        return grid[r][c]
    }
    /// the camera's 8 × 16 mosaic (the whole picture) as it lies under the field when the picture fills it (cropped, not
    /// stretched: a 3 : 4 picture), resampled to the field's own 8 × 16 — what the board shows and what each shape reads
    static func fieldGrid(_ g: [[Double]], aspect: Double) -> [[Double]] {
        guard g.count >= 8, g[0].count >= 16 else { return g }
        let fa = 0.75
        func at(_ u: Double, _ v: Double) -> Double {
            let x = min(15, max(0, u * 16 - 0.5)), y = min(7, max(0, v * 8 - 0.5))
            let c0 = Int(x), r0 = Int(y), c1 = min(15, c0 + 1), r1 = min(7, r0 + 1)
            let fx = x - Double(c0), fy = y - Double(r0)
            let top = g[r0][c0] + (g[r0][c1] - g[r0][c0]) * fx, bot = g[r1][c0] + (g[r1][c1] - g[r1][c0]) * fx
            return top + (bot - top) * fy
        }
        return (0..<8).map { r in (0..<16).map { c in
            let u = (Double(c) + 0.5) / 16, v = (Double(r) + 0.5) / 8
            return aspect > fa ? at(u, 0.5 + (v - 0.5) * fa / aspect) : at(0.5 + (u - 0.5) * aspect / fa, v)
        } }
    }
    /// how much of an icon a shape covers (0…1: 5 × 5 points over the icon)
    static func cover(_ i: Int, _ p: [Double], _ s: [Double], aspect: Double) -> Double {
        let (hw, hh) = (0.032, 0.032)                                       // (half its size, in heights)
        let b = bounds(s, aspect: aspect)                                   // (far from it: nothing to count)
        if p[0] + hw / aspect < b.0 || p[0] - hw / aspect > b.1 || p[1] + hh < b.2 || p[1] - hh > b.3 { return 0 }
        var n = 0
        for a in 0..<5 { for b in 0..<5 {
            let x = p[0] + (Double(a) - 2) / 2 * hw / aspect, y = p[1] + (Double(b) - 2) / 2 * hh
            if inside(x, y, s, aspect: aspect) { n += 1 }
        } }
        return Double(n) / 25
    }
    /// [icon, icon, strength 0…1000]: how much of each is covered sets how hard it is joined (just touched ~2M · all in 2K)
    static func iconLinks(icons: [[Double]], shapes: [[Double]], aspect: Double) -> [[Int]] {
        var cov = [Double](repeating: 0, count: count)
        var parent = Array(0..<(count + shapes.count))
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        func join(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }
        var hasIcon = [Bool](repeating: false, count: shapes.count)
        for (k, s) in shapes.enumerated() where s.count >= 4 {
            for i in 0..<count where i < icons.count {
                let c = cover(i, icons[i], s, aspect: aspect)
                if c > 0 { join(i, count + k); hasIcon[k] = true; cov[i] = max(cov[i], c) }
            }
        }
        for a in 0..<shapes.count { for b in (a + 1)..<shapes.count {        // (overlapping: centres closer than the radii)
            let s = shapes[a], t = shapes[b]
            guard s.count >= 4, t.count >= 4 else { continue }
            if samples(s, aspect: aspect).contains(where: { inside($0.0, $0.1, t, aspect: aspect) })
                || samples(t, aspect: aspect).contains(where: { inside($0.0, $0.1, s, aspect: aspect) }) { join(count + a, count + b) }
        } }
        var groups: [Int: [Int]] = [:]
        for i in 0..<count { groups[find(i), default: []].append(i) }
        var out: [[Int]] = []
        for (_, g0) in groups where g0.count >= 2 {
            // (the star's centre: not an output, and the most covered)
            let g = g0.sorted { a, b in
                let oa = outputs.contains(nodes[a]), ob = outputs.contains(nodes[b])
                return oa != ob ? !oa : cov[a] > cov[b]
            }
            for m in g.dropFirst() { out.append([min(g[0], m), max(g[0], m), Int(150 + 850 * min(cov[g[0]], cov[m]))]) }
        }
        return out
    }
}

/// Blasser's glyphs, as on the board
struct FrGlyph: Shape {
    let role: Int
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), s = min(r.width, r.height) / 2
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: c.x + x * s, y: c.y - y * s) }
        switch role {
        case 0, 3:                                                   // a cloud: the capacitor, the threshold
            p.addEllipse(in: CGRect(x: c.x - s * 0.9, y: c.y - s * 0.25, width: s * 1.8, height: s * 0.75))
            p.addEllipse(in: CGRect(x: c.x - s * 0.45, y: c.y - s * 0.7, width: s * 0.9, height: s * 0.8))
            if role == 3 { p.move(to: pt(-0.5, -0.75)); p.addLine(to: pt(0.5, -0.75)) }
        case 1:                                                      // two bowties: the buffer
            for dx in [-0.45, 0.45] {
                p.move(to: pt(dx - 0.35, 0.6)); p.addLine(to: pt(dx + 0.35, -0.6)); p.addLine(to: pt(dx + 0.35, 0.6))
                p.addLine(to: pt(dx - 0.35, -0.6)); p.closeSubpath()
            }
        case 2:                                                      // a bowtie: the pulse
            p.move(to: pt(-0.6, 0.6)); p.addLine(to: pt(0.6, -0.6)); p.addLine(to: pt(0.6, 0.6)); p.addLine(to: pt(-0.6, -0.6)); p.closeSubpath()
        case 4, 5:                                                   // a diamond: the gates
            p.move(to: pt(0, 0.85)); p.addLine(to: pt(0.5, 0)); p.addLine(to: pt(0, -0.85)); p.addLine(to: pt(-0.5, 0)); p.closeSubpath()
            if role == 5 { p.move(to: pt(-0.5, 0)); p.addLine(to: pt(0.5, 0)) }
        case 6, 7:                                                   // a star: the bounds
            for k in 0..<14 {
                let a = Double(k) * .pi / 7 + .pi / 2, rr = k % 2 == 0 ? 0.9 : 0.4
                let q = pt(cos(a) * rr, sin(a) * rr)
                if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
        case 8, 10:                                                  // a cross: the ladder's ends
            let a = 0.28, b = 0.8
            let xs: [(Double, Double)] = [(-a, b), (a, b), (a, a), (b, a), (b, -a), (a, -a), (a, -b), (-a, -b), (-a, -a), (-b, -a), (-b, a), (-a, a)]
            p.move(to: pt(xs[0].0, xs[0].1)); xs.dropFirst().forEach { p.addLine(to: pt($0.0, $0.1)) }; p.closeSubpath()
        case 11:                                                     // S&H IN: two bowties
            for dx in [-0.42, 0.42] {
                p.move(to: pt(dx - 0.32, 0.55)); p.addLine(to: pt(dx + 0.32, -0.55)); p.addLine(to: pt(dx + 0.32, 0.55))
                p.addLine(to: pt(dx - 0.32, -0.55)); p.closeSubpath()
            }
        case 12:                                                     // S&H GATE: a bowtie
            p.move(to: pt(-0.6, 0.55)); p.addLine(to: pt(0.6, -0.55)); p.addLine(to: pt(0.6, 0.55)); p.addLine(to: pt(-0.6, -0.55)); p.closeSubpath()
        case 14:                                                     // SOURCE △
            p.move(to: pt(0, 0.7)); p.addLine(to: pt(0.65, -0.5)); p.addLine(to: pt(-0.65, -0.5)); p.closeSubpath()
        case 15:                                                     // SINK ▽
            p.move(to: pt(0, -0.7)); p.addLine(to: pt(0.65, 0.5)); p.addLine(to: pt(-0.65, 0.5)); p.closeSubpath()
        default:                                                     // three bars: the ladder's middle · S&H OUT
            for x in [-0.4, 0.0, 0.4] { p.move(to: pt(x, 0.7)); p.addLine(to: pt(x, -0.7)) }
            p.move(to: pt(-0.7, 0)); p.addLine(to: pt(0.7, 0))
        }
        return p
    }
}

/// a drawn shape (type, centre, radius) in view space
struct FrShapePath: Shape {
    let type: Int
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), s = min(r.width, r.height) / 2
        switch type {
        case 1:
            p.move(to: CGPoint(x: c.x, y: c.y - s)); p.addLine(to: CGPoint(x: c.x + s * 0.866, y: c.y + s * 0.5))
            p.addLine(to: CGPoint(x: c.x - s * 0.866, y: c.y + s * 0.5)); p.closeSubpath()
        case 2: p.addRect(CGRect(x: c.x - s, y: c.y - s, width: s * 2, height: s * 2))
        default: p.addEllipse(in: CGRect(x: c.x - s, y: c.y - s, width: s * 2, height: s * 2))
        }
        return p
    }
}

/// the touches, with how much of the finger is down (UIKit: SwiftUI has no touch radius)
struct FrTouchLayer: UIViewRepresentable {
    var onChange: ([(id: Int, p: CGPoint, r: CGFloat, ended: Bool)]) -> Void
    func makeUIView(context: Context) -> V { let v = V(); v.onChange = onChange; v.isMultipleTouchEnabled = true; v.backgroundColor = .clear; return v }
    func updateUIView(_ v: V, context: Context) { v.onChange = onChange }
    final class V: UIView {
        var onChange: (([(id: Int, p: CGPoint, r: CGFloat, ended: Bool)]) -> Void)?
        private var ids: [ObjectIdentifier: Int] = [:]
        private func report(_ t: Set<UITouch>, ended: Bool) {
            var out: [(id: Int, p: CGPoint, r: CGFloat, ended: Bool)] = []
            for u in t {
                let k = ObjectIdentifier(u)
                if ids[k] == nil { ids[k] = (0..<5).first { f in !ids.values.contains(f) } ?? 4 }
                out.append((ids[k]!, u.location(in: self), u.majorRadius, ended))
                if ended { ids[k] = nil }
            }
            onChange?(out)
        }
        override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { report(t, ended: false) }
        override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { report(t, ended: false) }
        override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { report(t, ended: true) }
        override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { report(t, ended: true) }
    }
}

struct FoursesBoard: View {
    let d: Director
    @ObservedObject var rig: Rig
    /// the shapes' flicker and sway now
    @ObservedObject var live: Live
    @ObservedObject var cam: FrCamera
    /// the camera's light in each shape (not observed here: each shape's own view watches it)
    let light: CameraState
    @State private var fingers: [Int: (p: CGPoint, r: CGFloat)] = [:]
    @State private var draft: (start: CGPoint, now: CGPoint)? = nil
    @State private var freePts: [CGPoint] = []                                  // DRAW ✎: the stroke so far
    @State private var grab: (kind: Int, index: Int, offset: CGSize)? = nil    // EDIT: 0 an icon, 1 a shape
    @State private var grabAt: CGPoint = .zero
    @State private var grabMoved = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let field = CGSize(width: size.width, height: size.height * FrBoard.yMax)
            let nowShapes = FrBoard.flickered(rig.frShapes, rig.frFlick, rig.frGrav)   // (as they are now: ◉ where gravity has it)
            let level: [Int: Double] = {                                  // how hard each icon is joined (0…1): the orange's depth
                var m: [Int: Double] = [:]
                for l in FrBoard.iconLinks(icons: rig.frIcons, shapes: nowShapes.filter { $0.count >= 4 }, aspect: aspect(field)) {
                    let v = Double(l[2]) / 1000
                    m[l[0]] = max(m[l[0]] ?? 0, v); m[l[1]] = max(m[l[1]] ?? 0, v)
                }
                return m
            }()
            // each shape's depth: the hardest join among the icons it covers (once for all, from the joins above)
            let amps: [Double] = nowShapes.map { (s: [Double]) -> Double in
                guard s.count >= 4 else { return 0 }
                var a = 0.0
                for (i, v) in level where i < rig.frIcons.count && v > a && FrBoard.cover(i, rig.frIcons[i], s, aspect: aspect(field)) > 0 { a = v }
                return a
            }
            ZStack(alignment: .topLeading) {
                // the board: paper, a fine dot grid (CAMERA: the mosaic under it — each shape's LIGHT is its brightness)
                Rectangle().fill(cam.enabled ? PastelTheme.padScreen : FrBoard.paper)
                if cam.enabled && cam.running {                              // CAMERA: the picture, faint over the board and clear in the shapes
                    FrCameraLayer(state: cam.state, session: cam.session, shapes: rig.frShapes)
                        .frame(width: field.width, height: field.height)
                        .allowsHitTesting(false)
                }
                FrDotGrid()                                                  // (its own view: not drawn again with the board)
                // the three boards' corners (faint): TARPTERGE left, ARPSERGE right, INTERSEXON below
                FrRegionMarks(icons: rig.frIcons)
                    .frame(width: field.width, height: field.height)
                    .allowsHitTesting(false)
                // the shapes (each its own view: the camera's light redraws only them)
                ForEach(Array(rig.frShapes.enumerated()), id: \.offset) { k, s in
                    let fl: Double = FrBoard.flickKind(s) > 0 ? (k < rig.frFlick.count ? rig.frFlick[k] : 1) : 1   // its contact, flickering
                    let go: [Double] = FrBoard.swayKind(s) > 0 && k < rig.frGrav.count && rig.frGrav[k].count >= 2 ? rig.frGrav[k] : [0, 0]   // where it has swayed
                    FrShapeView(k: k, s: s, amp: k < amps.count ? amps[k] : 0, fl: fl, go: go, field: field, camOn: cam.enabled, light: light)
                }
                if draft != nil, rig.frShape == 4, freePts.count > 1 {
                    Path { p in p.move(to: freePts[0]); freePts.dropFirst().forEach { p.addLine(to: $0) } }
                        .stroke(FrBoard.shapeInk(rig.frShapes.count).opacity(0.5),
                                style: StrokeStyle(lineWidth: CGFloat(FrBoard.lineWidths[min(rig.drawWidth, FrBoard.lineWidths.count - 1)]) * field.height * 2, lineCap: .round, lineJoin: .round))
                } else if let dr = draft, rig.frShape == 3 {
                    Path { p in p.move(to: dr.start); p.addLine(to: dr.now) }
                        .stroke(FrBoard.shapeInk(rig.frShapes.count).opacity(0.5),
                                style: FrBoard.strokeStyle(dash: rig.drawDash, CGFloat(FrBoard.lineWidths[min(rig.drawWidth, FrBoard.lineWidths.count - 1)]) * field.height * 2))
                } else if let dr = draft {
                    let r = hypot(dr.now.x - dr.start.x, dr.now.y - dr.start.y)
                    FrShapePath(type: rig.frShape)
                        .stroke(FrBoard.shapeInk(rig.frShapes.count), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .frame(width: r * 2, height: r * 2).position(dr.start)
                }
                // the icons
                ForEach(0..<FrBoard.count, id: \.self) { i in
                    icon(i, level: touched(i, field) ? 1 : (level[i] ?? 0), field: field)
                }
                // the fingers
                ForEach(Array(fingers.keys), id: \.self) { f in
                    if let t = fingers[f] {
                        Circle().fill(FrBoard.red.opacity(0.08))
                            .overlay(Circle().strokeBorder(FrBoard.red.opacity(0.6), lineWidth: 1))
                            .frame(width: reach(t.r) * 2, height: reach(t.r) * 2).position(t.p)
                    }
                }
                FrTouchLayer { ts in touches(ts, field) }
                    .frame(width: field.width, height: field.height)
            }
            .clipped()
            .onAppear { d.frAspect = aspect(field); d.frSyncShapes() }
            .onChange(of: size) { _, s in d.frAspect = aspect(CGSize(width: s.width, height: s.height * FrBoard.yMax)) }
        }
    }

    // MARK: pieces

    private func icon(_ i: Int, level: Double, field: CGSize) -> some View {
        let p = rig.frIcons.indices.contains(i) ? rig.frIcons[i] : [0.5, 0.5]
        return FrIconView(meters: rig.meters, i: i, level: level, size: iconSize(field),
                          grabbed: grab?.kind == 0 && grab?.index == i)
            .position(view(p[0], p[1], field))
            .allowsHitTesting(false)
    }

    // MARK: geometry

    private func aspect(_ f: CGSize) -> Double { Double(f.width / max(1, f.height)) }
    private func view(_ x: Double, _ y: Double, _ f: CGSize) -> CGPoint { CGPoint(x: x * f.width, y: y * f.height) }
    private func norm(_ p: CGPoint, _ f: CGSize) -> [Double] {
        [min(0.98, max(0.02, Double(p.x / f.width))), min(0.98, max(0.02, Double(p.y / f.height)))]
    }
    private func iconSize(_ f: CGSize) -> CGFloat { max(14, min(24, f.height * 0.068)) }
    private func reach(_ r: CGFloat) -> CGFloat { 12 + r * 0.9 }
    private func touched(_ i: Int, _ f: CGSize) -> Bool {
        guard rig.frMode == 0, rig.frIcons.indices.contains(i) else { return false }
        let q = view(rig.frIcons[i][0], rig.frIcons[i][1], f)
        return fingers.values.contains { hypot($0.p.x - q.x, $0.p.y - q.y) < reach($0.r) }
    }
    private func iconAt(_ p: CGPoint, _ f: CGSize) -> Int? {
        var best: (Int, CGFloat)? = nil
        for i in 0..<min(FrBoard.count, rig.frIcons.count) {
            let q = view(rig.frIcons[i][0], rig.frIcons[i][1], f), dd = hypot(q.x - p.x, q.y - p.y)
            if dd < iconSize(f) * 0.9 && (best == nil || dd < best!.1) { best = (i, dd) }
        }
        return best?.0
    }
    private func shapeAt(_ p: CGPoint, _ f: CGSize) -> Int? {
        let n = norm(p, f)
        return rig.frShapes.indices.reversed().first { FrBoard.inside(n[0], n[1], rig.frShapes[$0], aspect: aspect(f)) }
    }

    // MARK: touches

    private func touches(_ ts: [(id: Int, p: CGPoint, r: CGFloat, ended: Bool)], _ f: CGSize) {
        switch rig.frMode {
        case 1:                                                                  // DRAW
            guard let t = ts.first else { return }
            if draft == nil { draft = (t.p, t.p); freePts = [t.p] } else { draft!.now = t.p }
            if rig.frShape == 4, let last = freePts.last, hypot(t.p.x - last.x, t.p.y - last.y) > 5 { freePts.append(t.p) }
            if t.ended, let dr = draft {
                let r = hypot(dr.now.x - dr.start.x, dr.now.y - dr.start.y)
                let travelled = zip(freePts, freePts.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
                let w = FrBoard.lineWidths[min(rig.drawWidth, FrBoard.lineWidths.count - 1)], fk = Double(rig.drawFlick), sk = Double(rig.drawSway)
                if r < 10 && travelled < 10 { if let k = shapeAt(dr.start, f) { d.frRemoveShape(k) } }   // a tap: the shape goes
                else if rig.frShape == 4 {                                       // ✎ a free stroke (at most 48 points)
                    let step = max(1, freePts.count / 48)
                    var pts = stride(from: 0, to: freePts.count, by: step).map { freePts[$0] }
                    if let e = freePts.last, pts.last != e { pts.append(e) }
                    let a = norm(pts[0], f)
                    d.frAddShape([6, a[0], a[1], 0, 0, fk, sk, w] + pts.flatMap { norm($0, f) })
                }
                else if rig.frShape == 3 { let a = norm(dr.start, f), b = norm(dr.now, f); d.frAddShape([3, a[0], a[1], b[0], b[1], fk, sk, w, Double(rig.drawDash)]) }
                else { let c = norm(dr.start, f); d.frAddShape([Double(rig.frShape), c[0], c[1], Double(r / f.height), 0, Double(rig.drawFlick), Double(rig.drawSway)]) }
                draft = nil; freePts = []
            }
        case 2:                                                                  // EDIT: move what is grabbed
            guard let t = ts.first else { return }
            if grab == nil {
                if let i = iconAt(t.p, f) {
                    let q = view(rig.frIcons[i][0], rig.frIcons[i][1], f)
                    grab = (0, i, CGSize(width: q.x - t.p.x, height: q.y - t.p.y))
                } else if let k = shapeAt(t.p, f) {
                    let q = view(rig.frShapes[k][1], rig.frShapes[k][2], f)
                    grab = (1, k, CGSize(width: q.x - t.p.x, height: q.y - t.p.y))
                } else { return }
                grabAt = t.p; grabMoved = false
            }
            if hypot(t.p.x - grabAt.x, t.p.y - grabAt.y) > 6 { grabMoved = true }
            if let g = grab, grabMoved {
                let n = norm(CGPoint(x: t.p.x + g.offset.width, y: t.p.y + g.offset.height), f)
                if g.kind == 0 { rig.frIcons[g.index] = n }
                else if rig.frShapes.indices.contains(g.index) {
                    let sh = rig.frShapes[g.index]
                    rig.frShapes[g.index] = FrBoard.shifted(sh, n[0] - sh[1], n[1] - sh[2])   // (a line, a stroke: all of it)
                }
            }
            if t.ended { grab = nil; d.frSyncShapes() }
        default:                                                                 // PLAY: fingers
            for t in ts { if t.ended { fingers[t.id] = nil } else { fingers[t.id] = (t.p, t.r) } }
            var links: [Int: [Int: Int]] = [:]
            for (fi, t) in fingers {
                let R = reach(t.r)
                for i in 0..<min(FrBoard.count, rig.frIcons.count) {
                    let q = view(rig.frIcons[i][0], rig.frIcons[i][1], f), dd = hypot(q.x - t.p.x, q.y - t.p.y)
                    guard dd < R else { continue }
                    let firm = min(1, max(0, (t.r - 7) / 22))                    // the finger's contact: tip … flat
                    let near = 1 - dd / R * 0.6                                   // (the edge of the finger touches less)
                    links[48 + fi, default: [:]][FrBoard.nodes[i]] = Int((150 + firm * 780) * near)
                }
                // a finger on a shape touches the shape: everything the shape covers, through the finger
                let n = norm(t.p, f)
                for sh in rig.frShapes where sh.count >= 4 && FrBoard.inside(n[0], n[1], sh, aspect: aspect(f)) {
                    let firm = min(1, max(0, (t.r - 7) / 22))
                    for i in 0..<min(FrBoard.count, rig.frIcons.count) {
                        let c = FrBoard.cover(i, rig.frIcons[i], sh, aspect: aspect(f))
                        guard c > 0 else { continue }
                        let v = Int((150 + firm * 780) * (0.4 + 0.6 * c))
                        links[48 + fi, default: [:]][FrBoard.nodes[i]] = max(links[48 + fi]?[FrBoard.nodes[i]] ?? 0, v)
                    }
                }
            }
            d.frTouches(links)
        }
    }
}

/// a drawn shape: its fill (a line: its stroke), deeper as it joins harder, and — with the camera — a glow that
/// breathes with the light inside it
struct FrShapeView: View {
    let k: Int
    let s: [Double]
    let amp: Double
    let fl: Double
    let go: [Double]
    let field: CGSize
    let camOn: Bool
    @ObservedObject var light: CameraState

    var body: some View {
        let live = amp > 0
        let ink = camOn ? PastelTheme.hudOrange : FrBoard.shapeInk(k)       // (CAMERA: as on the Cafe's board — one orange, thin)
        let lit: Double = camOn && k < 16 && k < light.shapeLight.count ? light.shapeLight[k] : 0
        let thin: Double = camOn ? 0.45 : 1
        let flo: Double = 0.35 + 0.65 * fl
        let strokeA: Double = (live ? 0.2 + 0.4 * amp : 0.12) * flo * thin
        let fillA: Double = camOn ? (live ? 0.15 + 0.40 * amp : 0.10) * thin * flo
                                  : (live ? 0.18 + 0.34 * amp : 0.12) * flo      // (light: the paper through it)
        let dark: Double = live && !camOn ? -0.12 * amp : 0
        let w0: Double = FrBoard.width(s)
        let wFl: Double = 0.4 + 0.6 * fl
        let wLit: Double = 1 + 0.5 * lit
        let wRel: CGFloat = CGFloat(w0 * wFl * wLit)
        let lw: CGFloat = wRel * field.height * 2
        let grow: CGFloat = CGFloat(1 + 0.08 * lit)
        ZStack(alignment: .topLeading) {
            if FrBoard.isStroke(s) {
                FrBoard.strokePath(FrBoard.shifted(s, go[0], go[1]), field)
                    .stroke(ink.opacity(strokeA), style: FrBoard.strokeStyle(s, lw))
                    .brightness(dark)
            } else if s.count >= 4 {
                let c = CGPoint(x: CGFloat(s[1] + go[0]) * field.width, y: CGFloat(s[2] + go[1]) * field.height)
                let r: CGFloat = CGFloat(s[3]) * field.height
                FrShapePath(type: FrBoard.geometry(s))
                    .fill(ink.opacity(fillA))   // (CAMERA: the colour shows through)
                    .brightness(dark)
                    .scaleEffect(grow)
                    .frame(width: r * 2, height: r * 2)
                    .position(c)
                if FrBoard.swayKind(s) > 0 {                                   // (the point it hangs from)
                    Circle().fill(ink.opacity(0.7)).frame(width: 4, height: 4)
                        .position(x: CGFloat(s[1]) * field.width, y: CGFloat(s[2]) * field.height)
                }
            }
        }
        .frame(width: field.width, height: field.height, alignment: .topLeading)
        .animation(camOn ? .easeOut(duration: 0.12) : nil, value: lit)
        .allowsHitTesting(false)
    }
}

/// the board's fine dot grid
struct FrDotGrid: View {
    var body: some View {
        Canvas { ctx, s in
            let step: CGFloat = 16
            for x in stride(from: step / 2, to: s.width, by: step) {
                for y in stride(from: step / 2, to: s.height * FrBoard.yMax, by: step) {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)), with: .color(FrBoard.gray.opacity(0.35)))
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// every shape as one area (a line: its band), for the camera's picture and colour to show through
struct FrShapesArea: Shape {
    let shapes: [[Double]]
    func path(in rect: CGRect) -> Path {
        var clip = Path()
        for sh in shapes where sh.count >= 4 {
            if FrBoard.isStroke(sh) {
                clip.addPath(FrBoard.strokePath(sh, rect.size).strokedPath(StrokeStyle(lineWidth: CGFloat(FrBoard.width(sh)) * rect.height * 2, lineCap: .round, lineJoin: .round)))
            } else {
                let r = CGFloat(sh[3]) * rect.height
                clip.addPath(FrShapePath(type: FrBoard.geometry(sh)).path(in: CGRect(x: sh[1] * rect.width - r, y: sh[2] * rect.height - r, width: r * 2, height: r * 2)))
            }
        }
        return clip
    }
}

/// one of the four LEDs: lit as long as its horse's output is high (a fast horse: a steady glow)
struct FrLed: View {
    @ObservedObject var meters: Meters
    let h: Int
    var body: some View {
        let v = meters.leds.indices.contains(h) ? meters.leds[h] : 0
        let cv = meters.cv.indices.contains(h) ? meters.cv[h] : 0
        let hue = FrIconView.heat(cv)                                   // (its CV: low cold, high warm)
        Circle()
            .fill(hue.opacity(0.3 + 0.7 * v))
            .shadow(color: hue.opacity(0.8 * v), radius: 3 * v)
            .frame(width: 8, height: 8)
    }
}

/// the camera's live picture (filling, cropped)
struct FrCameraView: UIViewRepresentable {
    let session: AVCaptureSession
    final class V: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> V {
        let v = V(); v.preview.session = session; v.preview.videoGravity = .resizeAspectFill; v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: V, context: Context) { if v.preview.session !== session { v.preview.session = session } }
}


/// the camera over the board: its picture faint everywhere and clear in the shapes, and a soft colour in them
struct FrCameraLayer: View {
    @ObservedObject var state: CameraState
    let session: AVCaptureSession
    let shapes: [[Double]]
    var body: some View {
        GeometryReader { geo in
            let field = geo.size
            ZStack(alignment: .topLeading) {
                FrCameraView(session: session)
                    .frame(width: field.width, height: field.height)
                    .mask(ZStack(alignment: .topLeading) {
                        Rectangle().fill(Color.black.opacity(0.14))
                        FrShapesArea(shapes: shapes).fill(Color.black)
                    })
                Canvas { ctx, s in
                    let g = FrBoard.fieldGrid(state.mosaic, aspect: Double(s.width / max(1, s.height)))
                    guard g.count >= 8, g[0].count >= 16 else { return }
                    ctx.clip(to: FrShapesArea(shapes: shapes).path(in: CGRect(origin: .zero, size: s)))
                    let cw = s.width / 16, ch = s.height / 8
                    let drift = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40) / 40
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: max(cw, ch) * 0.9))
                        for r in -1...8 { for c in -1...16 {
                            let b = g[min(7, max(0, r))][min(15, max(0, c))]
                            let hue = (0.58 - 0.50 * b + drift + Double(c) * 0.004).truncatingRemainder(dividingBy: 1)
                            l.fill(Path(CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw + 1, height: ch + 1)),
                                   with: .color(Color(hue: hue < 0 ? hue + 1 : hue, saturation: 0.30 + 0.45 * b, brightness: 1.0).opacity(0.30 + 0.25 * b)))
                        } }
                    }
                }
                .frame(width: field.width, height: field.height)
            }
        }
    }
}

/// an icon: its board's colour as its frame, and — when it is joined — a colour for the current it passes, cold to warm
struct FrIconView: View {
    @ObservedObject var meters: Meters
    let i: Int
    let level: Double
    let size: CGFloat
    let grabbed: Bool

    /// 0 … 1 → blue … cyan … green … yellow … red
    static func heat(_ a: Double) -> Color { Color(hue: 0.62 * (1 - a), saturation: 0.72, brightness: 0.93) }

    var body: some View {
        let k = FrBoard.kind(i), n = FrBoard.nodes[i], s = size
        let a = meters.activity.indices.contains(i) ? meters.activity[i] : 0
        let on = level > 0 || a > 0
        let heat = Self.heat(a)
        ZStack {
            if k < 11 {                                                              // a horse's node: its frame its board's colour
                RoundedRectangle(cornerRadius: s * 0.2).fill(on ? heat : FrBoard.paper)
                RoundedRectangle(cornerRadius: s * 0.2).strokeBorder(FrBoard.frameInk(n), lineWidth: 0.8)
                FrGlyph(role: k)
                    .stroke(FrBoard.ink.opacity(0.85), style: StrokeStyle(lineWidth: 1.0, lineJoin: .round))
                    .padding(s * 0.2)
            } else if k < 16 {                                                       // INTERSEXON: round, a yellow frame
                Circle().fill(on ? heat : FrBoard.paper)
                Circle().strokeBorder(FrBoard.frameInk(n), lineWidth: 1.2)
                FrGlyph(role: k)
                    .stroke(FrBoard.ink.opacity(0.85), style: StrokeStyle(lineWidth: 1.0, lineJoin: .round))
                    .padding(s * 0.26)
            } else {                                                                 // a terminal: a filled square in its own colour
                RoundedRectangle(cornerRadius: s * 0.2).fill(FrBoard.termInk(n))
                if on { RoundedRectangle(cornerRadius: s * 0.2).strokeBorder(heat, lineWidth: 2.2) }
                FrTermGlyph(node: n)
                    .stroke(FrBoard.paper, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .padding(s * 0.16)
            }
        }
        .frame(width: s, height: s)
        .scaleEffect(grabbed ? 1.3 : 1)
    }
}

/// the boards' places, faintly: corner ticks and names (where SORT puts them)
struct FrRegionMarks: View {
    /// the icons where they are: each board's corners drawn round its own icons (so they always meet), and only when
    /// the boards lie apart (SORT) — scattered, the corners would only cross each other
    let icons: [[Double]]
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let arp = box({ $0 >= 200 && $0 < 244 }, w, h)
            let tarp = box({ $0 < 44 }, w, h)
            let inter = box({ $0 >= 300 && $0 < 346 }, w, h)
            let apart: Bool = !arp.intersects(tarp) && !arp.intersects(inter) && !tarp.intersects(inter)
            let areas: [(String, Color, CGRect)] = [("ARP", FrBoard.blue, arp), ("TARP", FrBoard.ink, tarp), ("INTER", Color(hex: 0xD9A627), inter)]
            if apart {
                ForEach(areas.indices, id: \.self) { k in
                    let r = areas[k].2
                    HudCorners(arm: 8)
                        .stroke(areas[k].1.opacity(0.35), lineWidth: 1)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                    Text(areas[k].0)
                        .font(.hud(6.5, .semibold))
                        .tracking(1.2)
                        .foregroundStyle(areas[k].1.opacity(0.45))
                        .position(x: r.minX + 18, y: r.minY - 7)
                }
            }
        }
    }

    /// the box round a board's icons, with room for the icons themselves
    private func box(_ which: (Int) -> Bool, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        var x0 = CGFloat.greatestFiniteMagnitude, y0 = x0, x1 = -x0, y1 = -x0
        for i in 0..<min(FrBoard.count, icons.count) where which(FrBoard.nodes[i]) && icons[i].count >= 2 {
            let x = CGFloat(icons[i][0]) * w, y = CGFloat(icons[i][1]) * h
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        }
        guard x1 >= x0 else { return .zero }
        let pad: CGFloat = max(14, min(24, h * 0.068)) * 0.5 + 6
        return CGRect(x: x0 - pad, y: y0 - pad, width: x1 - x0 + 2 * pad, height: y1 - y0 + 2 * pad)
    }
}


// MARK: - the tools above the board: DRAW's four, DUB, the mode

/// one size for every tool
enum Tool {
    static let w: CGFloat = 44                                 // (near the keys above, and inside the screen)
    static let h: CGFloat = 18
    static let font = Font.hud(7, .semibold)
}

/// a tool: filled when on; its content in the middle
struct ToolPill<Content: View>: View {
    let ink: Color
    var on = false
    var dim = false
    /// DRAW's: a black edge, its colour inside (pale, full when on)
    var black = false
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .font(Tool.font)
            .tracking(0.3)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(black ? FrBoard.ink : (on ? FrBoard.paper : ink))
            .frame(width: Tool.w, height: Tool.h)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(black ? ink.opacity(on ? 0.85 : 0.28) : (on ? ink : Color.clear)))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(black ? FrBoard.ink : ink, lineWidth: 1))
            .opacity(dim ? 0.4 : 1)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

struct BoardToolbar: View {
    let d: Director
    @ObservedObject var rig: Rig
    @State private var lastShape = 0                                    // (○ △ □: the one the shape tool comes back to)
    var body: some View {
        ZStack {                                                        // (the mode laid over the bar's exact middle: DRAW under CLEAR)
            HStack(spacing: 10) {
                drawTools
                Spacer(minLength: 0)
                dubTools
            }
            modeSwitch
        }
    }

    /// DRAW: a tap takes the next (and brings DRAW on)
    private var drawTools: some View {
        let drawing = rig.frMode == 1
        let ink = FrBoard.shapeInk(rig.frShapes.count)
        let lining = rig.frShape >= 3
        return HStack(spacing: 4) {
            // shapes: ○ → △ → □ (a tap when a line is on comes back to the last shape)
            ToolPill(ink: ink, on: drawing && !lining, action: { next {
                if lining { rig.frShape = lastShape } else { rig.frShape = (rig.frShape + 1) % 3; lastShape = rig.frShape }
            } }) {
                Text(FrBoard.shapeNames[lining ? lastShape : rig.frShape]).font(.system(size: 11))
            }
            // lines: ✎ free · a straight line (solid / long / short dashes) · its width (four)
            HStack(spacing: 4) {
                // the line's kind, one key: ✎ free → ─ straight → long dashes → short dashes (a tap again: the next)
                let lk: Int = rig.frShape == 4 ? 0 : 1 + min(2, rig.drawDash)
                MiniKey(ink: ink, on: drawing && lining, action: { next {
                    if !lining { rig.frShape = 4 }
                    else {
                        let n = (lk + 1) % 4
                        if n == 0 { rig.frShape = 4 } else { rig.frShape = 3; rig.drawDash = n - 1 }
                    }
                } }) {
                    if !lining || lk == 0 {
                        Text(FrBoard.shapeNames[4]).font(.system(size: 11))
                    } else {
                        Path { p in p.move(to: CGPoint(x: 1, y: 4)); p.addLine(to: CGPoint(x: 21, y: 4)) }
                            .stroke(style: FrBoard.strokeStyle(dash: lk - 1, 1.6))
                            .frame(width: 22, height: 8)
                    }
                }
                let wk: Int = min(rig.drawWidth, FrBoard.lineWidths.count - 1)
                MiniKey(ink: ink, on: false, action: { next { rig.drawWidth = (wk + 1) % FrBoard.lineWidths.count; if !lining { rig.frShape = 4 } } }) {
                    Capsule().frame(width: 22, height: max(0.8, CGFloat(FrBoard.lineWidths[wk]) * 90))
                }
                .opacity(drawing && lining ? 1 : 0.45)
            }
            ToolPill(ink: FrBoard.red, on: rig.drawFlick > 0, dim: !drawing, action: { next { rig.drawFlick = (rig.drawFlick + 1) % FrBoard.flickNames.count } }) {
                Text("◌ " + FrBoard.flickNames[rig.drawFlick])
            }
            ToolPill(ink: FrBoard.blue, on: rig.drawSway > 0, dim: !drawing, action: { next { rig.drawSway = (rig.drawSway + 1) % FrBoard.swayNames.count } }) {
                Text("◉ " + FrBoard.swayNames[rig.drawSway])
            }
        }
    }

    /// PLAY · DRAW · EDIT
    private var modeSwitch: some View {
        HStack(spacing: 4) {                                              // (black edges, each its colour inside: full when chosen)
            ForEach(0..<3, id: \.self) { m in
                let tint: Color = [FrBoard.green, FrBoard.red, FrBoard.blue][m]
                Text(["PLAY", "DRAW", "EDIT"][m])
                    .font(.hud(8.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(rig.frMode == m ? FrBoard.paper : tint)
                    .frame(width: 46, height: 20)
                    .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(rig.frMode == m ? tint : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(tint, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { rig.frMode = m }
            }
        }
    }

    /// DUB: the filters at the end, on the right
    private var dubTools: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                DubSlider(label: "FREQ\nA", value: rig.dubFreq[0]) { d.setDubFreq(0, $0) }
                DubSlider(label: "RES\nA", value: rig.dubRes[0]) { d.setDubRes(0, $0) }
                DubSlider(label: "FREQ\nB", value: rig.dubFreq[1]) { d.setDubFreq(1, $0) }
                DubSlider(label: "RES\nB", value: rig.dubRes[1]) { d.setDubRes(1, $0) }
            }
            .opacity(rig.dubOn ? 1 : 0.4)
            ToolPill(ink: FrBoard.green, on: rig.dubOn, action: { d.setDubOn(!rig.dubOn) }) { Text("DUB") }
        }
    }

    /// a DRAW tool: changes what it shows, and takes DRAW
    private func next(_ change: () -> Void) {
        change()
        if rig.frMode != 1 { rig.frMode = 1 }
    }
}

/// a small key (a line's kind, its width): its colour's edge, filled when chosen
struct MiniKey<Content: View>: View {
    let ink: Color
    var on = false
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .foregroundStyle(on ? FrBoard.paper : ink)
            .frame(width: Tool.w, height: Tool.h)                       // (as wide as every other tool)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(on ? ink : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(ink, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

/// DUB's knobs: a small knob, its name beside it
struct DubSlider: View {
    let label: String
    let value: Double
    let set: (Double) -> Void
    var body: some View {
        HStack(spacing: 3) {
            Knob(value: value, tint: FrBoard.green, size: 26) { set($0) }
            Text(label)
                .font(.hud(6.5, .semibold))
                .tracking(0.4)
                .lineLimit(2)
                .foregroundStyle(FrBoard.ink)
                .fixedSize()
        }
    }
}

/// the terminals' marks: OUT — a speaker facing out (L left, R right) · DUB — a band-pass hump with + or − ·
/// CAFE — a cup
struct FrTermGlyph: Shape {
    let node: Int
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), s = min(r.width, r.height) / 2
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: c.x + x * s, y: c.y - y * s) }
        if node == 90 || node == 91 {                              // a cup and its saucer (B: steam over it)
            p.move(to: pt(-0.55, 0.45)); p.addLine(to: pt(-0.45, -0.35)); p.addLine(to: pt(0.35, -0.35)); p.addLine(to: pt(0.45, 0.45))
            p.closeSubpath()
            p.move(to: pt(0.45, 0.3)); p.addQuadCurve(to: pt(0.4, -0.05), control: pt(0.85, 0.15))
            p.move(to: pt(-0.8, -0.6)); p.addLine(to: pt(0.7, -0.6))
            if node == 91 { p.move(to: pt(-0.1, 0.65)); p.addQuadCurve(to: pt(0.0, 0.95), control: pt(0.15, 0.8)) }
        } else if node == 46 || node == 47 {
            let d: Double = node == 46 ? -1 : 1                      // (the way it faces)
            p.addRect(CGRect(x: min(pt(-0.55 * d, 0.3).x, pt(-0.2 * d, 0.3).x), y: pt(0, 0.3).y, width: s * 0.35, height: s * 0.6))
            p.move(to: pt(-0.2 * d, 0.3)); p.addLine(to: pt(0.35 * d, 0.75)); p.addLine(to: pt(0.35 * d, -0.75)); p.addLine(to: pt(-0.2 * d, -0.3))
            p.move(to: pt(0.6 * d, 0.35)); p.addQuadCurve(to: pt(0.6 * d, -0.35), control: pt(0.85 * d, 0))
        } else {
            // a hump (the band it lets through)
            p.move(to: pt(-0.9, -0.6))
            p.addCurve(to: pt(0, 0.45), control1: pt(-0.4, -0.6), control2: pt(-0.3, 0.45))
            p.addCurve(to: pt(0.9, -0.6), control1: pt(0.3, 0.45), control2: pt(0.4, -0.6))
            // + (A+ 81, B+ 83) or − (A− 80, B− 82): the frequency up or down
            p.move(to: pt(0.35, 0.8)); p.addLine(to: pt(0.85, 0.8))
            if node == 81 || node == 83 { p.move(to: pt(0.6, 0.55)); p.addLine(to: pt(0.6, 1.0)) }
        }
        return p
    }
}
}
