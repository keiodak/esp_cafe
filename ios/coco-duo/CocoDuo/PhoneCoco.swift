// PhoneCoco.swift — coco duo (k.odk)
// ARP_DELAY's third layer, COCO: a coco on the phone. Two samplers — A (left → Cafe A) and B (right → Cafe B) —
// each a file or a recording from the mic. Each Cafe plays its own with its jacks:
// FLIP = backwards (a press turns it round) · SKIP = from the start · EARTH = pitch up (its resting ~28 left out).
// The Cafes stay on the tap delay (the phone's audio goes through it).

import AVFoundation

final class PhoneCoco: NSObject, ObservableObject {
    /// one sampler: written on the main thread, read by the audio thread (plain numbers, no locks)
    final class Voice {
        fileprivate(set) var buf: UnsafeMutablePointer<Float>? = nil
        fileprivate(set) var n = 0
        var srcRate = 48000.0
        var start = 0.0, len = 1.0               // the loop: where it starts, how much of the rest (0…1)
        var step = 1.0                           // samples of the file per output sample (pitch · rates)
        var reverse = false
        var restart = false
        fileprivate var pos = 0.0
    }

    let v = [Voice(), Voice()]
    @Published var names = ["—", "—"]
    @Published var recording = -1               // which one the mic is going into (-1 = none)

    // settings (main thread)
    var pitch = 1.0, depth = 0.5
    var level = 0.8, cross = 0.0
    private var earth = [0.0, 0.0]
    private var flipWas = [false, false], skipWas = [false, false]

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr = 48000.0
    private var recorder: AVAudioRecorder?
    private var recURL: URL?

    // MARK: sound

    func start() {
        if node == nil {
            let s = AVAudioSession.sharedInstance()
            if recording < 0 { try? s.setCategory(.playback, options: [.mixWithOthers]) }
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
    func stop() {
        if recording >= 0 { stopRec() }
        engine.pause()
    }

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let l = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let r = abl.count > 1 ? abl[1].mData!.assumingMemoryBound(to: Float.self) : l
        let g = Float(level), c = Float(cross)
        for i in 0..<frames {
            let a = tick(v[0]) * g, b = tick(v[1]) * g
            l[i] = a + b * c
            r[i] = b + a * c
        }
    }

    private func tick(_ s: Voice) -> Float {
        let n = s.n
        guard n > 4, let p = s.buf else { return 0 }
        let s0 = min(n - 4, Int(s.start * Double(n - 1)))
        let e = min(n - 1, s0 + max(256, Int(s.len * Double(n - 1 - s0))))
        let lo = Double(s0), hi = Double(e), span = max(4, hi - lo)
        if s.restart { s.restart = false; s.pos = s.reverse ? hi - 1 : lo }
        var pos = s.pos
        if pos < lo || pos >= hi {                                   // round the loop
            pos = lo + (pos - lo).truncatingRemainder(dividingBy: span)
            if pos < lo { pos += span }
        }
        let j = min(Int(pos), n - 2), fr = Float(pos - Double(j))
        let x = p[j] + (p[j + 1] - p[j]) * fr
        let edge = Float(min(1, min(pos - lo, hi - pos) / 96))       // (no click where it goes round)
        s.pos = pos + (s.reverse ? -s.step : s.step)
        return x * edge
    }

    // MARK: the Cafes' jacks (called ~30x a second)

    /// k = which sampler; flip / skip / earth (0…255) of the Cafe playing it
    func jacks(_ k: Int, flip: Bool, skip: Bool, earth e: Int) {
        let s = v[k]
        if flip && !flipWas[k] { s.reverse.toggle() }               // FLIP: a press turns it round
        flipWas[k] = flip
        if skip && !skipWas[k] { s.restart = true }                  // SKIP: from the start
        skipWas[k] = skip
        // EARTH: at rest it reads ~28 — below 40 counts as nothing
        let t = max(0, Double(e) - 40) / 215
        earth[k] += (t - earth[k]) * 0.35
        update(k)
    }
    func update(_ k: Int) {
        let s = v[k]
        s.step = pitch * pow(2, earth[k] * 2 * depth) * s.srcRate / sr
    }
    func updateAll() { update(0); update(1) }

    // MARK: files and the mic

    func load(_ url: URL, into k: Int) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let f = try? AVAudioFile(forReading: url) else { return }
        let fmt = f.processingFormat
        let frames = AVAudioFrameCount(min(f.length, AVAudioFramePosition(fmt.sampleRate * 90)))   // (up to 90 s)
        guard frames > 4, let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames),
              (try? f.read(into: b, frameCount: frames)) != nil, let d = b.floatChannelData else { return }
        let n = Int(b.frameLength), ch = Int(fmt.channelCount)
        let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
        var peak: Float = 0
        for i in 0..<n {
            var x: Float = 0
            for c in 0..<ch { x += d[c][i] }
            x /= Float(ch); p[i] = x; peak = max(peak, abs(x))
        }
        let gain: Float = peak > 0.0001 ? 0.9 / peak : 1
        for i in 0..<n { p[i] *= gain }
        let s = v[k], old = s.buf
        s.n = 0                                                      // (the audio thread stops reading first)
        s.buf = p; s.srcRate = fmt.sampleRate; s.pos = 0
        s.n = n
        update(k)
        if let old { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { old.deallocate() } }
        names[k] = url.deletingPathExtension().lastPathComponent
    }

    /// REC: the mic into A or B (up to 30 s); again = stop and play it
    func toggleRec(_ k: Int) {
        if recording >= 0 { let was = recording; stopRec(); if was == k { return } }
        let s = AVAudioSession.sharedInstance()
        s.requestRecordPermission { ok in
            DispatchQueue.main.async {
                guard ok else { return }
                try? s.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
                try? s.setActive(true)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("coco_\(k).caf")
                let set: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
                                          AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16]
                guard let r = try? AVAudioRecorder(url: url, settings: set) else { return }
                self.recorder = r; self.recURL = url; self.recording = k
                r.record(forDuration: 30)
                DispatchQueue.main.asyncAfter(deadline: .now() + 30.2) { [weak self, weak r] in
                    if let self, let r, self.recorder === r { self.stopRec() }
                }
            }
        }
    }
    func stopRec() {
        let k = recording
        recorder?.stop(); recorder = nil; recording = -1
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        if node != nil && !engine.isRunning { try? engine.start() }
        if k >= 0, let u = recURL { load(u, into: k); names[k] = "MIC" }
    }
}
