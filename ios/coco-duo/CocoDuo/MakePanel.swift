// MakePanel.swift — coco duo (k.odk)
// MAKE: sounds made on the phone and written onto a Cafe's tape (ToneMaker). Opened from the MAKE key on A's bar
// (for A) or B's (for B); the target can be changed at the top. STRETCH = a file stretched into a still, looping
// cloud · CHORDS = 16 slices, a chord in each.

import SwiftUI

struct MakeView: View {
    @ObservedObject var hub: CafeHub
    @State var target: Int                 // 0 A · 1 B · 2 both
    @State private var stretchI = 1
    @State private var keyI = 0
    @State private var setI = 0
    @State private var picking = false
    @State private var busy = false

    var body: some View {
        PanelScaffold(title: "MAKE") {
            PanelCard(title: "TO") {
                HStack(spacing: PanelMetrics.chipSpacing) {
                    ForEach(0..<3, id: \.self) { t in
                        ChipButton(title: ["CAFE A", "CAFE B", "A + B"][t], filled: target == t) { target = t }
                    }
                }
                ForEach(units, id: \.slot) { u in ProgressLine(unit: u) }
            }
            PanelColumns(equalHeight: true) {
                PanelCard(title: "STRETCH", fill: true) {
                    HStack(spacing: PanelMetrics.chipSpacing) {
                        ForEach(ToneMaker.stretches.indices, id: \.self) { i in
                            ChipButton(title: "×\(Int(ToneMaker.stretches[i]))", filled: stretchI == i) { stretchI = i }
                        }
                    }
                    Spacer(minLength: 0)
                    BigButton(title: "FILE → STRETCH", busy: busy, enabled: ready) { picking = true }
                }
            } right: {
                PanelCard(title: "CHORDS", fill: true) {
                    VStack(spacing: PanelMetrics.chipSpacing) {
                        ForEach(0..<2, id: \.self) { r in
                            HStack(spacing: PanelMetrics.chipSpacing) {
                                ForEach(0..<6, id: \.self) { c in
                                    let k = r * 6 + c
                                    ChipButton(title: ToneMaker.keys[k], filled: keyI == k) { keyI = k }
                                }
                            }
                        }
                    }
                    HStack(spacing: PanelMetrics.chipSpacing) {
                        ForEach(ToneMaker.sets.indices, id: \.self) { i in
                            ChipButton(title: ToneMaker.sets[i], filled: setI == i) { setI = i }
                        }
                    }
                    Spacer(minLength: 0)
                    BigButton(title: "MAKE CHORDS", busy: busy, enabled: ready) { makeChords() }
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { stretchFile($0) }
    }

    private var units: [CafeUnit] { target == 2 ? hub.units : [hub.units[target]] }
    /// every target connected, and nothing on its way to them
    private var ready: Bool { !busy && units.allSatisfy { $0.isConnected && $0.loadProgress == nil } }

    private func stretchFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
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
