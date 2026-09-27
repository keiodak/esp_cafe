// MakePanel.swift — coco duo (k.odk)
// MAKE (CLOUD's key): sounds made on the phone and written onto the tape of the Cafes on CLOUD (ToneMaker).
// TO = which Cafe · STRETCH = a file stretched into a still, looping cloud · CHORDS = 16 slices, a chord in each.

import SwiftUI

/// CLOUD's MAKE key: STRETCH (1 a file · 2 how far · 3 go) and CHORDS (key · set · go), onto the tape of the Cafes on CLOUD
struct MakeSheet: View {
    let d: Director
    var body: some View {
        PanelScaffold(title: "MAKE") { MakeRows(d: d) }
    }
}

struct MakeRows: View {
    let d: Director
    var pick: Int? = nil                   // 0 A · 1 B · 2 both · nil = the Cafes the pads go to
    @State private var file: URL? = nil    // STRETCH: the file chosen
    @State private var stretchI = 1
    @State private var keyI = 0
    @State private var setI = 0
    @State private var picking = false
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.chipSpacing * 2) {
            PanelCard(title: "STRETCH") {
                HStack(spacing: PanelMetrics.chipSpacing) {
                    Step(n: 1)
                    ChipButton(title: "FILE", filled: file == nil) { picking = true }
                        .frame(width: 70)
                    Text(file?.deletingPathExtension().lastPathComponent ?? "—")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(file == nil ? PastelTheme.textSecondary : PastelTheme.hudBlack)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: PanelMetrics.chipSpacing) {
                    Step(n: 2)
                    ForEach(ToneMaker.stretches.indices, id: \.self) { i in
                        ChipButton(title: "×\(Int(ToneMaker.stretches[i]))", filled: stretchI == i) { stretchI = i }
                    }
                }
                HStack(spacing: PanelMetrics.chipSpacing) {
                    Step(n: 3)
                    BigButton(title: "STRETCH → " + targetName, busy: busy, enabled: ready && file != nil) {
                        if let f = file { stretchFile(f) }
                    }
                }
            }
            PanelCard(title: "CHORDS") {
                HStack(spacing: 2) {
                    ForEach(0..<12, id: \.self) { k in
                        ChipButton(title: ToneMaker.keys[k], filled: keyI == k) { keyI = k }
                    }
                }
                HStack(spacing: PanelMetrics.chipSpacing) {
                    ForEach(ToneMaker.sets.indices, id: \.self) { i in
                        ChipButton(title: ToneMaker.sets[i], filled: setI == i) { setI = i }
                    }
                }
                BigButton(title: "CHORDS → " + targetName, busy: busy, enabled: ready) { makeChords() }
            }
            ForEach(units, id: \.slot) { u in ProgressLine(unit: u) }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { r in
            if case .success(let url) = r { file = url }
        }
    }

    /// "A", "B", "A + B" (or — when no Cafe is on CLOUD)
    private var targetName: String {
        let u = units.map { $0.slot == 0 ? "A" : "B" }
        return u.isEmpty ? "—" : u.joined(separator: " + ")
    }
    private var units: [CafeUnit] {
        guard let p = pick else { return d.ctxUnits() }
        return p == 2 ? d.units : [d.units[p]]
    }
    private var ready: Bool { !busy && !units.isEmpty && units.allSatisfy { $0.isConnected && $0.loadProgress == nil } }
    private func stretchFile(_ url: URL) {
        let s = ToneMaker.stretches[stretchI]
        let targets = units
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            var made: [(CafeUnit, Result<[UInt16], Error>)] = []
            for u in targets {
                let rate = u.hz > 1000 ? u.hz : 44100
                made.append((u, Result {
                    let x = try ToneMaker.mono(url: url, rate: rate, maxCount: Int(Double(TAPE) / s) + 4096)
                    return ToneMaker.tape(ToneMaker.stretch(x, by: s))
                }))
            }
            DispatchQueue.main.async {
                busy = false
                for (u, r) in made {
                    switch r {
                    case .success(let samples): u.load(samples)
                    case .failure(let e): u.loadNote = e.localizedDescription
                    }
                }
            }
        }
    }

    private func makeChords() {
        let set = setI, key = keyI, targets = units
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let made = targets.map { u in (u, ToneMaker.tape(ToneMaker.chords(set: set, key: key, rate: u.hz > 1000 ? u.hz : 44100))) }
            DispatchQueue.main.async {
                busy = false
                for (u, s) in made { u.load(s) }
            }
        }
    }
}

/// one Cafe: A / B, and how far its tape is written (or what happened)
private struct ProgressLine: View {
    @ObservedObject var unit: CafeUnit
    var body: some View {
        HStack(spacing: 8) {
            Text(unit.slot == 0 ? "A" : "B")
                .font(.hud(9, .semibold))
                .foregroundStyle(PastelTheme.textPrimary)
                .frame(width: 12, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().strokeBorder(PastelTheme.textPrimary.opacity(0.45), lineWidth: 1)
                    Rectangle().fill(PastelTheme.hudOrange)
                        .frame(width: max(0, (geo.size.width - 2) * CGFloat(unit.loadProgress ?? 0)))
                        .padding(1)
                }
            }
            .frame(height: 7)
            Text(unit.isConnected ? (unit.loadProgress != nil ? "\(Int((unit.loadProgress ?? 0) * 100))%" : unit.loadNote) : "—")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(PastelTheme.textSecondary)
                .lineLimit(1)
                .frame(width: 110, alignment: .trailing)
        }
    }
}

/// 1 · 2 · 3: the order of STRETCH
private struct Step: View {
    let n: Int
    var body: some View {
        HudTag(text: "\(n)", size: 9).frame(width: 16)
    }
}

/// the one big key of a card
private struct BigButton: View {
    let title: String
    let busy: Bool
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(busy ? "…" : title)
                .font(.hud(11, .semibold))
                .tracking(1)
                .foregroundStyle(enabled ? PastelTheme.selectionText : PastelTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Rectangle().fill(enabled ? PastelTheme.hudOrange : PastelTheme.chipWell))
                .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
