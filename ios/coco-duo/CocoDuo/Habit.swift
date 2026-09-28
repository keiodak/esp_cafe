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

/// what the memory looks like, for the WHERE pad: min / max per bin, newest on the left (WHERE's 0 = now), and
/// where the playing is
final class HabitScope: ObservableObject {
    static let bins = 96
    @Published var lo = [Float](repeating: 0, count: HabitScope.bins)
    @Published var hi = [Float](repeating: 0, count: HabitScope.bins)
    @Published var play: Double = 0              // 0 (now) … 1 (the oldest held)
    @Published var full: Double = 0              // how much of the memory holds sound
}

/// drawn over the WHERE pad
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

/// HABIT's pads: WHERE · SPREAD, LENGTH · GAP, SPEED · REVERSE, STARVE · GLITCH / CLEAN · LEVEL, TONE · DRIFT,
/// ECHO · FEEDBACK, DETUNE · OCTAVES
enum HabitPad {
    static let titles = ["WHERE · SPREAD", "LENGTH · GAP", "SPEED · REVERSE", "STARVE · GLITCH",
                         "CLEAN · LEVEL", "TONE · DRIFT", "ECHO · FEEDBACK", "DETUNE · OCTAVES"]
    /// (it starts as a plain run: LENGTH at the top = the whole memory played on at ×1, a little behind)
    static let starts: [(Double, Double)] = [(0.0, 0.0), (1.0, 0.0), (0.5, 0.0), (0.0, 0.0),
                                             (0.5, 0.6), (1.0, 0.0), (0.0, 0.0), (0.0, 0.0)]
    /// LENGTH: 30 ms … 4 s, and at the top: the whole run (a tape delay from WHERE)
    static func whole(_ x: Double) -> Bool { x >= 0.97 }
    static func length(_ x: Double) -> Double { 0.03 * pow(4.0 / 0.03, min(1, x / 0.97)) }
    /// SPEED: ¼ … 4, with a catch at 1
    static func speed(_ x: Double) -> Double { abs(x - 0.5) < 0.04 ? 1 : pow(2, (x - 0.5) * 4) }
    static func caption(_ i: Int, _ x: Double, _ y: Double) -> String {
        switch i {
        case 0: return String(format: "%.0f s LATER · %d%%", HabitEngine.shownSeconds * (1 - x * 0.95), Int(y * 100))
        case 1: return (whole(x) ? "WHOLE" : String(format: "%.2f s", length(x))) + String(format: " · GAP %d%%", Int(y * 100))
        case 2: return String(format: "×%.2f · REV %d%%", speed(x), Int(y * 100))
        case 3: return "STARVE \(Int(x * 100))% · GLITCH \(Int(y * 100))%"
        case 4: return "CLEAN \(Int(x * 100))% · LEVEL \(Int(y * 100))%"
        case 5: return "TONE \(Int(x * 100))% · DRIFT \(Int(y * 100))%"
        case 6: return x < 0.02 ? "ECHO OFF" : String(format: "%.2f s · FB %d%%", 0.05 + x * x * 0.95, Int(y * 85))
        case 7: return "DETUNE \(Int(x * 100))% · OCT \(Int(y * 100))%"
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
    private var mem: [Int16]
    private var mw = 0                           // samples written, ever (the ring index is mw % cap)
    private let cap: Int
    // the Cafe's read head, as its last packet said (tape samples), and when
    private var rp: UInt32 = 0
    private var rpAt = Date.distantPast
    // the Cafe's read head, unwrapped, against the phone's clock: the packet that came quickest tells it best (the
    // others waited in the radio's queue), so the estimate takes the highest, slowly letting go of it
    private var rpUn: Double = 0, rpLast: UInt32 = 0, rpOff: Double = -.infinity
    private let t0 = Date()
    private var lastSeq: UInt16? = nil
    // the playing
    private var wh = 0                           // the next tape place (in rate samples) the phone writes
    private var synced = false
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
        mem = [Int16](repeating: 0, count: cap)
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
    func clear() { mw = 0; voices = []; wholeVoice = nil }

    // MARK: up — the Cafe's input into the memory

    private func receive(_ d: Data) {
        let b = [UInt8](d)
        upBytes += b.count
        guard active, b.count > 11 else { return }
        let seq = UInt16(b[0]) | UInt16(b[1]) << 8
        rp = UInt32(b[2]) | UInt32(b[3]) << 8 | UInt32(b[4]) << 16 | UInt32(b[5]) << 24
        rpAt = Date()
        if unit.hz > 1000 {
            let d = Int((rp &- rpLast) & 0x1FFFF)                // (the head goes round 131072)
            rpUn += Double(d); rpLast = rp
            let off = rpUn - rpAt.timeIntervalSince(t0) * unit.hz
            rpOff = off > rpOff ? off : rpOff - unit.hz * 0.002   // (lets go by 2 ms a packet)
        }
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
        let tapeLen = TAPE / div
        let r = rate
        // where the Cafe reads now (rate samples on the tape)
        guard rpOff.isFinite else { return }                    // (no packet timed yet: nothing to aim at)
        let unEst = rpOff + now.timeIntervalSince(t0) * unit.hz
        let est = (Double(rp) + (unEst - rpUn)) / Double(div)
        guard est.isFinite else { return }
        let head = ((Int(est) % tapeLen) + tapeLen) % tapeLen
        let lead = Int(1.2 * r), window = Int(0.5 * r)                // (over a second ahead: the link comes in bursts)
        var ahead = (wh - head) % tapeLen; if ahead < 0 { ahead += tapeLen }
        if !synced || ahead > tapeLen * 3 / 4 || ahead < lead / 5 {   // lost the thread: start again, ahead
            wh = (head + lead) % tapeLen
            ahead = lead
            synced = true
            pred = 0; ix = 0
        }
        var want = lead + window - ahead
        let maxLen = min(240, unit.habitMaxLen)
        let perPacket = max(16, (maxLen - 7) * 2)
        while want > 0 {
            let n = min(perPacket, want) & ~1
            if n < 2 { break }
            var pk = [UInt8](repeating: 0, count: 7 + n / 2)
            let pos = UInt32(wh)
            pk[0] = UInt8(pos & 255); pk[1] = UInt8((pos >> 8) & 255); pk[2] = UInt8((pos >> 16) & 255); pk[3] = UInt8(pos >> 24)
            let p16 = UInt16(bitPattern: Int16(pred))
            pk[4] = UInt8(p16 & 255); pk[5] = UInt8(p16 >> 8); pk[6] = UInt8(ix)
            var sp = pred, si = ix
            for k in 0..<n {
                let x = Int32(max(-32768, min(32767, next() * 32767)))
                let nb = Adpcm.enc(x, &sp, &si)
                if k & 1 == 0 { pk[7 + k / 2] = nb } else { pk[7 + k / 2] |= nb << 4 }
            }
            guard unit.habitSend(Data(pk)) else { break }         // (the link is full: next tick)
            pred = sp; ix = si
            downBytes += pk.count
            wh = (wh + n) % tapeLen
            want -= n
        }
    }

    // MARK: the Cafe's FLIP / SKIP / EARTH (from its status lines)
    private var flip = false, pull = false, flipWas = false
    /// AUTO: once the memory is full (LENGTH), it freezes by itself
    var auto = false
    var onAutoHold: (() -> Void)?
    private var rest: Double = -1                // EARTH's resting level (what an open input reads)
    private var earthOn = false
    private var earthBack: Double = 0            // EARTH's place (s back)
    private var jump = false                     // EARTH moved: go there now

    private func readInputs() {
        if unit.flip && !flipWas { flip.toggle() }                // FLIP: each press turns it round
        flipWas = unit.flip
        pull = unit.skip && (other?.active ?? false)
        let e = Double(unit.earth)
        if rest < 0 { rest = e }
        let margin = 14.0                        // (~5 %: the faint CV lives under this)
        if !earthOn {
            if e > rest + margin { earthOn = true } else { rest += (e - rest) * 0.02 }   // (the rest follows the drift)
        } else if e < rest + margin * 0.6 { earthOn = false }
        if earthOn {
            let span = max(20, 255 - rest - margin)
            let b = min(1, max(0, (e - rest - margin) / span)) * seconds
            if abs(b - earthBack) > seconds * 0.03 { earthBack = b; jump = true }
        }
    }

    /// one sample of the playing (±1)
    private func next() -> Double {
        let have = filled
        guard have > Int(rate * 0.2) else { return 0 }
        func a(_ i: Int) -> PadAxis { axes[i] }
        let r = rate
        // DRIFT: WHERE wanders by itself
        drift += Double.random(in: -1...1) * a(5).y * 0.00002
        drift = max(-0.3, min(0.3, drift * 0.99999))
        var whereBack = min(1, max(0, a(0).x + drift)) * Double(have - Int(r * 0.1)) + r * 0.05
        if earthOn { whereBack = min(Double(have) - r * 0.1, earthBack * r + r * 0.05) }          // EARTH: its place
        if pull, let o = other { whereBack = min(Double(have) - r * 0.1, max(r * 0.05, o.age * r)) }   // SKIP: the other's
        let dir: Double = flip ? -1 : 1                                                        // FLIP: backwards
        var out = 0.0
        if HabitPad.whole(a(1).x) {
            // WHOLE: the plain run. The recording is played back LENGTH (30 s …) later, on and on, while it goes on
            // recording; frozen (HOLD / AUTO), the held memory goes round. WHERE shortens the wait.
            let delay = seconds * r * (1 - a(0).x * 0.95)
            let lo = Double(mw - have + 2), hi = Double(mw - 2)
            if !hold && Double(mw) < delay { return 0 }                                           // (not yet: still taking)
            var target = Double(mw) - delay
            if earthOn { target = Double(mw) - min(Double(have) - r * 0.1, earthBack * r + r * 0.05) }
            if pull, let o = other { target = Double(mw) - min(Double(have) - r * 0.1, max(r * 0.05, o.age * r)) }
            if wholeVoice == nil || jump {
                wholeVoice = Voice(pos: max(lo, target), step: 1, left: .max, len: .max, fade: 1)
                jump = false
            }
            var st = HabitPad.speed(a(2).x) * dir
            if !hold {                                                                            // (kept on its place: a
                let err = target - wholeVoice!.pos                                                //  hair faster / slower,
                st += max(-0.03, min(0.03, err / (r * 2)))                                        //  never a jump)
            }
            wholeVoice!.step = st
            out = sample(wholeVoice!.pos)
            var p = wholeVoice!.pos + st
            if hold {                                                                             // frozen: round and round
                if p >= hi { p -= Double(have - 4) }
                if p < lo { p += Double(have - 4) }
            } else { p = min(hi, max(lo, p)) }
            wholeVoice!.pos = p
            age = (Double(mw) - p) / r
            voices = []
        } else {
            wholeVoice = nil
            let layers = 2
            let len = max(64, Int(HabitPad.length(a(1).x) * r))
            if jump { untilNext = 0; repeatsLeft = 0; jump = false }                              // EARTH: now
            if untilNext <= 0 && voices.count < layers {
                // REPEAT: the same place again, a few times
                var start: Double
                if repeatsLeft > 0 { repeatsLeft -= 1; start = lastStart }
                else {
                    let spread = a(0).y * Double(have) * 0.3
                    start = Double(mw) - whereBack - Double.random(in: 0...max(1, spread)) - Double(len) * 4
                    start = max(Double(mw - have + 2), start)
                }
                lastStart = start
                age = (Double(mw) - start) / r
                var step = HabitPad.speed(a(2).x)
                step *= pow(2, Double.random(in: -1...1) * a(7).x * 0.08)                  // DETUNE
                if Double.random(in: 0..<1) < a(7).y * 0.5 { step *= Bool.random() ? 2 : 0.5 }   // OCTAVES
                if Double.random(in: 0..<1) < a(2).y { step = -step }                        // REVERSE
                step *= dir                                                                  // FLIP
                let pos = step < 0 ? start + Double(len) * abs(step) : start
                let fade = max(32, Int(Double(len) * 0.2))
                voices.append(Voice(pos: pos, step: step, left: len, len: len, fade: fade))
                let gap = a(1).y * 3
                untilNext = max(32, Int(Double(len) / Double(layers) * (1 + gap)))
            }
            untilNext -= 1
            var k = 0
            while k < voices.count {
                var v = voices[k]
                let done = v.len - v.left
                let e = min(1, Double(min(done, v.left)) / Double(v.fade))
                out += sample(v.pos) * e * e
                v.pos += v.step
                v.left -= 1
                if v.left <= 0 { voices.remove(at: k) } else { voices[k] = v; k += 1 }
            }
            out /= max(1, Double(layers).squareRoot())
        }
        // TONE: a gentle low-pass (open at the top)
        let t = a(5).x
        if t < 0.98 {
            let c = 0.02 + t * t * 0.9
            lp += (out - lp) * c
            out = lp
        }
        out = effects(out, r)
        // CLEAN · LEVEL: brought up to the memory's loudness (at most ×3, never on near-silence), then CLEAN: the hiss
        // of the thin link taken off the top (a gentle low-pass) and out of the gaps (an expander under its floor)
        out *= min(3, 0.7 / max(0.15, peak)) * (a(4).y * 2)
        let c = a(4).x
        if c > 0.01 {
            dh += (out - dh) * (1 - c * 0.6)                      // (de-hiss: softens only the very top)
            out = dh
            env = max(abs(out), env * 0.9993)
            let th = 0.01 + c * 0.08
            let k = env >= th ? 1.0 : (env / th) * (env / th)
            eg += (k - eg) * 0.003
            out *= eg
        }
        return max(-1, min(1, out))
    }

    private func effects(_ x0: Double, _ r: Double) -> Double {
        var x = x0
        let sv = axes[3].x, gv = axes[3].y
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
        // ECHO
        let ex = axes[6].x
        if ex >= 0.02 {
            let d = max(1, min(echo.count - 1, Int(r * (0.05 + ex * ex * 0.95))))
            let e = echo[(ew - d + echo.count) % echo.count]
            let fb = axes[6].y * 0.85
            echo[ew] = x + e * fb
            ew = (ew + 1) % echo.count
            x += e * 0.6
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
