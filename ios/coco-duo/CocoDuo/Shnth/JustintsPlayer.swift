// JustintsPlayer.swift — coco duo (k.odk)
// JUSTINTS: Peter Blasser's justints (justints.c — a C port of his C++, MIT), the Shnth's just-intonation synth
// in integers: voices of four oscillators, each a ratio n/d; the bars bend the focused ones (king: one, queen: two,
// chosen with the minor buttons) up and down through the ratios the antenna's prime limit allows.
// The screen plays the part of the Shnth's USB report (1000 times a second, as the real one).

import AVFoundation
import Combine
import os

final class JustintsPlayer: ObservableObject {
    /// the examples that came with justints (Shnth/justints/ji_*.txt — his .texte files)
    static let examples: [(name: String, text: String)] = {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("ji_") }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
        return urls.compactMap { u in
            guard let s = try? String(contentsOf: u, encoding: .isoLatin1) else { return nil }
            return (String(u.deletingPathExtension().lastPathComponent.dropFirst(3)), s)
        }
    }()

    private static let d = UserDefaults.standard
    /// the example last loaded (kept)
    @Published private(set) var example: String = JustintsPlayer.d.string(forKey: "ji.example") ?? ""

    /// the controls: bars −1…1, the antenna 0…1, the four minor buttons (bit k)
    var bars: [Double] = [0, 0, 0, 0]
    var ant = 0.0
    var antB = 0.0
    var minor: UInt8 = 0

    private enum Cmd { case key(Int32), dupeVoice, dupeSlot, load(String), toggle(Int32, Int32, Int32, Int32) }
    private let e: OpaquePointer
    private var lock = os_unfair_lock()
    private var cmds: [Cmd] = []
    private var report: [Int8] = [0, 0, 0, 0, 0, 0, 0, 0]
    private var shown = ji_view()

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var running = false
    private var gain: Float = 0

    init() {
        e = ji_create()
        cmds.reserveCapacity(64)
        let start = Self.examples.first(where: { $0.name == example }) ?? Self.examples.first
        if let x = start { load(x.name) }
    }

    // MARK: what the hands and keys do

    /// a key as typed on the computer ("0"…"9", "\r", " ", "/", "\u{7f}", q w e …, a s d …, x c v …, z [ ')
    func key(_ c: Character) {
        guard let v = c.asciiValue else { return }
        send(.key(Int32(v)))
    }
    func dupeVoice() { send(.dupeVoice) }
    /// a tap on a routing square (voice, which, i, j — see ji_toggle)
    func toggle(_ k: Int, _ w: Int, _ i: Int, _ j: Int) { send(.toggle(Int32(k), Int32(w), Int32(i), Int32(j))) }
    func dupeSlot() { send(.dupeSlot) }
    /// the voices of the slot playing, as a .texte (KEEP)
    func saveText() -> String {
        var buf = [CChar](repeating: 0, count: 1 << 16)
        os_unfair_lock_lock(&lock)
        apply()
        _ = ji_save(e, &buf, Int32(buf.count))
        os_unfair_lock_unlock(&lock)
        return String(cString: buf)
    }
    /// a .texte made here (GEN) — not kept as the example
    func loadText(_ text: String, as name: String) {
        example = name
        send(.load(text))
    }
    func load(_ name: String) {
        guard let x = Self.examples.first(where: { $0.name == name }) else { return }
        example = name; Self.d.set(name, forKey: "ji.example")
        send(.load(x.text))
    }
    /// the hands -> the report (as the Shnth sends it: bars, antenna, …, buttons)
    func pushReport() {
        var b: [Int8] = [0, 0, 0, 0, 0, 0, 0, 0]
        for i in 0..<4 { b[i] = Int8(max(-127, min(127, (bars[i] * 127).rounded()))) }
        b[4] = Int8(max(0, min(127, (ant * 127).rounded())))
        b[5] = Int8(max(0, min(127, (antB * 127).rounded())))
        var bt: UInt8 = 0
        for k in 0..<4 where (minor >> UInt8(k)) & 1 == 1 { bt |= 1 << UInt8(2 * k) }
        b[7] = Int8(bitPattern: bt)
        os_unfair_lock_lock(&lock); report = b; os_unfair_lock_unlock(&lock)
    }
    private func send(_ c: Cmd) {
        os_unfair_lock_lock(&lock); cmds.append(c); os_unfair_lock_unlock(&lock)
        if !running { DispatchQueue.main.async { self.drainIdle() } }
    }
    /// (not sounding: the keys still change the voices)
    private func drainIdle() {
        guard !running else { return }
        os_unfair_lock_lock(&lock)
        apply()
        ji_get_view(e, &shown)
        os_unfair_lock_unlock(&lock)
    }
    private func apply() {
        for c in cmds {
            switch c {
            case .key(let k): ji_key(e, k)
            case .dupeVoice: ji_dupe_voice(e)
            case .dupeSlot: ji_dupe_slot(e)
            case .load(let t): _ = t.withCString { ji_load(e, $0) }
            case .toggle(let k, let w, let i, let j): ji_toggle(e, k, w, i, j)
            }
        }
        cmds.removeAll(keepingCapacity: true)
    }

    /// what the screen shows (read ~20x a second)
    func viewNow() -> ji_view {
        os_unfair_lock_lock(&lock); let v = shown; os_unfair_lock_unlock(&lock)
        return v
    }

    // MARK: sound

    func play(_ on: Bool) {
        if on == running { if on, node != nil, !engine.isRunning { try? engine.start() }; return }
        running = on
        if on { start() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in if self?.running == false { self?.engine.pause() } } }
    }
    private func start() {
        if node == nil {
            let s = AVAudioSession.sharedInstance()
            if s.category != .playback && s.category != .playAndRecord { try? s.setCategory(.playback, options: [.mixWithOthers]) }
            try? s.setActive(true)
            let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(JI_SR), channels: 2)!   // (44.1 kHz, as justints; the mixer converts)
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

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let l = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let r = abl.count > 1 ? abl[1].mData!.assumingMemoryBound(to: Float.self) : l
        if os_unfair_lock_trylock(&lock) {
            apply()
            report.withUnsafeBufferPointer { ji_set_report(e, $0.baseAddress) }
            os_unfair_lock_unlock(&lock)
        }
        ji_render(e, l, r, Int32(frames))
        let want: Float = running ? 1 : 0
        for i in 0..<frames {
            gain += (want - gain) * 0.002
            l[i] *= gain
            if abl.count > 1 { r[i] *= gain }
        }
        if os_unfair_lock_trylock(&lock) { ji_get_view(e, &shown); os_unfair_lock_unlock(&lock) }
    }
}

// MARK: - the view's C tuples, as arrays

extension ji_view {
    func voice(_ k: Int) -> ji_voice_view {
        withUnsafeBytes(of: v) { $0.bindMemory(to: ji_voice_view.self)[max(0, min(Int(JI_VOICES) - 1, k))] }
    }
}
extension ji_voice_view {
    var nums: [Int] { withUnsafeBytes(of: n) { $0.map { Int($0) } } }
    var dens: [Int] { withUnsafeBytes(of: d) { $0.map { Int($0) } } }
}
