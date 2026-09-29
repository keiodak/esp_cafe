// FoursesBoard.swift — coco duo (k.odk)
// FOURSES (BLE mode 7): crucFX's TARPTERGE (Cafe A) / ARPSERGE (Cafe B) as one open board over the whole pad area.
// Its 44 touch nodes (Blasser's glyphs) and four terminals (IN · EARTH · OUT L · OUT R) are icons lying on it.
// DRAW: a drag draws a shape (circle · triangle · square; the drag sets its size) or a line (from where the drag
//   starts to where it ends: every icon it passes over) — every icon inside a shape is
//   joined (a wire, 2K), shapes that overlap join their icons too. A tap on a shape takes it away.
// EDIT: the icons (and the shapes) are moved by dragging them. RANDOM throws the icons across the board.
// PLAY: a finger joins what it covers — lightly (a tip, ~10M) or flat (~20K) — and the body hums.
// The four pots are sliders along the bottom.

import SwiftUI
import UIKit

enum FrBoard {
    /// 0 capacitor · 1 buffer · 2 pulse · 3 threshold · 4 gate · 5 gate, inverted · 6 / 7 bounds · 8 / 9 / 10 the rate ladder
    static let role: [Int] = [4, 3, 2, 1, 0, 7, 9, 10, 8, 5, 6, 4, 3, 2, 1, 0, 9, 10, 8, 7, 5, 6, 4, 3, 2, 1, 0, 7, 9, 10, 8, 5, 6, 4, 3, 2, 1, 0, 9, 10, 8, 7, 5, 6]
    static let horse: [Int] = [0, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0]
    static let terms = ["IN", "EARTH", "OUT L", "OUT R"]
    /// the terminals' colours: what comes in (IN, EARTH, LINK IN) · what goes out (OUT, LINK OUT)
    static let inInk = Color(hex: 0x3D5566)
    static let outInk = Color(hex: 0x5B6B2E)
    /// the shapes: a light blue
    static let shapeBlue = Color(hex: 0x6FA8DC)
    /// the icons are these nodes: the board (0…43), the terminals (44…47), INTERSEXON's half (53…72: four sample &
    /// holds' IN · GATE · OUT, four current cells' SOURCE △ · SINK ▽), LINK OUT / IN (73 / 74: to / from the other Cafe)
    static let nodes: [Int] = Array(0..<48) + Array(53..<80)
    /// the outputs are each Cafe's own: MAIN / ASH / YELLOW A (46 · 47 · 76 on Cafe A) and B (77 · 78 · 79 here, 46 · 47 · 76
    /// on Cafe B); a Cafe is never sent the other's
    static let outputs: Set<Int> = [46, 47, 73, 76, 77, 78, 79]
    static let count = nodes.count
    /// what an icon is: < 44 a Fourses glyph (role) · 44…47 a terminal · 11 S&H IN · 12 S&H GATE · 13 S&H OUT ·
    /// 14 SOURCE · 15 SINK · 16 an input terminal (IN, EARTH, LINK IN) · 17 an output (OUT, LINK OUT)
    static func kind(_ i: Int) -> Int {
        let n = nodes[i]
        if n < 44 { return role[n] }
        if outputs.contains(n) { return 17 }                            // an output terminal
        if n < 48 || n >= 73 { return 16 }                              // an input terminal
        if n < 57 { return 11 }; if n < 61 { return 12 }; if n < 65 { return 13 }
        return (n - 65) % 2 == 0 ? 14 : 15
    }
    static func label(_ i: Int) -> String {
        let n = nodes[i]
        if n < 44 { return "" }
        if n == 45 { return "EARTH A" }; if n == 75 { return "EARTH B" }      // (Cafe A's, Cafe B's: each Cafe gets the other's by the phone)
        if n == 46 { return "MAIN A" }; if n == 47 { return "ASH A" }; if n == 76 { return "YELLOW A" }
        if n == 77 { return "MAIN B" }; if n == 78 { return "ASH B" }; if n == 79 { return "YELLOW B" }
        if n < 48 { return terms[n - 44] }
        if n == 73 { return "LINK OUT" }; if n == 74 { return "LINK IN" }
        let sh = ["A", "B", "C", "D"]
        if n < 65 { return sh[(n - 53) % 4] }
        return ["D→A", "A→D", "B→C", "C→B"][(n - 65) / 2]
    }
    static let shapeNames = ["○", "△", "□", "／"]
    /// the free field (the sliders take the bottom)
    static let yMax = 0.84
    static func buf(_ h: Int) -> Int { (0..<44).first { role[$0] == 1 && horse[$0] == h } ?? 0 }
    static func icon(ofNode n: Int) -> Int { nodes.firstIndex(of: n) ?? 0 }

    /// the icons thrown across the board, none on another (their boxes kept apart, in heights: aspect = width / height)
    static func scatter(seed: UInt64? = nil, aspect: Double = 2.5) -> [[Double]] {
        var s = seed ?? UInt64.random(in: 1...UInt64.max)
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
        let a = max(0.5, aspect)
        func ok(_ c: [Double]) -> Bool { !((c[0] < 0.36 || c[0] > 0.66) && c[1] < 0.17) }       // (the corners: DRAW, the mode)
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
    /// pushed apart until no two icons' boxes overlap
    static func relax(_ o: [[Double]], aspect: Double = 2.5) -> [[Double]] {
        var out = o
        let a = max(0.5, aspect)
        func half(_ i: Int) -> (Double, Double) { kind(i) >= 16 ? (0.15, 0.055) : (0.06, 0.06) }
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
            if !moved { break }
        }
        return out
    }
    /// the first board: scattered, OUT L beside H1's buffer and OUT R beside H3's, each in a circle
    static func defaultLayout() -> (icons: [[Double]], shapes: [[Double]]) {
        var ic = scatter(seed: 7)
        let b0 = ic[buf(0)], b2 = ic[buf(2)]
        ic[icon(ofNode: 46)] = [min(0.95, b0[0] + 0.05), max(0.05, b0[1] - 0.05)]
        ic[icon(ofNode: 77)] = [min(0.95, b0[0] + 0.05), min(yMax - 0.05, b0[1] + 0.05)]
        ic[icon(ofNode: 47)] = [min(0.95, b2[0] + 0.05), max(0.05, b2[1] - 0.05)]
        ic[icon(ofNode: 78)] = [min(0.95, b2[0] + 0.05), min(yMax - 0.05, b2[1] + 0.05)]
        ic = relax(ic)
        // a circle round each buffer and its two outputs (after they were pushed apart)
        func ring(_ m: [Int]) -> [Double] {
            let p = m.map { ic[$0] }
            let cx = p.map { $0[0] }.reduce(0, +) / Double(p.count), cy = p.map { $0[1] }.reduce(0, +) / Double(p.count)
            let r = p.map { hypot(($0[0] - cx) * 2.5, $0[1] - cy) }.max() ?? 0.1
            return [0, cx, cy, r + 0.05]
        }
        let sh = [ring([buf(0), icon(ofNode: 46), icon(ofNode: 77)]), ring([buf(2), icon(ofNode: 47), icon(ofNode: 78)])]
        return (ic, sh)
    }

    /// is (x, y) inside a shape [type, cx, cy, r]? (x scaled by the board's aspect: r is in heights)
    static let lineWidth = 0.035                                        // (a line reaches this far either side, in heights)
    static func inside(_ x: Double, _ y: Double, _ s: [Double], aspect: Double) -> Bool {
        if Int(s[0]) == 3 && s.count >= 5 {                              // a line [3, x1, y1, x2, y2]: near it
            let ax = s[1] * aspect, ay = s[2], bx = s[3] * aspect, by = s[4], px = x * aspect
            let vx = bx - ax, vy = by - ay, L = vx * vx + vy * vy
            let t = L > 0 ? max(0, min(1, ((px - ax) * vx + (y - ay) * vy) / L)) : 0
            return hypot(px - (ax + vx * t), y - (ay + vy * t)) <= lineWidth
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
    /// points on a shape (for overlaps): a line along its length, the others their centre and outline
    static func samples(_ s: [Double], aspect: Double) -> [(Double, Double)] {
        if Int(s[0]) == 3 && s.count >= 5 { return (0...12).map { k in let t = Double(k) / 12; return (s[1] + (s[3] - s[1]) * t, s[2] + (s[4] - s[2]) * t) } }
        var p = [(s[1], s[2])]
        for k in 0..<12 { let a = Double(k) * .pi / 6; p.append((s[1] + cos(a) * s[3] * 0.97 / aspect, s[2] + sin(a) * s[3] * 0.97)) }
        return p.filter { inside($0.0, $0.1, s, aspect: aspect) }
    }
    /// the wires the shapes make, as node pairs
    static func links(icons: [[Double]], shapes: [[Double]], aspect: Double, light: Bool = false) -> [[Int]] {
        var out = iconLinks(icons: icons, shapes: shapes, aspect: aspect).map { [min(nodes[$0[0]], nodes[$0[1]]), max(nodes[$0[0]], nodes[$0[1]]), $0[2]] }
        if light {                                                       // CAMERA: each shape's LIGHT (node 77 + k) on what it covers
            for (k, s) in shapes.prefix(16).enumerated() where s.count >= 4 {
                for i in 0..<min(count, icons.count) {
                    let c = cover(i, icons[i], s, aspect: aspect)
                    if c > 0 { out.append([nodes[i], 77 + k, Int(150 + 850 * c)]) }
                }
            }
        }
        return out
    }
    /// the icons in each shape joined; overlapping shapes joined (a star from the first)
    /// how bright the camera is inside a shape (the 8 × 16 mosaic over the field; 0…1)
    static func light(_ s: [Double], grid: [[Double]], aspect: Double) -> Double {
        guard grid.count >= 8, grid[0].count >= 16 else { return 0.5 }
        var sum = 0.0, n = 0
        for r in 0..<8 { for c in 0..<16 where inside((Double(c) + 0.5) / 16, (Double(r) + 0.5) / 8, s, aspect: aspect) { sum += grid[r][c]; n += 1 } }
        if n > 0 { return sum / Double(n) }
        let r = min(7, max(0, Int(s[2] * 8))), c = min(15, max(0, Int(s[1] * 16)))   // (smaller than a cell: the one under it)
        return grid[r][c]
    }
    /// how much of an icon a shape covers (0…1: 5 × 5 points over the icon)
    static func cover(_ i: Int, _ p: [Double], _ s: [Double], aspect: Double) -> Double {
        let (hw, hh) = kind(i) >= 16 ? (0.15, 0.05) : (0.045, 0.045)       // (half its size, in heights)
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
            // (the star's centre: not an output — each Cafe drops the other's — and the most covered)
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
    @ObservedObject var cam: CameraState
    var camOn: Bool
    @State private var fingers: [Int: (p: CGPoint, r: CGFloat)] = [:]
    @State private var draft: (start: CGPoint, now: CGPoint)? = nil
    @State private var grab: (kind: Int, index: Int, offset: CGSize)? = nil    // EDIT: 0 an icon, 1 a shape

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let field = CGSize(width: size.width, height: size.height * FrBoard.yMax)
            let level: [Int: Double] = {                                  // how hard each icon is joined (0…1): the orange's depth
                var m: [Int: Double] = [:]
                for l in FrBoard.iconLinks(icons: rig.frIcons, shapes: rig.frShapes, aspect: aspect(field)) {
                    let v = Double(l[2]) / 1000
                    m[l[0]] = max(m[l[0]] ?? 0, v); m[l[1]] = max(m[l[1]] ?? 0, v)
                }
                return m
            }()
            ZStack(alignment: .topLeading) {
                // the board: paper, a fine dot grid (CAMERA: the mosaic under it — each shape's LIGHT is its brightness)
                Rectangle().fill(PastelTheme.padScreen)
                if camOn {                                                   // CAMERA: the light, only inside the shapes
                    Canvas { ctx, s in
                        let g = cam.mosaicBrightness
                        guard g.count >= 8, g[0].count >= 16 else { return }
                        let fh = s.height * FrBoard.yMax
                        var clip = Path()
                        for sh in rig.frShapes where sh.count >= 4 {
                            if Int(sh[0]) == 3 && sh.count >= 5 {
                                var l = Path()
                                l.move(to: CGPoint(x: sh[1] * s.width, y: sh[2] * fh)); l.addLine(to: CGPoint(x: sh[3] * s.width, y: sh[4] * fh))
                                clip.addPath(l.strokedPath(StrokeStyle(lineWidth: CGFloat(FrBoard.lineWidth) * fh * 2, lineCap: .round)))
                            } else {
                                let r = CGFloat(sh[3]) * fh
                                clip.addPath(FrShapePath(type: Int(sh[0])).path(in: CGRect(x: sh[1] * s.width - r, y: sh[2] * fh - r, width: r * 2, height: r * 2)))
                            }
                        }
                        ctx.clip(to: clip)
                        let cw = s.width / 16, ch = fh / 8
                        for r in 0..<8 { for c in 0..<16 {
                            let b = g[r][c]
                            ctx.fill(Path(CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw + 0.5, height: ch + 0.5)),
                                     with: .color(Color(hue: 0.58, saturation: 0.15 + 0.45 * (1 - b), brightness: 0.30 + 0.70 * b).opacity(0.85)))   // (dark: deep blue · bright: a light)
                        } }
                    }
                }
                Canvas { ctx, s in
                    let step: CGFloat = 16
                    for x in stride(from: step / 2, to: s.width, by: step) {
                        for y in stride(from: step / 2, to: s.height * FrBoard.yMax, by: step) {
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)), with: .color(PastelTheme.hudDot.opacity(0.5)))
                        }
                    }
                }
                // the shapes
                ForEach(Array(rig.frShapes.enumerated()), id: \.offset) { k, s in
                    if Int(s[0]) == 3 && s.count >= 5 {
                        let live = FrBoard.links(icons: rig.frIcons, shapes: [s], aspect: aspect(field)).count > 0
                        Path { p in p.move(to: view(s[1], s[2], field)); p.addLine(to: view(s[3], s[4], field)) }
                            .stroke(FrBoard.shapeBlue.opacity(live ? 0.22 : 0.10), style: StrokeStyle(lineWidth: CGFloat(FrBoard.lineWidth) * field.height * 2, lineCap: .round))
                        Path { p in p.move(to: view(s[1], s[2], field)); p.addLine(to: view(s[3], s[4], field)) }
                            .stroke(FrBoard.shapeBlue.opacity(live ? 1 : 0.6), style: StrokeStyle(lineWidth: live ? 1.6 : 1, lineCap: .round, dash: live ? [] : [3, 3]))
                    } else if s.count == 4 {
                        let c = view(s[1], s[2], field), r = CGFloat(s[3]) * field.height
                        let live = FrBoard.links(icons: rig.frIcons, shapes: [s], aspect: aspect(field)).count > 0
                        FrShapePath(type: Int(s[0]))
                            .fill(FrBoard.shapeBlue.opacity(live ? 0.18 : 0.08))
                            .overlay(FrShapePath(type: Int(s[0])).stroke(FrBoard.shapeBlue.opacity(live ? 1 : 0.6),
                                                                      style: StrokeStyle(lineWidth: live ? 1.4 : 1, dash: live ? [] : [3, 3])))
                            .frame(width: r * 2, height: r * 2)
                            .position(c)
                    }
                }
                if let dr = draft, rig.frShape == 3 {
                    Path { p in p.move(to: dr.start); p.addLine(to: dr.now) }
                        .stroke(FrBoard.shapeBlue, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [4, 3]))
                } else if let dr = draft {
                    let r = hypot(dr.now.x - dr.start.x, dr.now.y - dr.start.y)
                    FrShapePath(type: rig.frShape)
                        .stroke(FrBoard.shapeBlue, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .frame(width: r * 2, height: r * 2).position(dr.start)
                }
                // the icons
                ForEach(0..<FrBoard.count, id: \.self) { i in
                    icon(i, level: touched(i, field) ? 1 : (level[i] ?? 0), field: field)
                }
                // the fingers
                ForEach(Array(fingers.keys), id: \.self) { f in
                    if let t = fingers[f] {
                        Circle().fill(PastelTheme.hudOrange.opacity(0.08))
                            .overlay(Circle().strokeBorder(PastelTheme.hudOrange.opacity(0.6), lineWidth: 1))
                            .frame(width: reach(t.r) * 2, height: reach(t.r) * 2).position(t.p)
                    }
                }
                FrTouchLayer { ts in touches(ts, field) }
                    .frame(width: field.width, height: field.height)
                // DRAW: which shape
                if rig.frMode == 1 {
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { k in
                            Text(FrBoard.shapeNames[k])
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(rig.frShape == k ? PastelTheme.selectionText : PastelTheme.hudBlack)
                                .frame(width: 30, height: 22)
                                .background(rig.frShape == k ? PastelTheme.hudBlack : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { rig.frShape = k }
                        }
                    }
                    .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
                    .padding(6)
                }
                // the mode: PLAY · DRAW · EDIT, always there (top right)
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { m in
                        Text(["PLAY", "DRAW", "EDIT"][m])
                            .font(.hud(8, .semibold))
                            .foregroundStyle(rig.frMode == m ? PastelTheme.selectionText : PastelTheme.hudBlack)
                            .frame(width: 40, height: 22)
                            .background(rig.frMode == m ? PastelTheme.hudBlack : PastelTheme.padScreen)
                            .contentShape(Rectangle())
                            .onTapGesture { rig.frMode = m }
                    }
                }
                .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
                .padding(6)
                .frame(width: size.width, alignment: .trailing)
                // the pots: four sliders along the bottom
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { h in slider(h) }
                }
                .padding(.horizontal, 10)
                .frame(width: size.width, height: size.height * (1 - FrBoard.yMax))
                .offset(y: size.height * FrBoard.yMax)
                Rectangle().fill(PastelTheme.hudLine).frame(width: size.width, height: 1).offset(y: size.height * FrBoard.yMax)
            }
            .clipped()
            .overlay(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
            .onAppear { d.frAspect = aspect(field) }
            .onChange(of: size) { _, s in d.frAspect = aspect(CGSize(width: s.width, height: s.height * FrBoard.yMax)) }
        }
    }

    // MARK: pieces

    private func icon(_ i: Int, level: Double, field: CGSize) -> some View {
        let lit = level > 0, deep = level > 0.55
        let orange = PastelTheme.hudOrange.opacity(0.2 + 0.8 * level)
        let p = rig.frIcons.indices.contains(i) ? rig.frIcons[i] : [0.5, 0.5]
        let q = view(p[0], p[1], field), s = iconSize(field)
        let k = FrBoard.kind(i)
        return ZStack {
            if k < 11 {
                RoundedRectangle(cornerRadius: 3).fill(PastelTheme.padScreen)
                if lit { RoundedRectangle(cornerRadius: 3).fill(orange) }
                RoundedRectangle(cornerRadius: 3).strokeBorder(lit ? PastelTheme.hudOrange : PastelTheme.hudBlack.opacity(0.55), lineWidth: 1)
                FrGlyph(role: k)
                    .stroke(deep ? PastelTheme.selectionText : PastelTheme.hudBlack, style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
                    .padding(s * 0.18)
            } else if k < 16 {                                                     // INTERSEXON: round
                Circle().fill(PastelTheme.padScreen)
                if lit { Circle().fill(orange) }
                Circle().strokeBorder(lit ? PastelTheme.hudOrange : PastelTheme.hudBlack.opacity(0.55), lineWidth: 1)
                FrGlyph(role: k)
                    .stroke(deep ? PastelTheme.selectionText : PastelTheme.hudBlack, style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
                    .padding(s * 0.22)
            } else {
                let out = k == 17
                Text(FrBoard.label(i))
                    .font(.hud(8, .semibold))
                    .foregroundStyle(PastelTheme.selectionText)
                    .padding(.horizontal, 5)
                    .frame(height: s * 0.8)
                    .background(ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(out ? FrBoard.outInk : FrBoard.inInk)
                        if lit { RoundedRectangle(cornerRadius: 3).fill(orange) }
                    })
                    .fixedSize()
            }
        }
        .frame(width: k < 16 ? s : nil, height: k < 16 ? s : nil)
        .scaleEffect(grab?.kind == 0 && grab?.index == i ? 1.25 : 1)
        .position(q)
        .allowsHitTesting(false)
    }

    private func slider(_ h: Int) -> some View {
        let v = rig.frPots[h]
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text("H\(h + 1)")
                    .font(.hud(7, .semibold))
                    .foregroundStyle(PastelTheme.textSecondary)
                // its range switch: AUDIO · LOW · CV (a tap: the next)
                Text(["CV", "LOW", "AUDIO"][rig.frRanges[h]])
                    .font(.hud(7, .semibold))
                    .foregroundStyle(rig.frRanges[h] < 2 ? PastelTheme.selectionText : PastelTheme.hudBlack)
                    .padding(.horizontal, 4).frame(height: 12)
                    .background(Rectangle().fill(rig.frRanges[h] < 2 ? PastelTheme.hudBlack : Color.clear))
                    .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { d.setFrRange(h, (rig.frRanges[h] + 2) % 3) }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(PastelTheme.trackOff).frame(height: 2)
                    Rectangle().fill(PastelTheme.hudBlack).frame(width: g.size.width * v, height: 2)
                    Rectangle().fill(PastelTheme.hudBlack).frame(width: 1, height: 8).position(x: g.size.width * 0.5, y: g.size.height / 2).opacity(0.35)
                    Rectangle().fill(PastelTheme.hudOrange).frame(width: 4, height: 12)
                        .position(x: g.size.width * v, y: g.size.height / 2)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { e in
                    d.setFrPot(h, min(1, max(0, e.location.x / max(1, g.size.width))))
                })
            }
        }
        .frame(maxHeight: 30)
    }

    // MARK: geometry

    private func aspect(_ f: CGSize) -> Double { Double(f.width / max(1, f.height)) }
    private func view(_ x: Double, _ y: Double, _ f: CGSize) -> CGPoint { CGPoint(x: x * f.width, y: y * f.height) }
    private func norm(_ p: CGPoint, _ f: CGSize) -> [Double] {
        [min(0.98, max(0.02, Double(p.x / f.width))), min(0.98, max(0.02, Double(p.y / f.height)))]
    }
    private func iconSize(_ f: CGSize) -> CGFloat { max(16, min(26, f.height * 0.085)) }
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
            if draft == nil { draft = (t.p, t.p) } else { draft!.now = t.p }
            if t.ended, let dr = draft {
                let r = hypot(dr.now.x - dr.start.x, dr.now.y - dr.start.y)
                if r < 10 { if let k = shapeAt(dr.start, f) { d.frRemoveShape(k) } }         // a tap: the shape goes
                else if rig.frShape == 3 { let a = norm(dr.start, f), b = norm(dr.now, f); d.frAddShape([3, a[0], a[1], b[0], b[1]]) }
                else { let c = norm(dr.start, f); d.frAddShape([Double(rig.frShape), c[0], c[1], Double(r / f.height)]) }
                draft = nil
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
            }
            if let g = grab {
                let n = norm(CGPoint(x: t.p.x + g.offset.width, y: t.p.y + g.offset.height), f)
                if g.kind == 0 { rig.frIcons[g.index] = n }
                else if rig.frShapes.indices.contains(g.index) {
                    var sh = rig.frShapes[g.index]
                    if Int(sh[0]) == 3 && sh.count >= 5 { sh[3] += n[0] - sh[1]; sh[4] += n[1] - sh[2] }   // (a line: both ends)
                    sh[1] = n[0]; sh[2] = n[1]
                    rig.frShapes[g.index] = sh
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
