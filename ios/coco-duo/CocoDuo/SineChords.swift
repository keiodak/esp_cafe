// SineChords.swift — coco duo (k.odk)
// APP+CAFE+OTHER's second layer (COCO+SINE): the phone plays too — a chord of sine waves at each SKIP / FLIP of either
// Cafe (built from Cafe A's CHORD · SPREAD and OCTAVE · RANGE, in the one scale). Up to 16 voices, each a sine with a
// short attack and a release; held while the gate is up (HOLD) or for the set LENGTH, as the OP-1's notes.

import AVFoundation
import os

final class SineChords {
    /// 0…1 (the SINE pad's X)
    var level = 0.6
    /// seconds a voice takes to die away once let go (the SINE pad's Y)
    var release = 0.6
    /// the voice's sound (BOUNCE's iOS key): 0 SINE · 1 TRI · 2 BELL (FM, ×1.4, the index dying with the note) · 3 ORGAN · 4 SQUARE
    static let waveNames = ["SINE", "TRI", "BELL", "ORGAN", "SQUARE"]
    var wave = 0
    private(set) var playing = false

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr = 48000.0

    // main thread -> audio thread: a short list of events behind a lock the audio thread only tries
    private enum Ev { case on([Int], [Double], Double), off([Int]), allOff, pluck(Double, Double, Double) }
    private var lock = os_unfair_lock()
    private var pending: [Ev] = []

    // the voices (audio thread only)
    private struct Voice { var key: [Int] = []; var hz = 0.0; var ph = 0.0; var amp = 0.0; var target = 0.0; var gate = false; var vel = 0.0; var live = false; var hold = 0; var rel = 0.0; var mph = 0.0 }
    private var v = [Voice](repeating: Voice(), count: 16)
    private var gain = 0.0

    func noteOn(_ key: [Int], notes: [UInt8], velocity: Int) {
        let hz = notes.map { 440 * pow(2, (Double($0) - 69) / 12) }
        push(.on(key, hz, Double(velocity) / 127))
    }
    func noteOff(_ key: [Int]) { push(.off(key)) }
    /// BOUNCE: one note struck — a short attack, then it dies away in `decay` seconds by itself
    func pluck(_ note: UInt8, velocity: Int, decay: Double) {
        push(.pluck(440 * pow(2, (Double(note) - 69) / 12), Double(velocity) / 127, decay))
    }
    private func push(_ e: Ev) {
        os_unfair_lock_lock(&lock); pending.append(e); os_unfair_lock_unlock(&lock)
    }

    func play(_ on: Bool) {
        if on == playing { if on { keep() }; return }
        playing = on
        if on { start() } else {
            push(.allOff)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in if self?.playing == false { self?.engine.pause() } }
        }
    }
    /// started, and kept running (an output change stops an engine by itself)
    func keep() {
        guard playing, node != nil, !engine.isRunning else { return }
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

    private func take() {
        guard os_unfair_lock_trylock(&lock) else { return }
        let evs = pending; pending.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&lock)
        for e in evs {
            switch e {
            case .allOff:
                for k in v.indices { v[k].gate = false }
            case .off(let key):
                for k in v.indices where v[k].live && v[k].key == key { v[k].gate = false }
            case .pluck(let hz, let vel, let decay):
                var best = -1, bestAmp = 9.0
                for k in v.indices {
                    if !v[k].live { best = k; break }
                    if !v[k].gate && v[k].amp < bestAmp { bestAmp = v[k].amp; best = k }
                }
                if best < 0 { best = 0 }
                v[best] = Voice(key: [-1], hz: hz, ph: 0, amp: 0, target: 0, gate: true, vel: vel, live: true,
                                hold: Int(sr * 0.015), rel: 1 - exp(-1 / (sr * max(0.02, decay) / 6.9)))
            case .on(let key, let hzs, let vel):
                for k in v.indices where v[k].live && v[k].key == key { v[k].gate = false }   // (the same key again: the last lets go)
                for hz in hzs {
                    // a free voice, or the quietest one let go
                    var best = -1, bestAmp = 9.0
                    for k in v.indices {
                        if !v[k].live { best = k; break }
                        if !v[k].gate && v[k].amp < bestAmp { bestAmp = v[k].amp; best = k }
                    }
                    if best < 0 { best = 0 }
                    v[best] = Voice(key: key, hz: hz, ph: 0, amp: v[best].live ? v[best].amp : 0, target: 0, gate: true, vel: vel, live: true)
                }
            }
        }
    }

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        take()
        let l = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let r = abl.count > 1 ? abl[1].mData!.assumingMemoryBound(to: Float.self) : l
        let att = 1 - exp(-1 / (sr * 0.006))                                   // ~6 ms attack (no click)
        let rel = 1 - exp(-1 / (sr * max(0.02, release) / 4.6))               // to −40 dB in `release` s
        let want = playing ? level : 0                                     // (was level²: too quiet)
        var live = 0
        for k in v.indices where v[k].live { live += 1 }
        let n = Double(max(1, live))
        let norm = 0.5 / pow(n, 0.35)                                          // (a chord about as loud as a note)
        let tw = 2 * Double.pi / sr
        let wv = wave
        for i in 0..<frames {
            gain += (want - gain) * 0.0008
            var s = 0.0
            for k in v.indices where v[k].live {
                let tgt = v[k].gate ? v[k].vel : 0
                v[k].amp += (tgt - v[k].amp) * (v[k].gate ? att : (v[k].rel > 0 ? v[k].rel : rel))
                if v[k].hold > 0 { v[k].hold -= 1; if v[k].hold == 0 { v[k].gate = false } }
                let ph = v[k].ph
                var w: Double
                switch wv {
                case 1: w = 1 - 4 * abs(ph / (2 * Double.pi) - 0.5)                                  // TRI
                case 2: w = sin(ph + 2.4 * (v[k].amp / max(0.01, v[k].vel)) * sin(v[k].mph))        // BELL
                        v[k].mph += v[k].hz * 1.4 * tw; if v[k].mph > 2 * Double.pi { v[k].mph -= 2 * Double.pi }
                case 3: w = (sin(ph) + 0.5 * sin(2 * ph) + 0.25 * sin(3 * ph)) * 0.62               // ORGAN
                case 4: w = (sin(ph) + sin(3 * ph) / 3 + sin(5 * ph) / 5 + sin(7 * ph) / 7) * 0.85 // SQUARE (soft)
                default: w = sin(ph)
                }
                s += w * v[k].amp
                v[k].ph += v[k].hz * tw
                if v[k].ph > 2 * Double.pi { v[k].ph -= 2 * Double.pi }
                if !v[k].gate && v[k].amp < 0.0005 { v[k].live = false }
            }
            let o = Float(tanh(s * norm * gain * 2.2) * 0.9)                // louder, and a soft limit (no clipping)
            l[i] = o; r[i] = o
        }
    }
}
