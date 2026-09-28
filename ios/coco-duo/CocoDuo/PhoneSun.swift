// PhoneSun.swift — coco duo (k.odk)
// APP+CAFE's BLIPPOO: a Blippoo Box on the phone (after Rob Hordijk's instrument, from its public descriptions):
//   two triangle oscillators, A and B, that bend each other's pitch (FM B→A, FM A→B);
//   the RUNGLER: an 8-step shift register clocked by A's square, fed with B's square (XOR its own last step; LOOP
//     = its own last step only, the pattern held), read by a 3-bit DAC from its last three steps — back onto both
//     oscillators' pitch and onto the filter's peaks;
//   S&H: B's triangle sampled on A's clock, onto the peaks;
//   the sound: the COMPARATOR (A's triangle against B's) into the TWIN PEAK — two resonant 18 dB low-passes whose
//     outputs are subtracted, so two peaks stand at their cutoffs with the band between.
// L = the twin peak's band (→ Cafe A), R = its low side (→ Cafe B). No random anywhere: it all comes from the circuit.
// The Cafes answer with a string tuned to B (KARPLUS) into a reverb (see Director.sunCafe).

import AVFoundation

final class PhoneSun: ObservableObject {
    // settings: written on the main thread, read by the audio thread (plain numbers, no locks)
    var freqA = 3.0, freqB = 180.0               // Hz
    var fmBA = 0.2, fmAB = 0.2                   // cross FM (0…1)
    var runOsc = 0.4, runPeak = 0.4              // RUNGLER → both oscillators · → the peaks
    var peakA = 0.3, peakB = 0.6                 // the two cutoffs (0…1 over 40 Hz … 6 kHz)
    var res = 0.85                               // resonance
    var level = 0.7
    /// S&H onto the peaks
    var mod = true
    /// LOOP: the rungler takes only its own last step (the pattern goes round, held)
    var loop = false
    @Published private(set) var playing = false

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr = 48000.0

    // the circuit (audio thread)
    private var pa = 0.0, pb = 0.25
    private var sqA = false, sqB = false
    private var reg: UInt8 = 0b1011_0010
    private var rung = 0.0, rungS = 0.0
    private var sh = 0.0, shS = 0.0
    private var la = [0.0, 0.0, 0.0], lb = [0.0, 0.0, 0.0]   // two three-pole ladders
    private var gain = 0.0, dcL = 0.0, dcR = 0.0
    private var fA = 3.0, fB = 180.0

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

    /// 40 Hz … 6 kHz
    static func hz(_ p: Double) -> Double { 40 * pow(150, min(1, max(0, p))) }

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let l = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let r = abl.count > 1 ? abl[1].mData!.assumingMemoryBound(to: Float.self) : l
        let want = playing ? level : 0
        let k = res * 7.5                                   // (three poles ring at 8)
        for i in 0..<frames {
            fA += (freqA - fA) * 0.002; fB += (freqB - fB) * 0.002
            gain += (want - gain) * 0.0005
            // the two triangles (−1…1) and their squares
            let triA = 1 - 4 * abs(pa - 0.5), triB = 1 - 4 * abs(pb - 0.5)
            rungS += (rung - rungS) * 0.02                       // (the DAC's steps, a hair rounded)
            shS += (sh - shS) * 0.02
            // pitch: the other's triangle (cross FM) and the rungler, in octaves
            let ra = (rungS - 0.5) * 4 * runOsc
            let a = fA * pow(2, triB * fmBA * 3 + ra)
            let b = fB * pow(2, triA * fmAB * 3 + ra * 0.75)
            pa += min(0.45, a / sr); pa -= floor(pa)
            pb += min(0.45, b / sr); pb -= floor(pb)
            let nA = triA > 0, nB = triB > 0
            // A's square rising: the rungler steps (data = B's square XOR its last step; LOOP = its last step) and
            // the S&H takes B's triangle
            if nA && !sqA {
                let last = (reg >> 7) & 1
                let bit: UInt8 = loop ? last : (last ^ (nB ? 1 : 0))
                reg = (reg << 1) | bit
                rung = Double((reg >> 5) & 0b111) / 7                  // 3-bit DAC of the last three steps
                sh = triB
            }
            sqA = nA; sqB = nB
            // the comparator: A's triangle against B's
            let cmp = triA > triB ? 0.8 : -0.8
            // the peaks: their base, the rungler, the S&H
            var ca = peakA + (rungS - 0.5) * runPeak * 0.8
            var cb = peakB + (rungS - 0.5) * runPeak * 0.8
            if mod { ca += shS * 0.25; cb += shS * 0.25 }
            let fa = Self.hz(ca), fb = Self.hz(cb)
            let lo = min(fa, fb), hi = max(fa, fb)
            let low = ladder(cmp, lo, k, &la), high = ladder(cmp, hi, k, &lb)
            var band = high - low                               // TWIN PEAK: the two subtracted
            var side = low
            dcL += (band - dcL) * 0.001; band -= dcL
            dcR += (side - dcR) * 0.001; side -= dcR
            l[i] = Float(tanh(band * 1.4) * gain)
            r[i] = Float(tanh(side * 1.2) * gain)
        }
    }

    /// a three-pole low-pass (18 dB) with resonance fed back from its last pole
    private func ladder(_ x: Double, _ fc: Double, _ k: Double, _ s: inout [Double]) -> Double {
        let g = 1 - exp(-2 * .pi * min(fc, sr * 0.3) / sr)
        let u = tanh(x - k * s[2])
        s[0] += g * (u - s[0])
        s[1] += g * (s[0] - s[1])
        s[2] += g * (s[1] - s[2])
        if !s[2].isFinite { s = [0, 0, 0] }
        return s[2] * (1 + k * 0.5)                               // (the resonance's loss made up)
    }
}
