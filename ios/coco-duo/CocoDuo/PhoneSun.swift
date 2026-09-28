// PhoneSun.swift — coco duo (k.odk)
// APP+CAFE's SUNDAY: a small Sunnandæg on the phone — a sine through three folds (soft clip · triangle fold ·
// rectifier) into a twin peak filter (two resonant peaks), its output fed back into the sine (FM). L goes to Cafe A,
// R to Cafe B (SPREAD pulls them apart). The Cafes answer with an effect that suits it: a string tuned to the
// phone's note (KARPLUS) into a reverb (see Director.sunCafe).

import AVFoundation

final class PhoneSun: ObservableObject {
    // settings: written on the main thread, read by the audio thread (plain numbers, no locks)
    var freq = 110.0, spread = 0.0               // Hz · cents between L and R (±)
    var fold1 = 0.0, fold2 = 0.0, fold3 = 0.0, feedback = 0.0
    var peak1 = 0.3, peak2 = 0.7                 // twin peak positions (0…1 = 60 Hz … 12 kHz)
    var level = 0.7
    /// MOD: a clock (RATE) steps a sample & hold into the sine's pitch (±1 oct) and a shift register into the twin
    /// peak's two positions; each side has its own, so L and R part ways
    var mod = false, rate = 2.0
    /// SYNC: the output fed back as hard sync — the sine starts again where the output rises through zero
    var sync = false
    @Published private(set) var playing = false

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr = 48000.0

    // audio-thread state, one per side
    private var ph = [0.0, 0.0], last = [0.0, 0.0], dc = [0.0, 0.0], dcx = [0.0, 0.0]
    private var lo = [[0.0, 0.0], [0.0, 0.0]], bd = [[0.0, 0.0], [0.0, 0.0]]
    private var fs = 110.0, c1s = 0.3, c2s = 0.7, gain = 0.0
    private var clk = 0.0, sh = [0.0, 0.0], srv = [0.0, 0.0], reg: [UInt8] = [0x5A, 0xA7], seed: UInt32 = 0x2545F491
    private var shs = [0.0, 0.0], srs = [0.0, 0.0]

    func play(_ on: Bool) {
        playing = on
        if on { start() }
    }

    /// started, and kept running: an engine stops by itself whenever the output changes (a USB interface, another
    /// engine setting the session up) — it was left stopped, silent. Called again ~30x a second while it plays.
    func keep() {
        guard playing, node != nil, !engine.isRunning else { return }
        let out = engine.outputNode.outputFormat(forBus: 0), mix = engine.outputNode.inputFormat(forBus: 0)
        if out.channelCount != mix.channelCount || abs(out.sampleRate - mix.sampleRate) > 1 {
            engine.disconnectNodeOutput(engine.mainMixerNode)
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        }
        try? engine.start()
    }

    private func start() {
        if node == nil {
            let s = AVAudioSession.sharedInstance()
            if s.category != .playback && s.category != .playAndRecord { try? s.setCategory(.playback, options: [.mixWithOthers]) }
            try? s.setActive(true)
            let hw = engine.outputNode.outputFormat(forBus: 0).sampleRate
            sr = hw > 1000 ? hw : (s.sampleRate > 0 ? s.sampleRate : 48000)
            let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
            let n = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frames, abl -> OSStatus in
                self.render(Int(frames), UnsafeMutableAudioBufferListPointer(abl))
                return noErr
            }
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: fmt)
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
            node = n
        }
        if !engine.isRunning { try? engine.start() }
    }
    /// silent, and the engine let go (another layer takes the output)
    func stop() {
        playing = false
        gain = 0
        engine.pause()
    }

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let l = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let r = abl.count > 1 ? abl[1].mData!.assumingMemoryBound(to: Float.self) : l
        let want = playing ? level : 0
        let a1 = fold1, a2 = fold2, a3 = fold3, fb = feedback, sp = spread, md = mod, sy = sync
        for i in 0..<frames {
            fs += (freq - fs) * 0.002                                   // (glides: no zipper)
            c1s += (peak1 - c1s) * 0.002
            c2s += (peak2 - c2s) * 0.002
            gain += (want - gain) * 0.0005
            // the clock: S&H (a new pitch) and the shift register (a new pair of peaks), one of each per side
            clk += rate / sr
            if clk >= 1 {
                clk -= 1
                for c in 0..<2 {
                    seed = seed &* 1664525 &+ 1013904223
                    sh[c] = Double(seed >> 8) / Double(1 << 24) * 2 - 1
                    let r = reg[c], bit = ((r >> 7) ^ (r >> 5) ^ (r >> 4) ^ (r >> 3)) & 1
                    reg[c] = (r << 1) | (bit ^ UInt8(seed >> 31))              // (a little noise in: it never locks)
                    srv[c] = Double(reg[c]) / 255 * 2 - 1
                }
            }
            for c in 0..<2 {                                                // (a hair of slew: steps, not clicks)
                shs[c] += ((md ? sh[c] : 0) - shs[c]) * 0.02
                srs[c] += ((md ? srv[c] : 0) - srs[c]) * 0.01
            }
            var o0 = 0.0, o1 = 0.0
            for c in 0..<2 {
                let f = fs * pow(2, (c == 0 ? -sp : sp) / 1200 + shs[c])       // (S&H: ±1 octave)
                ph[c] += f * (1 + fb * last[c] * 2) / sr                   // FEEDBACK: the output back as FM
                ph[c] -= floor(ph[c])
                let x = sin(2 * .pi * ph[c])
                let y = Self.folds(x, a1, a2, a3)
                // TWIN PEAK: two resonant band-passes, summed
                let b1 = svf(y, Self.hz(c1s + srs[c] * 0.25), c, 0), b2 = svf(y, Self.hz(c2s - srs[c] * 0.25), c, 1)   // (SR)
                var v = y * 0.3 + (b1 + b2) * 0.9
                dcx[c] += (v - dcx[c]) * 0.0015; v -= dcx[c]              // (the rectifier's DC out)
                v = tanh(v * 1.2)
                if sy && last[c] < 0 && v >= 0 { ph[c] = 0 }                 // SYNC: the output restarts the sine
                last[c] = v
                if c == 0 { o0 = v * gain } else { o1 = v * gain }
            }
            l[i] = Float(o0); r[i] = Float(o1)
        }
    }

    /// 60 Hz … 12 kHz
    static func hz(_ p: Double) -> Double { 60 * pow(200, min(1, max(0, p))) }

    private func svf(_ x: Double, _ fc: Double, _ c: Int, _ k: Int) -> Double {
        let f = 2 * sin(.pi * min(fc, sr / 6) / sr), q = 0.18        // (Q ≈ 5.5)
        lo[c][k] += f * bd[c][k]
        let hi = x - lo[c][k] - q * bd[c][k]
        bd[c][k] += f * hi
        bd[c][k] = max(-4, min(4, bd[c][k])); lo[c][k] = max(-4, min(4, lo[c][k]))
        return bd[c][k]
    }

    /// the three folds, in a row: soft clip → triangle fold → rectifier (as Sunnandæg's)
    static func folds(_ x0: Double, _ a1: Double, _ a2: Double, _ a3: Double) -> Double {
        var x = x0
        if a1 > 0 {
            let d = 1 + a1 * 8
            let s = tanh(x * d) / tanh(d)
            x = a1 >= 0.1 ? s : x * (1 - a1 / 0.1) + s * (a1 / 0.1)
        }
        if a2 > 0 {
            var f = x * (1 + a2 * 6)
            f = f.truncatingRemainder(dividingBy: 4)
            if f < -2 { f += 4 } else if f > 2 { f -= 4 }
            if f > 1 { f = 2 - f } else if f < -1 { f = -2 - f }
            x = x * (1 - a2) + f * a2
        }
        if a3 > 0 { x = x * (1 - a3) + (abs(x) * 2 - 1) * a3 }
        return x
    }
}
