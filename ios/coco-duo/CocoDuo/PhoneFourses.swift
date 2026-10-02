// PhoneFourses.swift — coco duo (k.odk)
// iOS (preset 6) · FOURSES: the Fourses on the phone itself — the Fourses app's circuit (FoursesDSP.c), driven by the
// same board: its shapes and fingers become the circuit's links, the pots / ranges / STARVE set it. The board's
// nodes are the Cafe's (one board: TARPTERGE, its terminals, half of INTERSEXON); they are named here as the
// circuit has them. What the phone cannot have (IN, EARTH, LINK) is left out.

import AVFoundation
import os

final class PhoneFourses {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private(set) var fr: OpaquePointer?
    private var running = false
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 8192)

    /// the board's node -> the circuit's (nil: nothing on the phone)
    static func node(_ n: Int) -> Int? {
        switch n {
        case 0..<44: return n                                   // TARPTERGE
        case 46: return 46                                      // OUT A -> left
        case 77, 47: return 47                                  // OUT B, ASH A -> right
        case 48...52: return n                                  // the fingers
        case 53..<57: return 300 + n - 53                       // S&H IN
        case 57..<61: return 310 + n - 57                       // S&H GATE
        case 61..<65: return 320 + n - 61                       // S&H OUT
        case 65..<73: return 330 + n - 65                       // the current cells
        case 100..<116: return n                                // a shape's own voltage
        default: return nil
        }
    }

    func play(_ on: Bool) {
        if on == running { return }
        running = on
        if on { start() } else { engine.pause() }
    }

    private func start() {
        if fr == nil {
            let s = AVAudioSession.sharedInstance()
            if s.category != .playback && s.category != .playAndRecord { try? s.setCategory(.playback, options: [.mixWithOthers]) }
            try? s.setActive(true)
            let hw = engine.outputNode.outputFormat(forBus: 0).sampleRate
            let rate = hw > 8000 ? hw : 48000
            fr = fr_create(rate)
            guard let e = fr, let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
            let scratch = self.scratch
            let src = AVAudioSourceNode(format: fmt) { _, _, frames, abl in
                let bufs = UnsafeMutableAudioBufferListPointer(abl)
                guard bufs.count > 0, let l = bufs[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                if bufs.count > 1, let r = bufs[1].mData?.assumingMemoryBound(to: Float.self) { fr_render(e, l, r, Int32(frames)) }
                else { fr_render(e, l, scratch, Int32(min(Int(frames), 8192))) }
                return noErr
            }
            engine.attach(src)
            engine.connect(src, to: engine.mainMixerNode, format: fmt)
            node = src
            onReady?()
        }
        if !engine.isRunning { try? engine.start() }
    }
    /// the circuit was made: everything must be sent to it
    var onReady: (() -> Void)?

    // MARK: what the board sets

    private var links: [[Int]: Int] = [:]                      // (shapes)
    private var fingers: [[Int]: Int] = [:]
    func setShapeLinks(_ l: [[Int]]) {
        var now: [[Int]: Int] = [:]
        for w in l where w.count >= 3 {
            guard let a = Self.node(w[0]), let b = Self.node(w[1]) else { continue }
            now[[min(a, b), max(a, b)]] = max(now[[min(a, b), max(a, b)]] ?? 0, w[2])
        }
        if now != links { links = now; push() }
    }
    func setFingerLinks(_ m: [Int: [Int: Int]]) {
        var now: [[Int]: Int] = [:]
        for (f, row) in m {
            for (i, v) in row {
                guard let a = Self.node(f), let b = Self.node(i) else { continue }
                now[[min(a, b), max(a, b)]] = max(1, min(1000, v))
            }
        }
        if now != fingers { fingers = now; push() }
    }
    private func push() {
        guard let e = fr else { return }
        var a: [Int32] = [], b: [Int32] = [], v: [Int32] = []
        for (k, x) in links { a.append(Int32(k[0])); b.append(Int32(k[1])); v.append(Int32(x)) }
        for (k, x) in fingers { a.append(Int32(k[0])); b.append(Int32(k[1])); v.append(Int32(x)) }
        let n = min(a.count, 512)
        a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in v.withUnsafeBufferPointer { pv in
            fr_set_links(e, pa.baseAddress, pb.baseAddress, pv.baseAddress, Int32(n))
        } } }
    }
    func setPot(_ h: Int, _ v: Double) { if let e = fr { fr_set_pot(e, Int32(h), Float(v)) } }
    func setRange(_ h: Int, _ r: Int) { if let e = fr { fr_set_range(e, Int32(h), Int32(r)) } }
    func setStarve(_ v: Double) { if let e = fr { fr_set_starve(e, Float(v)) } }
    /// an empty shape's own voltage (as the Cafe's "O 30+k": 0…1000 -> volts)
    func setDrift(_ k: Int, _ x: Int) { if let e = fr { fr_set_drift(e, Int32(k), Float(Double(x) * 0.0084)) } }
    func resendAll() { push() }
}
