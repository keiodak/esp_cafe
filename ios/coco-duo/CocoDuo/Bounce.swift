// Bounce.swift — coco duo (k.odk)
// APP+CAFE+OTHER's BOUNCE, after the Tenori-on's bounce: three panels side by side — the phone (sines), the OP-1
// (Bluetooth MIDI) and the Cafes (their own sine synth; A and B take turns: left, right, left …). Each panel is
// 12 columns (a note each, from the scale, between the two pointers of the top slider) over 8 rows: a tap drops a
// ball from that height; it falls a row a tick, sounds its column's note on the floor and bounces back to where it
// started (the lower, the faster it repeats). A tap on the lowest row (or on the same dot again) stops it. The bottom slider is the decay. The tick: the TEMPO (16ths), or
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
    /// GRID (after monome's step sequencers): columns are steps, rows are notes (low at the bottom), a playhead sweeps
    /// left to right; off = TENORI (the falling balls). Each panel keeps both.
    @Published var grid: Bool = BounceSeq.d.bool(forKey: "bn.grid") { didSet { Self.d.set(grid, forKey: "bn.grid") } }
    /// GRID's lit cells: per panel, per column, a bit per row (bit 0 = the bottom row)
    @Published var cells: [[Int]] = {
        let v = (BounceSeq.d.array(forKey: "bn.cells") as? [[Int]]) ?? []
        return v.count == 3 && v.allSatisfy { $0.count == BounceSeq.cols } ? v : Array(repeating: Array(repeating: 0, count: BounceSeq.cols), count: 3)
    }() { didSet { Self.d.set(cells, forKey: "bn.cells") } }
    /// each panel's DIVIDE: it moves on every n-th tick
    static let divs = [1, 2, 3, 4, 6, 8]
    @Published var div: [Int] = (BounceSeq.d.array(forKey: "bn.div") as? [Int]) ?? [1, 1, 1] { didSet { Self.d.set(div, forKey: "bn.div") } }
    /// the phone's sound (SineChords.waveNames)
    @Published var iosWave: Int = BounceSeq.d.integer(forKey: "bn.wave") { didSet { Self.d.set(iosWave, forKey: "bn.wave") } }
    /// GRID's playhead per panel
    @Published private(set) var step = [-1, -1, -1]
    private var divAt = [0, 0, 0]
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
        return snap(36 + (a + (b - a) * Double(c) / Double(Self.cols - 1)) * 60)
    }
    private func snap(_ m: Double) -> UInt8 {
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
        // (as the Tenori-on: the lowest row stops the column's ball; elsewhere: drop one from there, again = take it away)
        height[p][c] = (r == Self.rows - 1 || height[p][c] == h) ? 0 : h
        pos[p][c] = max(0, height[p][c] - 1); down[p][c] = true
    }
    /// CLR: the panel empty (what is shown: the balls, or the grid)
    func clear(panel p: Int) {
        if grid { cells[p] = Array(repeating: 0, count: Self.cols) } else { height[p] = Array(repeating: 0, count: Self.cols) }
    }
    /// ÷: the panel's next DIVIDE
    func nextDiv(panel p: Int) {
        let i = Self.divs.firstIndex(of: div[p]) ?? 0
        div[p] = Self.divs[(i + 1) % Self.divs.count]
        divAt[p] = 0
    }
    /// GRID: a cell on / off (row from the top)
    func toggle(panel p: Int, col c: Int, row r: Int) { cells[p][c] ^= 1 << (Self.rows - 1 - r) }
    /// SYNC: all from the start — the balls back where they drop from, the playheads to the first step
    func sync() {
        for p in 0..<3 { for c in 0..<Self.cols { pos[p][c] = max(0, height[p][c] - 1); down[p][c] = true } }
        step = [-1, -1, -1]; divAt = [0, 0, 0]
    }
    /// GRID: a row's note (8 notes between the two pointers, low at the bottom), snapped to the scale
    func rowNote(panel p: Int, row y: Int) -> UInt8 {
        let a = min(lo[p], hi[p]), b = max(lo[p], hi[p])
        return snap(36 + (a + (b - a) * Double(y) / Double(Self.rows - 1)) * 60)
    }

    /// one tick: every ball a row on; those on the floor sound
    func tick() {
        guard running else { return }
        var hits = Array(repeating: Array(repeating: false, count: Self.cols), count: 3)
        for p in 0..<3 {
            divAt[p] += 1                                               // DIVIDE: this panel moves on every n-th tick
            if divAt[p] < max(1, div[p]) { hits[p] = hit[p]; continue }
            divAt[p] = 0
            if grid {                                                   // GRID: the playhead a step on; its lit cells sound
                let c = (step[p] + 1) % Self.cols
                step[p] = c
                for y in 0..<Self.rows where cells[p][c] & (1 << y) != 0 {
                    hits[p][c] = true
                    onNote?(p, c, rowNote(panel: p, row: y), Self.decaySec(decay[p]))
                }
                continue
            }
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
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { p in BouncePanel(seq: seq, p: p) }
        }
    }
}

/// one panel: the range (two pointers) on top, the dots (Tenori-on's LEDs) in the middle, DECAY below.
/// (no numbers — the app's rule)
private struct BouncePanel: View {
    @ObservedObject var seq: BounceSeq
    let p: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: PanelMetrics.chipSpacing) {
                Text(BounceSeq.panelNames[p] + (p == 2 ? " · L R" : ""))
                    .font(.hud(PanelMetrics.labelFont, .semibold))
                    .foregroundStyle(PastelTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ChipButton(title: "÷\(seq.div[p])", filled: seq.div[p] > 1) { seq.nextDiv(panel: p) }.frame(width: 34)   // DIVIDE
                ChipButton(title: "CLR", filled: false) { seq.clear(panel: p) }.frame(width: 34)
            }
            RangeSlider(low: $seq.lo[p], high: $seq.hi[p])
            GeometryReader { g in
                let cw = g.size.width / CGFloat(BounceSeq.cols), rh = g.size.height / CGFloat(BounceSeq.rows)
                let dot = max(4, min(cw, rh) * 0.42)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<BounceSeq.rows, id: \.self) { r in
                        ForEach(0..<BounceSeq.cols, id: \.self) { c in
                            let y = BounceSeq.rows - 1 - r                      // (rows above the floor)
                            if seq.grid {                                        // GRID: lit cells; the playhead's column
                                let lit = seq.cells[p][c] & (1 << y) != 0, head = seq.step[p] == c
                                Circle()
                                    .fill(lit ? (head ? PastelTheme.hudOrange : PastelTheme.hudBlack)
                                              : PastelTheme.hudBlack.opacity(head ? 0.4 : PastelTheme.tickOffOpacity))
                                    .frame(width: lit ? dot * 1.5 : dot, height: lit ? dot * 1.5 : dot)
                                    .position(x: (CGFloat(c) + 0.5) * cw, y: (CGFloat(r) + 0.5) * rh)
                            } else {                                             // TENORI: the balls
                                let h = seq.height[p][c]
                                let ball = h > 0 && seq.pos[p][c] == y
                                let from = h > 0 && y == h - 1 && !ball
                                Circle()
                                    .fill(ball ? (y == 0 && seq.hit[p][c] ? PastelTheme.hudOrange : PastelTheme.hudBlack)
                                               : PastelTheme.hudBlack.opacity(from ? 0.45 : PastelTheme.tickOffOpacity))
                                    .frame(width: ball ? dot * 1.5 : dot, height: ball ? dot * 1.5 : dot)
                                    .position(x: (CGFloat(c) + 0.5) * cw, y: (CGFloat(r) + 0.5) * rh)
                            }
                        }
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { e in
                    let c = min(BounceSeq.cols - 1, max(0, Int(e.location.x / cw)))
                    let r = min(BounceSeq.rows - 1, max(0, Int(e.location.y / rh)))
                    if seq.grid { seq.toggle(panel: p, col: c, row: r) } else { seq.tap(panel: p, col: c, row: r) }
                })
            }
            HStack(spacing: PanelMetrics.rowGap) {
                Text("DECAY")
                    .font(.hud(PanelMetrics.labelFont, .medium))
                    .foregroundStyle(PastelTheme.textPrimary)
                CompactSlider(value: $seq.decay[p], fillColor: PastelTheme.sliderFill,
                              knobColor: PastelTheme.hudOrange, thinLine: true)
            }
        }
        .padding(8)
        .background(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
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

/// a key with a word (the bottom bar's look), for BOUNCE's own keys
struct BounceKey: View {
    let title: String
    var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.hud(8, .semibold)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(on ? PastelTheme.selectionText : PastelTheme.hudBlack)
                .padding(.horizontal, 3)
                .frame(width: 50, height: 21)
                .background(IconSquare(filled: on))
        }
    }
}
/// bottom left's right: the phone's sound (five)
struct BounceWaveKey: View {
    @ObservedObject var seq: BounceSeq
    var body: some View {
        BounceKey(title: SineChords.waveNames[min(max(seq.iosWave, 0), SineChords.waveNames.count - 1)]) {
            seq.iosWave = (seq.iosWave + 1) % SineChords.waveNames.count
        }
    }
}
/// bottom right's right: TENORI (falling balls) or GRID (monome-like step sequencer)
struct BounceModeKey: View {
    @ObservedObject var seq: BounceSeq
    var body: some View {
        BounceKey(title: seq.grid ? "GRID" : "TENORI", on: seq.grid) { seq.grid.toggle(); seq.sync() }
    }
}

/// the top right key (APP+CAFE+OTHER): the scale's name; a tap = the next scale
struct OtScaleKey: View {
    @ObservedObject var axis: PadAxis
    let action: () -> Void
    var body: some View {
        BounceKey(title: OtPad.scaleNames[OtPad.scale(axis.x)], action: action)
    }
}
