// PhoneSun.swift — coco duo (k.odk)
// APP+CAFE's SUNDAY: a small Sunnandæg on the phone, made the way Sunnandæg makes it —
//   sine -> FOLD 1 (soft clip) -> FOLD 2 (triangle fold) -> FOLD 3 (rectifier); the folds' output back into the sine
//   (FEEDBACK: as FM, or with SYNC as a pull of the phase to 0 where it rises past 1 − FEEDBACK);
//   S&H: FOLD 2 rising through 0 is the gate (÷ DIV), FOLD 1 the data -> the pitch (±1 oct);
//   SHIFT REGISTER: FOLD 3 the gate (÷ DIV), FOLD 1 the data, 8 steps -> both twin peak positions;
//   TWIN PEAK: two resonant band-passes, peak 1 riding FOLD 2, peak 2 riding FOLD 3 around PEAK 1 / PEAK 2 — that is
//   the output (as Sunnandæg's, no dry). No random anywhere: it all comes from the sound itself.
// L goes to Cafe A, R to Cafe B (a few cents apart: the two run their own way). The Cafes answer with a string
// tuned to the phone's note (KARPLUS) into a reverb (see Director.sunCafe).

import AVFoundation

final class PhoneSun: ObservableObject {
    // settings: written on the main thread, read by the audio thread (plain numbers, no locks)
    var freq = 110.0, spread = 6.0               // Hz · cents between L and R
    var fold1 = 0.0, fold2 = 0.0, fold3 = 0.0, feedback = 0.0
    var peak1 = 0.2, peak2 = 0.45                // twin peak positions (0…1 over ~80 Hz … 4 kHz)
    var level = 0.7
    /// MOD: the S&H into the pitch and the shift register into the twin peak (off: neither moves anything)
    var mod = false
    /// DIV: how many gates make one step of the S&H and the shift register (0 … 0.9995 -> ÷1 … ÷2000)
    var div = 0.5
    /// SYNC: the feedback goes back as sync instead of FM
    var sync = false
    @Published private(set) var playing = false

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr = 48000.0

    /// one side's circuit
    private struct Side {
        var phase = 0.0, prev = 0.0, syncPrev = 0.0
        var s1 = 0.0, s2 = 0.0, s3 = 0.0
        var shGate = 0.0, shCount = 0, sh = 0.0, shFactor = 1.0
        var srGate = 0.0, srCount = 0, reg = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0), srOut = 0.0
        var low1 = 0.0, band1 = 0.0, low2 = 0.0, band2 = 0.0
        var held1 = 300.0, held2 = 3000.0, cut1 = 300.0, cut2 = 3000.0, ctl = 0
    }
    private var side = [Side(), Side()]
    private var fs = 110.0, gain = 0.0
    private let q = 20.0, depth = 0.35, dataGain = 1.8, boost = 2.5
    private let loNorm = 0.05, hiNorm = 0.75         // (the peaks' range: ~80 Hz … ~4 kHz — higher only shrieked)

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
        for i in 0..<frames {
            fs += (freq - fs) * 0.002                                   // (glides: no zipper)
            gain += (want - gain) * 0.0005
            let a = tick(0), b = tick(1)
            l[i] = Float(a * gain); r[i] = Float(b * gain)
        }
    }

    private func tick(_ c: Int) -> Double {
        var s = side[c]
        let fb = feedback, md = mod
        let wSync = sync ? 1.0 : 0.0, wFM = sync ? 0.0 : 1.0
        let prev = s.prev
        // the sine: S&H on its speed, the feedback as FM or as sync
        let f = fs * pow(2, (c == 0 ? -spread : spread) / 2400)
        s.phase += f / sr * (md ? s.shFactor : 1)
        s.phase -= floor(s.phase)
        let th = 1 - fb
        if s.syncPrev < th && prev >= th { s.phase *= 1 - wSync }
        s.syncPrev = prev
        let sine = sin(2 * .pi * (s.phase + prev * fb * 2 * wFM))
        // the three folds
        s.s1 = Self.stage1(sine, fold1)
        s.s2 = Self.stage2(s.s1, fold2)
        s.s3 = Self.stage3(s.s2, fold3)
        let mx = max(max(fold1, fold2), max(fold3, fb))
        let out = mx <= 0 ? s.s3 : (mx >= 0.05 ? tanh(s.s3) : s.s3 * (1 - mx / 0.05) + tanh(s.s3) * (mx / 0.05))
        s.prev = out
        let ratio = min(5000, max(1, Int(1 / max(1 - min(div, 0.9995), 0.0002))))
        // SHIFT REGISTER: FOLD 3 rising through 0, ÷ DIV -> FOLD 1 in; its last step out
        if s.srGate < 0 && s.s3 >= 0 {
            s.srCount += 1
            if s.srCount >= ratio {
                s.srCount = 0
                let g = s.reg
                s.reg = (tanh(s.s1 * dataGain), g.0, g.1, g.2, g.3, g.4, g.5, g.6)
                s.srOut = s.reg.7
            }
        }
        s.srGate = s.s3
        // S&H: FOLD 2 rising through 0, ÷ DIV -> FOLD 1 held -> the pitch (±1 oct)
        if s.shGate < 0 && s.s2 >= 0 {
            s.shCount += 1
            if s.shCount >= ratio {
                s.shCount = 0
                s.sh = tanh(s.s1 * dataGain)
                s.shFactor = pow(2, s.sh)
            }
        }
        s.shGate = s.s2
        // TWIN PEAK: peak 1 rides FOLD 2, peak 2 FOLD 3, around PEAK 1 / 2; the shift register moves both
        if s.ctl % 8 == 0 {
            let lr = log(250.0), lo = 60 * exp(loNorm * lr), hi = 60 * exp(hiNorm * lr), span = log(hi / lo)
            func n(_ v: Double) -> Double { min(1, max(0, 0.5 + (min(1, max(0, (v + 1) / 2)) - 0.5) * boost)) }
            var c1 = min(1, max(0, peak1 + (n(s.s2) - 0.5) * depth * 2))
            var c2 = min(1, max(0, peak2 + (n(s.s3) - 0.5) * depth * 2))
            if md { c1 = min(1, max(0, c1 + s.srOut * 0.5)); c2 = min(1, max(0, c2 + s.srOut * 0.5)) }
            s.held1 = lo * exp(c1 * span); s.held2 = lo * exp(c2 * span)
        }
        s.ctl &+= 1
        s.cut1 += (s.held1 - s.cut1) * 0.25
        s.cut2 += (s.held2 - s.cut2) * 0.25
        let p1 = bp(out, s.cut1, &s.low1, &s.band1), p2 = bp(out, s.cut2, &s.low2, &s.band2)
        let at1 = min(1, max(0, (s.cut1 - 80) / 70)) * 0.6 + 0.4, at2 = min(1, max(0, (s.cut2 - 80) / 70)) * 0.6 + 0.4
        var y = (p1 * at1 + p2 * at2) * 0.5
        if !y.isFinite { s.low1 = 0; s.band1 = 0; s.low2 = 0; s.band2 = 0; y = 0 }
        else if abs(y) > 2 { let e = abs(y) - 2; y = (y >= 0 ? 1 : -1) * (2 + tanh(e / 2) * 2) }
        side[c] = s
        return tanh(y * 0.9)
    }

    /// Sunnandæg's band-pass (Chamberlin, held below its unstable corner)
    private func bp(_ x: Double, _ cutoff: Double, _ low: inout Double, _ band: inout Double) -> Double {
        let f = 2 * sin(.pi * min(cutoff, sr / 6) / sr)
        let qInv = max(1 / max(q, 0.5), max(0, f - 0.92))
        let high = x - low - qInv * band
        band += f * high
        low += f * band
        return band
    }

    /// twin peak's positions in Hz (for the captions): 0…1 over ~80 Hz … 4 kHz
    static func hz(_ p: Double) -> Double {
        let lr = log(250.0), lo = 60 * exp(0.05 * lr), hi = 60 * exp(0.75 * lr)
        return lo * exp(min(1, max(0, p)) * log(hi / lo))
    }

    // Sunnandæg's three stages
    static func stage1(_ x: Double, _ a: Double) -> Double {
        guard a > 0 else { return x }
        let d = 1 + a * 8, s = tanh(x * d) / tanh(d)
        return a >= 0.1 ? s : x * (1 - a / 0.1) + s * (a / 0.1)
    }
    static func stage2(_ x: Double, _ a: Double) -> Double {
        guard a > 0 else { return x }
        var f = (x * (1 + a * 6)).truncatingRemainder(dividingBy: 4)
        if f < -2 { f += 4 } else if f > 2 { f -= 4 }
        if f > 1 { f = 2 - f } else if f < -1 { f = -2 - f }
        return x * (1 - a) + f * a
    }
    static func stage3(_ x: Double, _ a: Double) -> Double {
        guard a > 0 else { return x }
        return x * (1 - a) + (abs(x) * 2 - 1) * a
    }
}
