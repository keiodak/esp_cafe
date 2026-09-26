// PresetManager.swift — coco duo (k.odk)
// The PRESET MANAGER sheet (tap a bar's status in the main screen):
//   TARGET   A / B / A + B — who the presets (and the pads) go to
//   PRESETS  grouped: PLAYED HERE (BLE with its 4 modes under it, MULTI) · iOS + CAFE (ARP_DELAY) · ON THE CAFE.
//            A / B marks show where each Cafe is. (TEMPO moved to the CAFES panel.)
//   UPDATE   write a new firmware over Bluetooth to A / B / both (the .ino.bin from "Export Compiled Binary")

import SwiftUI
import UniformTypeIdentifiers

struct PresetManagerView: View {
    let d: Director
    @ObservedObject var rig: Rig
    @ObservedObject var a: CafeUnit
    @ObservedObject var b: CafeUnit
    @State private var picking = false
    @State private var fileNote = ""

    private let who = ["A", "B", "A + B"]

    private func section(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(c).frame(width: 3, height: 9)
            Text(t)
                .font(.hud(7, .semibold))
                .tracking(1.2)
                .foregroundStyle(c)
        }
        .padding(.top, 4)
    }

    var body: some View {
        PanelScaffold(title: "PRESET MANAGER") {
            PanelColumns {
                PanelCard(title: "TARGET", note: "presets and pads go to") {
                    HStack(spacing: PanelMetrics.chipSpacing) {
                        ForEach(0..<3, id: \.self) { t in
                            ChipButton(title: who[t], filled: rig.target == t) { d.setTarget(t) }
                        }
                    }
                }
                PanelCard(title: "PRESETS", note: "tap one", spacing: 3) {
                    // played from here: BLE (its four modes right under it), MULTI, then iOS + CAFE
                    section("PLAYED HERE", PastelTheme.cafeBlue)
                    PresetRow(n: Preset.ble, rig: rig, a: a, b: b) { d.setPreset(Preset.ble) }
                    HStack(spacing: PanelMetrics.chipSpacing) {
                        Text("└").font(.hud(9)).foregroundStyle(PastelTheme.textSecondary).frame(width: 14)
                        ForEach(0..<4, id: \.self) { m in
                            ChipButton(title: Preset.modeNames[m], filled: rig.ctxPreset == Preset.ble && rig.ctxMode == m) {
                                if rig.ctxPreset != Preset.ble { d.setPreset(Preset.ble) }
                                d.setMode(m)
                            }
                            .overlay(alignment: .bottom) { Rectangle().fill(PastelTheme.mode(m)).frame(height: 2) }
                        }
                    }
                    .padding(.vertical, 2)
                    PresetRow(n: Preset.multi, rig: rig, a: a, b: b) { d.setPreset(Preset.multi) }
                    section("iOS + CAFE", PastelTheme.cafePurple)
                    PresetRow(n: Preset.arp, rig: rig, a: a, b: b, indent: true) { d.setPreset(Preset.arp) }
                    section("ON THE CAFE", PastelTheme.cafeGreen)
                    ForEach(Preset.cafeOrder, id: \.self) { n in
                        PresetRow(n: n, rig: rig, a: a, b: b) { d.setPreset(n) }
                    }
                }
            } right: {
                if rig.padSet == .grain {
                    PanelCard(title: "GRAIN", note: "BLE · GRAIN") { GrainOptions(d: d, grain: d.grain) }
                }
                if rig.preset.contains(Preset.multi) {
                    MultiCard(d: d, rig: rig)
                }
                if rig.preset.contains(Preset.arp) {
                    ArpCard(d: d, rig: rig)
                }
                PanelCard(title: "UPDATE", note: "firmware over bluetooth") {
                    HStack(spacing: PanelMetrics.chipSpacing) {
                        ForEach(0..<3, id: \.self) { t in
                            ChipButton(title: who[t], filled: rig.updTarget == t) { rig.updTarget = t }
                        }
                    }
                    ChipButton(title: "CHOOSE .BIN AND WRITE", filled: a.ota != nil || b.ota != nil) {
                        if a.ota == nil && b.ota == nil { picking = true }
                    }
                    UpdateRow(unit: a)
                    UpdateRow(unit: b)
                    if !fileNote.isEmpty {
                        Text(fileNote)
                            .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                            .foregroundStyle(PastelTheme.textSecondary)
                    }
                    Text("Arduino IDE: Sketch > Export Compiled Binary, then pick esp_cafe_duo.ino.bin (not .merged / .bootloader). The sound stops while it writes; the Cafe restarts with the new firmware. Two Cafes can be written at once.")
                        .font(.hud(8))
                        .foregroundStyle(PastelTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { fileNote = "could not read the file"; return }
            fileNote = "\(url.lastPathComponent) · \(data.count / 1024) KB"
            d.update([UInt8](data))
        }
    }
}

/// GRAIN's switches: MOVE (Ikue Mori-like pitch), and the marks (places to take grains from)
private struct GrainOptions: View {
    let d: Director
    @ObservedObject var grain: GrainMode

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: PanelMetrics.chipSpacing) {
            ChipButton(title: "MOVE PITCH", filled: grain.move) { grain.setMove(!grain.move, d.ctxUnits()) }
            ChipButton(title: "FREEZE", filled: grain.freeze) { grain.setFreeze(!grain.freeze, d.ctxUnits()) }
            ChipButton(title: "PERC", filled: grain.perc) { grain.setPerc(!grain.perc, d.ctxUnits()) }
        }
        HStack(spacing: PanelMetrics.chipSpacing) {
            ChipButton(title: "MARK", filled: false) { grain.mark(d.ctxUnits()) }
            ChipButton(title: "ONLY MARKS", filled: grain.useMarks) { grain.setUseMarks(!grain.useMarks, d.ctxUnits()) }
            ChipButton(title: "CLEAR \(grain.marks)", filled: false) { grain.clearMarks(d.ctxUnits()) }
        }
        Text("MOVE PITCH: every grain its own pitch from all intervals, gliding up or down (Ikue Mori-like). Off: pitch held for phrases (PITCH / REV·HOLD pads).")
            .font(.hud(8))
            .foregroundStyle(PastelTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// MULTI: which effect each Cafe is on, LINK, and the switches
private struct MultiCard: View {
    let d: Director
    @ObservedObject var rig: Rig

    var body: some View {
        PanelCard(title: "MULTI", note: "FLIP = next · SKIP = random") {
            ForEach(0..<2, id: \.self) { s in
                HStack(spacing: PanelMetrics.chipSpacing) {
                    HudTag(text: s == 0 ? "A" : "B", size: 8)
                    ForEach(0..<Fx.count, id: \.self) { e in
                        ChipButton(title: Fx.short[e], filled: rig.fxLocal[s] == e) { d.setFx(s, e) }
                    }
                }
                .disabled(rig.preset[s] != Preset.multi)
                .unlit(rig.preset[s] != Preset.multi)
            }
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: "LINK FX", filled: rig.fxLink) { d.setFxLink(!rig.fxLink) }
                ChipButton(title: "LINK PADS", filled: rig.fxPadLink) { d.setFxPadLink(!rig.fxPadLink) }
                ChipButton(title: "HOLD", filled: rig.fxHold) { d.fxToggleHold() }
                ChipButton(title: "DRIFT", filled: rig.fxDrift) { d.setFxDrift(!rig.fxDrift) }
                ChipButton(title: "TAKE SAMPLE", filled: false) { d.fxSetting("F 92") }
                ChipButton(title: "TRIGGER", filled: false) { d.fxSetting("F 93") }
                ChipButton(title: "SYNC", filled: false) { d.fxSetting("Z") }
            }
            PanelRow(label: "XFADE", value: Binding(get: { rig.fxXfade },
                                                    set: { rig.fxXfade = $0; d.fxSetting("F 91 \(Int($0 * 1000))") }))
            PanelRow(label: "EARTH", value: Binding(get: { rig.fxEarth },
                                                    set: { rig.fxEarth = $0; d.fxSetting("F 95 \(Int($0 * 1000))") }))
            PanelRow(label: "LOCK", value: Binding(get: { rig.fxLock },
                                                   set: { rig.fxLock = $0; d.fxSetting("F 96 \(Int($0 * 1000))") }))
            Text("XFADE 0.02–2 s between effects · EARTH = how much it modulates each effect (level, delay time, sampler pitch + trigger, reverse speed, glitch chance, fold drive, reverb size) · LOCK = the shortest time between two changes (0.05–5 s), so fast gates on FLIP / SKIP don't make it flutter. LINK FX: both Cafes on the same effect (and the same random jumps). LINK PADS: the XY pads move both Cafes. Each can be on or off.")
                .font(.hud(8))
                .foregroundStyle(PastelTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// ARP_DELAY: the arpeggiator's sound, and play / hold / sync
private struct ArpCard: View {
    let d: Director
    @ObservedObject var rig: Rig

    var body: some View {
        PanelCard(title: "ARP", note: "phone audio -> Cafe input") {
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: rig.arpPlaying ? "STOP" : "PLAY", filled: rig.arpPlaying) { d.arpToggle() }
                ChipButton(title: "SYNC", filled: false) { d.arpSync() }
                ChipButton(title: "TAP", filled: false) { d.tapTempo() }
                ChipButton(title: "HOLD", filled: rig.fxHold) { d.fxToggleHold() }
            }
            PanelRow(label: "GLIDE", value: Binding(get: { rig.arpGlide }, set: { rig.arpGlide = $0; d.applyArp() }))
            PanelRow(label: "FIFTH", value: Binding(get: { rig.arpFifth }, set: { rig.arpFifth = $0; d.applyArp() }))
            PanelRow(label: "LEVEL", value: Binding(get: { rig.arpLevel }, set: { rig.arpLevel = $0; d.applyArp() }))
            Text("Plug the iPhone's audio out into the Cafe's input. Top pads = the arpeggio (7 patterns, 7 chords), bottom pads = the Cafe's stereo tap delay (main = L, ASH = R). Tempo both ways: BPM here -> Cafes; SKIP on a Cafe = tap -> the arpeggio follows and restarts on the beat.")
                .font(.hud(8))
                .foregroundStyle(PastelTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// one preset slot: number, name, what it is, and which Cafe sits on it
private struct PresetRow: View {
    let n: Int
    @ObservedObject var rig: Rig
    @ObservedObject var a: CafeUnit
    @ObservedObject var b: CafeUnit
    var indent = false
    let action: () -> Void

    private var exists: Bool { n < Preset.count }
    private func on(_ u: CafeUnit) -> Bool { (u.isConnected && u.preset >= 0 ? u.preset : rig.preset[u.slot]) == n }

    var body: some View {
        let chosen = exists && rig.slots.allSatisfy { rig.preset[$0] == n }
        HStack(spacing: 6) {
            if indent { Text("└").font(.hud(9)).foregroundStyle(PastelTheme.textSecondary).frame(width: 14) }
            HudTag(text: String(format: "%02ld", n + 1),
                   fill: chosen ? PastelTheme.hudOrange : (exists ? PastelTheme.hudBlack : PastelTheme.hudLine), size: 9)
            Text(Preset.names[n])
                .font(.hudBig(13))
                .foregroundStyle(exists ? PastelTheme.hudBlack : PastelTheme.textSecondary)
                .frame(width: 78, alignment: .leading)
            Text(Preset.notes[n])
                .font(.hud(7.5))
                .foregroundStyle(PastelTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            mark("A", on(a), a.isConnected)
            mark("B", on(b), b.isConnected)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 3)
        .background(Rectangle().fill(chosen ? PastelTheme.hudOrange.opacity(0.12) : Color.clear))
        .overlay(alignment: .bottom) { Rectangle().fill(PastelTheme.hudLine.opacity(0.6)).frame(height: 0.5) }
        .contentShape(Rectangle())
        .onTapGesture { if exists { action() } }
        .opacity(exists ? 1 : 0.45)
    }

    private func mark(_ s: String, _ here: Bool, _ live: Bool) -> some View {
        Text(s)
            .font(.hud(8, .semibold))
            .foregroundStyle(here ? Color.white : PastelTheme.hudLine)
            .frame(width: 14, height: 13)
            .background(Rectangle().fill(here ? (live ? PastelTheme.hudOrange : PastelTheme.textSecondary) : Color.clear))
            .overlay(Rectangle().strokeBorder(here ? Color.clear : PastelTheme.hudLine, lineWidth: 1))
    }
}

/// one Cafe's firmware update: progress bar and what happened
private struct UpdateRow: View {
    @ObservedObject var unit: CafeUnit

    var body: some View {
        HStack(spacing: PanelMetrics.rowGap) {
            HudTag(text: unit.slot == 0 ? "A" : "B", fill: unit.isConnected ? PastelTheme.hudBlack : PastelTheme.hudLine, size: 8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
                    Rectangle().fill(PastelTheme.hudOrange)
                        .frame(width: max(0, (geo.size.width - 2) * CGFloat(unit.ota ?? 0)))
                        .padding(1)
                }
            }
            .frame(height: 8)
            Text(unit.otaNote.isEmpty ? (unit.isConnected ? "ready" : "not connected") : unit.otaNote)
                .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                .foregroundStyle(PastelTheme.textSecondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
        }
    }
}
