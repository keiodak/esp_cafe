// Speech.swift — coco duo (k.odk)
// SPEECH: the second layer of ARP_DELAY. The phone reads a line with its own speech voice (written, not played:
// AVSpeechSynthesizer.write), keeps it as a loop and plays it through a small chain — FREEZE · PITCH (+ a harmony
// a fifth above) · RESONATOR — into the Cafe, which is on COCO for it (a record head and a looping play head).
// After Mōnandæg's SPEAK room: the voice is material, not a message.
//
// top pads (the phone):  PITCH · HARMONY · RESONATOR · FREEZE · SIZE · SPEED · GAP
// bottom pads (the Cafe): COCO's SPEED · DUB · LOOP · EARTH FM · FILTER

import AVFoundation

// MARK: - reading a line into a buffer

final class SpeechRenderer {
    static let rate: Double = 48000
    private let syn = AVSpeechSynthesizer()
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: SpeechRenderer.rate,
                                       channels: 1, interleaved: false)!
    private var conv: AVAudioConverter?
    private var acc: [Float] = []
    private var done: (([Float]) -> Void)?
    private(set) var busy = false
    private var watchdog: DispatchWorkItem?
    private let limit = Int(SpeechRenderer.rate * 40)          // 40 s at most

    /// the device's voices that can be written (novelty and personal voices return nothing)
    static let voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
        .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
        .sorted { ($0.language + $0.name) < ($1.language + $1.name) }

    /// a first voice in the phone's own language
    static var homeVoice: Int {
        let lang = Locale.preferredLanguages.first?.prefix(2) ?? "en"
        return voices.firstIndex { $0.language.hasPrefix(String(lang)) } ?? 0
    }

    func render(_ text: String, voice: AVSpeechSynthesisVoice?, rate: Float, completion: @escaping ([Float]) -> Void) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !body.isEmpty else { completion([]); return }
        busy = true
        acc.removeAll(keepingCapacity: true)
        conv = nil
        done = completion
        let u = AVSpeechUtterance(string: body)
        if let voice { u.voice = voice }
        u.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        u.volume = 1
        u.preUtteranceDelay = 0
        u.postUtteranceDelay = 0
        let w = DispatchWorkItem { [weak self] in self?.finish() }      // no end mark within 30 s: stop there
        watchdog = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: w)
        syn.write(u) { [weak self] buffer in
            guard let self else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { self.finish(); return }
            self.take(pcm)
        }
    }

    private func take(_ pcm: AVAudioPCMBuffer) {
        guard acc.count < limit else { return }
        if conv == nil { conv = AVAudioConverter(from: pcm.format, to: target) }
        guard let c = conv else { return }
        let cap = AVAudioFrameCount(Double(pcm.frameLength) * target.sampleRate / pcm.format.sampleRate) + 64
        guard let ob = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
        var fed = false
        var err: NSError?
        _ = c.convert(to: ob, error: &err) { _, flag in
            if fed { flag.pointee = .noDataNow; return nil }
            fed = true
            flag.pointee = .haveData
            return pcm
        }
        guard err == nil, let ch = ob.floatChannelData, ob.frameLength > 0 else { return }
        let n = min(Int(ob.frameLength), limit - acc.count)
        if n > 0 { acc.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n)) }
    }

    private func finish() {
        guard busy else { return }
        watchdog?.cancel(); watchdog = nil
        var out = acc
        acc.removeAll(keepingCapacity: true)
        conv = nil
        busy = false
        // level it: the loudest point at 0.9
        var pk: Float = 0
        for v in out { pk = max(pk, abs(v)) }
        if pk > 0.0001 { let g = min(8, 0.9 / pk); for k in out.indices { out[k] *= g } }
        let f = done
        done = nil
        DispatchQueue.main.async { f?(out) }
    }
}

// MARK: - the voice on the audio thread

/// the loop and its chain. Settings are plain numbers written on the main thread and read by the audio thread;
/// a new loop is handed over through `pending` and taken at the top of a sample (the audio thread never waits).
final class SpeechVoice {
    // settings (main thread)
    var playing = false
    var semis = 0.0          // PITCH, -12 … +12
    var harmony = 0.0        // a second voice a fifth above the pitched one, 0 … 1
    var resHz = 110.0        // RESONATOR pitch
    var resAmt = 0.0         // RESONATOR amount, 0 … 1 (0 = off)
    var freeze = 0.0         // FREEZE: the last moment held and looped, 0 … 1 (0 = off)
    var grainMs = 120.0      // FREEZE's piece, ms
    var speed = 1.0          // SPEED: tape-like, 0.5 … 2
    var gap = 0.0            // GAP: silence between two readings, s
    var level = 0.8
    private var restartFlag = false
    func restart() { restartFlag = true }

    // the loop
    private var buf: UnsafeMutablePointer<Float>?
    private var len = 0
    private var pendBuf: UnsafeMutablePointer<Float>?
    private var pendLen = 0
    private var pendFlag = false
    private var live: UnsafeMutablePointer<Float>?          // (main thread: the last one handed over)

    /// hand over a new loop (main thread). The one before is freed a second later, once the audio thread let go.
    func load(_ s: [Float]) {
        guard !s.isEmpty else { return }
        let p = UnsafeMutablePointer<Float>.allocate(capacity: s.count)
        s.withUnsafeBufferPointer { p.initialize(from: $0.baseAddress!, count: s.count) }
        let old = live
        live = p
        pendBuf = p; pendLen = s.count; pendFlag = true
        if let old { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { old.deallocate() } }
    }
    var hasLoop: Bool { live != nil }

    // audio-thread state
    private var pos = 0.0
    private var gapLeft = 0
    private static let histN = 32768, ringN = 8192, combN = 4096, frzN = 24000
    private let hist = UnsafeMutablePointer<Float>.allocate(capacity: SpeechVoice.histN)
    private var hi = 0
    private let frz = UnsafeMutablePointer<Float>.allocate(capacity: SpeechVoice.frzN)
    private var frzLen = 0, frzPos = 0, frzOn = false
    private let ring = UnsafeMutablePointer<Float>.allocate(capacity: SpeechVoice.ringN)
    private var wi = 0
    private var d1 = 0.0, dh = 0.0
    private let comb = UnsafeMutablePointer<Float>.allocate(capacity: SpeechVoice.combN)
    private var ci = 0
    private var lp: Float = 0
    private var dc: Float = 0, dcOut: Float = 0

    init() {
        hist.initialize(repeating: 0, count: Self.histN)
        frz.initialize(repeating: 0, count: Self.frzN)
        ring.initialize(repeating: 0, count: Self.ringN)
        comb.initialize(repeating: 0, count: Self.combN)
    }
    deinit { hist.deallocate(); frz.deallocate(); ring.deallocate(); comb.deallocate() }

    @inline(__always) private func ringRead(_ d: Double) -> Float {     // d samples ago, interpolated
        let p = Double(wi) - d
        var i = Int(floor(p))
        let f = Float(p - Double(i))
        i &= Self.ringN - 1
        let a = ring[i], b = ring[(i + 1) & (Self.ringN - 1)]
        return a + (b - a) * f
    }

    /// a delay-line pitch shifter: two taps half a window apart, each faded by a sine window
    @inline(__always) private func shift(_ d: inout Double, ratio: Double, win: Double) -> Float {
        d += 1 - ratio
        if d < 0 { d += win } else if d >= win { d -= win }
        var d2 = d + win * 0.5
        if d2 >= win { d2 -= win }
        let g1 = Float(sin(Double.pi * d / win)), g2 = Float(sin(Double.pi * d2 / win))
        return ringRead(d + 2) * g1 * g1 + ringRead(d2 + 2) * g2 * g2
    }

    /// one sample
    func next(_ sr: Double) -> Float {
        if pendFlag { buf = pendBuf; len = pendLen; pendFlag = false; pos = 0; gapLeft = 0 }
        if restartFlag { restartFlag = false; pos = 0; gapLeft = 0 }

        // the loop (tape-like speed), a 5 ms fade at both ends, then the GAP
        var x: Float = 0
        if playing, let b = buf, len > 4 {
            if gapLeft > 0 { gapLeft -= 1 }
            else {
                let i = Int(pos), f = Float(pos - Double(i))
                let a = b[min(i, len - 1)], c = b[min(i + 1, len - 1)]
                let fade = sr * 0.005
                let e = Float(min(1, pos / fade, Double(len - 1 - i) / fade))
                x = (a + (c - a) * f) * max(0, e)
                pos += speed * SpeechRenderer.rate / sr
                if pos >= Double(len - 1) { pos = 0; gapLeft = Int(gap * sr) }
            }
        }

        // FREEZE: keep the recent past; on the way up, take the last piece and loop it (two halves crossfaded)
        hist[hi] = x
        hi = (hi + 1) & (Self.histN - 1)
        if freeze > 0.02 {
            if !frzOn {
                frzLen = min(Self.frzN, max(256, Int(grainMs * 0.001 * sr)))
                for k in 0..<frzLen { frz[k] = hist[(hi - frzLen + k + Self.histN) & (Self.histN - 1)] }
                frzPos = 0; frzOn = true
            }
            let n = Double(frzLen)
            let p1 = frzPos, p2 = (frzPos + frzLen / 2) % frzLen
            let w1 = Float(sin(Double.pi * Double(p1) / n)), w2 = Float(sin(Double.pi * Double(p2) / n))
            let fz = frz[p1] * w1 * w1 + frz[p2] * w2 * w2
            frzPos = (frzPos + 1) % frzLen
            let k = Float(freeze)
            x = x * (1 - k) + fz * k
        } else { frzOn = false }

        // PITCH (+ HARMONY a fifth above it)
        ring[wi] = x
        let win = sr * 0.06
        let r = pow(2.0, semis / 12)
        var y: Float = abs(semis) < 0.05 ? x : shift(&d1, ratio: r, win: win)
        if harmony > 0.01 {
            let h = Float(harmony)
            y = (y + shift(&dh, ratio: r * 1.4983, win: win) * h) / (1 + h * 0.5)
        }
        wi = (wi + 1) & (Self.ringN - 1)

        // RESONATOR: a tuned comb with a soft damping in its loop
        if resAmt > 0.01 {
            let dl = min(Double(Self.combN - 4), max(8, sr / max(30, resHz)))
            let p = Double(ci) - dl
            var i = Int(floor(p)); let f = Float(p - Double(i)); i &= Self.combN - 1
            let c = comb[i] + (comb[(i + 1) & (Self.combN - 1)] - comb[i]) * f
            lp += (c - lp) * 0.45
            let fb = Float(0.55 + 0.43 * resAmt)
            let v = y * 0.35 + lp * fb
            comb[ci] = v
            ci = (ci + 1) & (Self.combN - 1)
            let a = Float(resAmt)
            y = y * (1 - a * 0.75) + v * a * 0.9
        }

        // DC out, level, a soft ceiling (the Cafe's input)
        dcOut = y - dc + 0.995 * dcOut
        dc = y
        let o = dcOut * Float(level)
        return o / (1 + abs(o) * 0.6)
    }
}
