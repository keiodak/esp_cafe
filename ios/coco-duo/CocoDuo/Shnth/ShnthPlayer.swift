// ShnthPlayer.swift — coco duo (k.odk)
// SHNTH: the Shbobo Shnth's sound engine, run on the phone and/or sent to the Cafes. The engine (shnth_engine.c) and
// the shlisp compiler (shlisp_compile.c) are a C port of Peter Blasser's firmware and compiler (MIT, github.com/
// pblasser/shbobo; bit-exact against the original firmware); the example patches are his and the players'.
//   a patch (shlisp text) -> shlisp_compile -> the upload image -> the engine (here) / the Cafes ("A" lines over BLE).
// Inputs as the Shnth has them: four bars (bipolar flex: 0 at rest), two antennae (0 untouched), eight buttons + TAR.

import AVFoundation
import Combine
import os

final class ShnthPlayer: ObservableObject {
    /// the patches in the app (Shnth/patches/shnth_*.txt)
    static let patches: [(name: String, source: String)] = {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("shnth_") && !$0.lastPathComponent.contains("LICENSE") }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
        return urls.compactMap { u in
            guard let s = try? String(contentsOf: u, encoding: .isoLatin1) else { return nil }
            return (String(u.deletingPathExtension().lastPathComponent.dropFirst(6)), s)
        }
    }()

    private static let d = UserDefaults.standard
    /// which patch / preset (kept)
    @Published private(set) var patch: Int = ShnthPlayer.d.integer(forKey: "sh.patch")
    @Published private(set) var preset: Int = ShnthPlayer.d.integer(forKey: "sh.preset")
    @Published private(set) var presetCount = 0
    /// where it sounds: the phone · the Cafes (kept)
    @Published var onPhone: Bool = (ShnthPlayer.d.object(forKey: "sh.phone") as? Bool) ?? true { didSet { Self.d.set(onPhone, forKey: "sh.phone") } }
    @Published var onCafe: Bool = (ShnthPlayer.d.object(forKey: "sh.cafe") as? Bool) ?? true { didSet { Self.d.set(onCafe, forKey: "sh.cafe") } }
    @Published private(set) var error = ""
    /// the compiled patch (what the Cafes are sent)
    private(set) var image: [UInt8] = []
    /// a new image / preset for the Cafes (the Director sends it, then clears it)
    var cafeDirty = true

    /// the controls: bars −1…1 (0 = rest), antennae 0…1, buttons (SHNTH_BTN_*)
    var bars: [Double] = [0, 0, 0, 0]
    var corp: [Double] = [0, 0]
    var buttons: UInt16 = 0

    var playing: Bool { running }

    private let eng = UnsafeMutablePointer<shnth_engine>.allocate(capacity: 1)
    private let dl = UnsafeMutablePointer<Int16>.allocate(capacity: Int(SHNTH_DL_SAMPLES))
    private let tmp = UnsafeMutablePointer<Int16>.allocate(capacity: 8192 * 2)
    private var lock = os_unfair_lock()
    // main -> audio: a new image / preset / inputs (taken by the render block when it gets the lock)
    private var pendingImg: UnsafeMutablePointer<UInt8>?
    private var pendingLen = 0
    private var pendingPreset: Int?
    private var pendingInputs = shnth_inputs()
    private var engineImg: UnsafeMutablePointer<UInt8>?
    private var retired: [UnsafeMutablePointer<UInt8>] = []

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr = 48000.0
    private var running = false
    private var gain: Float = 0

    init() {
        dl.initialize(repeating: 0, count: Int(SHNTH_DL_SAMPLES))
        shnth_init(eng, dl)
        if Self.patches.isEmpty { error = "no patches in the app" }
        else { select(patch: min(patch, Self.patches.count - 1), preset: preset) }
    }

    // MARK: the patch

    /// compile a patch (and pick a preset in it)
    func select(patch p: Int, preset n: Int = 0) {
        guard !Self.patches.isEmpty else { return }
        customName = ""
        let i = (p % Self.patches.count + Self.patches.count) % Self.patches.count
        var out = [UInt8](repeating: 0, count: 70000)
        var err = [CChar](repeating: 0, count: 256)
        let len = Self.patches[i].source.withCString { shlisp_compile($0, &out, Int32(out.count), &err, Int32(err.count)) }
        guard len > 0 else { error = String(cString: err); return }
        error = ""
        image = Array(out.prefix(Int(len)))
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(len))
        buf.update(from: image, count: Int(len))
        let count = image.count >= 2 ? Int(image[1]) + 1 : 1
        patch = i; Self.d.set(i, forKey: "sh.patch")
        presetCount = count
        preset = min(max(n, 0), count - 1); Self.d.set(preset, forKey: "sh.preset")
        os_unfair_lock_lock(&lock)
        if let old = pendingImg { retired.append(old) }
        pendingImg = buf; pendingLen = Int(len); pendingPreset = preset
        os_unfair_lock_unlock(&lock)
        cafeDirty = true
        freeRetired()
    }
    /// any shlisp text (GEN, KEPT): compile it and play it, here and on the Cafes (nil = it compiled; else the message)
    @discardableResult
    func play(source: String, preset n: Int = 0) -> String? {
        var out = [UInt8](repeating: 0, count: 70000)
        var err = [CChar](repeating: 0, count: 256)
        let len = source.withCString { shlisp_compile($0, &out, Int32(out.count), &err, Int32(err.count)) }
        guard len > 0 else { error = String(cString: err); return error }
        error = ""
        image = Array(out.prefix(Int(len)))
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(len))
        buf.update(from: image, count: Int(len))
        presetCount = image.count >= 2 ? Int(image[1]) + 1 : 1
        preset = min(max(n, 0), presetCount - 1)
        os_unfair_lock_lock(&lock)
        if let old = pendingImg { retired.append(old) }
        pendingImg = buf; pendingLen = Int(len); pendingPreset = preset
        os_unfair_lock_unlock(&lock)
        cafeDirty = true
        freeRetired()
        return nil
    }
    /// the code playing when it is not a patch from the list (GEN): its name (empty: the list's)
    @Published var customName = ""
    /// … and its code (PATCH's panel shows it)
    var customSource = ""
    /// PATCH's panel (the corner key)
    @Published var panelOpen = false
    /// GEN (the corner key): a new patch at random, here and on the Cafes
    func gen() {
        if let src = ShlispGen.make(chaos: Double.random(in: 0...1), title: ""), play(source: src) == nil { customName = "GEN"; customSource = src }
    }
    func nextPatch() { select(patch: patch + 1) }
    func prevPatch() { select(patch: patch - 1) }
    func setPreset(_ n: Int) {
        guard presetCount > 0 else { return }
        preset = (n % presetCount + presetCount) % presetCount; Self.d.set(preset, forKey: "sh.preset")
        os_unfair_lock_lock(&lock); pendingPreset = preset; os_unfair_lock_unlock(&lock)
        cafeDirty = true
    }
    var patchName: String { Self.patches.isEmpty ? "—" : Self.patches[patch].name }

    /// the image for a Cafe: the whole patch if it fits in one of the Cafe's memory pieces (1536 bytes), else just this
    /// preset on its own (a one-preset image: vector header 00 00, its soup, 16 zero bytes) — returns (image, preset)
    func cafeImage() -> ([UInt8], Int) {
        if image.count <= 1536 { return (image, preset) }
        let n = presetCount
        var starts: [Int] = [2 * (n - 1) + 2]
        for k in 0..<(n - 1) { starts.append(Int(image[2 + 2 * k]) | Int(image[3 + 2 * k]) << 8) }
        let me = starts[min(preset, starts.count - 1)]
        let after = (starts.filter { $0 > me }.min()) ?? (image.count - 16)
        let soup = Array(image[me..<max(me, min(after, image.count))])
        return ([0, 0] + soup + [UInt8](repeating: 0, count: 16), 0)
    }

    // MARK: the controls

    /// the controls -> the engine (called ~30x a second; raw units as the firmware reads them)
    func pushInputs() {
        var inp = shnth_inputs()
        inp.bar = (Int16(bars[0] * 1040), Int16(bars[1] * 1040), Int16(bars[2] * 1040), Int16(bars[3] * 1040))
        inp.corp = (Int16(corp[0] * 512), Int16(corp[1] * 512))
        inp.wind = 0
        inp.buttons = buttons
        inp.cooked = 0
        os_unfair_lock_lock(&lock); pendingInputs = inp; os_unfair_lock_unlock(&lock)
    }
    /// the same, as a Cafe line: "a <bar0..3> <corp0..1> <buttons>"
    func cafeInputLine() -> String {
        let b = bars.map { String(Int($0 * 1040)) }.joined(separator: " ")
        let c = corp.map { String(Int($0 * 512)) }.joined(separator: " ")
        return "a \(b) \(c) \(buttons)"
    }

    // MARK: sound

    func play(_ on: Bool) {
        if on == running { if on { keep() }; return }
        running = on
        if on { start() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in if self?.running == false { self?.engine.pause() } } }
    }
    func keep() {
        guard running, node != nil, !engine.isRunning else { return }
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

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let l = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let r = abl.count > 1 ? abl[1].mData!.assumingMemoryBound(to: Float.self) : l
        if os_unfair_lock_trylock(&lock) {
            if let img = pendingImg {
                _ = shnth_load(eng, img, UInt32(pendingLen))
                if let old = engineImg { retired.append(old) }
                engineImg = img; pendingImg = nil
            }
            if let p = pendingPreset { shnth_select(eng, Int32(p)); pendingPreset = nil }
            var inp = pendingInputs
            shnth_set_inputs(eng, &inp)
            os_unfair_lock_unlock(&lock)
        }
        let want: Float = running && onPhone && engineImg != nil ? 1 : 0
        var done = 0
        while done < frames {
            let n = min(8192, frames - done)
            if engineImg != nil { shnth_render(eng, tmp, Int32(n), UInt32(sr)) }
            for i in 0..<n {
                gain += (want - gain) * 0.002
                l[done + i] = Float(engineImg != nil ? tmp[2 * i] : 0) / 32768 * gain
                r[done + i] = Float(engineImg != nil ? tmp[2 * i + 1] : 0) / 32768 * gain
            }
            done += n
        }
    }

    /// the LEDs (the patch's `lights` / `jump`), for the board (read ~20x a second; a byte, no lock needed)
    func ledsNow() -> UInt8 { shnth_leds(eng) }

    private func freeRetired() {
        os_unfair_lock_lock(&lock)
        let old = retired; retired = []
        os_unfair_lock_unlock(&lock)
        // (an image the audio thread has let go of: freed a little later, never while it may still be read)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { old.forEach { $0.deallocate() } }
    }
}
