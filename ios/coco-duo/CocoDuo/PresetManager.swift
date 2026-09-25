// PresetManager.swift — coco duo (k.odk)
// The PRESET MANAGER sheet (tap a bar's status in the main screen):
//   TARGET   A / B / A + B — who the presets (and the pads) go to
//   PRESETS  1–10 (1–7 exist in esp_cafe_duo v3, 8–10 are empty slots). A / B marks show where each Cafe is.
//   BLE MODE GRAIN / RUNGLER / DELAY / NOISE (preset 3)
//   TEMPO    the shared BPM (DELAY / HARMONY), TAP
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
                PanelCard(title: "PRESETS", note: "1–7 · 8–10 empty", spacing: 3) {
                    ForEach(0..<10, id: \.self) { n in
                        PresetRow(n: n, rig: rig, a: a, b: b) { d.setPreset(n) }
                    }
                }
            } right: {
                PanelCard(title: "BLE MODE", note: rig.ctxPreset == Preset.ble ? "preset 3" : "choose preset 3 first") {
                    HStack(spacing: PanelMetrics.chipSpacing) {
                        ForEach(0..<4, id: \.self) { m in
                            ChipButton(title: Preset.modeNames[m], filled: rig.ctxPreset == Preset.ble && rig.ctxMode == m) {
                                d.setMode(m)
                            }
                        }
                    }
                    .disabled(rig.ctxPreset != Preset.ble)
                    .unlit(rig.ctxPreset != Preset.ble)
                }
                PanelCard(title: "TEMPO", note: "delay · harmony · SKIP on a Cafe = tap") {
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

/// one preset slot: number, name, what it is, and which Cafe sits on it
private struct PresetRow: View {
    let n: Int
    @ObservedObject var rig: Rig
    @ObservedObject var a: CafeUnit
    @ObservedObject var b: CafeUnit
    let action: () -> Void

    private var exists: Bool { n < Preset.count }
    private func on(_ u: CafeUnit) -> Bool { (u.isConnected && u.preset >= 0 ? u.preset : rig.preset[u.slot]) == n }

    var body: some View {
        let chosen = exists && rig.slots.allSatisfy { rig.preset[$0] == n }
        HStack(spacing: 6) {
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
