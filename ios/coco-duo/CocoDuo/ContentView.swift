// ContentView.swift — coco duo (k.odk)
// HUD layout: top bar = Cafe A, eight XY pads, bottom bar = Cafe B.
// What the pads are depends on the preset the TARGET Cafe is on (see Modes.swift):
//   BLE preset  GRAIN / COCO / NOISE: the 8 pads go to every Cafe on that mode
//               DELAY: top row = Cafe A's delay, bottom row = Cafe B's (LINK = both rows move together)
//   HARMONY     like DELAY (top row A, bottom row B)
//   MULTI       top row = the 4 pads of A's effect, bottom row = B's (LINK = same effect, both rows together)
//   knob presets (COCO_MOD, ECHO, RESONATOR, FORMANT, SATURATOR, RUNGLER, SELF_READ): a placard, the Cafe is played with its own controls
// Keys:  top    [CAFES] [ctx 1] … status (tap = PRESET MANAGER) … [ctx 3] [WAVE]
//        bottom [MODE ] [ctx 2] … status (tap = PRESET MANAGER) … [ctx 4] [CAMERA]
//   GRAIN   freeze · percussion · MOVE (pitch) · sync          COCO     rec · reverse · to the loop start · sync
//   DELAY   hold · link · grid · tap                   HARMONY  hold · link · grid · tap
//   NOISE   dice · sync                                 MULTI    next effect · random effect (per Cafe)

import SwiftUI
import UIKit

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
    let camera = CameraRig()
    var units: [CafeUnit] { hub.units }
    private var started = false

    /// connected Cafes that are on what the screen shows
    func ctxUnits() -> [CafeUnit] { units.filter { $0.isConnected && rig.inCtx($0.slot) } }

    func start() {
        guard !started else { return }
        started = true
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
    }

    /// the 8 pads of the current set (the camera moves these)
    func axes() -> [PadAxis] {
        switch rig.padSet {
        case .grain: return grain.axes
        case .coco: return rig.coAxes
        case .delay: return rig.dlAxes
        case .noise: return rig.nzAxes
        case .harmony: return rig.hdAxes
        case .multi: return (0..<2).flatMap { rig.fxAxes[$0][rig.fxLocal[$0]] }
        case .knob: return []
        }
    }

    func refresh() { camera.axes = axes() }

    // MARK: presets

    /// put a Cafe on its preset (and mode), then give it every pad
    func sendAll(to u: CafeUnit) {
        let s = u.slot
        u.send("G \(rig.preset[s])")
        u.send("K \(Int((rig.bpm * 10).rounded()))")
        switch rig.preset[s] {
        case Preset.ble:
            u.send("M 25 \(rig.mode[s])")
            switch rig.mode[s] {
            case 0: grain.allCommands(slot: s).forEach(u.send)
            case 1: rig.coAll(slot: s).forEach(u.send)
            case 2: rig.dlAll(slot: s).forEach(u.send)
            default: rig.nzAll(slot: s).forEach(u.send)
            }
        case Preset.harmony:
            rig.hdAll(slot: s).forEach(u.send)
        case Preset.multi:
            rig.fxAll(slot: s).forEach(u.send)
        default:
            break
        }
    }

    func setPreset(_ n: Int) {
        guard n >= 0 && n < Preset.count else { return }
        var p = rig.preset
        for s in rig.slots { p[s] = n }
        rig.preset = p
        for s in rig.slots where units[s].isConnected { sendAll(to: units[s]) }
        refresh()
        syncIfPair()
    }

    func setMode(_ m: Int) {
        var md = rig.mode
        for s in rig.slots where rig.preset[s] == Preset.ble { md[s] = m }
        rig.mode = md
        for s in rig.slots where rig.preset[s] == Preset.ble && units[s].isConnected { sendAll(to: units[s]) }
        refresh()
        syncIfPair()
    }

    func cycleMode() { if rig.ctxPreset == Preset.ble { setMode((rig.ctxMode + 1) % 4) } }

    func setTarget(_ t: Int) { rig.target = t; refresh() }

    /// both Cafes on the same thing: start them together (grain score / coco loop / the click)
    func syncIfPair() {
        let u = ctxUnits()
        if u.count == 2 && rig.padSet != .knob && rig.padSet != .noise { u.forEach { $0.send("Z") } }
    }
    func sync() { ctxUnits().forEach { $0.send("Z") } }

    // MARK: pads

    func padMoved(_ i: Int) {
        switch rig.padSet {
        case .grain:
            let resync = i == GrainPad.stereo.rawValue && grain.separationReturned()
            for u in ctxUnits() { grain.commands(pad: i, slot: u.slot).forEach(u.send) }
            if resync { sync() }
        case .coco:
            for u in ctxUnits() { rig.coCommands(pad: i, slot: u.slot).forEach(u.send) }
        case .noise:
            for u in ctxUnits() { rig.nzCommands(pad: i, slot: u.slot).forEach(u.send) }
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
            if rig.fxLink && rig.fxLocal[1 - row] == e {             // LINK: the other Cafe's pad follows
                let b = rig.fxAxes[1 - row][e][k]
                b.x = a.x; b.y = a.y
                rows = [0, 1]
            }
            for r in rows where rig.inCtx(r) && units[r].isConnected {
                rig.fxCommands(slot: r, e: e, k: k).forEach(units[r].send)
            }
        case .knob:
            break
        }
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

    func setFxLink(_ on: Bool) {
        rig.fxLink = on
        guard on else { return }
        // B takes A's effect and all of A's pads
        for e in 0..<Fx.count { for k in 0..<4 { let a = rig.fxAxes[0][e][k], b = rig.fxAxes[1][e][k]; b.x = a.x; b.y = a.y } }
        var loc = rig.fxLocal; loc[1] = loc[0]; rig.fxLocal = loc
        let b = units[1]
        if b.isConnected && rig.preset[1] == Preset.multi { rig.fxAll(slot: 1).forEach(b.send) }
        multiUnits().forEach { $0.send("Z") }                         // the same random order from now on
        refresh()
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
        if rig.padSet == .harmony { ctxUnits().forEach { $0.send("V 11 \(v)") } }
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

    func tapTempo() { if let b = rig.tap() { setBpm(b) } }

    func setBpm(_ b: Double) {
        rig.bpm = min(max(b, 30), 300)
        let v = Int((rig.bpm * 10).rounded())
        units.filter { $0.isConnected }.forEach { $0.send("K \(v)") }
    }

    /// SKIP was tapped on a Cafe: that is everyone's tempo now
    func tempoFromCafe(_ b: Double, slot: Int) {
        guard abs(b - rig.bpm) > 0.3 else { return }
        rig.bpm = b
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
            HudBar(d: d, unit: hub.units[0], rig: rig, grain: grain, camera: camera,
                   showCafes: $showCafes, showWave: $showWave, showPresets: $showPresets)
                .frame(height: barHeight)
            pads
            HudBar(d: d, unit: hub.units[1], rig: rig, grain: grain, camera: camera,
                   showCafes: $showCafes, showWave: $showWave, showPresets: $showPresets)
                .frame(height: barHeight)
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
        .sheet(isPresented: $showCafes) { CafesView(hub: hub, camera: camera) }
        .sheet(isPresented: $showWave) { WaveView(hub: hub) }
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
            KnobPlacard(rig: rig, a: hub.units[0], b: hub.units[1])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) { ForEach(0..<4, id: \.self) { pad($0) } }
                HStack(spacing: 6) { ForEach(4..<8, id: \.self) { pad($0) } }
            }
            .frame(maxHeight: .infinity)
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
        case .delay: return (rig.dlAxes[i], DlPad(rawValue: i % 4)!.title)
        case .noise: return (rig.nzAxes[i], NzPad(rawValue: i)!.title)
        case .harmony: return (rig.hdAxes[i], HdPad(rawValue: i % 4)!.title)
        case .multi: let e = rig.fxLocal[i / 4]; return (rig.fxAxes[i / 4][e][i % 4], Fx.titles[e][i % 4])
        case .knob: return (rig.nzAxes[i], "")
        }
    }

    @ViewBuilder private func pad(_ i: Int) -> some View {
        let item = info(i)
        let live = (rig.perRow ? rig.inCtx(i / 4) : true) && item.1 != "—"
        let tag = rig.perRow ? (i < 4 ? "A" : "B") + String(format: ".%02ld", i % 4 + 1) : String(format: "%02ld", i + 1)
        let director = d
        HudPad(axis: item.0, title: item.1, tag: tag,
               send: { director.padMoved(i) },
               cam: camera.state, cameraMode: camera.enabled, index: i, padHeight: padHeight)
            .frame(height: padHeight)
            .opacity(live ? 1 : 0.35)
            .allowsHitTesting(live)
            .id("\(rig.padSet)\(i)-\(rig.padSet == .multi ? rig.fxLocal[i / 4] : 0)")
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
    }
}

/// knob presets: nothing to play here, the Cafe is played with its own controls
private struct KnobPlacard: View {
    @ObservedObject var rig: Rig
    @ObservedObject var a: CafeUnit
    @ObservedObject var b: CafeUnit

    var body: some View {
        let n = rig.ctxPreset
        ZStack {
            Rectangle().fill(PastelTheme.padScreen)
            HudDots(step: 12)
            Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
            HudCorners(arm: 12).stroke(PastelTheme.hudBlack, lineWidth: 1.4).padding(4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    HudTag(text: "KNOB_CONTROL", size: 9)
                    HudTag(text: rig.target == 2 ? "A+B" : (rig.target == 0 ? "A" : "B"), fill: PastelTheme.hudOrange, size: 9)
                }
                Text(Preset.tag(n))
                    .font(.hudBig(46))
                    .foregroundStyle(PastelTheme.hudBlack)
                Rectangle().fill(PastelTheme.hudOrange).frame(width: 120, height: 3)
                Text(n >= 0 && n < Preset.notes.count ? Preset.notes[n].uppercased() : "")
                    .font(.hud(11, .medium))
                    .tracking(0.8)
                    .foregroundStyle(PastelTheme.textSecondary)
                HStack(spacing: 14) {
                    side("A", a)
                    side("B", b)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func side(_ name: String, _ u: CafeUnit) -> some View {
        HStack(spacing: 5) {
            HudTag(text: name, fill: u.isConnected ? PastelTheme.hudBlack : PastelTheme.hudLine, size: 8)
            Text(u.isConnected ? Preset.tag(u.preset) : "NO_LINK")
                .font(.hud(9, .semibold))
                .foregroundStyle(PastelTheme.hudBlack)
        }
    }
}

// MARK: - top / bottom bar (one Cafe each)

private struct HudBar: View {
    let d: Director
    @ObservedObject var unit: CafeUnit
    @ObservedObject var rig: Rig
    @ObservedObject var grain: GrainMode
    @ObservedObject var camera: CameraRig
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
                    key(Preset.modeIcons[min(max(rig.ctxMode, 0), 3)], on: false,
                        enabled: rig.ctxPreset == Preset.ble) { d.cycleMode() }
                }
                contextKey(top ? 0 : 1)
            }
            Button { showPresets = true } label: { status }
                .buttonStyle(.plain)
            HStack(spacing: 8) {
                contextKey(top ? 2 : 3)
                if top { key("waveform") { showWave = true } }
                else { key("camera.aperture", on: camera.enabled) { camera.enabled.toggle() } }
            }
        }
    }

    /// A · name · preset · mode · tempo · clock ··· (tap = the preset manager)
    private var status: some View {
        let p = unit.isConnected && unit.preset >= 0 ? unit.preset : rig.preset[unit.slot]
        let m = unit.isConnected ? unit.mode : rig.mode[unit.slot]
        let inView = rig.inCtx(unit.slot)
        return HStack(spacing: 6) {
            HudTag(text: top ? "A" : "B", fill: unit.isConnected ? PastelTheme.hudBlack : PastelTheme.hudLine, size: 9)
            Text((unit.name ?? "NO_LINK").uppercased().replacingOccurrences(of: "-", with: "_"))
                .font(.hud(9, .semibold))
                .foregroundStyle(PastelTheme.hudBlack)
                .lineLimit(1)
            HudTag(text: Preset.tag(p), fill: inView ? PastelTheme.hudBlack : PastelTheme.textSecondary, size: 8)
            if p == Preset.ble {
                Text(Preset.modeNames[min(max(m, 0), 3)])
                    .font(.hud(10, .semibold))
                    .tracking(1)
                    .foregroundStyle(PastelTheme.hudOrange)
            }
            if p == Preset.multi {
                Text(Fx.names[min(max(unit.isConnected && unit.fx >= 0 ? unit.fx : rig.fxLocal[unit.slot], 0), Fx.count - 1)])
                    .font(.hud(10, .semibold))
                    .tracking(1)
                    .foregroundStyle(PastelTheme.hudOrange)
                if rig.fxLink { HudTag(text: "LINK", fill: PastelTheme.hudOrange, size: 7) }
            }
            if (p == Preset.ble && m == 2) || p == Preset.harmony {
                Text(String(format: "%.1f", unit.bpm > 0 ? unit.bpm : rig.bpm))
                    .font(.hudBig(14))
                    .foregroundStyle(PastelTheme.hudBlack)
                Text("BPM").font(.hud(7, .medium)).foregroundStyle(PastelTheme.textSecondary)
                if rig.link && rig.padSet == .delay { HudTag(text: "LINK", fill: PastelTheme.hudOrange, size: 7) }
            }
            Rectangle().fill(PastelTheme.hudLine).frame(height: 1)
            if let o = unit.ota {
                HudTag(text: String(format: "UPD_%02ld%%", Int(o * 100)), fill: PastelTheme.hudOrange, size: 8)
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
            case 2: key("waveform.path", on: grain.move) { grain.setMove(!grain.move, d.ctxUnits()) }
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
            case 2: key("squareshape.split.3x3", on: rig.grid) { d.toggleGrid() }
            default: key("hand.tap") { d.tapTempo() }
            }
        case .noise:
            switch n {
            case 0: key("dice") { d.noiseDice() }
            case 1: key("arrow.triangle.2.circlepath") { d.sync() }
            default: blank
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
        Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1).frame(width: 21, height: 21)
    }

    private func key(_ name: String, on: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? PastelTheme.selectionText : PastelTheme.hudBlack)
                .frame(width: 21, height: 21)
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
    @ObservedObject var hub: CafeHub
    @ObservedObject var camera: CameraRig

    var body: some View {
        PanelScaffold(title: "CAFES") {
            PanelColumns {
                CafeCard(hub: hub, unit: hub.units[0])
                CafeCard(hub: hub, unit: hub.units[1])
            } right: {
                PanelCard(title: "NEARBY", note: hub.bluetoothReady ? "searching" : "bluetooth off") {
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
                                .frame(width: 44)
                            ChipButton(title: "→ B", filled: hub.units[1].savedID == f.id) { hub.assign(f, to: 1) }
                                .frame(width: 44)
                        }
                    }
                }
                CameraCard(camera: camera)
            }
        }
        .onAppear { hub.startScan() }
        .onDisappear { hub.stopScan() }
    }
}

private struct CafeCard: View {
    @ObservedObject var hub: CafeHub
    @ObservedObject var unit: CafeUnit

    var body: some View {
        PanelCard(title: unit.slot == 0 ? "CAFE A · TOP" : "CAFE B · BOTTOM") {
            DiagRow("NAME", unit.name ?? "—")
            DiagRow("STATE", unit.state)
            DiagRow("CLOCK", unit.hz > 0 ? String(format: "%.1f kHz", unit.hz / 1000) : "—")
            DiagRow("PRESET", unit.preset < 0 ? "—" : Preset.tag(unit.preset))
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: "DISCONNECT", filled: false) { hub.disconnect(unit.slot) }
                ChipButton(title: "FORGET", filled: false) { hub.forget(unit.slot) }
            }
        }
    }
}

/// Camera settings. MODE cycles MOTION / BRIGHT / DARK.
private struct CameraCard: View {
    @ObservedObject var camera: CameraRig

    var body: some View {
        PanelCard(title: "CAMERA", toggle: $camera.enabled) {
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
