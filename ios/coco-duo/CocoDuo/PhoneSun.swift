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
    @Published private(set) var playing = false

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr = 48000.0

    // audio-thread state, one per side
    private var ph = [0.0, 0.0], last = [0.0, 0.0], dc = [0.0, 0.0], dcx = [0.0, 0.0]
    private var lo = [[0.0, 0.0], [0.0, 0.0]], bd = [[0.0, 0.0], [0.0, 0.0]]
    private var fs = 110.0, c1s = 0.3, c2s = 0.7, gain = 0.0

    func play(_ on: Bool) {
        playing = on
        if on { start() }
    }

    private func start() {
        if node == nil {
            let s = AVAudioSession.sharedInstance()
            try? s.setCategory(.playback, options: [.mixWithOthers])
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
        let a1 = fold1, a2 = fold2, a3 = fold3, fb = feedback, sp = spread
        for i in 0..<frames {
            fs += (freq - fs) * 0.002                                   // (glides: no zipper)
            c1s += (peak1 - c1s) * 0.002
            c2s += (peak2 - c2s) * 0.002
            gain += (want - gain) * 0.0005
            var o0 = 0.0, o1 = 0.0
            for c in 0..<2 {
                let f = fs * pow(2, (c == 0 ? -sp : sp) / 1200)
                ph[c] += f * (1 + fb * last[c] * 2) / sr                   // FEEDBACK: the output back as FM
                ph[c] -= floor(ph[c])
                let x = sin(2 * .pi * ph[c])
                let y = Self.folds(x, a1, a2, a3)
                // TWIN PEAK: two resonant band-passes, summed
                let b1 = svf(y, Self.hz(c1s), c, 0), b2 = svf(y, Self.hz(c2s), c, 1)
                var v = y * 0.3 + (b1 + b2) * 0.9
                dcx[c] += (v - dcx[c]) * 0.0015; v -= dcx[c]              // (the rectifier's DC out)
                v = tanh(v * 1.2)
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
