// PresetManager.swift — coco duo (k.odk)
// The PRESET MANAGER sheet (tap a bar's status in the main screen):
//   PRESETS  the playlist, numbered in its order. A · B on each row: where each Cafe is, and a tap puts it there
//            (that is also who the pads go to); the row itself = both. 12 = PRESET DESIGN (edit the playlist).
//   BLE MODE GRAIN / COCO / DELAY / NOISE · MULTI · ARP cards when those presets are on
//   (TEMPO and UPDATE live in the CAFES panel.)

import SwiftUI
import UniformTypeIdentifiers

struct PresetManagerView: View {
    let d: Director
    @ObservedObject var rig: Rig
    @ObservedObject var a: CafeUnit
    @ObservedObject var b: CafeUnit
    @State private var design = false

    var body: some View {
        PanelScaffold(title: "PRESET MANAGER") {
            PanelColumns {
                PanelCard(title: "PRESETS", note: "A · B = which Cafe", spacing: 3) {
                    ForEach(rig.playlist, id: \.self) { n in
                        PresetRow(n: n, rig: rig, a: a, b: b) { t in d.setTarget(t); d.setPreset(n) }
                    }
                    // 12: PRESET DESIGN — which presets are in the list (and the Cafe's BUTTON menu)
                    HStack(spacing: 6) {
                        HudTag(text: "12", fill: design ? PastelTheme.hudOrange : PastelTheme.hudBlack, size: 9)
                        Text("PRESET_DESIGN")
                            .font(.hudBig(13))
                            .foregroundStyle(PastelTheme.hudBlack)
                        Text("add / remove presets (up to 11) · Apple π's are here too")
                            .font(.hud(7.5))
                            .foregroundStyle(PastelTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: design ? "chevron.right.circle.fill" : "chevron.right.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(design ? PastelTheme.hudOrange : PastelTheme.hudBlack)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 3)
                    .background(Rectangle().fill(design ? PastelTheme.hudOrange.opacity(0.12) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture { design.toggle() }
                }
            } right: {
                if design {
                    DesignCard(d: d, rig: rig)
                } else {
                PanelCard(title: "BLE MODE", note: rig.ctxPreset == Preset.ble ? Preset.tag(Preset.ble) : "choose BLE first") {
                    HStack(spacing: PanelMetrics.chipSpacing) {
                        ForEach(0..<4, id: \.self) { m in
                            ChipButton(title: Preset.modeNames[m], filled: rig.ctxPreset == Preset.ble && rig.ctxMode == m) {
                                d.setMode(m)
                            }
                        }
                    }
                    .disabled(rig.ctxPreset != Preset.ble)
                    .unlit(rig.ctxPreset != Preset.ble)
                    if rig.padSet == .grain {
                        GrainOptions(d: d, grain: d.grain)
                    }
                }
                if rig.preset.contains(Preset.multi) {
                    MultiCard(d: d, rig: rig)
                }
                if rig.preset.contains(Preset.arp) {
                    ArpCard(d: d, rig: rig)
                }
                }
            }
        }
    }
}

/// PRESET DESIGN: the playlist (up to 11, in order: ▲ ▼ move, − takes out) and everything else the firmware has (+ puts in).
/// Every change goes to the Cafes at once ("L …"); their BUTTON menu follows, and they keep it.
private struct DesignCard: View {
    let d: Director
    @ObservedObject var rig: Rig

    var body: some View {
        let list = rig.playlist
        PanelCard(title: "PRESET DESIGN", note: "\(list.count) / \(Preset.maxPlaylist)", spacing: 3) {
            ForEach(Array(list.enumerated()), id: \.element) { i, n in
                HStack(spacing: 5) {
                    HudTag(text: String(format: "%02ld", i + 1), size: 8)
                    Text(Preset.names[n]).font(.hud(9, .semibold)).foregroundStyle(PastelTheme.hudBlack)
                    Spacer(minLength: 0)
                    small("▲", i > 0) { var l = list; l.swapAt(i, i - 1); d.setPlaylist(l) }
                    small("▼", i < list.count - 1) { var l = list; l.swapAt(i, i + 1); d.setPlaylist(l) }
                    small("−", list.count > 1) { var l = list; l.remove(at: i); d.setPlaylist(l) }
                }
            }
            Text("NOT IN THE LIST")
                .font(.hud(7, .semibold)).tracking(1.2)
                .foregroundStyle(PastelTheme.hudOrange)
                .padding(.top, 6)
            ForEach((0..<Preset.poolCount).filter { !list.contains($0) }, id: \.self) { n in
                HStack(spacing: 5) {
                    Text(Preset.names[n]).font(.hud(9, .semibold)).foregroundStyle(PastelTheme.hudBlack)
                        .frame(width: 84, alignment: .leading)
                    Text(Preset.notes[n]).font(.hud(7)).foregroundStyle(PastelTheme.textSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    small("+", list.count < Preset.maxPlaylist) { d.setPlaylist(list + [n]) }
                }
            }
            ChipButton(title: "BACK TO THE DEFAULT 11", filled: false) { d.setPlaylist(Preset.defaultPlaylist) }
                .padding(.top, 6)
        }
    }

    private func small(_ t: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
        Text(t)
            .font(.hud(10, .semibold))
            .foregroundStyle(on ? PastelTheme.hudBlack : PastelTheme.hudLine)
            .frame(width: 24, height: 18)
            .overlay(Rectangle().strokeBorder(on ? PastelTheme.hudBlack : PastelTheme.hudLine, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { if on { act() } }
    }
}

/// UPDATE (in the CAFES panel): write a new firmware over Bluetooth to A / B / both
struct UpdateCard: View {
    let d: Director
    @ObservedObject var rig: Rig
    @ObservedObject var a: CafeUnit
    @ObservedObject var b: CafeUnit
    @State private var picking = false
    @State private var fileNote = ""
    private let who = ["A", "B", "A + B"]

    var body: some View {
        PanelCard(title: "UPDATE", note: "firmware over bluetooth", spacing: 5) {
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
            Text("Arduino IDE: Sketch > Export Compiled Binary → esp_cafe_duo.ino.bin (not .merged / .bootloader). The Cafe restarts with it.")
                .font(.hud(8))
                .foregroundStyle(PastelTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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

/// GRAIN's switches: MOVE (a moving pitch), and the marks (places to take grains from)
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
            // the 8 places: filled = kept
            HStack(spacing: 2) {
                ForEach(0..<8, id: \.self) { i in
                    Rectangle()
                        .fill(i < grain.marks ? PastelTheme.hudOrange : Color.clear)
                        .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
                        .frame(width: 9, height: 12)
                }
            }
            ChipButton(title: "ONLY MARKS", filled: grain.useMarks) { grain.setUseMarks(!grain.useMarks, d.ctxUnits()) }
                .disabled(grain.marks == 0)
                .unlit(grain.marks == 0)
            ChipButton(title: "CLEAR", filled: false) { grain.clearMarks(d.ctxUnits()) }
        }
        Text("MARK keeps the place of the grain you just heard (up to 8, shown as the boxes). ONLY MARKS: grains then come only from those places — a phrase you like, again and again. CLEAR forgets them.")
            .font(.hud(8))
            .foregroundStyle(PastelTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        Text("MOVE PITCH: every grain its own pitch from all intervals, gliding up or down. Off: pitch held for phrases (PITCH / REV·HOLD pads).")
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

/// one preset: its number (the order in this list), name, what it is, and A · B —
/// each shows where that Cafe is and puts it there. Tapping the row itself = both.
private struct PresetRow: View {
    let n: Int
    @ObservedObject var rig: Rig
    @ObservedObject var a: CafeUnit
    @ObservedObject var b: CafeUnit
    let choose: (Int) -> Void                    // 0 = A, 1 = B, 2 = both

    private func on(_ u: CafeUnit) -> Bool { (u.isConnected && u.preset >= 0 ? u.preset : rig.preset[u.slot]) == n }

    var body: some View {
        let onA = on(a), onB = on(b)
        HStack(spacing: 6) {
            HudTag(text: String(format: "%02ld", Preset.number(n)),
                   fill: onA && onB ? PastelTheme.hudOrange : PastelTheme.hudBlack, size: 9)
            Text(Preset.names[n])
                .font(.hudBig(13))
                .foregroundStyle(PastelTheme.hudBlack)
                .frame(width: 78, alignment: .leading)
            Text(Preset.notes[n])
                .font(.hud(7.5))
                .foregroundStyle(PastelTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            mark("A", onA, a.isConnected) { choose(0) }
            mark("B", onB, b.isConnected) { choose(1) }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 3)
        .background(Rectangle().fill(onA || onB ? PastelTheme.hudOrange.opacity(0.12) : Color.clear))
        .overlay(alignment: .bottom) { Rectangle().fill(PastelTheme.hudLine.opacity(0.6)).frame(height: 0.5) }
        .contentShape(Rectangle())
        .onTapGesture { choose(2) }
    }

    private func mark(_ s: String, _ here: Bool, _ live: Bool, _ tap: @escaping () -> Void) -> some View {
        Text(s)
            .font(.hud(9, .semibold))
            .foregroundStyle(here ? Color.white : PastelTheme.hudBlack)
            .frame(width: 22, height: 17)
            .background(Rectangle().fill(here ? (live ? PastelTheme.hudOrange : PastelTheme.textSecondary) : Color.clear))
            .overlay(Rectangle().strokeBorder(here ? Color.clear : PastelTheme.hudLine, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
    }
}

/// one Cafe's firmware update: progress bar and what happened
struct UpdateRow: View {
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
