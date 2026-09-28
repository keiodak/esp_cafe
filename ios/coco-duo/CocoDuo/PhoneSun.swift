// PhoneSun.swift — coco duo (k.odk)
// APP+CAFE's BLIPPOO: a Blippoo Box on the phone, after Rob Hordijk's own description ("The Blippoo Box: A Chaotic
// Electronic Music Instrument, Bent by Design", Leonardo Music Journal 19, 2009) and notes from those who rebuilt it:
//   the CHAOTIC CORE — two oscillators (triangle and square, exponential, ~16 octaves up to 12 kHz) that bend each
//   other three ways:
//     SWEEP: the other's triangle onto the pitch (two knobs);
//     STEP: two runglers — short single-bit delay lines (4 steps, cross-patched, no XOR): one clocked by B's square
//       taking A's square, the other clocked by A's square taking B's; three consecutive steps read as a 3-bit
//       level (seven steps) — each onto the other oscillator (two knobs);
//     TIME WARP: a sample & hold, clocked each time the two triangles are equal, taking triangle B (or the mix of
//       the two runglers), onto both oscillators (one knob);
//   the TWIN PEAK RESONATOR — two parallel, highly resonant three-pole low-passes, the second subtracted from the
//   first, pinged by that same pulse train (a short pulse whenever the triangles meet); its "distortion": the second
//   filter's second pole fed back onto both cutoffs.
// Mono, the same to L and R. No random anywhere.

import AVFoundation
import SwiftUI

final class PhoneSun: ObservableObject {
    // settings: written on the main thread, read by the audio thread (plain numbers, no locks)
    var oscA = 0.55, oscB = 0.75                 // pitch knobs (0…1 over ~16 octaves, 12 kHz at the top)
    var sweepBA = 0.2, sweepAB = 0.2             // SWEEP: B's triangle → A · A's → B
    var stepA = 0.3, stepB = 0.3                 // STEP: rungler → A · rungler → B
    var shAmt = 0.2, shSrc = 0.0                 // TIME WARP: S&H → both oscillators · what it takes (triangle B … the runglers)
    var peakA = 0.35, peakB = 0.6                // the resonator's two peaks (0…1 over 30 Hz … 9 kHz)
    var q = 0.9, dist = 0.2                      // resonance (shared) · distortion (filter 2's second pole → the cutoffs)
    var runPA = 0.3, runPB = 0.3                 // rungler → peak A · rungler → peak B
    var ping = 0.3, dry = 0.0                    // the pulse's length · the pulses themselves in the output
    var level = 0.7
    @Published private(set) var playing = false

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr = 48000.0

    // the circuit (audio thread)
    private var pa = 0.0, pb = 0.3
    private var sqA = false, sqB = false
    private var r1: UInt8 = 0b0101, r2: UInt8 = 0b1100             // the two runglers (4 steps each)
    private var d1 = 0.0, d2 = 0.0
    private var sh = 0.0
    private var prevD = 0.0, pulseLeft = 0
    private var l1 = [0.0, 0.0, 0.0], l2 = [0.0, 0.0, 0.0]         // the two three-pole low-passes
    private var gain = 0.0, dc = 0.0
    private var sA = 0.55, sB = 0.75

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

    /// 30 Hz … 9 kHz (where a peak stands)
    static func hz(_ p: Double) -> Double { 30 * pow(300, min(1, max(0, p))) }
    /// an oscillator's knob: ~16 octaves below 12 kHz
    static func oscHz(_ x: Double) -> Double { 12000 * pow(2, -(1 - min(1, max(0, x))) * 16) }

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let l = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let r = abl.count > 1 ? abl[1].mData!.assumingMemoryBound(to: Float.self) : l
        let want = playing ? level : 0
        let k = q * 8.2                                     // (three poles sing by themselves at 8)
        let comp = 1 + k * 0.5
        let pingN = max(1, Int(sr * (0.00005 + ping * ping * 0.003)))
        for i in 0..<frames {
            sA += (oscA - sA) * 0.002; sB += (oscB - sB) * 0.002
            gain += (want - gain) * 0.0005
            let triA = 1 - 4 * abs(pa - 0.5), triB = 1 - 4 * abs(pb - 0.5)
            // the chaotic core: sweep (the other's triangle), step (a rungler), time warp (the S&H), in octaves
            let a = Self.oscHz(sA) * pow(2, sweepBA * triB * 4 + stepA * (d1 - 0.5) * 4 + shAmt * sh * 3)
            let b = Self.oscHz(sB) * pow(2, sweepAB * triA * 4 + stepB * (d2 - 0.5) * 4 + shAmt * sh * 3)
            pa += min(0.45, a / sr); pa -= floor(pa)
            pb += min(0.45, b / sr); pb -= floor(pb)
            let nA = triA > 0, nB = triB > 0
            if nB && !sqB { r1 = ((r1 << 1) | (nA ? 1 : 0)) & 0xF; d1 = Double((r1 >> 1) & 0b111) / 7 }   // B clocks, A in
            if nA && !sqA { r2 = ((r2 << 1) | (nB ? 1 : 0)) & 0xF; d2 = Double((r2 >> 1) & 0b111) / 7 }   // A clocks, B in
            sqA = nA; sqB = nB
            // the triangles meet: a pulse (it pings the resonator) and the S&H takes its value
            let dlt = triA - triB
            if (dlt >= 0) != (prevD >= 0) {
                pulseLeft = pingN
                sh = triB * (1 - shSrc) + (d1 + d2 - 1) * shSrc
            }
            prevD = dlt
            let x: Double = pulseLeft > 0 ? 1 : 0
            if pulseLeft > 0 { pulseLeft -= 1 }
            // the twin peak resonator (its peaks on the runglers; filter 2's second pole back onto both: distortion)
            let fm = pow(2, dist * l2[1] * 2)
            let f1 = Self.hz(peakA + runPA * (d1 - 0.5) * 0.6) * fm / 1.732      // (three poles peak at √3 × their corner)
            let f2 = Self.hz(peakB + runPB * (d2 - 0.5) * 0.6) * fm / 1.732
            ladder(x, f1, k, &l1)
            ladder(x, f2, k, &l2)
            var y = (l1[2] - l2[2]) * comp + (x - 0.5) * dry
            dc += (y - dc) * 0.002; y -= dc
            let o = Float(tanh(y * 0.7) * gain)
            l[i] = o; r[i] = o
        }
    }

    /// a three-pole low-pass (18 dB); the resonance fed back from its last pole through a soft limit
    private func ladder(_ x: Double, _ fc: Double, _ k: Double, _ s: inout [Double]) {
        let g = 1 - exp(-2 * .pi * min(fc, sr * 0.3) / sr)
        let u = x - k * tanh(s[2])
        s[0] += g * (u - s[0])
        s[1] += g * (s[0] - s[1])
        s[2] += g * (s[1] - s[2])
        if !s[2].isFinite { s = [0, 0, 0] }
    }
}
