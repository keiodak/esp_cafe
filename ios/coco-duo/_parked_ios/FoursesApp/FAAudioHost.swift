// FAAudioHost.swift — Fourses (k.odk)
// (in coco duo: the Fourses app as it is, inside FA — iOS · FOURSES)
// The engine (C, FoursesDSP) in an AVAudioSourceNode. It runs at four times the output's rate and decimates.

import AVFoundation

extension FA {
final class AudioHost {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    /// the circuit (an opaque C object)
    private(set) var fr: OpaquePointer?
    private var rate: Double = 48000
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
    /// called when the engine was made anew (a new rate): everything must be sent again
    var onRebuilt: (() -> Void)?

    /// (in coco duo: made and started only while iOS · FOURSES is on the screen)
    private(set) var running = false
    func run(_ on: Bool) {
        guard on != running else { return }
        running = on
        if on {
            configureSession()
            if fr == nil { build(); onRebuilt?() } else { restart() }
        } else {
            engine.pause()
        }
    }

    init() {
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            if self?.running == true { self?.restart() }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended, self?.running == true else { return }
            self?.restart()
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard self?.running == true else { return }
            self?.configureSession(); self?.restart()
        }
    }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        // (coco duo's session as it is: its other engines share it)
        if s.category != .playback && s.category != .playAndRecord { try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers]) }
        try? s.setActive(true)
    }

    private func build() {
        let sr = AVAudioSession.sharedInstance().sampleRate
        rate = sr > 8000 ? sr : 48000
        let old = fr
        fr = fr_create(rate)
        if let old { fr_destroy(old) }
        guard let e = fr, let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let scratch = self.scratch
        let src = AVAudioSourceNode(format: fmt) { _, _, frames, abl in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            let n = Int(frames)
            guard bufs.count > 0, let l = bufs[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            if bufs.count > 1, let r = bufs[1].mData?.assumingMemoryBound(to: Float.self) {
                fr_render(e, l, r, Int32(n))
            } else {
                fr_render(e, l, scratch, Int32(min(n, 8192)))
            }
            return noErr
        }
        if let n = node { engine.detach(n) }
        node = src
        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: fmt)
        engine.prepare()
        try? engine.start()
    }

    func restart() {
        engine.stop()
        let sr = AVAudioSession.sharedInstance().sampleRate
        if abs(sr - rate) > 1 {
            build(); onRebuilt?()
        } else {
            try? engine.start()
        }
    }
}
}
