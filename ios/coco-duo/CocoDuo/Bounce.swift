// Bounce.swift — coco duo (k.odk)
// APP+CAFE+OTHER's BOUNCE, after the Tenori-on's bounce: three panels side by side — the phone (sines), the OP-1
// (Bluetooth MIDI) and the Cafes (their own sine synth; A and B take turns: left, right, left …). Each panel is
// 12 columns (a note each, from the scale, between the two pointers of the top slider) over 8 rows: a tap drops a
// ball from that height; it falls a row a tick, sounds its column's note on the floor and bounces back to where it
// started (a tap on the same cell takes it away). The bottom slider is the decay. The tick: the TEMPO (16ths), or
// the Cafes' FLIP (FLIP SYNC: every FLIP that goes up is one tick).

import Combine
import SwiftUI

final class BounceSeq: ObservableObject {
    static let cols = 12, rows = 8
    static let panelNames = ["iOS", "OP-1", "CAFE"]
    private static let d = UserDefaults.standard

    /// each panel's balls: the height a column's ball drops from (0 = none, 1…8 = rows above the floor)
    @Published var height: [[Int]] = {
        let v = (BounceSeq.d.array(forKey: "bn.height") as? [[Int]]) ?? []
        return v.count == 3 && v.allSatisfy { $0.count == BounceSeq.cols } ? v : Array(repeating: Array(repeating: 0, count: BounceSeq.cols), count: 3)
    }() { didSet { Self.d.set(height, forKey: "bn.height") } }
    /// the top slider: the pitch range's two pointers (0…1 over C2…C7), per panel
    @Published var lo: [Double] = (BounceSeq.d.array(forKey: "bn.lo") as? [Double]) ?? [0.35, 0.3, 0.3] { didSet { Self.d.set(lo, forKey: "bn.lo") } }
    @Published var hi: [Double] = (BounceSeq.d.array(forKey: "bn.hi") as? [Double]) ?? [0.75, 0.7, 0.65] { didSet { Self.d.set(hi, forKey: "bn.hi") } }
    /// the bottom slider: decay (0…1 → 0.05 … 3 s), per panel
    @Published var decay: [Double] = (BounceSeq.d.array(forKey: "bn.decay") as? [Double]) ?? [0.4, 0.3, 0.4] { didSet { Self.d.set(decay, forKey: "bn.decay") } }
    /// FLIP SYNC: the Cafes' FLIP is the tick (off: the TEMPO)
    @Published var flipSync: Bool = BounceSeq.d.bool(forKey: "bn.flip") { didSet { Self.d.set(flipSync, forKey: "bn.flip"); retime() } }
    /// where each ball is now (rows above the floor) and which way it goes; which columns just sounded (for the light)
    @Published private(set) var pos: [[Int]] = Array(repeating: Array(repeating: 0, count: BounceSeq.cols), count: 3)
    @Published private(set) var hit: [[Bool]] = Array(repeating: Array(repeating: false, count: BounceSeq.cols), count: 3)
    private var down: [[Bool]] = Array(repeating: Array(repeating: true, count: BounceSeq.cols), count: 3)

    /// the scale the columns take their notes from (set by the Director from the SCALE · ROOT pad)
    var scale: [Int] = [0, 2, 4, 7, 9]
    var root = 0
    var bpm = 120.0 { didSet { if abs(bpm - oldValue) > 0.01 { retime() } } }
    /// a ball on the floor: (panel, column, midi note, decay seconds)
    var onNote: ((Int, Int, UInt8, Double) -> Void)?

    var running = false { didSet { if running != oldValue { retime() } } }
    private var timer: DispatchSourceTimer?

    static func decaySec(_ v: Double) -> Double { 0.05 + v * v * 2.95 }

    /// a column's note: its place between the two pointers (C2…C7), snapped to the scale
    func note(panel p: Int, col c: Int) -> UInt8 {
        let a = min(lo[p], hi[p]), b = max(lo[p], hi[p])
        let m = 36 + (a + (b - a) * Double(c) / Double(Self.cols - 1)) * 60
        let target = Int(m.rounded())
        var best = target, dist = 99
        for n in (target - 6)...(target + 6) {
            let pc = ((n - root) % 12 + 12) % 12
            if scale.contains(pc), abs(n - target) < dist { dist = abs(n - target); best = n }
        }
        return UInt8(clamping: min(127, max(0, best)))
    }

    /// a tap on (panel, column, row from the top): drop a ball from there, or take it away
    func tap(panel p: Int, col c: Int, row r: Int) {
        let h = Self.rows - r
        height[p][c] = height[p][c] == h ? 0 : h
        pos[p][c] = max(0, height[p][c] - 1); down[p][c] = true
    }
    func clear(panel p: Int) {
        height[p] = Array(repeating: 0, count: Self.cols)
    }

    /// one tick: every ball a row on; those on the floor sound
    func tick() {
        guard running else { return }
        var hits = Array(repeating: Array(repeating: false, count: Self.cols), count: 3)
        for p in 0..<3 {
            for c in 0..<Self.cols where height[p][c] > 0 {
                let top = height[p][c] - 1
                var y = min(pos[p][c], top)
                if top == 0 { y = 0 }                                   // (on the floor: a note every tick)
                else if down[p][c] { y -= 1; if y <= 0 { y = 0; down[p][c] = false } }
                else { y += 1; if y >= top { y = top; down[p][c] = true } }
                pos[p][c] = y
                if y == 0 {
                    hits[p][c] = true
                    onNote?(p, c, note(panel: p, col: c), Self.decaySec(decay[p]))
                }
            }
        }
        hit = hits
    }

    private func retime() {
        timer?.cancel(); timer = nil
        guard running, !flipSync else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        let iv = 60.0 / max(20, bpm) / 4                                // 16ths of the TEMPO
        t.schedule(deadline: .now() + iv, repeating: iv, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }
}

/// the three panels
struct BounceBoard: View {
    @ObservedObject var seq: BounceSeq

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { p in BouncePanel(seq: seq, p: p) }
        }
    }
}

private struct BouncePanel: View {
    @ObservedObject var seq: BounceSeq
    let p: Int

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(BounceSeq.panelNames[p] + (p == 2 ? "  L·R" : ""))
                    .font(.hud(9, .semibold)).foregroundStyle(PastelTheme.textPrimary)
                Spacer(minLength: 0)
                Text(rangeText).font(.hud(8)).foregroundStyle(PastelTheme.textSecondary)
            }
            BounceRange(lo: $seq.lo[p], hi: $seq.hi[p])
                .frame(height: 18)
            GeometryReader { g in
                let cw = g.size.width / CGFloat(BounceSeq.cols), rh = g.size.height / CGFloat(BounceSeq.rows)
                ZStack(alignment: .topLeading) {
                    Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
                    ForEach(0..<BounceSeq.cols, id: \.self) { c in
                        let h = seq.height[p][c]
                        if h > 0 {
                            // where it drops from (an outline) and the ball (filled); the floor lights when it sounds
                            Rectangle().strokeBorder(PastelTheme.hudBlack.opacity(0.5), lineWidth: 1)
                                .frame(width: cw - 3, height: rh - 3)
                                .offset(x: CGFloat(c) * cw + 1.5, y: CGFloat(BounceSeq.rows - h) * rh + 1.5)
                            Circle().fill(seq.hit[p][c] ? PastelTheme.hudOrange : PastelTheme.hudBlack)
                                .frame(width: min(cw, rh) - 5, height: min(cw, rh) - 5)
                                .offset(x: CGFloat(c) * cw + (cw - min(cw, rh) + 5) / 2,
                                        y: CGFloat(BounceSeq.rows - 1 - seq.pos[p][c]) * rh + (rh - min(cw, rh) + 5) / 2)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { e in
                    let c = min(BounceSeq.cols - 1, max(0, Int(e.location.x / cw)))
                    let r = min(BounceSeq.rows - 1, max(0, Int(e.location.y / rh)))
                    seq.tap(panel: p, col: c, row: r)
                })
            }
            HStack(spacing: 6) {
                Text("DECAY").font(.hud(8)).foregroundStyle(PastelTheme.textSecondary)
                Slider(value: $seq.decay[p], in: 0...1).tint(PastelTheme.hudBlack)
                Text(String(format: "%.2fS", BounceSeq.decaySec(seq.decay[p]))).font(.hud(8)).foregroundStyle(PastelTheme.textSecondary)
                    .frame(width: 32, alignment: .trailing)
            }
            .frame(height: 18)
        }
        .padding(6)
        .background(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
    }

    private var rangeText: String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        func n(_ v: UInt8) -> String { names[Int(v) % 12] + "\(Int(v) / 12 - 1)" }
        return n(seq.note(panel: p, col: 0)) + "–" + n(seq.note(panel: p, col: BounceSeq.cols - 1))
    }
}

/// a slider with two pointers (the pitch range)
private struct BounceRange: View {
    @Binding var lo: Double
    @Binding var hi: Double
    @State private var grabbing = 0          // 0 none · 1 lo · 2 hi

    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width - 12)
            ZStack(alignment: .leading) {
                Rectangle().fill(PastelTheme.hudLine).frame(height: 2).offset(x: 6)
                Rectangle().fill(PastelTheme.hudBlack)
                    .frame(width: CGFloat(abs(hi - lo)) * w, height: 3)
                    .offset(x: 6 + CGFloat(min(lo, hi)) * w)
                thumb.offset(x: CGFloat(lo) * w)
                thumb.offset(x: CGFloat(hi) * w)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in
                    let v = min(1, max(0, Double((e.location.x - 6) / w)))
                    if grabbing == 0 { grabbing = abs(v - lo) <= abs(v - hi) ? 1 : 2 }
                    if grabbing == 1 { lo = v } else { hi = v }
                }
                .onEnded { _ in grabbing = 0 })
        }
    }
    private var thumb: some View {
        Rectangle().fill(PastelTheme.hudBlack).frame(width: 12, height: 14)
    }
}

/// BOUNCE's clock key (top bar): TEMPO (16ths of the BPM) or FLIP SYNC
struct BounceClockKey: View {
    @ObservedObject var seq: BounceSeq
    var body: some View {
        Button { seq.flipSync.toggle() } label: {
            Text(seq.flipSync ? "FLIP SYNC" : "TEMPO")
                .font(.hud(8, .semibold)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(seq.flipSync ? PastelTheme.selectionText : PastelTheme.hudBlack)
                .padding(.horizontal, 3)
                .frame(width: 50, height: 21)
                .background(IconSquare(filled: seq.flipSync))
        }
    }
}
