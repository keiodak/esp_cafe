// FoursesBoard.swift — coco duo (k.odk)
// FOURSES (BLE mode 7): crucFX's TARPTERGE (Cafe A) / ARPSERGE (Cafe B) as one open board over the whole pad area.
// Its 44 touch nodes (Blasser's glyphs) and four terminals (IN · EARTH · OUT L · OUT R) are icons lying on it.
// DRAW: a drag draws a shape (circle · triangle · square; the drag sets its size) — every icon inside a shape is
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
    static let count = 48
    static let shapeNames = ["○", "△", "□"]
    /// the free field (the sliders take the bottom)
    static let yMax = 0.84
    static func buf(_ h: Int) -> Int { (0..<44).first { role[$0] == 1 && horse[$0] == h } ?? 0 }

    /// the icons thrown across the board (none too near another)
    static func scatter(seed: UInt64? = nil) -> [[Double]] {
        var s = seed ?? UInt64.random(in: 1...UInt64.max)
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
        var out: [[Double]] = []
        for _ in 0..<count {
            var best = [0.5, 0.5], bestD = -1.0
            for _ in 0..<24 {                                            // (the candidate farthest from the others)
                let c = [0.05 + rnd() * 0.90, 0.07 + rnd() * (yMax - 0.12)]
                let d = out.map { hypot(($0[0] - c[0]) * 2, $0[1] - c[1]) }.min() ?? 1
                if d > bestD { bestD = d; best = c }
            }
            out.append(best)
        }
        return out
    }
    /// the first board: scattered, OUT L beside H1's buffer and OUT R beside H3's, each in a circle
    static func defaultLayout() -> (icons: [[Double]], shapes: [[Double]]) {
        var ic = scatter(seed: 7)
        let b0 = ic[buf(0)], b2 = ic[buf(2)]
        ic[46] = [min(0.95, b0[0] + 0.06), b0[1]]
        ic[47] = [min(0.95, b2[0] + 0.06), b2[1]]
        let sh = [[0, b0[0] + 0.03, b0[1], 0.09], [0, b2[0] + 0.03, b2[1], 0.09]]
        return (ic, sh)
    }

    /// is (x, y) inside a shape [type, cx, cy, r]? (x scaled by the board's aspect: r is in heights)
    static func inside(_ x: Double, _ y: Double, _ s: [Double], aspect: Double) -> Bool {
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
    /// the wires the shapes make: the icons in each shape joined; overlapping shapes joined (a star from the first)
    static func links(icons: [[Double]], shapes: [[Double]], aspect: Double) -> [[Int]] {
        var parent = Array(0..<(count + shapes.count))
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        func join(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }
        var hasIcon = [Bool](repeating: false, count: shapes.count)
        for (k, s) in shapes.enumerated() where s.count == 4 {
            for i in 0..<count where i < icons.count && inside(icons[i][0], icons[i][1], s, aspect: aspect) {
                join(i, count + k); hasIcon[k] = true
            }
        }
        for a in 0..<shapes.count { for b in (a + 1)..<shapes.count {        // (overlapping: centres closer than the radii)
            let s = shapes[a], t = shapes[b]
            if hypot((s[1] - t[1]) * aspect, s[2] - t[2]) < (s[3] + t[3]) * 0.9 { join(count + a, count + b) }
        } }
        var groups: [Int: [Int]] = [:]
        for i in 0..<count { groups[find(i), default: []].append(i) }
        var out: [[Int]] = []
        for (_, g) in groups where g.count >= 2 { for m in g.dropFirst() { out.append([min(g[0], m), max(g[0], m)]) } }
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
        default:                                                     // three bars: the ladder's middle
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
    @State private var fingers: [Int: (p: CGPoint, r: CGFloat)] = [:]
    @State private var draft: (start: CGPoint, now: CGPoint)? = nil
    @State private var grab: (kind: Int, index: Int, offset: CGSize)? = nil    // EDIT: 0 an icon, 1 a shape

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let field = CGSize(width: size.width, height: size.height * FrBoard.yMax)
            let sounding = Set(FrBoard.links(icons: rig.frIcons, shapes: rig.frShapes, aspect: aspect(field)).flatMap { $0 })
            ZStack(alignment: .topLeading) {
                // the board: paper, a fine dot grid
                Rectangle().fill(PastelTheme.padScreen)
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
                    if s.count == 4 {
                        let c = view(s[1], s[2], field), r = CGFloat(s[3]) * field.height
                        let live = FrBoard.links(icons: rig.frIcons, shapes: [s], aspect: aspect(field)).count > 0
                        FrShapePath(type: Int(s[0]))
                            .fill(PastelTheme.hudOrange.opacity(live ? 0.10 : 0.04))
                            .overlay(FrShapePath(type: Int(s[0])).stroke(live ? PastelTheme.hudOrange : PastelTheme.hudBlack.opacity(0.45),
                                                                      style: StrokeStyle(lineWidth: live ? 1.4 : 1, dash: live ? [] : [3, 3])))
                            .frame(width: r * 2, height: r * 2)
                            .position(c)
                    }
                }
                if let dr = draft {
                    let r = hypot(dr.now.x - dr.start.x, dr.now.y - dr.start.y)
                    FrShapePath(type: rig.frShape)
                        .stroke(PastelTheme.hudOrange, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .frame(width: r * 2, height: r * 2).position(dr.start)
                }
                // the icons
                ForEach(0..<FrBoard.count, id: \.self) { i in
                    icon(i, lit: sounding.contains(i) || touched(i, field), field: field)
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
                        ForEach(0..<3, id: \.self) { k in
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

    private func icon(_ i: Int, lit: Bool, field: CGSize) -> some View {
        let p = rig.frIcons.indices.contains(i) ? rig.frIcons[i] : [0.5, 0.5]
        let q = view(p[0], p[1], field), s = iconSize(field)
        return ZStack {
            if i < 44 {
                RoundedRectangle(cornerRadius: 3).fill(lit ? PastelTheme.hudOrange : PastelTheme.padScreen)
                RoundedRectangle(cornerRadius: 3).strokeBorder(lit ? PastelTheme.hudOrange : PastelTheme.hudBlack.opacity(0.55), lineWidth: 1)
                FrGlyph(role: FrBoard.role[i])
                    .stroke(lit ? PastelTheme.selectionText : PastelTheme.hudBlack, style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
                    .padding(s * 0.18)
            } else {
                Text(FrBoard.terms[i - 44])
                    .font(.hud(8, .semibold))
                    .foregroundStyle(lit ? PastelTheme.selectionText : PastelTheme.padScreen)
                    .padding(.horizontal, 5)
                    .frame(height: s * 0.8)
                    .background(RoundedRectangle(cornerRadius: 3).fill(lit ? PastelTheme.hudOrange : PastelTheme.hudBlack))
                    .fixedSize()
            }
        }
        .frame(width: i < 44 ? s : nil, height: i < 44 ? s : nil)
        .scaleEffect(grab?.kind == 0 && grab?.index == i ? 1.25 : 1)
        .position(q)
        .allowsHitTesting(false)
    }

    private func slider(_ h: Int) -> some View {
        let v = rig.frPots[h]
        return VStack(alignment: .leading, spacing: 3) {
            Text("H\(h + 1)")
                .font(.hud(7, .semibold))
                .foregroundStyle(PastelTheme.textSecondary)
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
                if g.kind == 0 { rig.frIcons[g.index] = n } else if rig.frShapes.indices.contains(g.index) { rig.frShapes[g.index][1] = n[0]; rig.frShapes[g.index][2] = n[1] }
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
                    links[48 + fi, default: [:]][i] = Int((150 + firm * 780) * near)
                }
            }
            d.frTouches(links)
        }
    }
}
