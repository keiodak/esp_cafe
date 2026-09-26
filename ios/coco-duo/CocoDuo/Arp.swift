// Arp.swift — coco duo (k.odk)
// ARP: a simple sine arpeggiator on the iPhone, for preset 11 (ARP_DELAY) of esp_cafe_duo.
// Patch the phone's audio out into the Cafe's input: the arpeggio goes through the Cafe's stereo tap delay.
// Tempo is shared both ways: the app's BPM goes to the Cafes ("K"), a tap on a Cafe's SKIP comes back (the arp follows
// and restarts on the beat). SYNC restarts the arpeggio and the Cafes' clicks together.
//
// 7 patterns: UP · DOWN · UP·DOWN · RANDOM · CONVERGE (outside in) · PEDAL (root between every note) · SPIRAL
// 7 chords:   MAJ · MIN · SUS4 · MAJ7 · MIN7 · ADD9 · FIFTHS, over 1–4 octaves
// Rates: 1/4 · 1/8 · 1/8T · 1/16 · 1/16T · 1/32, swing, gate, decay, glide, a quiet fifth above, level.

import AVFoundation

final class ArpEngine {
    static let patterns = ["UP", "DOWN", "UP·DOWN", "RANDOM", "CONVERGE", "PEDAL", "SPIRAL"]
    static let chordNames = ["MAJ", "MIN", "SUS4", "MAJ7", "MIN7", "ADD9", "FIFTHS"]
    static let chords: [[Int]] = [[0, 4, 7], [0, 3, 7], [0, 5, 7], [0, 4, 7, 11], [0, 3, 7, 10], [0, 4, 7, 14], [0, 7, 14]]
    static let rateNames = ["1/4", "1/8", "1/8T", "1/16", "1/16T", "1/32"]
    static let rateBeats: [Double] = [1, 0.5, 1.0 / 3, 0.25, 1.0 / 6, 0.125]
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // settings: written on the main thread, read by the audio thread (plain numbers, no locks)
    var bpm: Double = 120
    var root = 48 { didSet { rebuild() } }
    var chord = 0 { didSet { rebuild() } }
    var octaves = 2 { didSet { rebuild() } }
    var pattern = 0
    var rateIndex = 3
    var swing = 0.0
    var gate = 0.5
    var decay = 0.35
    var glide = 0.0
    var fifth = 0.0
    var level = 0.7
    /// EARTH → NOTES: the Cafe's EARTH (0…1, from its status lines) picks the note, quantized to the chord's notes
    /// over the octaves (ROOT · CHORD and OCTAVES pads); the rhythm stays the arpeggiator's (RATE on the BPM, swing, gate)
    var earthNotes = true
    /// LOW (0…1): an EQ-like low shelf — notes below middle C get louder, up to about +9 dB two octaves down
    /// (the Cafe's input and small speakers lose the low end of a pure sine); higher notes are left as they are
    var low = 0.5
    var earth = 0.0
    /// STEREO: a second voice on the right channel (→ Cafe B), with its own EARTH (Cafe B's), RATE and SWING;
    /// root, chord, octaves, pattern, gate and decay are shared, the tempo is the same. MONO: both channels = voice 1.
    var stereo = false
    var rateIndex2 = 3
    var swing2 = 0.0
    var earth2 = 0.0
    private(set) var playing = false
    private(set) var running = false

    // the notes of the chord over the octaves (a fixed buffer: the audio thread never sees an array change)
    private let notes = UnsafeMutablePointer<Int32>.allocate(capacity: 32)
    private var noteCount = 3
    private var chordSize = 3

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr: Double = 44100

    // audio-thread state, one per voice
    private struct Voice {
        var toNext = 0.0, step = 0, phase = 0.0, freq = 220.0, target = 220.0, env = 0.0
        var attackLeft = 0, gateLeft = 0, noteGain = 1.0
        var seed: UInt32
    }
    private var v0 = Voice(seed: 0x2545F491)
    private var v1 = Voice(seed: 0x1B873593)
    private var restartFlag = false

    init() { rebuild() }
    deinit { notes.deallocate() }

    var label: String {
        "\(Self.patterns[pattern]) · \(Self.noteNames[root % 12])\(root / 12 - 1) \(Self.chordNames[chord]) · \(Self.rateNames[rateIndex])"
    }

    private func rebuild() {
        let c = Self.chords[min(max(chord, 0), Self.chords.count - 1)]
        var n = 0
        for o in 0..<min(max(octaves, 1), 4) {
            for iv in c where n < 32 { notes[n] = Int32(root + 12 * o + iv); n += 1 }
        }
        chordSize = c.count
        noteCount = max(1, n)
    }

    /// start the audio (once); the arpeggio itself starts with play()
    private var observers: [NSObjectProtocol] = []

    /// start the audio, or bring it back: iOS stops the engine when the output changes (a USB mixer such as the
    /// TX-6 reconnecting, a new sample rate, a call...) and it stays silent unless we start it again
    func startAudio() {
        if running, node != nil {
            if !engine.isRunning { try? AVAudioSession.sharedInstance().setActive(true); try? engine.start() }
            return
        }
        if observers.isEmpty {
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                self?.rebuildAudio()
            })
            observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.startAudio()
            })
            observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
                self?.startAudio()
            })
        }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, options: [.mixWithOthers])
        try? s.setActive(true)
        sr = s.sampleRate > 0 ? s.sampleRate : 44100
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let n = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frameCount, abl -> OSStatus in
            self.render(Int(frameCount), UnsafeMutableAudioBufferListPointer(abl))
            return noErr
        }
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: fmt)
        node = n
        do { try engine.start(); running = true } catch { running = false }
    }

    /// the output changed under us: build the node again at the new sample rate and start
    private func rebuildAudio() {
        engine.stop()
        if let n = node { engine.detach(n) }
        node = nil; running = false
        startAudio()
    }

    func play() { startAudio(); restartFlag = true; playing = true }
    func stop() { playing = false }
    /// back to the first note, now (SYNC, or a tap on the Cafe)
    func restart() { restartFlag = true }

    private func stepSamples(_ rate: Int) -> Double {
        let beat = 60.0 / max(20, bpm) * sr
        return beat * Self.rateBeats[min(max(rate, 0), Self.rateBeats.count - 1)]
    }

    private func nextNote(_ v: inout Voice, _ e: Double) -> Int {
        let n = noteCount, s = v.step
        if earthNotes {
            let i = Int(min(max(e, 0), 0.9999) * Double(n))
            return Int(notes[min(max(i, 0), n - 1)])
        }
        var i = 0
        switch pattern {
        case 0: i = s % n
        case 1: i = n - 1 - s % n
        case 2: if n > 1 { let k = s % (2 * n - 2); i = k < n ? k : 2 * n - 2 - k }
        case 3:
            v.seed = v.seed &* 1664525 &+ 1013904223
            i = Int(v.seed >> 16) % n
        case 4: let k = s % n; i = k % 2 == 0 ? k / 2 : n - 1 - k / 2
        case 5: if n > 1 { let k = s % (2 * (n - 1)); i = k % 2 == 0 ? 0 : 1 + (k / 2) % (n - 1) }
        default:                                   // SPIRAL: each octave starts one chord tone later
            let cs = max(1, chordSize), oc = max(1, n / cs)
            let o = (s / cs) % oc
            i = min(n - 1, o * cs + (s + s / cs) % cs)
        }
        return Int(notes[min(max(i, 0), n - 1)])
    }

    /// one sample of one voice
    private func tick(_ v: inout Voice, rate: Int, swing: Double, earth e: Double,
                      kd: Double, kr: Double, gl: Double, atk: Int) -> Float {
        if playing {
            v.toNext -= 1
            if v.toNext <= 0 {
                let len = stepSamples(rate)
                let sw = v.step % 2 == 0 ? 1 + swing * 0.5 : 1 - swing * 0.5
                v.toNext += len * sw
                let m = nextNote(&v, e)
                v.target = 440.0 * pow(2.0, Double(m - 69) / 12.0)
                let below = min(max(log2(261.6 / v.target), 0), 2.5)          // octaves under middle C
                v.noteGain = 1.0 + low * below * 0.6
                if gl >= 1.0 { v.freq = v.target }
                v.gateLeft = Int(len * gate)
                v.attackLeft = atk
                v.step += 1
            }
        }
        v.freq += (v.target - v.freq) * gl
        if v.attackLeft > 0 { v.env += (1.0 - v.env) / Double(v.attackLeft); v.attackLeft -= 1 }
        else if v.gateLeft > 0 { v.env *= kd }
        else { v.env *= kr }
        if v.gateLeft > 0 { v.gateLeft -= 1 }
        v.phase += 2.0 * Double.pi * v.freq / sr; if v.phase > 2.0 * Double.pi { v.phase -= 2.0 * Double.pi }
        // a pure sine, at a level that leaves the Cafe's input headroom
        return Float(sin(v.phase) * v.env * level * 0.45 * v.noteGain)
    }

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let kd = exp(-1.0 / (sr * (0.03 + decay * decay * 1.5)))   // decay while the note is held
        let kr = exp(-1.0 / (sr * 0.030))                           // release after the gate (soft: no click)
        let gl = glide <= 0.001 ? 1.0 : 1.0 - exp(-1.0 / (sr * glide * 0.25))
        let atk = Int(sr * 0.006)                                   // (6 ms: a clean start, no click)
        let st = stereo
        for f in 0..<frames {
            if restartFlag { restartFlag = false; v0.step = 0; v0.toNext = 0; v1.step = 0; v1.toNext = 0 }
            let a = tick(&v0, rate: rateIndex, swing: swing, earth: earth, kd: kd, kr: kr, gl: gl, atk: atk)
            let b = st ? tick(&v1, rate: rateIndex2, swing: swing2, earth: earth2, kd: kd, kr: kr, gl: gl, atk: atk) : a
            for (k, buf) in abl.enumerated() {
                if let p = buf.mData?.assumingMemoryBound(to: Float.self) { p[f] = k == 0 ? a : b }
            }
        }
    }
}
