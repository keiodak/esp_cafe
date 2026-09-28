// PhoneCoco.swift — coco duo (k.odk)
// ARP_DELAY's third layer, COCO: a coco on the phone. Two samplers — A (left → Cafe A) and B (right → Cafe B) —
// each a file or a recording from the mic. Each Cafe plays its own with its jacks:
// FLIP = backwards (a press turns it round) · SKIP = from the start · EARTH = pitch up (its resting ~28 left out).
// The Cafes stay on the tap delay (the phone's audio goes through it).

import AVFoundation
import SwiftUI

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

    override init() {
        super.init()
        if let l = UserDefaults.standard.array(forKey: "pc.link") as? [Int], l.count == 2 { link = l.map { $0 == 1 ? 1 : 0 } }
        side = link
    }
    @Published var names = ["—", "—"]
    @Published var recording = -1               // which one the mic is going into (-1 = none)
    /// which Cafe each sampler belongs to: 0 = A (its jacks; out on the left) · 1 = B (the right)
    @Published var link = [0, 1] { didSet { UserDefaults.standard.set(link, forKey: "pc.link") } }
    @Published var loading = [false, false]     // a file being read (shown on its FILE key)
    /// each sampler's sound, drawn: the loudest in each of 96 pieces (empty = nothing loaded)
    @Published var peaks: [[Float]] = [[], []]
    static let bins = 96
    /// where each one is playing (0…1 of the whole), for the drawing (read by a timeline, not published)
    func playing(_ k: Int) -> Double { let s = v[k]; return s.n > 1 ? min(1, max(0, s.pos / Double(s.n - 1))) : 0 }

    // settings (main thread)
    var pitch = 1.0, depth = 0.5
    var level = 0.8, cross = 0.0
    private var earth = [0.0, 0.0]
    /// what each sampler last heard from its Cafe (drawn on its waveform: FLIP · SKIP · EARTH), and SKIPs counted
    private(set) var seen: [(flip: Bool, skip: Bool, earth: Double)] = [(false, false, 0), (false, false, 0)]
    private(set) var skips = [0, 0]
    private var side = [0, 1]                    // (link, as the audio thread reads it)
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
        let ra: Float = side[0] == 1 ? 1 : 0, rb: Float = side[1] == 1 ? 1 : 0     // (0 = left, 1 = right)
        for i in 0..<frames {
            let a = tick(v[0]) * g, b = tick(v[1]) * g
            let al = a * (1 - ra) + a * ra * c, ar = a * ra + a * (1 - ra) * c    // each on its Cafe's side,
            let bl = b * (1 - rb) + b * rb * c, br = b * rb + b * (1 - rb) * c    //   CROSS = some on the other
            l[i] = al + bl
            r[i] = ar + br
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
        s.reverse = flip                                             // FLIP: backwards while it is on (as the Cafe's COCO)
        if skip && !skipWas[k] { s.restart = true; skips[k] += 1 }   // SKIP: from the loop's start
        skipWas[k] = skip
        // EARTH: at rest it reads ~28 — below 36 counts as nothing; above, up to 4 octaves (PITCH · EARTH's Y)
        let t = max(0, Double(e) - 36) / 219
        earth[k] += (t - earth[k]) * 0.6
        seen[k] = (flip, skip, earth[k])
        update(k)
    }
    func update(_ k: Int) {
        let s = v[k]
        s.step = pitch * pow(2, earth[k] * 4 * depth) * s.srcRate / sr
    }
    func updateAll() { update(0); update(1); side = link }

    // MARK: files and the mic

    /// a file (or the mic's recording) into A or B — read off the main thread (a long file takes a moment: its FILE
    /// key says LOAD… meanwhile), then swapped in
    func load(_ url: URL, into k: Int, name: String? = nil) {
        loading[k] = true
        let access = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let got = Self.read(url)
            if access { url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading[k] = false
                guard let g = got else { return }
                let (p, n, rate) = g
                self.peaks[k] = Self.draw(p, n)
                let s = self.v[k], old = s.buf
                s.n = 0                                              // (the audio thread stops reading first)
                s.buf = p; s.srcRate = rate; s.pos = 0
                s.n = n
                self.update(k)
                if let old { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { old.deallocate() } }
                self.names[k] = name ?? url.deletingPathExtension().lastPathComponent
            }
        }
    }
    /// CLEAR: that sampler empty
    func clear(_ k: Int) {
        if recording == k { recorder?.stop(); recorder = nil; recording = -1 }
        let s = v[k], old = s.buf
        s.n = 0
        s.buf = nil
        if let old { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { old.deallocate() } }
        names[k] = "—"; peaks[k] = []
    }
    private static func draw(_ p: UnsafeMutablePointer<Float>, _ n: Int) -> [Float] {
        (0..<bins).map { b in
            let a = b * n / bins, e = max(a + 1, (b + 1) * n / bins)
            var m: Float = 0
            var i = a
            while i < e { m = max(m, abs(p[i])); i += max(1, (e - a) / 256) }
            return m
        }
    }
    private static func read(_ url: URL) -> (UnsafeMutablePointer<Float>, Int, Double)? {
        guard let f = try? AVAudioFile(forReading: url) else { return nil }
        let fmt = f.processingFormat
        let frames = AVAudioFrameCount(min(f.length, AVAudioFramePosition(fmt.sampleRate * 90)))   // (up to 90 s)
        guard frames > 4, let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames),
              (try? f.read(into: b, frameCount: frames)) != nil, let d = b.floatChannelData else { return nil }
        let n = Int(b.frameLength), ch = Int(fmt.channelCount)
        guard n > 4, ch > 0 else { return nil }
        let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
        var peak: Float = 0
        for i in 0..<n {
            var x: Float = 0
            for c in 0..<ch { x += d[c][i] }
            x /= Float(ch); p[i] = x; peak = max(peak, abs(x))
        }
        let gain: Float = peak > 0.0001 ? 0.9 / peak : 1
        for i in 0..<n { p[i] *= gain }
        return (p, n, fmt.sampleRate)
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
        if k >= 0, let u = recURL { load(u, into: k, name: "MIC") }
    }
}

/// a sampler's sound: its peaks, the loop (START · LENGTH) lit, where it plays in orange
struct PcWave: View {
    @ObservedObject var pc: PhoneCoco
    let k: Int
    @ObservedObject var axis: PadAxis                // (its START · LENGTH pad)
    var body: some View {
        let start = axis.x, len = PcPad.len(axis.y)
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { _ in
            Canvas { ctx, size in
                let pk = pc.peaks[k]
                ctx.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(PastelTheme.hudLine), lineWidth: 1)
                guard !pk.isEmpty else { return }
                let w = size.width / CGFloat(pk.count), mid = size.height / 2
                let lo = start, hi = start + (1 - start) * len
                ctx.fill(Path(CGRect(x: CGFloat(lo) * size.width, y: 0, width: CGFloat(hi - lo) * size.width, height: size.height)),
                         with: .color(PastelTheme.hudOrange.opacity(0.12)))
                var bars = Path()
                for (i, m) in pk.enumerated() {
                    let h = max(0.8, CGFloat(m) * mid * 0.95)
                    bars.addRect(CGRect(x: CGFloat(i) * w, y: mid - h, width: max(0.8, w * 0.8), height: h * 2))
                }
                ctx.fill(bars, with: .color(PastelTheme.hudBlack.opacity(0.4)))
                let x = CGFloat(pc.playing(k)) * size.width
                ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(PastelTheme.hudOrange))
                // what comes from its Cafe: FLIP · SKIP lit while on, EARTH as a bar on the right
                let j = pc.seen[k]
                func tag(_ t: String, _ on: Bool, _ at: CGFloat) {
                    ctx.draw(Text(t).font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(on ? PastelTheme.hudOrange : PastelTheme.hudLine),
                             at: CGPoint(x: at, y: 6), anchor: .topLeading)
                }
                tag("FLIP", j.flip, 4)
                tag("SKIP \(pc.skips[k] % 100)", j.skip, 34)
                let eh = CGFloat(min(1, j.earth)) * size.height
                ctx.fill(Path(CGRect(x: size.width - 4, y: size.height - eh, width: 3, height: eh)), with: .color(PastelTheme.hudOrange))
            }
        }
        .allowsHitTesting(false)
    }
}
