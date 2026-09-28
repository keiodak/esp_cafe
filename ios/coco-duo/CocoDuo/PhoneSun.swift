// PhoneSun.swift — coco duo (k.odk)
// APP+CAFE's BLIPPOO: a Blippoo Box on the phone (after Rob Hordijk's instrument, from its public descriptions:
// Hordijk's blog, Perfect Circuit's notes on the rungler and the Blippoo Box):
//   two triangle oscillators, A and B, that bend each other's pitch (FM B→A, FM A→B);
//   two RUNGLERS: 8-step shift registers, one clocked by A with B as its data, the other clocked by B with A as its
//     data (each XOR its own last step; LOOP = its own last step only: the pattern held), read by a 3-bit DAC from
//     the last three steps — the "stepped havoc" CVs, each back onto the other oscillator's pitch and onto one peak;
//   S&H: B's triangle taken on A's clock;
//   the COMPARATOR: the S&H against A's triangle (S&H off: B against A) — a pulse, the sound;
//   the TWIN PEAK: two 18 dB (three-pole) low-passes sharing one resonance, their outputs subtracted: a peak stands
//     at each cutoff and the band between them passes (the upper one's input tilted up so both peaks are heard).
// L = the twin peak (→ Cafe A), R = its lower filter alone (→ Cafe B). No random anywhere.
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
    /// S&H: the comparator weighs the S&H against A (off: B against A)
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
    private var r1: UInt8 = 0b1011_0010, r2: UInt8 = 0b0110_1001  // the two runglers
    private var d1 = 0.0, d2 = 0.0, d1s = 0.0, d2s = 0.0              // their DACs (and a hair rounded)
    private var sh = 0.0
    private var la = [0.0, 0.0, 0.0], lb = [0.0, 0.0, 0.0]         // the twin peak's two three-pole low-passes
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

    /// 40 Hz … 6 kHz (where the peak stands)
    static func hz(_ p: Double) -> Double { 40 * pow(150, min(1, max(0, p))) }

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let l = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let r = abl.count > 1 ? abl[1].mData!.assumingMemoryBound(to: Float.self) : l
        let want = playing ? level : 0
        let k = res * 8.4                                   // (three poles ring at 8: the top sings by itself)
        let comp = 1 + k * 0.5
        for i in 0..<frames {
            fA += (freqA - fA) * 0.002; fB += (freqB - fB) * 0.002
            gain += (want - gain) * 0.0005
            let triA = 1 - 4 * abs(pa - 0.5), triB = 1 - 4 * abs(pb - 0.5)
            d1s += (d1 - d1s) * 0.02; d2s += (d2 - d2s) * 0.02
            // pitch: the other's triangle (cross FM) and the other rungler, in octaves
            let a = fA * pow(2, triB * fmBA * 3 + (d2s - 0.5) * 4 * runOsc)
            let b = fB * pow(2, triA * fmAB * 3 + (d1s - 0.5) * 4 * runOsc)
            pa += min(0.45, a / sr); pa -= floor(pa)
            pb += min(0.45, b / sr); pb -= floor(pb)
            let nA = triA > 0, nB = triB > 0
            if nA && !sqA {                                  // A's clock: rungler 1 takes B, the S&H takes B
                let last = (r1 >> 7) & 1
                r1 = (r1 << 1) | (loop ? last : last ^ (nB ? 1 : 0))
                d1 = Double((r1 >> 5) & 0b111) / 7
                sh = triB
            }
            if nB && !sqB {                                  // B's clock: rungler 2 takes A
                let last = (r2 >> 7) & 1
                r2 = (r2 << 1) | (loop ? last : last ^ (nA ? 1 : 0))
                d2 = Double((r2 >> 5) & 0b111) / 7
            }
            sqA = nA; sqB = nB
            // the comparator: the S&H (or B) against A
            let cmp = (mod ? sh : triB) > triA ? 1.0 : -1.0
            // the twin peak: each peak on its rungler
            let f1 = Self.hz(peakA + (d1s - 0.5) * runPeak * 0.8), f2 = Self.hz(peakB + (d2s - 0.5) * runPeak * 0.8)
            let lo = min(f1, f2) / 1.732, hi = max(f1, f2) / 1.732          // (three poles peak at √3 × their corner)
            let tilt = min(4, max(1, (hi / lo).squareRoot()))
            let low = ladder(cmp, lo, k, &la) * comp
            let high = ladder(cmp * tilt, hi, k, &lb) * comp / tilt.squareRoot()
            var tp = high - low, side = low
            dcL += (tp - dcL) * 0.002; tp -= dcL
            dcR += (side - dcR) * 0.002; side -= dcR
            l[i] = Float(tanh(tp * 0.6) * gain)
            r[i] = Float(tanh(side * 0.6) * gain)
        }
    }

    /// a three-pole low-pass (18 dB); the resonance fed back from its last pole through a soft limit
    private func ladder(_ x: Double, _ fc: Double, _ k: Double, _ s: inout [Double]) -> Double {
        let g = 1 - exp(-2 * .pi * min(fc, sr * 0.3) / sr)
        let u = x - k * tanh(s[2])
        s[0] += g * (u - s[0])
        s[1] += g * (s[0] - s[1])
        s[2] += g * (s[1] - s[2])
        if !s[2].isFinite { s = [0, 0, 0] }
        return s[2]
    }
}
