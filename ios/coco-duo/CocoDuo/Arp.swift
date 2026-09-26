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
    private var noteGain = 1.0
    var earth = 0.0
    private(set) var playing = false
    private(set) var running = false

    // the notes of the chord over the octaves (a fixed buffer: the audio thread never sees an array change)
    private let notes = UnsafeMutablePointer<Int32>.allocate(capacity: 32)
    private var noteCount = 3
    private var chordSize = 3

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr: Double = 44100

    // audio-thread state
    private var toNext = 0.0
    private var step = 0
    private var phase = 0.0, phase5 = 0.0
    private var freq = 220.0, target = 220.0
    private var env = 0.0
    private var attackLeft = 0
    private var gateLeft = 0
    private var seed: UInt32 = 0x2545F491
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
    func startAudio() {
        guard !running else { return }
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

    func play() { startAudio(); restartFlag = true; playing = true }
    func stop() { playing = false }
    /// back to the first note, now (SYNC, or a tap on the Cafe)
    func restart() { restartFlag = true }

    private func stepSamples() -> Double {
        let beat = 60.0 / max(20, bpm) * sr
        return beat * Self.rateBeats[min(max(rateIndex, 0), Self.rateBeats.count - 1)]
    }

    private func nextNote() -> Int {
        let n = noteCount, s = step
        if earthNotes {
            let i = Int(min(max(earth, 0), 0.9999) * Double(n))
            return Int(notes[min(max(i, 0), n - 1)])
        }
        var i = 0
        switch pattern {
        case 0: i = s % n
        case 1: i = n - 1 - s % n
        case 2: if n > 1 { let k = s % (2 * n - 2); i = k < n ? k : 2 * n - 2 - k }
        case 3:
            seed = seed &* 1664525 &+ 1013904223
            i = Int(seed >> 16) % n
        case 4: let k = s % n; i = k % 2 == 0 ? k / 2 : n - 1 - k / 2
        case 5: if n > 1 { let k = s % (2 * (n - 1)); i = k % 2 == 0 ? 0 : 1 + (k / 2) % (n - 1) }
        default:                                   // SPIRAL: each octave starts one chord tone later
            let cs = max(1, chordSize), oc = max(1, n / cs)
            let o = (s / cs) % oc
            i = min(n - 1, o * cs + (s + s / cs) % cs)
        }
        return Int(notes[min(max(i, 0), n - 1)])
    }

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let twoPi = 2.0 * Double.pi
        let kd = exp(-1.0 / (sr * (0.03 + decay * decay * 1.5)))   // decay while the note is held
        let kr = exp(-1.0 / (sr * 0.030))                           // release after the gate (soft: no click)
        let gl = glide <= 0.001 ? 1.0 : 1.0 - exp(-1.0 / (sr * glide * 0.25))
        let atk = Int(sr * 0.006)                                   // (6 ms: a clean start, no click)
        for f in 0..<frames {
            if restartFlag { restartFlag = false; step = 0; toNext = 0 }
            if playing {
                toNext -= 1
                if toNext <= 0 {
                    let len = stepSamples()
                    let sw = step % 2 == 0 ? 1 + swing * 0.5 : 1 - swing * 0.5
                    toNext += len * sw
                    let m = nextNote()
                    target = 440.0 * pow(2.0, Double(m - 69) / 12.0)
                    let below = min(max(log2(261.6 / target), 0), 2.5)            // octaves under middle C
                    noteGain = 1.0 + low * below * 0.6
                    if gl >= 1.0 { freq = target }
                    gateLeft = Int(len * gate)
                    attackLeft = atk
                    step += 1
                }
            }
            freq += (target - freq) * gl
            if attackLeft > 0 { env += (1.0 - env) / Double(attackLeft); attackLeft -= 1 }
            else if gateLeft > 0 { env *= kd }
            else { env *= kr }
            if gateLeft > 0 { gateLeft -= 1 }
            phase += twoPi * freq / sr; if phase > twoPi { phase -= twoPi }
            phase5 += twoPi * freq * 1.5 / sr; if phase5 > twoPi { phase5 -= twoPi }
            // a pure sine (no fifth), at a level that leaves the Cafe's input headroom
            let v = Float(sin(phase) * env * level * 0.45 * noteGain)
            for b in abl {
                if let p = b.mData?.assumingMemoryBound(to: Float.self) { p[f] = v }
            }
        }
    }
}
