// PresetManager.swift — coco duo (k.odk)
// The PRESET MANAGER sheet (tap a bar's status in the main screen):
//   PRESETS  the playlist, numbered in its order. A · B on each row: where each Cafe is, and a tap puts it there
//            (that is also who the pads go to); the row itself = both. 12 = PRESET DESIGN: 11 slots, pick one then a
//            preset from the right (3 across), the bin empties a slot; empty slots are skipped on the Cafe.
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

    @State private var sel: Int? = nil          // PRESET DESIGN: the slot picked on the left

    /// PRESET DESIGN, on the left: tap a slot to pick it (to move a preset, pick a slot and tap that preset on the right)
    private func tapSlot(_ i: Int) {
        if bin { var l = rig.design; l[i] = -1; d.setDesign(l) } else { sel = i }
    }
    @State private var presetsH: CGFloat = 0
    @State private var bin = false               // 🗑 on: a tap on a slot empties it, on a memory erases it
    var body: some View {
        PanelScaffold(title: "PRESET MANAGER") {
            PanelColumns {
                PanelCard(title: "PRESETS", note: "A · B = which Cafe", spacing: 3) {
                    if design {
                        ForEach(0..<Preset.maxPlaylist, id: \.self) { i in
                            SlotRow(i: i, n: rig.design[i], picked: sel == i)
                                .onTapGesture { tapSlot(i) }
                        }
                    } else {
                        ForEach(0..<Preset.maxPlaylist, id: \.self) { i in
                            let n = rig.design[i]
                            if n >= 0 {
                                PresetRow(n: n, rig: rig, a: a, b: b) { t in d.setTarget(t); d.setPreset(n) }
                            } else {
                                SlotRow(i: i, n: -1, picked: false).opacity(0.5)
                            }
                        }
                    }
                    // 12: PRESET DESIGN — which presets are in the list (and the Cafe's BUTTON menu)
                    HStack(spacing: 6) {
                        HudTag(text: "12", fill: design ? PastelTheme.hudOrange : PastelTheme.hudBlack, size: 9)
                        Text("PRESET_DESIGN")
                            .font(.hudBig(13))
                            .foregroundStyle(PastelTheme.hudBlack)
                        Spacer(minLength: 0)
                        Image(systemName: design ? "chevron.right.circle.fill" : "chevron.right.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(design ? PastelTheme.hudOrange : PastelTheme.hudBlack)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 3)
                    .background(Rectangle().fill(design ? PastelTheme.hudOrange.opacity(0.12) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture { design.toggle(); sel = design ? 0 : nil; bin = false }      // opens with slot 01 picked
                }
                // measure PRESETS: PRESET DESIGN is given exactly this height (one way only: no feedback)
                .background(GeometryReader { g in Color.clear.preference(key: PresetsHeight.self, value: g.size.height) })
                .onPreferenceChange(PresetsHeight.self) { h in if abs(h - presetsH) > 0.5 { presetsH = h } }
            } right: {
                if design {
                    DesignCard(d: d, rig: rig, sel: $sel, bin: $bin)
                        .frame(height: presetsH > 0 ? presetsH : nil, alignment: .top)
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

/// PRESET DESIGN, left: one slot of the 11 (empty = nothing there; empty slots are skipped on the Cafe)
private struct SlotRow: View {
    let i: Int
    let n: Int
    let picked: Bool

    var body: some View {
        HStack(spacing: 6) {
            HudTag(text: String(format: "%02ld", i + 1), fill: picked ? PastelTheme.hudOrange : (n < 0 ? PastelTheme.hudLine : (Preset.phonePlayed.contains(n) ? PastelTheme.bleInk : PastelTheme.hudBlack)), size: 9)
            Text(n >= 0 ? Preset.names[n] : "— EMPTY —")
                .font(.hudBig(13))
                .foregroundStyle(n >= 0 ? PastelTheme.hudBlack : PastelTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 17)
        .padding(.vertical, 2)
        .padding(.horizontal, 3)
        .background(Rectangle().fill(picked ? PastelTheme.hudOrange.opacity(0.15) : (Preset.phonePlayed.contains(n) ? PastelTheme.bleWash : Color.clear)))
        .overlay(Rectangle().strokeBorder(picked ? PastelTheme.hudOrange : Color.clear, lineWidth: 1))
        .overlay(alignment: .bottom) { Rectangle().fill(PastelTheme.hudLine.opacity(0.6)).frame(height: 0.5) }
        .contentShape(Rectangle())
    }
}

/// PRESET DESIGN, right: every preset the firmware has, 3 across. Pick a slot on the left, then a preset here to put it
/// in (one that is already in the list moves there: the two swap). The bin empties the picked slot.
private struct DesignCard: View {
    let d: Director
    @ObservedObject var rig: Rig
    @Binding var sel: Int?
    @Binding var bin: Bool

    var body: some View {
        PanelCard(title: "PRESET DESIGN", note: sel.map { String(format: "%02ld", $0 + 1) } ?? "", spacing: 2, fill: true) {
            // BLE, MULTI, ARP_DELAY: fixed on top; everything else scrolls under it (3 across)
            grid([2, 9, 10])
            ScrollView {
                grid(Self.appleOrder)
            }
            .frame(maxHeight: .infinity)
            // bin · INIT · memories 1–5 (tap = recall, hold = save, with the bin on: tap = erase)
            HStack(spacing: 3) {
                small("🗑", on: bin) { bin.toggle() }
                small("INIT", on: false) { d.setDesign(Preset.defaultPlaylist); sel = 0; bin = false }
                Rectangle().fill(PastelTheme.hudLine).frame(width: 1, height: 14).padding(.horizontal, 3)
                ForEach(0..<5, id: \.self) { k in
                    small("\(k + 1)", on: false, filled: !rig.designBank[k].isEmpty, hold: {
                        var b = rig.designBank; b[k] = rig.design; rig.designBank = b
                    }) {
                        if bin {
                            var b = rig.designBank; b[k] = []; rig.designBank = b
                        } else if !rig.designBank[k].isEmpty {
                            d.setDesign(rig.designBank[k]); sel = 0
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 1)
        }
    }

    /// a small square key: on = orange, filled = a thin ink bar under the text (a memory with something in it)
    private func small(_ t: String, on: Bool, filled: Bool = false, enabled: Bool = true, hold: (() -> Void)? = nil, _ act: @escaping () -> Void) -> some View {
        Text(t)
            .font(.hud(9, .semibold))
            .foregroundStyle(on ? Color.white : (enabled ? PastelTheme.hudBlack : PastelTheme.hudLine))
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 19)
            .background(Rectangle().fill(on ? PastelTheme.hudOrange : PastelTheme.padScreen))
            .overlay(Rectangle().strokeBorder(enabled ? PastelTheme.hudBlack : PastelTheme.hudLine, lineWidth: 1))
            .overlay(alignment: .bottom) { if filled { Rectangle().fill(PastelTheme.hudBlack).frame(height: 3).padding(.horizontal, 3).padding(.bottom, 2) } }
            .contentShape(Rectangle())
            .onTapGesture { if enabled { act() } }
            .onLongPressGesture(minimumDuration: 0.6) { if enabled, let hold { hold() } }
    }


    /// everything but the BLE row, in Apple π's own order (ours where Apple π has the same preset);
    /// HARMONY, RUNGLER and SELF_READ (not in Apple π) at the very end
    static let appleOrder = [0, 11, 1, 12, 4, 13, 14, 3, 15, 16, 17, 18, 5, 19, 20, 21, 22, 24, 25, 26, 27, 23,
                             28, 29, 30, 31, 32, 33, 34, 35, 6, 7, 8]

    private func grid(_ ids: [Int]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), alignment: .leading, spacing: 3) {
            ForEach(ids, id: \.self) { n in cell(n) }
        }
    }

    private func cell(_ n: Int) -> some View {
        let at = rig.design.firstIndex(of: n)
        return HStack(spacing: 3) {
            Text(at.map { String(format: "%02ld", $0 + 1) } ?? "")
                .font(.hud(7, .semibold))
                .foregroundStyle(Color.white)
                .frame(width: at == nil ? 0 : 14, height: 14)
                .background(Rectangle().fill(at == nil ? Color.clear : PastelTheme.hudBlack))
            Text(Preset.names[n])
                .font(.hud(8, .semibold))
                .foregroundStyle(PastelTheme.hudBlack)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .frame(height: 18)
        .background(Rectangle().fill(at != nil ? Color.white : (Preset.phonePlayed.contains(n) ? PastelTheme.bleWash : PastelTheme.padScreen)))
        .overlay(Rectangle().strokeBorder(at != nil ? PastelTheme.hudBlack.opacity(0.5) : PastelTheme.hudLine, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { put(n) }
    }

    /// a preset into the picked slot (none picked: the first empty one)
    private func put(_ n: Int) {
        var l = rig.design
        let s = sel ?? l.firstIndex(of: -1) ?? 0
        if let j = l.firstIndex(of: n) { l.swapAt(s, j) } else { l[s] = n }
        d.setDesign(l)
        if sel != nil { sel = min(s + 1, Preset.maxPlaylist - 1) }      // next slot, for filling in a row
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
        PanelCard(title: "UPDATE", note: "firmware over bluetooth", spacing: 5, fill: true) {
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
                   fill: onA && onB ? PastelTheme.hudOrange : (Preset.phonePlayed.contains(n) ? PastelTheme.bleInk : PastelTheme.hudBlack), size: 9)
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
        .background(Rectangle().fill(onA || onB ? PastelTheme.hudOrange.opacity(0.12) : (Preset.phonePlayed.contains(n) ? PastelTheme.bleWash : Color.clear)))
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

/// the PRESETS card's height (PRESET DESIGN matches it)
private struct PresetsHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
