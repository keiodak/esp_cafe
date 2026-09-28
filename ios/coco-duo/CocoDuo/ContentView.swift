// ContentView.swift — coco duo (k.odk)
// HUD layout: top bar = Cafe A, eight XY pads, bottom bar = Cafe B.
// What the pads are depends on the preset the TARGET Cafe is on (see Modes.swift):
//   BLE preset  GRAIN / COCO / NOISE: the 8 pads go to every Cafe on that mode
//               DELAY: top row = Cafe A's delay, bottom row = Cafe B's (LINK = both rows move together)
//   HARMONY     like DELAY (top row A, bottom row B)
//   MULTI       top row = the 4 pads of A's effect, bottom row = B's (LINK = same effect, both rows together)
//   ARP_DELAY   top row = the phone's sine arpeggiator, bottom row = the Cafes' stereo tap delay
//   knob presets (COCO_MOD, ECHO, RESONATOR, FORMANT, SATURATOR, RUNGLER, SELF_READ): a placard, the Cafe is played with its own controls
// Keys:  top    [CAFES] [ctx 1] … status (tap = PRESET MANAGER) … [ctx 3] [WAVE]
//        bottom [MODE ] [ctx 2] … status (tap = PRESET MANAGER) … [ctx 4] [CAMERA]
//   GRAIN   freeze · percussion · MOVE (pitch) · sync      HARMONY  hold · link · sync (cycles) · tap          COCO     rec · reverse · to the loop start · sync
//   DELAY   hold · link · grid · tap                   HARMONY  hold · link · grid · tap
//   NOISE   dice · sync                                 MULTI    next effect · random effect (per Cafe)
//   ARP     play / stop · hold · tap · sync

import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class PadAxis: ObservableObject {
    @Published var x: Double
    @Published var y: Double
    init(_ p: (Double, Double)) { x = p.0; y = p.1 }
}

/// Everything the keys and pads do. Owns the Bluetooth hub and the models.
final class Director: ObservableObject {
    let hub = CafeHub()
    let rig = Rig()
    let grain = GrainMode()
    /// HABIT: one memory per Cafe
    lazy var habits: [HabitEngine] = hub.units.map { HabitEngine(unit: $0, axes: rig.habitAxes) }
    lazy var habitPlayer = HabitPlayer(habits)                // (HABIT plays on the phone: L = A, R = B)
    let camera = CameraRig()
    let arp = ArpEngine()
    /// ARP_DELAY's COCO: the phone's two samplers
    let pcoco = PhoneCoco()
    var units: [CafeUnit] { hub.units }
    private var started = false

    /// connected Cafes that are on what the screen shows
    func ctxUnits() -> [CafeUnit] { units.filter { $0.isConnected && rig.inCtx($0.slot) } }

    private var earthTimer: Timer?

    func start() {
        guard !started else { return }
        started = true
        // ARP_DELAY: the EARTH of the Cafe on that preset reaches the arpeggiator ~30x a second
        earthTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self else { return }
            // STEREO: A's EARTH -> voice 1 (left), B's -> voice 2 (right); MONO: the first Cafe on ARP_DELAY
            let on = self.units.filter { $0.isConnected && self.rig.preset[$0.slot] == Preset.arp }
            if let u = on.first { self.arp.earth = Double(u.earth) / 255 }
            if self.rig.arpStereo, let u = on.first(where: { $0.slot == 1 }) ?? on.last { self.arp.earth2 = Double(u.earth) / 255 }
            if self.rig.arpStereo, let u = on.first(where: { $0.slot == 0 }) { self.arp.earth = Double(u.earth) / 255 }
            // a Cafe left ARP_DELAY (from the app or its own BUTTON menu): the arpeggio stops too
            let onArp = self.units.contains { u in (u.isConnected && u.preset >= 0 ? u.preset : self.rig.preset[u.slot]) == Preset.arp }
            if !onArp && self.arp.playing { self.arp.stop(); self.rig.arpPlaying = false }
            // PHONE_COCO: each Cafe's FLIP / SKIP / EARTH play its own sampler (one Cafe on it: it plays both);
            // a Cafe left it: the samplers and SPEECH stop
            let onPc = onArp && self.rig.arpMode == 1
            if onPc && self.rig.pcMode == 0 {
                for k in 0..<2 {
                    if let u = on.first(where: { $0.slot == self.pcoco.link[k] }) ?? on.first {   // (its Cafe; one on it: that one)
                        self.pcoco.jacks(k, flip: u.flip, skip: u.skip, earth: u.earth)
                    }
                }
            }
            if !onPc { self.pcoco.stop() }
            if !onPc && self.arp.speech.playing { self.arp.speech.playing = false; self.rig.speechPlaying = false }
        }
        for u in units {
            u.onReady = { [weak self, weak u] in
                guard let self, let u else { return }
                self.sendAll(to: u)
                self.syncIfPair()
            }
            u.onBpm = { [weak self, weak u] b in
                guard let self, let u else { return }
                self.tempoFromCafe(b, slot: u.slot)
            }
            u.onFx = { [weak self, weak u] e in
                guard let self, let u, e >= 0, e < Fx.count else { return }
                self.fxFromCafe(e, slot: u.slot)
            }
        }
        camera.axes = axes()
        camera.onPadMoved = { [weak self] i in self?.padMoved(i) }
        camera.warm()
        applyArp()
        arp.speechOn = rig.arpMode == 1 && rig.pcMode == 1
        applySpeech()
    }

    /// the 8 pads of the current set (the camera moves these)
    func axes() -> [PadAxis] {
        switch rig.padSet {
        case .grain: return grain.axes
        case .coco: return rig.coAxes
        case .byte: return rig.bbAxes
        case .delay: return rig.dlAxes
        case .noise: return rig.nzAxes
        case .sidrax: return rig.sxAxes
        case .wave: return rig.wvAxes
        case .habit: return rig.habitAxes
        case .harmony: return rig.hdAxes
        case .multi: return (0..<2).flatMap { rig.fxAxes[$0][rig.fxLocal[$0]] }
        case .arp: return rig.arpAxes
        case .speech: return rig.spAxes
        case .pcoco: return rig.pcAxes
        case .knob: return []
        }
    }

    func refresh() { camera.axes = axes() }

    // MARK: presets

    /// put a Cafe on its preset (and mode), then give it every pad
    func sendAll(to u: CafeUnit) {
        let s = u.slot
        u.send("L " + rig.playlist.map(String.init).joined(separator: " "))
        u.send("G \(rig.preset[s])")
        u.send("K \(Int((rig.bpm * 10).rounded()))")
        let pr = rig.preset[s]
        if !(pr == Preset.ble && rig.mode[s] == 6) { habits[s].stop() }          // (HABIT only while the Cafe is on it)
        if pr >= 0 && pr < Preset.count { u.send("X \(Int((rig.charV[s][pr] * 1000).rounded())) \(pr)") }
        switch rig.preset[s] {
        case Preset.ble:
            u.send("M 25 \(rig.mode[s])")
            switch rig.mode[s] {
            case 0: grain.allCommands(slot: s).forEach(u.send)
            case 1: rig.bbAll(slot: s).forEach(u.send)
            case 2: rig.dlAll(slot: s).forEach(u.send)
            case 4: rig.sxAll().forEach(u.send); sxRoles()
            case 5: rig.wvAll().forEach(u.send); sxRoles()
            case 6:
                u.send("B 0 \(rig.habit8k ? 1000 : 0)"); rig.habitLevels().forEach(u.send)
                habits[s].div = rig.habit8k ? 8 : 4; habits[s].hold = rig.habitHold; habits[s].auto = rig.habitAuto
                habits[s].onAutoHold = { [weak self] in self?.rig.habitHold = true }
                habits[s].seconds = rig.habitSeconds; habits[s].other = habits[1 - s]; habits[s].useEarth = rig.habitEarth
                habits[s].start()                  // (the playing goes back to the Cafe)
            default: rig.nzAll(slot: s).forEach(u.send)
            }
        case Preset.harmony:
            rig.hdAll(slot: s).forEach(u.send)
        case Preset.multi:
            rig.fxAll(slot: s).forEach(u.send)
        case Preset.arp:
            u.send("F 97 \(rig.arpMode == 1 ? 1 : 0)")               // ARP: the tap delay · PHONE_COCO: the Cafe is COCO
            if rig.arpMode == 1 {
                rig.coAll(slot: s).forEach(u.send)
                if rig.pcMode == 0 { applyPc(); pcoco.start() } else { arp.speechOn = true; arp.startAudio() }
            } else { rig.arpDelayAll().forEach(u.send) }
        default:
            break
        }
    }

    func setPreset(_ n: Int) {
        guard n >= 0 && n < Preset.poolCount else { return }
        var p = rig.preset
        for s in rig.slots { p[s] = n }
        rig.preset = p
        if n == Preset.arp { arp.speechOn = rig.arpMode == 1 && rig.pcMode == 1; arp.startAudio() }
        arpFollowPresets()
        for s in rig.slots where units[s].isConnected { sendAll(to: units[s]) }
        refresh()
        syncIfPair()
    }

    /// one Cafe only (the knob screen's halves): the other keeps its preset
    func setPreset(_ n: Int, only s: Int) {
        guard n >= 0 && n < Preset.poolCount, s == 0 || s == 1 else { return }
        var p = rig.preset
        p[s] = n
        rig.preset = p
        if n == Preset.arp { arp.speechOn = rig.arpMode == 1 && rig.pcMode == 1; arp.startAudio() }
        arpFollowPresets()
        if units[s].isConnected { sendAll(to: units[s]) }
        refresh()
    }

    func setMode(_ m: Int) {
        var md = rig.mode
        for s in rig.slots where rig.preset[s] == Preset.ble { md[s] = m }
        rig.mode = md
        for s in rig.slots where rig.preset[s] == Preset.ble && units[s].isConnected { sendAll(to: units[s]) }
        refresh()
        syncIfPair()
    }

    func cycleMode() {
        if rig.ctxPreset == Preset.ble { setMode((rig.ctxMode + 1) % Preset.modeNames.count) }
        else if rig.ctxPreset == Preset.arp {                                        // ARP -> COCO -> SPEECH -> ARP
            if rig.arpMode == 0 { rig.pcMode = 0; setArpMode(1) }
            else if rig.pcMode == 0 { setPcMode(1) }
            else { setArpMode(0) }
        }
    }

    func setTarget(_ t: Int) { rig.target = t; refresh() }

    /// PRESET DESIGN: the 11 slots (-1 = empty) -> the playlist (without the empties) -> both Cafes
    func setDesign(_ slots: [Int]) {
        var v = Array((slots + Array(repeating: -1, count: Preset.maxPlaylist)).prefix(Preset.maxPlaylist))
        for i in v.indices where v[i] >= Preset.poolCount { v[i] = -1 }
        rig.design = v
        setPlaylist(v.filter { $0 >= 0 })
    }

    /// PRESET DESIGN: a new playlist (up to 11 pool ids) -> both Cafes (their BUTTON menu follows)
    func setPlaylist(_ p: [Int]) {
        let v = Array(p.filter { $0 >= 0 && $0 < Preset.poolCount }.prefix(Preset.maxPlaylist))
        rig.playlist = v
        guard !v.isEmpty else { return }                      // all slots empty: the Cafes keep their last list
        let line = "L " + v.map(String.init).joined(separator: " ")
        units.filter { $0.isConnected }.forEach { $0.send(line) }
    }

    /// both Cafes on the same thing: start them together (grain score / coco loop / the click)
    func syncIfPair() {
        let u = ctxUnits()
        if u.count == 2 && rig.padSet != .knob && rig.padSet != .noise && rig.padSet != .sidrax { u.forEach { $0.send("Z") } }
    }
    func sync() {
        ctxUnits().forEach { $0.send("Z") }
    }

    // MARK: pads

    func padMoved(_ i: Int) {
        if rig.isTapPad(i) { return }                       // (the TAP pad has no parameters)
        switch rig.padSet {
        case .grain:
            let resync = i == GrainPad.stereo.rawValue && grain.separationReturned()
            for u in ctxUnits() { grain.commands(pad: i, slot: u.slot).forEach(u.send) }
            if resync { sync() }
        case .habit:
            break                                                // (the phone reads HABIT's pads itself)
        case .coco:
            for u in ctxUnits() { rig.coCommands(pad: i, slot: u.slot).forEach(u.send) }
        case .byte:
            if BytePad.isView(i) { return }                     // (the formula is not XY)
            for u in ctxUnits() { rig.bbPad(i, slot: u.slot).forEach(u.send) }
        case .noise:
            for u in ctxUnits() { rig.nzCommands(pad: i, slot: u.slot).forEach(u.send) }
        case .sidrax:
            for u in ctxUnits() { rig.sxCommands(pad: i).forEach(u.send) }
        case .wave:
            for u in ctxUnits() { rig.wvCommands(pad: i).forEach(u.send) }
        case .delay, .harmony:
            let delay = rig.padSet == .delay
            let axes = delay ? rig.dlAxes : rig.hdAxes
            let row = i / 4, k = i % 4
            var rows = [row]
            if rig.link {                                   // LINK: the other row follows
                let j = (1 - row) * 4 + k
                axes[j].x = axes[i].x; axes[j].y = axes[i].y
                rows = [0, 1]
            }
            for r in rows where rig.inCtx(r) && units[r].isConnected {
                let cmds = delay ? rig.dlCommands(pad: r * 4 + k) : rig.hdCommands(pad: r * 4 + k)
                cmds.forEach(units[r].send)
            }
        case .multi:
            let row = i / 4, k = i % 4
            let e = rig.fxLocal[row]
            let a = rig.fxAxes[row][e][k]
            var rows = [row]
            if rig.fxPadLink && rig.fxLocal[1 - row] == e {          // LINK PADS: the other Cafe's pad follows
                let b = rig.fxAxes[1 - row][e][k]
                b.x = a.x; b.y = a.y
                rows = [0, 1]
            }
            for r in rows where rig.inCtx(r) && units[r].isConnected {
                rig.fxCommands(slot: r, e: e, k: k).forEach(units[r].send)
            }
        case .speech:
            if i < 4 { applySpeech() }
            else { for u in ctxUnits() { rig.coCommands(pad: SpPad.coPad[i - 4], slot: u.slot).forEach(u.send) } }
        case .pcoco:
            if i < 4 { applyPc() }
            else { for u in ctxUnits() { rig.coCommands(pad: SpPad.coPad[i - 4], slot: u.slot).forEach(u.send) } }
        case .arp:
            if i < 4 || i == 6 { applyArp() }                          // (6 = voice 2's RATE · SWING in STEREO)
            else { for u in ctxUnits() { rig.arpDelayCommands(pad: i).forEach(u.send) } }
        case .knob:
            break
        }
    }

    // MARK: COCO (ARP_DELAY's third layer)

    /// the top pads -> the phone's samplers
    func applyPc() {
        let a = rig.pcTop, p = pcoco
        p.v[0].start = a[0].x; p.v[0].len = PcPad.len(a[0].y)
        p.v[1].start = a[1].x; p.v[1].len = PcPad.len(a[1].y)
        p.pitch = PcPad.pitch(a[2].x); p.depth = a[2].y
        p.level = a[3].x; p.cross = a[3].y * 0.5
        p.updateAll()
    }

    // MARK: ARP

    /// the top pads and the sliders -> the arpeggiator
    func applyArp() {
        let a = rig.arpAxes
        arp.bpm = rig.bpm
        arp.root = ArpPad.root(a[0].x); arp.chord = ArpPad.chord(a[0].y)
        arp.pattern = ArpPad.pattern(a[1].x); arp.octaves = ArpPad.octaves(a[1].y)
        arp.rateIndex = ArpPad.rate(a[2].x); arp.swing = a[2].y * 0.6
        arp.gate = 0.05 + a[3].x * 0.9; arp.decay = a[3].y
        arp.glide = rig.arpGlide; arp.fifth = rig.arpFifth; arp.level = rig.arpLevel
        arp.earthNotes = rig.arpEarth; arp.low = rig.arpLow
        arp.stereo = rig.arpStereo
        arp.rateIndex2 = ArpPad.rate(a[6].x); arp.swing2 = a[6].y * 0.6
    }
    func arpToggle() {
        applyArp()
        if arp.playing { arp.stop() } else { arp.play(); ctxUnits().forEach { $0.send("Z") } }
        rig.arpPlaying = arp.playing
    }
    /// the arpeggio from its first note, and the Cafes' clicks with it
    func arpSync() { arp.restart(); ctxUnits().forEach { $0.send("Z") } }

    // MARK: ARP_DELAY: ARP or PHONE_COCO — PHONE_COCO = COCO (the phone's samplers) or SPEECH, the Cafe on COCO in both

    func setArpMode(_ m: Int) {
        rig.arpMode = m == 1 ? 1 : 0
        if rig.arpMode == 1 {
            if arp.playing { arp.stop(); rig.arpPlaying = false }
        } else {
            pcoco.stop()
            arp.speech.playing = false; rig.speechPlaying = false
            arp.speechOn = false
        }
        for u in units where u.isConnected && rig.preset[u.slot] == Preset.arp {
            u.send("F 97 \(rig.arpMode)")
            if rig.arpMode == 1 { rig.coAll(slot: u.slot).forEach(u.send) } else { rig.arpDelayAll().forEach(u.send) }
        }
        if rig.arpMode == 1 { setPcMode(rig.pcMode) } else { refresh() }
    }
    /// the Cafe's COCO recording on / off — the same as a press of its EARTH
    func setPcCafeRec(_ s: Int) { if units[s].isConnected { units[s].send("F 98") } }
    func setPcMode(_ m: Int) {
        rig.pcMode = m == 1 ? 1 : 0
        guard rig.arpMode == 1 else { refresh(); return }
        arp.speechOn = rig.pcMode == 1
        if rig.pcMode == 1 {
            pcoco.stop()
            arp.startAudio()
        } else {
            arp.speech.playing = false; rig.speechPlaying = false
            if rig.preset.contains(Preset.arp) { applyPc(); pcoco.start() }
        }
        applySpeech()
        refresh()
    }
    /// the top pads and the sliders -> the voice chain
    func applySpeech() {
        let a = rig.spTop, v = arp.speech
        v.semis = SpPad.semis(a[0].x); v.harmony = a[0].y
        v.resHz = SpPad.resHz(a[1].x); v.resAmt = a[1].y
        v.freeze = a[2].x < 0.02 ? 0 : a[2].x; v.grainMs = SpPad.grainMs(a[2].y)
        v.speed = SpPad.speed(a[3].x); v.gap = SpPad.gap(a[3].y)
        v.level = rig.speechLevel
    }
    private let speaker = SpeechRenderer()
    /// read the line (written, not spoken aloud) and loop it
    func say() {
        let text = rig.speechText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rig.speaking else { return }
        if text.isEmpty { speechDice(); return }                     // nothing written: write something at random
        let vs = SpeechRenderer.voices
        let voice = vs.isEmpty ? nil : vs[min(max(rig.speechVoice, 0), vs.count - 1)]
        rig.speaking = true
        speaker.render(text, voice: voice, rate: Float(0.12 + rig.speechRate * 0.48)) { [weak self] s in
            guard let self else { return }
            self.rig.speaking = false
            guard s.count > 2048 else { return }
            self.arp.speech.load(s)
            self.applySpeech()
            self.arp.speechOn = true
            self.arp.startAudio()
            self.arp.speech.playing = true
            self.rig.speechPlaying = true
        }
    }
    /// DICE: a new line at random (in the voice's language), read at once
    func speechDice() {
        let vs = SpeechRenderer.voices
        let lang = vs.isEmpty ? "en" : vs[min(max(rig.speechVoice, 0), vs.count - 1)].language
        let l = SpeechScraps.line(language: lang)
        guard !l.isEmpty else { return }
        rig.speechText = l
        say()
    }
    /// play / stop the loop (no loop yet: read the line first)
    func speechToggle() {
        if !arp.speech.hasLoop { say(); return }
        arp.speech.playing.toggle()
        if arp.speech.playing { arp.speechOn = true; arp.startAudio(); arp.speech.restart() }
        rig.speechPlaying = arp.speech.playing
    }
    /// the voice from the top, and the Cafe's loop from its start
    func speechSync() { arp.speech.restart(); ctxUnits().forEach { $0.send("C 17 1") } }
    func speechVoiceStep(_ d: Int) {
        let n = SpeechRenderer.voices.count
        guard n > 0 else { return }
        rig.speechVoice = (rig.speechVoice + d + n) % n
    }

    // MARK: MULTI

    /// Cafes that are on MULTI right now
    private func multiUnits() -> [CafeUnit] { units.filter { $0.isConnected && rig.preset[$0.slot] == Preset.multi } }

    /// choose effect e on this Cafe (LINK: on both)
    func setFx(_ s: Int, _ e: Int) {
        let targets = rig.fxLink ? [0, 1] : [s]
        var loc = rig.fxLocal
        for t in targets {
            loc[t] = e
            let u = units[t]
            if u.isConnected && rig.preset[t] == Preset.multi { u.send("F 90 \(e)") }
        }
        rig.fxLocal = loc
        refresh()
    }
    func fxNext(_ s: Int) { setFx(s, (rig.fxLocal[s] + 1) % Fx.count) }
    // DRIFT (MULTI): the XY pads of the effect each Cafe is on wander by themselves — a smooth random walk,
    // sent like a finger would. Only the pads that do something; the TAP pad stays.
    private var driftTimer: Timer?
    private var driftVel = [Double](repeating: 0, count: 16)
    func setFxDrift(_ on: Bool) {
        rig.fxDrift = on
        driftTimer?.invalidate(); driftTimer = nil
        if on {
            driftTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.driftStep() }
        }
    }
    private func driftStep() {
        guard rig.padSet == .multi else { return }
        for i in 0..<8 {
            let row = i / 4, k = i % 4
            if k == 3 || !rig.inCtx(row) { continue }
            if rig.fxPadLink && row == 1 && rig.fxLocal[0] == rig.fxLocal[1] { continue }   // A's pads take B along
            let e = rig.fxLocal[row]
            if Fx.titles[e][k] == "—" { continue }
            let a = rig.fxAxes[row][e][k]
            for c in 0..<2 {
                let j = i * 2 + c
                driftVel[j] = driftVel[j] * 0.92 + Double.random(in: -1...1) * 0.0022
                var v = (c == 0 ? a.x : a.y) + driftVel[j]
                if v < 0.02 { v = 0.02; driftVel[j] = abs(driftVel[j]) }
                if v > 0.98 { v = 0.98; driftVel[j] = -abs(driftVel[j]) }
                if c == 0 { a.x = v } else { a.y = v }
            }
            padMoved(i)
        }
    }
    func fxRandom(_ s: Int) { setFx(s, (rig.fxLocal[s] + 1 + Int.random(in: 0..<(Fx.count - 1))) % Fx.count) }

    /// a Cafe changed its effect itself (FLIP / SKIP): show it, and with LINK take the other Cafe along
    func fxFromCafe(_ e: Int, slot: Int) {
        var loc = rig.fxLocal
        loc[slot] = e
        if rig.fxLink {
            let o = 1 - slot
            loc[o] = e
            let u = units[o]
            if u.isConnected && u.preset == Preset.multi && u.fx != e { u.send("F 90 \(e)") }
        }
        if loc != rig.fxLocal { rig.fxLocal = loc; refresh() }
    }

    /// LINK FX: both Cafes on the same effect (B takes A's), and the same random order from now on
    func setFxLink(_ on: Bool) {
        rig.fxLink = on
        guard on else { return }
        if rig.fxLocal[1] != rig.fxLocal[0] {
            var loc = rig.fxLocal; loc[1] = loc[0]; rig.fxLocal = loc
            let b = units[1]
            if b.isConnected && rig.preset[1] == Preset.multi { b.send("F 90 \(loc[1])") }
        }
        multiUnits().forEach { $0.send("Z") }
        refresh()
    }

    /// LINK PADS: the XY pads move both Cafes (B takes all of A's pad positions)
    func setFxPadLink(_ on: Bool) {
        rig.fxPadLink = on
        guard on else { return }
        for e in 0..<Fx.count { for k in 0..<4 { let a = rig.fxAxes[0][e][k], b = rig.fxAxes[1][e][k]; b.x = a.x; b.y = a.y } }
        let b = units[1]
        if b.isConnected && rig.preset[1] == Preset.multi {
            for e in 0..<Fx.count { for k in 0..<4 { rig.fxCommands(slot: 1, e: e, k: k).forEach(b.send) } }
        }
    }

    func fxSetting(_ line: String) { multiUnits().forEach { $0.send(line) } }
    func fxToggleHold() { rig.fxHold.toggle(); fxSetting("F 94 \(rig.fxHold ? 1 : 0)") }

    // MARK: keys

    func toggleHold() {
        if rig.padSet == .delay {
            rig.dlHold.toggle()
            ctxUnits().forEach { $0.send("Y 10 \(rig.dlHold ? 1000 : 0)") }
        } else if rig.padSet == .harmony {
            rig.hdHold.toggle()
            ctxUnits().forEach { $0.send("V 13 \(rig.hdHold ? 1000 : 0)") }
        }
    }

    func toggleGrid() {
        rig.grid.toggle()
        let v = rig.grid ? 1000 : 0
        if rig.padSet == .delay { ctxUnits().forEach { $0.send("Y 8 \(v)") } }
    }

    /// LINK: the two Cafes as one. DELAY: one line per Cafe, ping-pong goes A -> B. Both rows take A's pads.
    func toggleLink() {
        rig.link.toggle()
        let delay = rig.padSet == .delay
        let axes = delay ? rig.dlAxes : rig.hdAxes
        if rig.link { for k in 0..<4 { axes[4 + k].x = axes[k].x; axes[4 + k].y = axes[k].y } }
        let b = Int((rig.bpm * 10).rounded())
        for u in ctxUnits() {
            u.send("K \(b)")
            if delay {
                u.send("Y 12 \(u.slot == 1 ? 1000 : 0)")
                u.send("Y 11 \(rig.link ? 1000 : 0)")
            }
            for k in 0..<4 {
                let cmds = delay ? rig.dlCommands(pad: u.slot * 4 + k) : rig.hdCommands(pad: u.slot * 4 + k)
                cmds.forEach(u.send)
            }
        }
        sync()
    }

    /// CHAR (the slider next to the tempo) for one Cafe's current preset
    func setChar(_ v: Double, slot: Int) {
        let p = rig.preset[slot]
        guard p >= 0 && p < Preset.count else { return }
        let c = min(max(v, 0), 1)
        var cv = rig.charV
        cv[slot][p] = c
        if rig.fxLink && p == Preset.multi || rig.link { cv[1 - slot][p] = c }
        rig.charV = cv
        let msg = "X \(Int((c * 1000).rounded())) \(p)"
        let who = (rig.fxLink && p == Preset.multi) || rig.link ? [0, 1] : [slot]
        for s in who where rig.preset[s] == p && units[s].isConnected { units[s].send(msg) }
    }

    func tapTempo() {
        guard let b = rig.tap() else { return }
        setBpm(b)
        if rig.padSet == .arp {                     // ARP_DELAY: the tap is the downbeat, for the phone and the Cafe
            if arp.playing { arp.restart() }
            ctxUnits().forEach { $0.send("Z") }
        }
    }

    /// the arpeggio only sounds while a Cafe is on ARP_DELAY
    private func arpFollowPresets() {
        if !rig.preset.contains(Preset.arp) && arp.playing { arp.stop(); rig.arpPlaying = false }
        if !rig.preset.contains(Preset.arp) && arp.speech.playing { arp.speech.playing = false; rig.speechPlaying = false }
        if !rig.preset.contains(Preset.arp) { pcoco.stop() }
    }

    func setBpm(_ b: Double) {
        rig.bpm = min(max(b, 30), 300)
        arp.bpm = rig.bpm
        let v = Int((rig.bpm * 10).rounded())
        units.filter { $0.isConnected }.forEach { $0.send("K \(v)") }
    }

    /// SKIP was tapped on a Cafe: that is everyone's tempo now
    func tempoFromCafe(_ b: Double, slot: Int) {
        guard abs(b - rig.bpm) > 0.3 else { return }
        rig.bpm = b
        arp.bpm = b
        if arp.playing { arp.restart() }                          // the tap was on the beat: start the arpeggio there
        let v = Int((b * 10).rounded())
        for u in units where u.slot != slot && u.isConnected { u.send("K \(v)") }
        if rig.link { sync() }
    }

    func toggleRec() {
        let r = units[rig.focus].recording ? 0 : 1
        ctxUnits().forEach { $0.send("R \(r)") }
    }

    func toggleCoReverse() {
        rig.coReverse.toggle()
        ctxUnits().forEach { $0.send("C 16 \(rig.coReverse ? 1 : 0)") }
    }

    func setNzSpeed(_ s: Int) {
        rig.nzSpeed = s == 1 ? 1 : 0
        ctxUnits().forEach { $0.send("N 15 \(rig.nzSpeed * 500)") }
    }

    // MARK: SIDRAX
    /// the seesaw needs to know which Cafe is which: two on SIDRAX = A (0) and B (1); one alone plays both halves (2)
    func sxRoles() {
        let on = units.filter { $0.isConnected && rig.preset[$0.slot] == Preset.ble && rig.mode[$0.slot] >= 4 && rig.mode[$0.slot] <= 5 }
        for u in on { u.send("S 9 \(on.count == 2 ? u.slot : 2)") }
    }
    /// SIDRAX / WAVE: FREEZE on / off · BYTEBEAT: FREEZE = t loops the last beat
    func setSxFreeze(_ m: Int) { rig.sxFreeze = m; ctxUnits().forEach { $0.send("S 24 \(Rig.freezeValue(m))") } }
    func setWvFreeze(_ m: Int) { rig.wvFreeze = m; ctxUnits().forEach { $0.send("S 24 \(Rig.freezeValue(m))") } }
    func setBbFreeze(_ on: Bool) {
        rig.bbFreeze = on
        ctxUnits().forEach { $0.send("J 9 14 \(on ? 1000 : 0)") }
    }
    /// BYTEBEAT: the formula, sent when it reads
    func setBbFormula(_ f: String) {
        rig.bbCode = f
        guard Bytebeat.parse(f) != nil else { return }
        for u in ctxUnits() { rig.bbFormulaLines(slot: u.slot).forEach(u.send) }
    }
    /// a new one
    func bbDice() { setBbFormula(Bytebeat.random()) }
    /// SLOW: t at 1/32
    func setBbRev(_ on: Bool) { rig.bbRev = on; ctxUnits().forEach { $0.send("J 9 15 \(on ? 1000 : 0)") } }
    // MARK: HABIT
    func setHabit8k(_ on: Bool) {
        rig.habit8k = on
        for u in ctxUnits() { u.send("B 0 \(on ? 1000 : 0)"); habits[u.slot].div = on ? 8 : 4; habits[u.slot].clear() }
    }
    func setHabitHold(_ on: Bool) { rig.habitHold = on; habits.forEach { $0.hold = on } }
    func setHabitEarth(_ on: Bool) { rig.habitEarth = on; habits.forEach { $0.useEarth = on } }
    func setHabitAuto(_ on: Bool) {
        rig.habitAuto = on
        habits.forEach { e in
            e.auto = on
            e.onAutoHold = { [weak self] in self?.rig.habitHold = true }
        }
    }
    func setHabitSeconds(_ v: Double) {
        rig.habitSeconds = v; HabitEngine.shownSeconds = v
        habits.forEach { $0.seconds = v }
    }
    func habitClear() { for u in ctxUnits() { habits[u.slot].clear() } }
    /// the memory of the first Cafe on HABIT, as a WAV
    func habitSave() {
        guard let u = ctxUnits().first else { return }
        rig.habitWav = habits[u.slot].wav()
    }
    func setSxAligned(_ on: Bool) { rig.sxAligned = on; ctxUnits().forEach { $0.send("S 8 \(on ? 1000 : 0)") } }
    /// HOLD: a lifted finger leaves its plate sounding; off = every plate lifts
    func setSxHold(_ on: Bool) {
        rig.sxHold = on
        if !on { rig.sxArea = [0, 0, 0, 0]; for k in 0..<4 { padMoved(4 + k) } }
    }
    /// WAVE: an audio file -> a 64-frame wavetable -> the start of the tape of every Cafe on WAVE
    func loadWaveTable(_ url: URL) {
        let targets = ctxUnits()
        rig.wvNote = "making the table…"
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let outcome = Result { try WaveTable.make(url: url) }
            DispatchQueue.main.async {
                switch outcome {
                case .success(let t):
                    self.rig.wvNote = url.deletingPathExtension().lastPathComponent
                    targets.forEach { u in u.load(t) { u.send("S 25 1") } }       // (then: the table is good)
                case .failure(let e): self.rig.wvNote = e.localizedDescription
                }
            }
        }
    }
    func sxDice() {
        for i in 0..<4 { rig.sxAxes[i].x = Double.random(in: 0.05...0.95); rig.sxAxes[i].y = Double.random(in: 0.0...0.8) }
        for i in 0..<4 { padMoved(i) }
    }

    func setNzDist(_ on: Bool) { rig.nzDist = on; ctxUnits().forEach { $0.send("N 16 \(on ? 1 : 0)") } }

    func noiseDice() {
        rig.nzDice()
        for u in ctxUnits() { rig.nzAll(slot: u.slot).forEach(u.send) }
    }

    // MARK: firmware update

    func update(_ data: [UInt8]) {
        let t = rig.updTarget == 2 ? [0, 1] : [rig.updTarget]
        for s in t { units[s].startUpdate(data) }
    }
}

struct ContentView: View {
    @StateObject private var d = Director()

    var body: some View {
        MainScreen(d: d, hub: d.hub, rig: d.rig, grain: d.grain, camera: d.camera)
    }
}

private struct MainScreen: View {
    let d: Director
    @ObservedObject var hub: CafeHub
    @ObservedObject var rig: Rig
    @ObservedObject var grain: GrainMode
    @ObservedObject var camera: CameraRig
    @State private var padHeight: CGFloat = 122
    @State private var showCafes = false
    @State private var showWave = false
    @State private var showPresets = false
    @State private var safeLeading: CGFloat = 0
    @State private var safeTrailing: CGFloat = 0
    private let barHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 7) {
            HudBar(d: d, unit: hub.units[0], rig: rig, grain: grain, camera: camera, pc: d.pcoco,
                   showCafes: $showCafes, showWave: $showWave, showPresets: $showPresets)
                .frame(maxWidth: .infinity)                  // (never wider than the screen: the pads keep off the camera)
                .frame(height: barHeight)
            pads
                .frame(maxWidth: .infinity)
                .zIndex(1)
            HudBar(d: d, unit: hub.units[1], rig: rig, grain: grain, camera: camera, pc: d.pcoco,
                   showCafes: $showCafes, showWave: $showWave, showPresets: $showPresets)
                .frame(maxWidth: .infinity)                  // (never wider than the screen: the pads keep off the camera)
                .frame(height: barHeight)
        }
        .overlayPreferenceValue(PlateAnchors.self) { a in                                   // SIDRAX / WAVE: the fingers, over everything
            if rig.padSet == .sidrax || rig.padSet == .wave { FingerDiscs(rig: rig, anchors: a) }
        }
        .fileImporter(isPresented: $rig.wvPicking, allowedContentTypes: [.audio]) { result in   // WAVE: FILE
            if case .success(let url) = result { d.loadWaveTable(url) }
        }
        .padding(8)
        .padding(.leading, max(0, safeTrailing - safeLeading))
        .padding(.trailing, max(0, safeLeading - safeTrailing))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PastelTheme.screenBackdrop.ignoresSafeArea())
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        readSafeArea()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { readSafeArea() }
                    }
                    .onChange(of: geo.size) { _, _ in readSafeArea() }
            }
            .ignoresSafeArea()
        )
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .sheet(isPresented: $showCafes) { CafesView(d: d, hub: hub, camera: camera) }
        .sheet(isPresented: $showWave) { WaveView(hub: hub) }
        .fileExporter(isPresented: Binding(get: { rig.habitWav != nil }, set: { if !$0 { rig.habitWav = nil } }),
                      document: WavDoc(data: rig.habitWav ?? Data()), contentType: .wav,
                      defaultFilename: "habit") { _ in rig.habitWav = nil }
        .sheet(isPresented: $showPresets) {
            PresetManagerView(d: d, rig: rig, a: hub.units[0], b: hub.units[1])
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            d.start()
        }
        .onChange(of: rig.target) { _, _ in d.refresh() }
    }

    @ViewBuilder private var pads: some View {
        if rig.padSet == .knob {
            KnobPlacard(d: d, rig: rig, a: hub.units[0], b: hub.units[1])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) { ForEach(0..<4, id: \.self) { pad($0) } }
                HStack(spacing: 6) { ForEach(4..<8, id: \.self) { pad($0) } }
                    .zIndex(1)
            }
            .frame(maxHeight: .infinity)
            .fileImporter(isPresented: Binding(get: { rig.pcPicking >= 0 }, set: { if !$0 { rig.pcPicking = -1 } }),
                          allowedContentTypes: [.audio]) { result in                        // COCO: FILE A / B
                if case .success(let url) = result { d.pcoco.load(url, into: rig.pcSlot) }
                rig.pcPicking = -1
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { padHeight = max(60, (geo.size.height - 6) / 2) }
                        .onChange(of: geo.size) { _, s in padHeight = max(60, (s.height - 6) / 2) }
                }
            )
        }
    }

    private func info(_ i: Int) -> (PadAxis, String) {
        switch rig.padSet {
        case .grain: return (grain.axes[i], GrainPad(rawValue: i)!.title)
        case .coco: return (rig.coAxes[i], CoPad(rawValue: i)!.title)
        case .byte: return (rig.bbAxes[i], BytePad.titles[i])
        case .delay: return (rig.dlAxes[i], DlPad(rawValue: i % 4)!.title)
        case .noise: return (rig.nzAxes[i], NzPad(rawValue: i)!.title)
        case .sidrax: return (rig.sxAxes[i], SxPad.titles[i])
        case .wave: return (rig.wvAxes[i], WvPad.titles[i])
        case .habit: return (rig.habitAxes[i], HabitPad.titles[i])
        case .harmony: return (rig.hdAxes[i], HdPad(rawValue: i % 4)!.title)
        case .multi: let e = rig.fxLocal[i / 4]; return (rig.fxAxes[i / 4][e][i % 4], Fx.titles[e][i % 4])
        case .arp: return (rig.arpAxes[i], i == 6 ? (rig.arpStereo ? "RATE · SWING (R)" : "—") : ArpPad.titles[i])
        case .speech: return (rig.spAxes[i], i < 4 ? SpPad.titles[i] : "—")       // (the Cafe is COCO_MOD: its knobs)
        case .pcoco: return (rig.pcAxes[i], i < 4 ? PcPad.titles[i] : "—")
        case .knob: return (rig.nzAxes[i], "")
        }
    }

    /// the small text under a pad's title (what it is set to), for the pads that have one
    private func captionFor(_ i: Int) -> ((Double, Double) -> String)? {
        switch rig.padSet {
        case .arp:
            if i == 6 && rig.arpStereo { return { x, y in ArpPad.caption(2, x, y) } }
            if i >= 4 { return nil }
            return { x, y in ArpPad.caption(i, x, y) }
        case .harmony:
            return { x, y in HdPad.caption(i % 4, x, y) }
        case .speech:
            if i >= 4 { return nil }
            return { x, y in SpPad.caption(i, x, y) }
        case .pcoco:
            if i >= 4 { return nil }
            return { x, y in PcPad.caption(i, x, y) }
        case .habit:
            return { x, y in HabitPad.caption(i, x, y) }
        case .byte:
            if BytePad.isView(i) { return nil }
            return { x, y in BytePad.caption(i, x, y) }
        case .sidrax:
            if i >= 4 { return nil }
            let r = rig
            return { x, y in SxPad.caption(i, x, y, rig: r) }
        case .wave:
            if i >= 4 { return nil }
            let r = rig
            if i == 1 || i == 2 { return { x, y in WvPad.caption(i, x, y) } }
            return { x, y in SxPad.caption(i, x, y, rig: r) }
        default:
            return nil
        }
    }

    @ViewBuilder private func pad(_ i: Int) -> some View {
        if (rig.padSet == .sidrax || rig.padSet == .wave) && i >= 4 {   // SIDRAX / WAVE: the bottom row = four touch plates
            let director = d
            PlatePad(axis: rig.sxAxes[i], rig: rig, k: i - 4, tag: String(format: "%02ld", i + 1), send: { director.padMoved(i) })
                .frame(height: padHeight)
                .zIndex(rig.sxArea[i - 4] > 0 ? 2 : 1)                  // the finger's disc goes over the pads beside it
                .id("sx\(i)")
        } else if rig.padSet == .byte && i == 2 {                   // BYTEBEAT: the formula
            let director = d
            FormulaPad(rig: rig, xy: rig.bbAxes[1], tag: "03", set: { director.setBbFormula($0) })
                .frame(height: padHeight)
        } else if rig.isTapPad(i) {
            TapPad(rig: rig, tag: rig.perRow ? (i < 4 ? "A" : "B") + ".04" : "08", tap: { d.tapTempo() })
                .frame(height: padHeight)
        } else {
        let item = info(i)
        let live = (rig.perRow ? rig.inCtx(i / 4) : true) && item.1 != "—"
        let caption = captionFor(i)
        let tag = rig.perRow ? (i < 4 ? "A" : "B") + String(format: ".%02ld", i % 4 + 1) : String(format: "%02ld", i + 1)
        let director = d
        HudPad(axis: item.0, title: item.1, tag: tag,
               send: { director.padMoved(i) },
               cam: camera.state, cameraMode: camera.enabled, index: i, padHeight: padHeight, caption: caption)
            .frame(height: padHeight)
            .opacity(live ? 1 : 0.35)
            .allowsHitTesting(live)
            .overlay {                                                        // HABIT: the memory, under WHERE
                if rig.padSet == .habit && i == 0 { HabitStereoScope(l: d.habits[0].scope, r: d.habits[1].scope) }
                if rig.padSet == .pcoco && i < 2 {                                // COCO: the sampler's sound, under its pad
                    PcWave(pc: d.pcoco, k: i, axis: rig.pcTop[i]).padding(.vertical, 22)
                }
            }
            .id("\(rig.padSet)\(i)-\(rig.padSet == .multi ? rig.fxLocal[i / 4] : 0)")
        }
    }

    private func readSafeArea() {
        let win = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        let i = win?.safeAreaInsets ?? .zero
        safeLeading = i.left
        safeTrailing = i.right
    }
}

// MARK: - one pad

private struct HudPad: View {
    @ObservedObject var axis: PadAxis
    let title: String
    let tag: String
    let send: () -> Void
    @ObservedObject var cam: CameraState
    let cameraMode: Bool
    let index: Int
    let padHeight: CGFloat
    var caption: ((Double, Double) -> String)? = nil

    private var edgeGlow: Double {
        guard cameraMode else { return 0 }
        return min(max((cam.cameraMotion - 0.05) / 0.22, 0), 1)
    }

    /// this pad's 4 × 4 cells of the 8 × 16 mosaic
    private var block: [[Double]] {
        let g = cam.mosaicBrightness
        let r0 = (index / 4) * 4, c0 = (index % 4) * 4
        guard g.count >= r0 + 4, g[0].count >= c0 + 4 else { return Array(repeating: Array(repeating: 0.5, count: 4), count: 4) }
        return (0..<4).map { r in (0..<4).map { c in g[r0 + r][c0 + c] } }
    }

    var body: some View {
        XYPad(
            label: "", xLabel: "", yLabel: "",
            x: $axis.x, y: $axis.y,
            padHeight: padHeight,
            interactionEnabled: !cameraMode,
            onDrag: { _, _ in send() },
            cornerRadii: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0),
            trace: nil,
            mosaic: cameraMode ? block : nil,
            edgeGlow: edgeGlow,
            cameraMode: cameraMode
        )
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                HudTag(text: tag, size: 7)
                Text(title.replacingOccurrences(of: " · ", with: "_").replacingOccurrences(of: " ", with: "_"))
                    .font(.hud(8, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(PastelTheme.hudOrange)
            }
            .padding(.leading, 7)
            .padding(.top, 6)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            if let caption {
                Text(caption(axis.x, axis.y))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(PastelTheme.hudBlack.opacity(0.7))
                    .padding(.leading, 8)
                    .padding(.bottom, 6)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// TAP: one pad for the tempo. Every touch is a tap (two or more set the BPM, sent to the Cafes).
private struct TapPad: View {
    @ObservedObject var rig: Rig
    let tag: String
    let tap: () -> Void
    @State private var lit = false

    var body: some View {
        ZStack {
            Rectangle().fill(lit ? PastelTheme.hudOrange.opacity(0.35) : PastelTheme.padScreen)
            HudDots(step: 12)
            Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
            HudCorners(arm: 8).stroke(PastelTheme.hudBlack, lineWidth: 1.2).padding(3)
            VStack(spacing: 2) {
                Text(String(format: "%.1f", rig.bpm))
                    .font(.hudBig(30))
                    .foregroundStyle(PastelTheme.hudBlack)
                Text("BPM · TAP")
                    .font(.hud(8, .semibold))
                    .tracking(1)
                    .foregroundStyle(PastelTheme.hudOrange)
            }
            .offset(y: 4)                                   // the digits' box is taller below: down to the true centre
        }
        .overlay(alignment: .topLeading) {
            HudTag(text: tag, size: 7).padding(.leading, 7).padding(.top, 6)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
            if !lit { lit = true; tap() }
        }.onEnded { _ in lit = false })
    }
}

/// knob presets: nothing to play here, the Cafe is played with its own controls
/// knob presets: the Cafe is played with its own controls. Split down the middle — A left, B right, side by side —
/// each half shows its Cafe's preset, big (they can be on different presets; change them in the preset manager).
private struct KnobPlacard: View {
    let d: Director
    @ObservedObject var rig: Rig
    @ObservedObject var a: CafeUnit
    @ObservedObject var b: CafeUnit

    var body: some View {
        ZStack {
            Rectangle().fill(PastelTheme.padScreen)
            HudDots(step: 12)
            Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
            HudCorners(arm: 12).stroke(PastelTheme.hudBlack, lineWidth: 1.4).padding(4)
            HStack(spacing: 0) {
                KnobHalf(d: d, rig: rig, unit: a)
                Rectangle().fill(PastelTheme.hudLine).frame(width: 1).padding(.vertical, 14)
                KnobHalf(d: d, rig: rig, unit: b)
            }
        }
    }
}

private struct KnobHalf: View {
    let d: Director
    @ObservedObject var rig: Rig
    @ObservedObject var unit: CafeUnit

    var body: some View {
        let s = unit.slot
        let n = unit.isConnected && unit.preset >= 0 ? unit.preset : rig.preset[s]
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                HudTag(text: s == 0 ? "A" : "B", fill: unit.isConnected ? PastelTheme.hudBlack : PastelTheme.hudLine, size: 9)
                Text(unit.isConnected ? (unit.name ?? "") : "NO_LINK")
                    .font(.hud(8, .semibold))
                    .foregroundStyle(PastelTheme.textSecondary)
                    .lineLimit(1)
            }
            Text(Preset.tag(n))
                .font(.hudBig(44))
                .foregroundStyle(PastelTheme.hudBlack)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Rectangle().fill(PastelTheme.hudOrange).frame(width: 110, height: 3)
            Text(n >= 0 && n < Preset.notes.count ? Preset.notes[n].uppercased() : "")
                .font(.hud(10, .medium))
                .tracking(0.6)
                .foregroundStyle(PastelTheme.textSecondary)
                .lineLimit(3)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - top / bottom bar (one Cafe each)

private struct HudBar: View {
    let d: Director
    @ObservedObject var unit: CafeUnit
    @ObservedObject var rig: Rig
    @ObservedObject var grain: GrainMode
    @ObservedObject var camera: CameraRig
    @ObservedObject var pc: PhoneCoco
    @Binding var showCafes: Bool
    @Binding var showWave: Bool
    @Binding var showPresets: Bool

    private var top: Bool { unit.slot == 0 }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                if top {
                    key("dot.radiowaves.left.and.right", on: unit.isConnected) { showCafes = true }
                } else {
                    if rig.padSet == .multi {
                        key("wind", on: rig.fxDrift) { d.setFxDrift(!rig.fxDrift) }      // DRIFT: the pads wander
                    } else {
                        key(rig.ctxPreset == Preset.arp ? (rig.arpMode == 0 ? "pianokeys" : rig.pcMode == 1 ? "waveform.and.mic" : "recordingtape")
                                                        : Preset.modeIcons[min(max(rig.ctxMode, 0), Preset.modeIcons.count - 1)], on: false,
                            enabled: rig.ctxPreset == Preset.ble || rig.ctxPreset == Preset.arp) { d.cycleMode() }
                    }
                }
                contextKey(top ? 0 : 1)
            }
            HStack(spacing: 6) {
                Button { showPresets = true } label: { status }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                CharControl(d: d, rig: rig, slot: unit.slot, preset: shownPreset)
                statusEnd
            }
            HStack(spacing: 8) {
                contextKey(top ? 2 : 3)
                if top { key("waveform") { showWave = true } }
                else { key("camera.aperture", on: camera.enabled) { camera.enabled.toggle() } }
            }
        }
    }

    private var shownPreset: Int { unit.isConnected && unit.preset >= 0 ? unit.preset : rig.preset[unit.slot] }

    /// A · name · preset · mode · tempo (tap = the preset manager)
    private var status: some View {
        let p = unit.isConnected && unit.preset >= 0 ? unit.preset : rig.preset[unit.slot]
        let m = unit.isConnected ? unit.mode : rig.mode[unit.slot]
        let inView = rig.inCtx(unit.slot)
        // one line, every part on a fixed width: switching presets never pushes the slider or the keys about
        var info = ""
        if p == Preset.ble { info = Preset.modeNames[min(max(m, 0), Preset.modeNames.count - 1)] }
        if p == Preset.ble && m == 6 {                                              // HABIT: kB/s — or, while nothing
            info = unit.hbUp > 0 ? String(format: "↑%.1f↓%.1f", unit.hbUp, unit.hbDown)  // comes: the Cafe's made / sent / MTU
                                 : "M\(unit.hbMade % 1000)S\(unit.hbSent % 1000)U\(unit.cafeMtu)"
        }
        if p == Preset.multi { info = Fx.names[min(max(unit.isConnected && unit.fx >= 0 ? unit.fx : rig.fxLocal[unit.slot], 0), Fx.count - 1)] + (rig.fxLink ? " LINK" : "") }
        if (p == Preset.ble && m == 2) || p == Preset.harmony || p == Preset.arp {
            info += (info.isEmpty ? "" : " ") + String(format: "%.0fBPM", unit.bpm > 0 ? unit.bpm : rig.bpm)
        }
        let guide = p == Preset.ble ? Preset.modeGuides[min(max(m, 0), Preset.modeGuides.count - 1)]
                  : (p >= 0 && p < Preset.notes.count ? Preset.notes[p] : "")
        return HStack(alignment: .center, spacing: 6) {
            HudTag(text: top ? "A" : "B", fill: unit.isConnected ? PastelTheme.hudBlack : PastelTheme.hudLine, size: 9)
            Text((unit.name ?? "NO_LINK").uppercased().replacingOccurrences(of: "-", with: "_"))
                .font(.hud(9, .semibold))
                .foregroundStyle(PastelTheme.hudBlack)
                .lineLimit(1)
                .frame(width: 50, alignment: .leading)
            HStack(spacing: 0) {
                HudTag(text: Preset.tag(p), fill: inView ? PastelTheme.hudBlack : PastelTheme.textSecondary, size: 9)
                Spacer(minLength: 0)
            }
            .frame(width: 88).clipped()
            Text(info)
                .font(.hud(9, .semibold).monospacedDigit())
                .tracking(1)
                .foregroundStyle(PastelTheme.hudOrange)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)
            GuideTicker(text: guide)
            // the preset manager lives behind this box: say so
            HudTag(text: "▾", size: 9)
        }
        .frame(maxHeight: .infinity)
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .frame(height: 20)
        .background(Rectangle().fill(PastelTheme.padScreen))
        .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
        .contentShape(Rectangle())
    }

    /// ··· update · clock · link lamp
    private var statusEnd: some View {
        HStack(spacing: 6) {
            Rectangle().fill(PastelTheme.hudLine).frame(height: 1)
                .overlay {                                           // (laid over the line: it never widens the bar)
                    if let o = unit.ota {
                        HudTag(text: String(format: "UPD_%02ld%%", Int(o * 100)), fill: PastelTheme.hudOrange, size: 8)
                            .fixedSize()
                    }
                }
            Text(unit.hz > 0 ? String(format: "%.1fK", unit.hz / 1000) : "—")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(PastelTheme.textSecondary)
            Rectangle()
                .fill(unit.isConnected ? PastelTheme.hudOrange : Color.clear)
                .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
                .frame(width: 7, height: 7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// the two keys that change with the pads (0/2 on the top bar, 1/3 on the bottom)
    @ViewBuilder private func contextKey(_ n: Int) -> some View {
        switch rig.padSet {
        case .grain:
            switch n {
            case 0: key("snowflake", on: grain.freeze) { grain.setFreeze(!grain.freeze, d.ctxUnits()) }
            case 1: key("metronome", on: grain.perc) { grain.setPerc(!grain.perc, d.ctxUnits()) }
            case 2: key(grain.fold ? "wave.3.forward" : "waveform.path", on: grain.move || grain.fold) {   // off -> PITCH -> FOLD
                        grain.cyclePitchFold(d.ctxUnits())
                    }
            default: key("arrow.triangle.2.circlepath") { d.sync() }
            }
        case .coco:
            switch n {
            case 0: key("record.circle", on: d.units[rig.focus].recording) { d.toggleRec() }
            case 1: key("arrow.left.arrow.right", on: rig.coReverse) { d.toggleCoReverse() }
            case 2: key("backward.end") { d.ctxUnits().forEach { $0.send("C 17 1") } }
            default: key("arrow.triangle.2.circlepath") { d.sync() }
            }
        case .delay, .harmony:
            switch n {
            case 0: key("pause.circle", on: rig.padSet == .delay ? rig.dlHold : rig.hdHold) { d.toggleHold() }
            case 1: key("link", on: rig.link) { d.toggleLink() }
            case 2:
                if rig.padSet == .delay { key("squareshape.split.3x3", on: rig.grid) { d.toggleGrid() } }
                else { key("arrow.triangle.2.circlepath") { d.sync() } }       // HARMONY: cycles start together
            default: key("hand.tap") { d.tapTempo() }
            }
        case .byte:
            switch n {
            case 0: key("dice") { d.bbDice() }                                      // a new formula
            case 1: key("arrow.triangle.2.circlepath") { d.sync() }                // the same t on both Cafes
            case 2: textKey("FREEZE", on: rig.bbFreeze) { d.setBbFreeze(!rig.bbFreeze) }   // t round the last two steps
            default: textKey("REV", on: rig.bbRev) { d.setBbRev(!rig.bbRev) }              // t runs backwards
            }
        case .habit:
            switch n {
            case 0: textKey(rig.habit8k ? "4K" : "8K", on: rig.habit8k) { d.setHabit8k(!rig.habit8k) }    // the rate: 8K / 4K
            case 1: key("pause.circle", on: rig.habitHold) { d.setHabitHold(!rig.habitHold) }            // HOLD: keep the memory
            case 2: textKey("AUTO", on: rig.habitAuto) { d.setHabitAuto(!rig.habitAuto) }             // full -> it freezes
            default: textKey("CLEAR", on: false) { d.habitClear() }
            }
        case .wave:
            switch n {
            case 0: key("tuningfork", on: rig.sxAligned) { d.setSxAligned(!rig.sxAligned) }     // ALIGNED / FREE
            case 1: key("pause.circle", on: rig.sxHold) { d.setSxHold(!rig.sxHold) }
            case 2: textKey("FREEZE", on: rig.wvFreeze > 0) { d.setWvFreeze(rig.wvFreeze > 0 ? 0 : 1) }
            default: textKey("FILE", on: rig.wvPicking) { rig.wvPicking = true }                // an audio file -> the table
            }
        case .sidrax:
            switch n {
            case 0: key("tuningfork", on: rig.sxAligned) { d.setSxAligned(!rig.sxAligned) }     // ALIGNED / FREE
            case 1: key("pause.circle", on: rig.sxHold) { d.setSxHold(!rig.sxHold) }             // HOLD the plates
            case 2: textKey("FREEZE", on: rig.sxFreeze > 0) { d.setSxFreeze(rig.sxFreeze > 0 ? 0 : 1) }
            default: key("dice") { d.sxDice() }
            }
        case .noise:
            switch n {
            case 0: key("dice") { d.noiseDice() }
            case 1: key("arrow.triangle.2.circlepath") { d.sync() }
            case 2: textKey(rig.nzSpeed == 1 ? "LFO" : "FAST", on: rig.nzSpeed == 1) { d.setNzSpeed(1 - rig.nzSpeed) }   // FAST <-> LFO
            default: textKey("DIST", on: rig.nzDist) { d.setNzDist(!rig.nzDist) }                              // overdrive on / off
            }
        case .arp:
            switch n {
            case 0: key(rig.arpPlaying ? "stop.fill" : "play.fill", on: rig.arpPlaying) { d.arpToggle() }
            case 1: key(rig.arpStereo ? "speaker.wave.2" : "speaker", on: rig.arpStereo) {   // MONO / STEREO
                        rig.arpStereo.toggle(); d.applyArp(); d.refresh()
                    }
            case 2: key("hand.tap") { d.tapTempo() }
            default: key("arrow.triangle.2.circlepath") { d.arpSync() }
            }
        case .pcoco:
            switch n {
            case 0: textKey(pc.loading[0] ? "LOAD…" : "FILE A", on: rig.pcPicking == 0 || pc.loading[0]) { rig.pcSlot = 0; rig.pcPicking = 0 }
            case 1: textKey(pc.loading[1] ? "LOAD…" : "FILE B", on: rig.pcPicking == 1 || pc.loading[1]) { rig.pcSlot = 1; rig.pcPicking = 1 }
            case 2: textKey("REC", on: unit.recording) { d.setPcCafeRec(0) }     // the Cafe's COCO recording on / off (as EARTH)
            default: textKey("REC", on: unit.recording) { d.setPcCafeRec(1) }
            }
        case .speech:
            switch n {
            case 0: key(rig.speechPlaying ? "stop.fill" : "play.fill", on: rig.speechPlaying) { d.speechToggle() }
            case 1: key("text.bubble", on: rig.speaking) { d.say() }                    // SAY: read the line again
            case 2: key("dice", on: rig.speaking) { d.speechDice() }                    // DICE: a random line, read
            default: key("arrow.triangle.2.circlepath") { d.speechSync() }
            }
        case .multi:
            switch n {
            case 0: key("forward.end") { d.fxNext(0) }
            case 1: key("forward.end") { d.fxNext(1) }
            case 2: key("dice") { d.fxRandom(0) }
            default: key("dice") { d.fxRandom(1) }
            }
        case .knob:
            blank
        }
    }

    private var blank: some View {
        Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1).frame(width: Self.keyW, height: 21)
    }

    /// every key says what it does (the icons alone were guesswork)
    private static let keyNames: [String: String] = [
        "dot.radiowaves.left.and.right": "CAFES", "waveform": "WAVE", "camera.aperture": "CAM", "wind": "DRIFT",
        "snowflake": "FREEZE", "metronome": "PERC", "waveform.path": "PITCH", "arrow.triangle.2.circlepath": "SYNC",
        "record.circle": "REC", "arrow.left.arrow.right": "REV", "backward.end": "START", "pause.circle": "HOLD",
        "link": "LINK", "squareshape.split.3x3": "GRID", "hand.tap": "TAP", "dice": "DICE", "forward.end": "NEXT",
        "play.fill": "PLAY", "stop.fill": "STOP", "speaker": "MONO", "speaker.wave.2": "STEREO",
        "wave.3.forward": "FOLD",
        "tuningfork": "ALIGN", "hand.point.up.left": "MODE",
        "pianokeys": "ARP", "recordingtape": "COCO", "waveform.and.mic": "SPEECH", "text.bubble": "SAY",
        "circle.grid.3x3": "MODE", "infinity": "MODE", "number": "MODE", "repeat": "MODE", "scribble.variable": "MODE",
        "waveform.circle": "MODE",
    ]

    /// a key with a word only (no icon)
    private func textKey(_ label: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.hud(8, .semibold))
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(on ? PastelTheme.selectionText : PastelTheme.hudBlack)
                .padding(.horizontal, 3)
                .frame(width: Self.keyW, height: 21)
                .background(IconSquare(filled: on))
        }
    }
    /// every key the same width, whatever its word: switching presets never moves anything
    static let keyW: CGFloat = 50

    private func key(_ name: String, on: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: name)
                    .font(.system(size: 9, weight: .medium))
                Text(Self.keyNames[name] ?? "")
                    .font(.hud(8, .semibold))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(on ? PastelTheme.selectionText : PastelTheme.hudBlack)
            .padding(.horizontal, 3)
            .frame(width: Self.keyW, height: 21)
            .background(IconSquare(filled: on))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// a key's square: a thin black frame, orange when it is on
struct IconSquare: View {
    var filled: Bool = false

    var body: some View {
        Rectangle()
            .fill(filled ? PastelTheme.hudOrange : PastelTheme.padScreen)
            .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
    }
}

// MARK: - the Cafes panel (connection + camera)

struct CafesView: View {
    let d: Director
    @ObservedObject var hub: CafeHub
    @ObservedObject var camera: CameraRig

    var body: some View {
        PanelScaffold(title: "CAFES") {
            PanelColumns(equalHeight: true) {
                // left, tight: both Cafes, who is nearby, the camera
                PanelCard(title: "CAFES", note: hub.bluetoothReady ? "searching" : "bluetooth off", spacing: 4) {
                    CafeLine(hub: hub, unit: hub.units[0])
                    CafeLine(hub: hub, unit: hub.units[1])
                    Rectangle().fill(PastelTheme.hudLine.opacity(0.6)).frame(height: 0.5)
                    if hub.found.isEmpty {
                        Text("Turn the Cafe on (esp_cafe_duo).")
                            .font(.hud(PanelMetrics.labelFont))
                            .foregroundStyle(PastelTheme.textSecondary)
                    }
                    ForEach(hub.found) { f in
                        HStack(spacing: PanelMetrics.rowGap) {
                            Text(f.name)
                                .font(.hud(PanelMetrics.labelFont, .medium))
                                .foregroundStyle(PastelTheme.textPrimary)
                            Spacer(minLength: 0)
                            ChipButton(title: "→ A", filled: hub.units[0].savedID == f.id) { hub.assign(f, to: 0) }
                                .frame(width: 40)
                            ChipButton(title: "→ B", filled: hub.units[1].savedID == f.id) { hub.assign(f, to: 1) }
                                .frame(width: 40)
                        }
                    }
                }
                CameraCard(camera: camera)
            } right: {
                TempoCard(d: d, rig: d.rig)
                UpdateCard(d: d, rig: d.rig, a: hub.units[0], b: hub.units[1])
            }
        }
        .onAppear { hub.startScan() }
        .onDisappear { hub.stopScan() }
    }
}

/// one Cafe in one line (+ a small second line): A · name · state · clock · preset · disconnect / forget
private struct CafeLine: View {
    @ObservedObject var hub: CafeHub
    @ObservedObject var unit: CafeUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                HudTag(text: unit.slot == 0 ? "A" : "B", fill: unit.isConnected ? PastelTheme.hudBlack : PastelTheme.hudLine, size: 8)
                Text(unit.name ?? "—")
                    .font(.hud(PanelMetrics.labelFont, .semibold))
                    .foregroundStyle(PastelTheme.textPrimary)
                    .lineLimit(1)
                Text(unit.state)
                    .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                    .foregroundStyle(PastelTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ChipButton(title: "DISC", filled: false) { hub.disconnect(unit.slot) }.frame(width: 36)
                ChipButton(title: "FORGET", filled: false) { hub.forget(unit.slot) }.frame(width: 48)
            }
            Text("v\(unit.fw.isEmpty ? "?" : unit.fw)\(unit.flashes > 0 ? " #\(unit.flashes)" : "")  ·  " + "\(unit.hz > 0 ? String(format: "%.1f kHz", unit.hz / 1000) : "—")  ·  \(unit.preset < 0 ? "—" : Preset.tag(unit.preset))"
                 + (unit.preset == Preset.ble && unit.mode == 6
                    ? String(format: "  ·  ↑%.1f ↓%.1f kB/s  made %d sent %d  mtu %d/%d", unit.hbUp, unit.hbDown, unit.hbMade, unit.hbSent, unit.cafeMtu, unit.mtu) : ""))
                .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                .foregroundStyle(PastelTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.leading, 19)
        }
    }
}

/// TEMPO (moved here from the preset manager): the shared BPM — DELAY · HARMONY · MULTI · ARP. SKIP on a Cafe = tap.
private struct TempoCard: View {
    let d: Director
    @ObservedObject var rig: Rig

    var body: some View {
        PanelCard(title: "TEMPO", note: "SKIP on a Cafe = tap") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", rig.bpm))
                    .font(.hudBig(30))
                    .foregroundStyle(PastelTheme.hudBlack)
                Text("BPM")
                    .font(.hud(9, .semibold))
                    .foregroundStyle(PastelTheme.hudOrange)
                Spacer(minLength: 0)
                ChipButton(title: "−", filled: false) { d.setBpm((rig.bpm - 1).rounded()) }.frame(width: 30)
                ChipButton(title: "+", filled: false) { d.setBpm((rig.bpm + 1).rounded()) }.frame(width: 30)
                ChipButton(title: "TAP", filled: false) { d.tapTempo() }.frame(width: 44)
            }
            CompactSlider(value: Binding(get: { (rig.bpm - 40) / 200 },
                                         set: { d.setBpm((40 + $0 * 200).rounded()) }),
                          fillColor: PastelTheme.sliderFill,
                          knobColor: PastelTheme.hudOrange, thinLine: true)
            Text("delay · harmony · multi · arp_delay")
                .font(.hud(8))
                .foregroundStyle(PastelTheme.textSecondary)
        }
    }
}

/// Camera settings. MODE cycles MOTION / BRIGHT / DARK.
private struct CameraCard: View {
    @ObservedObject var camera: CameraRig

    var body: some View {
        PanelCard(title: "CAMERA", toggle: $camera.enabled, fill: true) {
            VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
                HStack(spacing: PanelMetrics.rowGap) {
                    label("MODE")
                    ChipButton(title: CameraRig.attractNames[camera.attractMode], filled: true) {
                        camera.attractMode = (camera.attractMode + 1) % CameraRig.attractNames.count
                    }
                    .frame(width: 60)
                    Spacer(minLength: 0)
                }
                HStack(spacing: PanelMetrics.rowGap) {
                    label("FRONT")
                    Spacer(minLength: 0)
                    CompactToggle(isOn: $camera.usesFront, width: 28, height: 15, onColor: PastelTheme.selection)
                }
                PanelRow(label: "FPS", value: Binding(get: { Double(camera.fps - 1) / 29.0 },
                                                      set: { camera.fps = 1 + Int(($0 * 29.0).rounded()) }))
                PanelRow(label: "SENS", value: $camera.sensitivity)
            }
            .disabled(!camera.enabled)
            .unlit(!camera.enabled)
        }
    }

    private func label(_ t: String) -> some View {
        Text(t)
            .font(.hud(PanelMetrics.labelFont, .medium))
            .foregroundStyle(PastelTheme.textPrimary)
            .frame(width: PanelMetrics.labelWidth, alignment: .leading)
    }
}

/// CHAR: the slider next to the tempo, for this Cafe's preset — one row: NAME ——o—— 042
/// (HARMONY: CLEAN <-> GRAIN · BIT = fewer bits + sample-and-hold · WEAR · VOWEL (Q) · DRIVE)
private struct CharControl: View {
    let d: Director
    @ObservedObject var rig: Rig
    let slot: Int
    let preset: Int

    var body: some View {
        let p = min(max(preset, 0), Preset.count - 1)          // (Apple π presets have no CHAR: hidden below)
        let v = rig.charV[slot][p]
        let isHarmony = p == Preset.harmony
        HStack(spacing: 5) {
            Text(isHarmony ? (v < 0.5 ? "CLEAN" : "GRAIN") : Preset.charNames[p])
                .font(.hud(7, .semibold))
                .tracking(0.8)
                .foregroundStyle(PastelTheme.hudOrange)
                .lineLimit(1)
                .frame(width: 34, alignment: .leading)
            CompactSlider(value: Binding(get: { rig.charV[slot][p] },
                                         set: { d.setChar($0, slot: slot) }),
                          touchHeight: 20,
                          fillColor: PastelTheme.sliderFill,
                          knobColor: PastelTheme.hudOrange, thinLine: true)
                .frame(width: 64, height: 12)
            Text(String(format: "%03ld", Int((v * 100).rounded())))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(PastelTheme.hudBlack)
                .frame(width: 18, alignment: .trailing)
        }
        .padding(.horizontal, 5)
        .frame(height: 18)
        .overlay(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
        .fixedSize()
        .opacity(preset >= 0 && preset < Preset.count && !isHarmony ? 1 : 0)     // (HARMONY: no CHAR any more — always clean)
        .allowsHitTesting(preset >= 0 && preset < Preset.count && !isHarmony)
    }
}


/// the guide on the status line: the words step along one character at a time, like an old LCD ticker
private struct GuideTicker: View {
    let text: String
    static let step = 0.14
    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: GuideTicker.step)) { tl in
            let chars = Array("   " + text.uppercased() + "   ·")
            let n = max(chars.count, 1)
            let k = Int(tl.date.timeIntervalSinceReferenceDate / GuideTicker.step) % n
            Text(String((chars[k...] + chars[..<k]).prefix(16)))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(PastelTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(minWidth: 0, maxWidth: 76, alignment: .leading)     // (gives way first when the bar is tight)
        .clipped()
    }
}
