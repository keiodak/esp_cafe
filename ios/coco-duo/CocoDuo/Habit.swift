// Habit.swift — coco duo (k.odk)
// HABIT (BLE mode 7), after Chase Bliss's Habit: the Cafe sends its input to the phone all the time (IMA ADPCM at
// 1/2 or 1/4 of its clock); the phone keeps the last 2½ minutes, and plays them back — pieces, or the whole run —
// by writing ADPCM onto the Cafe's tape a second ahead of its read head. The Cafe plays the tape (main and ASH), brought
// up to the memory's loudness (LEVEL · DRIVE). SAVE hands the memory to Files as a WAV.
// The Cafe's own inputs play it too: FLIP = backwards · SKIP (held) = pulled to where the other Cafe is playing ·
// EARTH = jumps through the memory (a resting level is learnt and ignored: an open input's faint CV does nothing).

import Foundation
import Combine
import SwiftUI
import AVFoundation

/// what the memory looks like, for the WHERE pad: min / max per bin, newest on the left (WHERE's 0 = now), and
/// where the playing is
final class HabitScope: ObservableObject {
    static let bins = 96
    @Published var lo = [Float](repeating: 0, count: HabitScope.bins)
    @Published var hi = [Float](repeating: 0, count: HabitScope.bins)
    @Published var play: Double = 0              // 0 (now) … 1 (the oldest held)
    @Published var full: Double = 0              // how much of the memory holds sound
}

/// both memories over the WHERE pad: L (Cafe A) above, R (Cafe B) below
struct HabitStereoScope: View {
    @ObservedObject var l: HabitScope
    @ObservedObject var r: HabitScope
    var body: some View {
        VStack(spacing: 2) {
            HabitScopeView(scope: l).overlay(alignment: .bottomTrailing) { tag("L") }
            HabitScopeView(scope: r).overlay(alignment: .bottomTrailing) { tag("R") }
        }
        .padding(.vertical, 18)
        .allowsHitTesting(false)
    }
    private func tag(_ s: String) -> some View {
        Text(s).font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(PastelTheme.hudBlack.opacity(0.5)).padding(3)
    }
}

/// one memory
struct HabitScopeView: View {
    @ObservedObject var scope: HabitScope
    var body: some View {
        Canvas { ctx, size in
            let n = HabitScope.bins, w = size.width / CGFloat(n), mid = size.height / 2
            var p = Path()
            for k in 0..<n {
                let top = mid - CGFloat(scope.hi[k]) * mid * 0.9, bot = mid - CGFloat(scope.lo[k]) * mid * 0.9
                p.addRect(CGRect(x: CGFloat(k) * w, y: min(top, bot), width: max(0.8, w * 0.8), height: max(0.8, abs(bot - top))))
            }
            ctx.fill(p, with: .color(PastelTheme.hudBlack.opacity(0.35)))
            let x = CGFloat(scope.play) * size.width
            ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(PastelTheme.hudOrange))
        }
        .allowsHitTesting(false)
    }
}

enum Adpcm {
    static let steps: [Int32] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
        130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060,
        1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484,
        7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
    static let idx: [Int] = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

    /// the same arithmetic as the Cafe's (hb_enc / hb_dec): the two must stay alike
    static func enc(_ x: Int32, _ pred: inout Int32, _ ix: inout Int) -> UInt8 {
        let st = steps[ix]
        var d = x - pred
        var n: UInt8 = 0
        if d < 0 { n = 8; d = -d }
        var dq = st >> 3
        if d >= st { n |= 4; d -= st; dq += st }
        if d >= st >> 1 { n |= 2; d -= st >> 1; dq += st >> 1 }
        if d >= st >> 2 { n |= 1; dq += st >> 2 }
        pred += (n & 8) != 0 ? -dq : dq
        pred = min(32767, max(-32768, pred))
        ix = min(88, max(0, ix + idx[Int(n)]))
        return n
    }
    static func dec(_ n: UInt8, _ pred: inout Int32, _ ix: inout Int) -> Int32 {
        let st = steps[ix]
        var dq = st >> 3
        if n & 4 != 0 { dq += st }
        if n & 2 != 0 { dq += st >> 1 }
        if n & 1 != 0 { dq += st >> 2 }
        pred += (n & 8) != 0 ? -dq : dq
        pred = min(32767, max(-32768, pred))
        ix = min(88, max(0, ix + idx[Int(n)]))
        return pred
    }
}

/// HABIT's pads, one set per side: the left half plays Cafe A's memory (L), the right half Cafe B's (R).
/// WHERE · JUMP (how far back · how often it jumps somewhere else), PITCH · WOW, GLITCH · STARVE, LOOP · DRIFT (a
/// short loop where it plays · the loop sliding on through the memory). The sound itself
/// comes out plain: clean, dry, at full level.
enum HabitPad {
    static let titles = ["L WHERE · JUMP", "L PITCH · WOW", "R PITCH · WOW", "R WHERE · JUMP",
                         "L GLITCH · STARVE", "L LOOP · DRIFT", "R LOOP · DRIFT", "R GLITCH · STARVE"]
    static let starts: [(Double, Double)] = [(0.0, 0.0), (0.5, 0.0), (0.5, 0.0), (0.0, 0.0),
                                             (0.0, 0.0), (0.0, 0.0), (0.0, 0.0), (0.0, 0.0)]
    /// each side's pads: WHERE, PITCH, GLITCH, LOOP
    static let pads = [[0, 1, 4, 5], [3, 2, 7, 6]]
    /// LOOP: off at the left, then 50 ms … 4 s
    static func loop(_ x: Double) -> Double { x < 0.03 ? 0 : 0.05 * pow(80, (x - 0.03) / 0.97) }
    /// PITCH: -12 … +12 semitones, a catch at 0
    static func semis(_ x: Double) -> Double { abs(x - 0.5) < 0.03 ? 0 : ((x - 0.5) * 24).rounded() }
    static func caption(_ i: Int, _ x: Double, _ y: Double) -> String {
        switch i {
        case 0, 3: return String(format: "%.0f s LATER · JUMP %d%%", HabitEngine.shownSeconds * (1 - x * 0.95), Int(y * 100))
        case 1, 2: let st = Int(semis(x)); return "\(st > 0 ? "+" : "")\(st) st · WOW \(Int(y * 100))%"
        case 4, 7: return "GLITCH \(Int(x * 100))% · STARVE \(Int(y * 100))%"
        case 5, 6: let l = loop(x); return (l == 0 ? "LOOP OFF" : String(format: "%.2f s", l)) + " · DRIFT \(Int(y * 100))%"
        default: return ""
        }
    }
}

/// one Cafe's memory and its playing
final class HabitEngine {
    static let maxSeconds = 300.0
    static var shownSeconds = 150.0              // (for the WHERE caption)
    static let lengths: [Double] = [30, 60, 150, 300]
    var seconds = 150.0                          // LENGTH of the memory: 30 s … 5 min
    weak var other: HabitEngine?                 // the other Cafe's (SKIP pulls towards it)
    /// how far back this one is playing now (s)
    private(set) var age: Double = 0
    let unit: CafeUnit
    let axes: [PadAxis]
    var div = 4                                  // 1/4 (8K) or 1/8 (4K) of the Cafe's clock
    var hold = false                             // HOLD: the memory takes nothing new
    var active = false
    let scope = HabitScope()
    private var scopeT = Date()

    // the memory: a ring of 16-bit samples at the rate the Cafe sends
    private let mem: UnsafeMutablePointer<Int16>    // (a plain block: the audio thread reads it while the link writes it)
    private var mw = 0                           // samples written, ever (the ring index is mw % cap)
    private let cap: Int
    // the Cafe's queue (the tape): how full it was (samples at the rate) and how many it had got, as its last packet
    // said, and when that came — the phone sends to keep it about LEAD full; the Cafe plays it at its own pace
    private var fillRep = 0, gotRep: UInt16 = 0
    private var rpAt = Date.distantPast
    private var sent: UInt16 = 0                 // samples sent, in all (wraps as the Cafe's count does)
    private static let lead = 1.2                // seconds kept in the Cafe's queue (the link comes in bursts)
    private var lastSeq: UInt16? = nil
    // the playing
    private var synced = false
    private var pending: (pk: Data, pred: Int32, ix: Int, n: Int)? = nil   // (a packet the link could not take yet)
    private var pred: Int32 = 0, ix = 0
    private struct Voice { var pos: Double; var step: Double; var left: Int; var len: Int; var fade: Int }
    private var voices: [Voice] = []
    private var untilNext = 0                    // samples to the next piece
    private var lastStart: Double = 0, repeatsLeft = 0
    private var lp: Double = 0, drift: Double = 0
    private var peak: Double = 0.05              // how loud the memory is (the playing is brought up to it)
    private var dh: Double = 0, env: Double = 0, eg: Double = 1   // CLEAN
    // STARVE (a dying digital box: held samples, fewer bits, drop-outs) · GLITCH (stutters of what just played,
    // sometimes backwards) · ECHO (on the way out)
    private var held: Double = 0, heldN = 0, gateOn = true, gateN = 0
    private var hist = [Double](repeating: 0, count: 16000), hw = 0
    private var gl = 0, glLen = 0, glLeft = 0, glRev = false
    private var echo = [Double](repeating: 0, count: 16000), ew = 0
    private var wholeVoice: Voice? = nil
    // speeds
    private var upBytes = 0, downBytes = 0, statT = Date()
    private var timer: Timer?

    init(unit: CafeUnit, axes: [PadAxis]) {
        self.unit = unit
        self.axes = axes
        cap = Int(Self.maxSeconds * 17000)
        mem = UnsafeMutablePointer<Int16>.allocate(capacity: cap)
        mem.initialize(repeating: 0, count: cap)
        unit.onHabit = { [weak self] d in self?.receive(d) }
    }

    /// the rate the memory is at (samples per second)
    var rate: Double { (unit.hz > 1000 ? unit.hz : 32000) / Double(div) }
    /// how much of the memory holds sound (samples)
    var filled: Int { min(mw, cap, Int(seconds * rate)) }

    func start() {
        guard timer == nil else { return }
        active = true
        synced = false
        statT = Date(); upBytes = 0; downBytes = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 40, repeats: true) { [weak self] _ in self?.tick() }
    }
    func stop() {
        active = false
        timer?.invalidate(); timer = nil
        unit.hbUp = 0; unit.hbDown = 0
    }
    func clear() { mw = 0; pos = -1 }

    // MARK: up — the Cafe's input into the memory

    private func receive(_ d: Data) {
        let b = [UInt8](d)
        upBytes += b.count
        guard active, b.count > 11 else { return }
        let seq = UInt16(b[0]) | UInt16(b[1]) << 8
        fillRep = Int(b[2]) | Int(b[3]) << 8
        gotRep = UInt16(b[4]) | UInt16(b[5]) << 8
        rpAt = Date()
        unit.hbDrops = Int(UInt16(b[6]) | UInt16(b[7]) << 8)
        lastSeq = seq
        guard !hold else { return }
        var p = Int32(Int16(bitPattern: UInt16(b[8]) | UInt16(b[9]) << 8))
        var i = min(88, Int(b[10]))
        for k in 11..<b.count {
            for h in 0..<2 {
                let n = h == 0 ? b[k] & 15 : b[k] >> 4
                let v = Adpcm.dec(n, &p, &i)
                mem[mw % cap] = Int16(v)
                mw += 1
                let av = Double(abs(v)) / 32768
                peak = av > peak ? av : peak * 0.99998 + 0.0000002
            }
        }
    }

    // MARK: down — the playing, onto the tape ahead of the Cafe's read head

    private func tick() {
        let now = Date()
        if now.timeIntervalSince(statT) >= 1 {
            let dt = now.timeIntervalSince(statT)
            unit.hbUp = Double(upBytes) / dt / 1000
            unit.hbDown = Double(downBytes) / dt / 1000
            upBytes = 0; downBytes = 0; statT = now
        }
        guard active, rpAt != .distantPast, unit.hz > 1000 else { return }
        readInputs()
        if auto && !hold && filled >= Int(seconds * rate) - 1 { hold = true; onAutoHold?() }
        if now.timeIntervalSince(scopeT) >= 0.2 { scopeT = now; drawScope() }
        guard toCafe else { return }                            // (the phone plays it itself: nothing goes back)
        let r = rate
        if !synced { sent = gotRep; pred = 0; ix = 0; pending = nil; synced = true }
        var inFlight = Int(sent &- gotRep)                       // sent, not yet come
        if inFlight > 30000 { sent = gotRep; inFlight = 0 }      // (the Cafe started again: count from its count)
        let fillNow = Double(fillRep) - now.timeIntervalSince(rpAt) * r + Double(inFlight)
        var want = min(Int(Self.lead * r - fillNow), Int(0.5 * r))
        if let q = pending {                                     // (first the one that waited: no sound is lost)
            guard unit.habitSend(q.pk) else { return }
            pred = q.pred; ix = q.ix; downBytes += q.pk.count; sent = sent &+ UInt16(q.n); want -= q.n
            pending = nil
        }
        let maxLen = min(240, unit.habitMaxLen)
        let perPacket = max(16, (maxLen - 7) * 2)
        while want > 0 {
            let n = min(perPacket, want) & ~1
            if n < 2 { break }
            var pk = [UInt8](repeating: 0, count: 7 + n / 2)
            let pos = UInt32(sent)
            pk[0] = UInt8(pos & 255); pk[1] = UInt8((pos >> 8) & 255); pk[2] = UInt8((pos >> 16) & 255); pk[3] = UInt8(pos >> 24)
            let p16 = UInt16(bitPattern: Int16(pred))
            pk[4] = UInt8(p16 & 255); pk[5] = UInt8(p16 >> 8); pk[6] = UInt8(ix)
            var sp = pred, si = ix
            for k in 0..<n {
                let x = Int32(max(-32768, min(32767, next() * 32767)))
                let nb = Adpcm.enc(x, &sp, &si)
                if k & 1 == 0 { pk[7 + k / 2] = nb } else { pk[7 + k / 2] |= nb << 4 }
            }
            guard unit.habitSend(Data(pk)) else { pending = (Data(pk), sp, si, n); break }   // (the link is full: next tick)
            pred = sp; ix = si
            downBytes += pk.count
            sent = sent &+ UInt16(n)
            want -= n
        }
    }

    // MARK: the Cafe's FLIP / SKIP / EARTH (from its status lines)
    private var flip = false, pull = false, flipWas = false
    /// AUTO: once the memory is full (LENGTH), it freezes by itself
    var auto = false
    /// EARTH jumps through the memory only when this is on (off by default: a floating input kept moving it)
    var useEarth = false
    /// where the playing goes: false = the phone's own output (L = Cafe A, R = Cafe B: smooth, nothing over the
    /// link but the recording); true = back onto the Cafe's tape (the old way)
    var toCafe = true
    // the phone's output: the memory's rate brought up to the output's, in straight lines
    private var ph: Double = 1, pv: Double = 0, cv: Double = 0
    /// one sample at the output's rate (called on the audio thread)
    func pull(_ outRate: Double) -> Float {
        guard active, !toCafe else { return 0 }
        ph += rate / outRate
        while ph >= 1 { ph -= 1; pv = cv; cv = next() }
        return Float(pv + (cv - pv) * ph)
    }
    var onAutoHold: (() -> Void)?
    private var rest: Double = -1                // EARTH's resting level (what an open input reads)
    private var earthOn = false
    private var earthBack: Double = 0            // EARTH's place (s back)
    private var jump = false                     // EARTH moved: go there now

    private func readInputs() {
        if unit.flip && !flipWas { flip.toggle() }                // FLIP: each press turns it round
        flipWas = unit.flip
        pull = unit.skip && (other?.active ?? false)
        guard useEarth else { earthOn = false; jump = false; return }   // (EARTH only when asked: off, it moves nothing)
        let e = Double(unit.earth)
        if rest < 0 { rest = e }
        let margin = 30.0                        // (~12 %: the faint CV and its wobble live under this)
        if !earthOn {
            if e > rest + margin { earthOn = true } else { rest += (e - rest) * 0.02 }   // (the rest follows the drift)
        } else if e < rest + margin * 0.6 { earthOn = false }
        if earthOn {
            let span = max(20, 255 - rest - margin)
            let b = min(1, max(0, (e - rest - margin) / span)) * seconds
            if abs(b - earthBack) > seconds * 0.03 { earthBack = b; jump = true }
        }
    }

    /// one sample of the playing (±1): the plain run, LENGTH (… minus WHERE) behind the recording; JUMP moves it
    /// now and then; PITCH shifts it without moving it (two overlapping heads); then GLITCH · STARVE; full level
    private var pos: Double = -1                 // the play head (memory samples, ever)
    private var jumpOff: Double = 0, jumpNow = false
    private var loopStart: Double = -1
    private var whereWas: Double = -1
    private var fadeIn: Double = 1
    private var pd: Double = 0, wow: Double = 0
    private func next() -> Double {
        let have = filled
        guard have > Int(rate * 0.2) else { return 0 }
        let r = rate
        let side = HabitPad.pads[unit.slot == 1 ? 1 : 0]
        let wh = axes[side[0]], pt = axes[side[1]], gl = axes[side[2]], lp = axes[side[3]]
        let lo = Double(mw - have + 2), hi = Double(mw - 2)
        let delay = seconds * r * (1 - wh.x * 0.95)
        if !hold && Double(mw) < delay { return 0 }                                           // (not yet: still taking)
        // JUMP: now and then somewhere else in the memory (Y = how often: up to ~4 a second)
        if wh.y > 0.02 {
            if Double.random(in: 0..<1) < wh.y * wh.y * 4 / r { jumpOff = Double.random(in: 0...Double(have) * 0.9); jumpNow = true }
        } else if jumpOff != 0 { jumpOff = 0; jumpNow = true }
        var back = delay + jumpOff
        if earthOn { back = earthBack * r + r * 0.05 }                                            // EARTH: its place
        if pull, let o = other { back = max(r * 0.05, o.age * r) }                                // SKIP: the other's
        back = min(Double(have) - r * 0.1, back)
        let target = Double(mw) - back
        if pos < 0 || jump || jumpNow || pos < lo { pos = max(lo, target); fadeIn = 0; jump = false; jumpNow = false; loopStart = -1 }
        let L = HabitPad.loop(lp.x) * r
        if L > 0 {                                                                               // LOOP: round a short piece
            if loopStart < 0 { loopStart = max(lo, pos - L) }
            loopStart += lp.y * 0.5                                                              // DRIFT: the piece slides on
            loopStart = min(max(lo, loopStart), max(lo, hi - L))
            pos += flip ? -1 : 1
            if pos >= loopStart + L { pos = loopStart; fadeIn = 0 }
            if pos < loopStart { pos = loopStart + L - 1; fadeIn = 0 }
        } else if flip {                                                                         // FLIP: backwards, freely
            pos -= 1
            if pos < lo { pos = hi - 1 }
        } else if hold {                                                                         // frozen: round and round
            pos += 1
            if pos >= hi { pos -= Double(have - 4) }
        } else {
            // (WHERE moved: go there. Not "far from the target": the phone plays ~1 s ahead of the Cafe's ears — the
            //  queue — so it always looks far, and jumping back on that made it repeat the same second, not play)
            if abs(wh.x - whereWas) > 0.01 { whereWas = wh.x; pos = target; fadeIn = 0 }
            pos += 1                                                                             // (straight: ×1, nothing bent)
            pos = min(hi, max(lo, pos))
        }
        if L <= 0 { loopStart = -1 }
        age = (Double(mw) - pos) / r
        // PITCH (+ WOW): two heads behind the play head, sliding, crossfaded — the place stays, the pitch moves
        wow += 2 * .pi * 0.6 / r; if wow > 2 * .pi { wow -= 2 * .pi }
        let ratio = pow(2, HabitPad.semis(pt.x) / 12) * (1 + pt.y * 0.03 * sin(wow))
        var out: Double
        if ratio == 1 {
            out = sample(pos)
        } else {
            let w = r * 0.08
            pd -= ratio - 1
            pd = pd.truncatingRemainder(dividingBy: w); if pd < 0 { pd += w }
            let d2 = (pd + w / 2).truncatingRemainder(dividingBy: w)
            let g1 = 1 - abs(2 * pd / w - 1), g2 = 1 - abs(2 * d2 / w - 1)
            out = sample(pos - pd) * g1 + sample(pos - d2) * g2
        }
        if fadeIn < 1 { fadeIn = min(1, fadeIn + 1 / (r * 0.006)); out *= fadeIn }            // (no click on a jump)
        out = effects(out, r, glitch: gl.x, starve: gl.y)
        // straight: one fixed gain (no riding of the level, no tone lift — what was recorded, as it was; the Cafe now
        // sends it ×4 hotter, so the link's noise sits further under it)
        out *= 1
        return max(-1, min(1, out))
    }

    private func effects(_ x0: Double, _ r: Double, glitch gv: Double, starve sv: Double) -> Double {
        var x = x0
        // GLITCH: now and then, a piece of what just played again (2 … 6 times, sometimes backwards)
        hist[hw] = x; hw = (hw + 1) % hist.count
        if glLeft <= 0 && gv > 0.01 && Double.random(in: 0..<1) < gv * gv * 0.0006 {
            glLen = max(16, Int(r * Double.random(in: 0.02...0.16)))
            glLeft = glLen * Int.random(in: 2...6)
            gl = 0
            glRev = Double.random(in: 0..<1) < 0.3
        }
        if glLeft > 0 {
            let k = gl % glLen
            let back = glLen - (glRev ? glLen - 1 - k : k)
            x = hist[(hw - 1 - back + hist.count * 2) % hist.count]
            gl += 1; glLeft -= 1
        }
        // STARVE: held samples (the rate sags), fewer bits, and the sound dropping out as the power fails
        if sv > 0.01 {
            if heldN <= 0 { held = x; heldN = 1 + Int(sv * sv * 10 * Double.random(in: 0.7...1.3)) }
            heldN -= 1
            let levels = pow(2, 12 - sv * 9)
            x = (held * levels).rounded() / levels
            if gateN <= 0 {
                gateOn = Double.random(in: 0..<1) > sv * 0.45
                gateN = Int(r * Double.random(in: 0.01...0.12))
            }
            gateN -= 1
            if !gateOn { x *= 0.05 }
        }
        return x
    }

    private func sample(_ p: Double) -> Double {
        let lo = mw - filled
        guard p.isFinite else { return 0 }
        let i = Int(floor(p))
        guard i >= lo, i + 1 < mw else { return 0 }
        let f = p - Double(i)
        let a = Double(mem[i % cap]), b = Double(mem[(i + 1) % cap])
        return (a + (b - a) * f) / 32768
    }

    /// the memory in bins (newest first), sampled sparsely: cheap
    private func drawScope() {
        let have = filled, n = HabitScope.bins
        guard have > n else { return }
        var lo = [Float](repeating: 0, count: n), hi = [Float](repeating: 0, count: n)
        let per = have / n, stride = max(1, per / 48)
        for k in 0..<n {
            var a: Float = 0, b: Float = 0
            var j = 0
            while j < per {
                let v = Float(mem[(mw - 1 - (k * per + j)) % cap]) / 32768
                a = min(a, v); b = max(b, v)
                j += stride
            }
            lo[k] = a; hi[k] = b
        }
        scope.lo = lo; scope.hi = hi
        scope.play = min(1, max(0, age * rate / Double(have)))
        scope.full = Double(have) / (seconds * rate)
    }

    // MARK: SAVE

    /// the memory as a 16-bit mono WAV (oldest first)
    func wav() -> Data {
        let n = filled, sr = UInt32(rate.rounded())
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 2)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(sr); u32(sr * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 2))
        var body = [Int16](repeating: 0, count: n)
        for k in 0..<n { body[k] = mem[(mw - n + k) % cap] }
        body.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}


/// HABIT's sound on the phone: Cafe A's memory on the left, Cafe B's on the right
final class HabitPlayer {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let habits: [HabitEngine]
    init(_ habits: [HabitEngine]) { self.habits = habits }

    func start() {
        if node != nil { if !engine.isRunning { try? engine.start() }; return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, options: [.mixWithOthers])
        try? s.setActive(true)
        let hw = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sr = hw > 1000 ? hw : 48000
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let hs = habits
        let n = AVAudioSourceNode(format: fmt) { _, _, frames, abl -> OSStatus in
            let b = UnsafeMutableAudioBufferListPointer(abl)
            guard b.count >= 2, let l = b[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = b[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for i in 0..<Int(frames) {
                l[i] = hs[0].pull(sr)
                r[i] = hs.count > 1 ? hs[1].pull(sr) : 0
            }
            return noErr
        }
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: fmt)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        node = n
        try? engine.start()
    }
}
