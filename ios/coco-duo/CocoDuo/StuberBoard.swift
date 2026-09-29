// StuberBoard.swift — coco duo (k.odk)
// STUBER (BLE mode 9): Blasser's Din Datin Dudero Stuber on a Cafe. Its sandrodes lie on a board between the two big
// wheels (L: the left channel's cutoff, R: the right's), a resonance knob under each (the left one inverso). It sings
// with nothing patched once a resonance passes ~75 %. As on FOURSES: DRAW shapes join the jacks they cover (as hard as
// they cover them), PLAY fingers join what they touch, EDIT moves the jacks and the shapes.
import SwiftUI
import UIKit

enum StBoard {
    /// the jacks, by node (the Cafe's numbers): B · D the audio filters (L · R), A · C the gesture filters, the dividers,
    /// the parasites, the Sh'mance clocks, IN, EARTH
    static let names: [String] = {
        let f = ["LP", "BP", "M+", "M−", "RES", "Q+", "Q−"]
        var n: [String] = []
        for c in ["B", "D", "A", "C"] { n += f.map { c + " " + $0 } }
        n += ["÷2", "÷16", "÷256", "÷4K", "÷2", "÷16", "÷256", "÷4K", "PAR L", "PAR R", "CLK A", "CLK B", "IN", "EARTH"]
        return n
    }()
    static let count = 42
    /// each group its colour: B red · D blue · A orange · C green · the dividers grey (L light, R dark) · parasites violet ·
    /// clocks mustard · IN / EARTH brown
    static func ink(_ i: Int) -> Color {
        switch i {
        case 0..<7: return Color(hex: 0xC0392B)
        case 7..<14: return Color(hex: 0x2E6DA4)
        case 14..<21: return PastelTheme.hudOrange
        case 21..<28: return Color(hex: 0x2E7D4F)
        case 28..<32: return Color(hex: 0x9A9A9A)
        case 32..<36: return Color(hex: 0x5E5E5E)
        case 36, 37: return Color(hex: 0x7B4FA0)
        case 38, 39: return Color(hex: 0xC29A12)
        default: return Color(hex: 0x7A4E2D)
        }
    }
    static let shapeNames = ["○", "△", "□", "／"]
    static let ink0 = Color(hex: 0x6FA8DC)

    static func scatter(seed: UInt64? = nil, aspect: Double = 2.0) -> [[Double]] {
        var s = seed ?? UInt64.random(in: 1...UInt64.max)
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
        let a = max(0.5, aspect)
        func ok(_ c: [Double]) -> Bool { !((c[0] < 0.30 && c[1] < 0.20) || (c[0] > 0.62 && c[1] < 0.16)) }   // (DRAW, the mode)
        var out: [[Double]] = []
        for _ in 0..<count {
            var best = [0.5, 0.5], bestD = -1.0
            for _ in 0..<40 {
                let c = [0.05 + rnd() * 0.90, 0.07 + rnd() * 0.86]
                if !ok(c) { continue }
                let d = out.map { hypot(($0[0] - c[0]) * a, $0[1] - c[1]) }.min() ?? 1
                if d > bestD { bestD = d; best = c }
            }
            out.append(best)
        }
        return out
    }
    /// how much of a jack a shape covers (0…1)
    static func cover(_ p: [Double], _ s: [Double], aspect: Double) -> Double {
        let hw = 0.045, hh = 0.045
        var n = 0
        for a in 0..<5 { for b in 0..<5 {
            let x = p[0] + (Double(a) - 2) / 2 * hw / aspect, y = p[1] + (Double(b) - 2) / 2 * hh
            if FrBoard.inside(x, y, s, aspect: aspect) { n += 1 }
        } }
        return Double(n) / 25
    }
    /// the patches the shapes make: [a, b, strength 0…1000] — the jacks in a shape (and in shapes that overlap) each to
    /// each (a big group: a star from the most covered)
    static func links(icons: [[Double]], shapes: [[Double]], aspect: Double) -> [[Int]] {
        let sh = shapes.filter { $0.count >= 4 }
        var cov = [Double](repeating: 0, count: count)
        var parent = Array(0..<(count + sh.count))
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        func join(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }
        for (k, s) in sh.enumerated() {
            for i in 0..<min(count, icons.count) {
                let c = cover(icons[i], s, aspect: aspect)
                if c > 0 { join(i, count + k); cov[i] = max(cov[i], c) }
            }
        }
        for a in 0..<sh.count { for b in (a + 1)..<sh.count {
            let s = sh[a], t = sh[b]
            if FrBoard.samples(s, aspect: aspect).contains(where: { FrBoard.inside($0.0, $0.1, t, aspect: aspect) })
                || FrBoard.samples(t, aspect: aspect).contains(where: { FrBoard.inside($0.0, $0.1, s, aspect: aspect) }) { join(count + a, count + b) }
        } }
        var groups: [Int: [Int]] = [:]
        for i in 0..<count where cov[i] > 0 { groups[find(i), default: []].append(i) }
        var out: [[Int]] = []
        for (_, g0) in groups where g0.count >= 2 {
            let g = g0.sorted { cov[$0] > cov[$1] }
            let pairs: [(Int, Int)] = g.count <= 6 ? g.indices.flatMap { x in g.indices.filter { $0 > x }.map { (g[x], g[$0]) } }
                                                   : g.dropFirst().map { (g[0], $0) }
            for (a, b) in pairs { out.append([min(a, b), max(a, b), Int(150 + 850 * min(cov[a], cov[b]))]) }
        }
        return Array(out.prefix(120))
    }
}

struct StuberBoard: View {
    let d: Director
    @ObservedObject var rig: Rig
    @State private var fingers: [Int: (p: CGPoint, r: CGFloat)] = [:]
    @State private var draft: (start: CGPoint, now: CGPoint)? = nil
    @State private var grab: (kind: Int, index: Int, offset: CGSize)? = nil
    @State private var grabAt: CGPoint = .zero
    @State private var grabMoved = false

    var body: some View {
        HStack(spacing: 8) {
            side(0)
            board
            side(1)
        }
        .padding(.horizontal, 4)
    }

    /// a wheel, big, and its resonance knob under it
    private func side(_ h: Int) -> some View {
        VStack(spacing: 6) {
            NbKnob(a: rig.stAx[h], y: false) { d.stKnob(h) }
            NbKnob(a: rig.stAx[h], y: true) { d.stKnob(h) }
                .frame(maxWidth: 54, maxHeight: 54)
            Text(h == 0 ? "L" : "R").font(.hud(9, .semibold)).foregroundStyle(PastelTheme.hudBlack)
        }
        .frame(maxWidth: 140)
    }

    private var board: some View {
        GeometryReader { geo in
            let f = geo.size
            let lv: [Int: Double] = {
                var m: [Int: Double] = [:]
                for l in StBoard.links(icons: rig.stIcons, shapes: rig.stShapes, aspect: aspect(f)) {
                    let v = Double(l[2]) / 1000; m[l[0]] = max(m[l[0]] ?? 0, v); m[l[1]] = max(m[l[1]] ?? 0, v)
                }
                return m
            }()
            ZStack(alignment: .topLeading) {
                Rectangle().fill(PastelTheme.padScreen)
                ForEach(Array(rig.stShapes.enumerated()), id: \.offset) { _, s in
                    let amp = (StBoard.links(icons: rig.stIcons, shapes: [s], aspect: aspect(f)).map { Double($0[2]) }.max() ?? 0) / 1000
                    if Int(s[0]) == 3 && s.count >= 5 {
                        Path { p in p.move(to: pt(s[1], s[2], f)); p.addLine(to: pt(s[3], s[4], f)) }
                            .stroke(StBoard.ink0.opacity(amp > 0 ? 0.2 + 0.45 * amp : 0.12),
                                    style: StrokeStyle(lineWidth: CGFloat(FrBoard.lineWidth) * f.height * 2, lineCap: .round))
                    } else if s.count >= 4 {
                        let r = CGFloat(s[3]) * f.height
                        FrShapePath(type: Int(s[0]))
                            .fill(StBoard.ink0.opacity(amp > 0 ? 0.15 + 0.40 * amp : 0.10))
                            .frame(width: r * 2, height: r * 2).position(pt(s[1], s[2], f))
                    }
                }
                if let dr = draft, rig.stShape == 3 {
                    Path { p in p.move(to: dr.start); p.addLine(to: dr.now) }
                        .stroke(StBoard.ink0, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [4, 3]))
                } else if let dr = draft {
                    let r = hypot(dr.now.x - dr.start.x, dr.now.y - dr.start.y)
                    FrShapePath(type: rig.stShape).stroke(StBoard.ink0, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .frame(width: r * 2, height: r * 2).position(dr.start)
                }
                ForEach(0..<StBoard.count, id: \.self) { i in jack(i, level: touched(i, f) ? 1 : (lv[i] ?? 0), f) }
                ForEach(Array(fingers.keys), id: \.self) { k in
                    if let t = fingers[k] {
                        Circle().fill(PastelTheme.hudOrange.opacity(0.08))
                            .overlay(Circle().strokeBorder(PastelTheme.hudOrange.opacity(0.6), lineWidth: 1))
                            .frame(width: reach(t.r) * 2, height: reach(t.r) * 2).position(t.p)
                    }
                }
                FrTouchLayer { ts in touches(ts, f) }.frame(width: f.width, height: f.height)
                if rig.stMode == 1 {
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { k in
                            Text(StBoard.shapeNames[k])
                                .font(.system(size: 13))
                                .foregroundStyle(rig.stShape == k ? PastelTheme.selectionText : PastelTheme.hudBlack)
                                .frame(width: 30, height: 22)
                                .background(rig.stShape == k ? PastelTheme.hudBlack : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { rig.stShape = k }
                        }
                    }
                    .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
                    .padding(6)
                }
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { m in
                        Text(["PLAY", "DRAW", "EDIT"][m])
                            .font(.hud(8, .semibold))
                            .foregroundStyle(rig.stMode == m ? PastelTheme.selectionText : PastelTheme.hudBlack)
                            .frame(width: 40, height: 22)
                            .background(rig.stMode == m ? PastelTheme.hudBlack : PastelTheme.padScreen)
                            .contentShape(Rectangle())
                            .onTapGesture { rig.stMode = m }
                    }
                }
                .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
                .padding(6)
                .frame(width: f.width, alignment: .trailing)
            }
            .clipped()
            .overlay(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
            .onAppear { d.stAspect = aspect(f) }
            .onChange(of: f) { _, s in d.stAspect = aspect(s) }
        }
    }

    /// a banana jack: its colour ring, the name under it
    private func jack(_ i: Int, level: Double, _ f: CGSize) -> some View {
        let p = rig.stIcons.indices.contains(i) ? rig.stIcons[i] : [0.5, 0.5]
        let s = jackSize(f), ink = StBoard.ink(i)
        return VStack(spacing: 1) {
            ZStack {
                Circle().fill(level > 0 ? PastelTheme.hudOrange.opacity(0.25 + 0.75 * level) : PastelTheme.padScreen)
                Circle().strokeBorder(ink, lineWidth: s * 0.22)
                Circle().fill(PastelTheme.hudBlack.opacity(0.75)).frame(width: s * 0.22, height: s * 0.22)
            }
            .frame(width: s, height: s)
            Text(StBoard.names[i]).font(.hud(6, .semibold)).foregroundStyle(PastelTheme.hudBlack.opacity(0.8)).fixedSize()
        }
        .scaleEffect(grab?.kind == 0 && grab?.index == i ? 1.25 : 1)
        .position(CGPoint(x: pt(p[0], p[1], f).x, y: pt(p[0], p[1], f).y + 4))
        .allowsHitTesting(false)
    }

    // MARK: geometry
    private func aspect(_ f: CGSize) -> Double { Double(f.width / max(1, f.height)) }
    private func pt(_ x: Double, _ y: Double, _ f: CGSize) -> CGPoint { CGPoint(x: x * f.width, y: y * f.height) }
    private func norm(_ p: CGPoint, _ f: CGSize) -> [Double] {
        [min(0.98, max(0.02, Double(p.x / f.width))), min(0.98, max(0.02, Double(p.y / f.height)))]
    }
    private func jackSize(_ f: CGSize) -> CGFloat { max(14, min(22, f.height * 0.07)) }
    private func reach(_ r: CGFloat) -> CGFloat { 12 + r * 0.9 }
    private func touched(_ i: Int, _ f: CGSize) -> Bool {
        guard rig.stMode == 0, rig.stIcons.indices.contains(i) else { return false }
        let q = pt(rig.stIcons[i][0], rig.stIcons[i][1], f)
        return fingers.values.contains { hypot($0.p.x - q.x, $0.p.y - q.y) < reach($0.r) }
    }
    private func jackAt(_ p: CGPoint, _ f: CGSize) -> Int? {
        var best: (Int, CGFloat)? = nil
        for i in 0..<min(StBoard.count, rig.stIcons.count) {
            let q = pt(rig.stIcons[i][0], rig.stIcons[i][1], f), dd = hypot(q.x - p.x, q.y - p.y)
            if dd < jackSize(f) * 0.9 && (best == nil || dd < best!.1) { best = (i, dd) }
        }
        return best?.0
    }
    private func shapeAt(_ p: CGPoint, _ f: CGSize) -> Int? {
        let n = norm(p, f)
        return rig.stShapes.indices.reversed().first { FrBoard.inside(n[0], n[1], rig.stShapes[$0], aspect: aspect(f)) }
    }

    // MARK: touches
    private func touches(_ ts: [(id: Int, p: CGPoint, r: CGFloat, ended: Bool)], _ f: CGSize) {
        switch rig.stMode {
        case 1:                                                                  // DRAW
            guard let t = ts.first else { return }
            if draft == nil { draft = (t.p, t.p) } else { draft!.now = t.p }
            if t.ended, let dr = draft {
                let r = hypot(dr.now.x - dr.start.x, dr.now.y - dr.start.y)
                if r < 10 { if let k = shapeAt(dr.start, f) { d.stRemoveShape(k) } }
                else if rig.stShape == 3 { let a = norm(dr.start, f), b = norm(dr.now, f); d.stAddShape([3, a[0], a[1], b[0], b[1]]) }
                else { let c = norm(dr.start, f); d.stAddShape([Double(rig.stShape), c[0], c[1], Double(r / f.height)]) }
                draft = nil
            }
        case 2:                                                                  // EDIT
            guard let t = ts.first else { return }
            if grab == nil {
                if let i = jackAt(t.p, f) {
                    let q = pt(rig.stIcons[i][0], rig.stIcons[i][1], f)
                    grab = (0, i, CGSize(width: q.x - t.p.x, height: q.y - t.p.y))
                } else if let k = shapeAt(t.p, f) {
                    let q = pt(rig.stShapes[k][1], rig.stShapes[k][2], f)
                    grab = (1, k, CGSize(width: q.x - t.p.x, height: q.y - t.p.y))
                } else { return }
                grabAt = t.p; grabMoved = false
            }
            if hypot(t.p.x - grabAt.x, t.p.y - grabAt.y) > 6 { grabMoved = true }
            if let g = grab, grabMoved {
                let n = norm(CGPoint(x: t.p.x + g.offset.width, y: t.p.y + g.offset.height), f)
                if g.kind == 0 { rig.stIcons[g.index] = n }
                else if rig.stShapes.indices.contains(g.index) {
                    var sh = rig.stShapes[g.index]
                    if Int(sh[0]) == 3 && sh.count >= 5 { sh[3] += n[0] - sh[1]; sh[4] += n[1] - sh[2] }
                    sh[1] = n[0]; sh[2] = n[1]
                    rig.stShapes[g.index] = sh
                }
            }
            if t.ended { grab = nil; d.stSync() }
        default:                                                                 // PLAY: a finger is a passing circle
            for t in ts { if t.ended { fingers[t.id] = nil } else { fingers[t.id] = (t.p, t.r) } }
            d.stFingers = fingers.values.map { t in let c = norm(t.p, f); return [0, c[0], c[1], Double(reach(t.r) / f.height)] }
            d.stSync()
        }
    }
}
