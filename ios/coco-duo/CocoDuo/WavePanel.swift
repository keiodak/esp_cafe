// WavePanel.swift — coco duo (k.odk)
// The WAVE panel, once for each Cafe: the tape (in DELAY / NOISE it shows their memory), the write head (orange)
// and the read head (ink) · REC · LOAD (an audio file onto the tape, recording off) · EARTH / FLIP / SKIP / BUTTON,
// clock, buffer length, preset, mode, tempo
// (no WAV saving here: esp_cafe_duo has no tape dump — use coco-pc with esp_cafe_ble for that)

import SwiftUI
import UniformTypeIdentifiers

struct WaveView: View {
    @ObservedObject var hub: CafeHub

    var body: some View {
        PanelScaffold(title: "WAVE") {
            PanelColumns {
                CafeWaveCard(unit: hub.units[0])
            } right: {
                CafeWaveCard(unit: hub.units[1])
            }
        }
    }
}

private struct CafeWaveCard: View {
    @ObservedObject var unit: CafeUnit
    @State private var picking = false
    @State private var decoding = false


    var body: some View {
        PanelCard(title: unit.slot == 0 ? "CAFE A" : "CAFE B",
                  note: unit.name.map { "\($0) · \(unit.state)" } ?? unit.state, spacing: 4) {
            TapeView(scope: unit.scope, unit: unit)
                .frame(height: 78)
                .opacity(unit.isConnected ? 1 : 0.4)
            HStack(spacing: PanelMetrics.chipSpacing) {
                PositionLine(scope: unit.scope, unit: unit)
                Spacer(minLength: 0)
                ChipButton(title: "REC", filled: unit.isConnected && unit.recording) {
                    unit.send("R \(unit.recording ? 0 : 1)")
                }
                .frame(width: 40)
                ChipButton(title: "LOAD", filled: decoding || unit.loadProgress != nil) {
                    if unit.isConnected && !decoding && unit.loadProgress == nil { picking = true }
                }
                .frame(width: 44)
                ChipButton(title: "SAVE", filled: unit.saveProgress != nil) {
                    if unit.isConnected && unit.saveProgress == nil { unit.saveTape() }
                }
                .frame(width: 44)
            }
            HStack(spacing: PanelMetrics.chipSpacing) {
                OutWindow(outs: unit.outs, title: "ASH", yellow: false)
                OutWindow(outs: unit.outs, title: "YELLOW", yellow: true)
            }
            .frame(height: 34)
            .opacity(unit.isConnected ? 1 : 0.4)
            if unit.saveProgress != nil || !unit.saveNote.isEmpty {
                HStack(spacing: PanelMetrics.rowGap) {
                    Text("SAVE")
                        .font(.hud(PanelMetrics.labelFont, .medium))
                        .foregroundStyle(PastelTheme.textPrimary)
                    if let p = unit.saveProgress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().strokeBorder(PastelTheme.textPrimary.opacity(0.45), lineWidth: 1)
                                Rectangle().fill(PastelTheme.hudOrange)
                                    .frame(width: max(0, (geo.size.width - 2) * CGFloat(p)))
                                    .padding(1)
                            }
                        }
                        .frame(height: 6)
                    } else {
                        Text(unit.saveNote)
                            .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                            .foregroundStyle(PastelTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            if decoding || unit.loadProgress != nil || !unit.loadNote.isEmpty {
                HStack(spacing: PanelMetrics.rowGap) {
                    Text("FILE")
                        .font(.hud(PanelMetrics.labelFont, .medium))
                        .foregroundStyle(PastelTheme.textPrimary)
                    if let p = unit.loadProgress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().strokeBorder(PastelTheme.textPrimary.opacity(0.45), lineWidth: 1)
                                Rectangle().fill(PastelTheme.textPrimary.opacity(0.8))
                                    .frame(width: max(0, (geo.size.width - 2) * CGFloat(p)))
                                    .padding(1)
                            }
                        }
                        .frame(height: 6)
                    } else {
                        Text(decoding ? "reading the file…" : unit.loadNote)
                            .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                            .foregroundStyle(PastelTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            // the Cafe's own inputs, in one row: EARTH bar · FLIP · SKIP · BUTTON
            HStack(spacing: 8) {
                Text("EARTH")
                    .font(.hud(PanelMetrics.labelFont, .medium))
                    .foregroundStyle(PastelTheme.textPrimary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().strokeBorder(PastelTheme.textPrimary.opacity(0.45), lineWidth: 1)
                        Rectangle().fill(PastelTheme.textPrimary.opacity(0.8))
                            .frame(width: max(0, (geo.size.width - 2) * CGFloat(unit.earth) / 255))
                            .padding(1)
                    }
                }
                .frame(height: 7)
                lamp("FLIP", unit.flip)
                lamp("SKIP", unit.skip)
                lamp("BTN", unit.button)
            }
            // clock · buffer · preset · mode · tempo, two short lines
            Text("\(unit.hz > 0 ? String(format: "%.1f kHz", unit.hz / 1000) : "—")  ·  \(unit.hz > 1000 ? String(format: "%.2f s", Double(TAPE) / unit.hz) : "—")  ·  \(unit.bpm > 0 ? String(format: "%.1f BPM", unit.bpm) : "—")")
                .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                .foregroundStyle(PastelTheme.textSecondary)
                .lineLimit(1)
            Text("\(unit.preset < 0 ? "—" : Preset.tag(unit.preset))\(unit.preset == Preset.ble ? "  ·  " + Preset.modeNames[min(max(unit.mode, 0), Preset.modeNames.count - 1)] : "")")
                .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                .foregroundStyle(PastelTheme.textSecondary)
                .lineLimit(1)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { loadFile($0) }
        // SAVE: once the tape is in, hand the WAV to Files
        .fileExporter(isPresented: Binding(get: { unit.savedWav != nil }, set: { if !$0 { unit.savedWav = nil } }),
                      document: WavDoc(data: unit.savedWav ?? Data()),
                      contentType: .wav,
                      defaultFilename: "\(unit.name ?? "Cafe")-tape") { _ in unit.savedWav = nil }
    }

    /// decode off the main thread, then hand the samples to the Cafe link
    private func loadFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let rate = unit.hz > 1000 ? unit.hz : 44100
        decoding = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let outcome = Result { try AudioLoader.tapeSamples(url: url, rate: rate) }
            DispatchQueue.main.async {
                decoding = false
                switch outcome {
                case .success(let samples): unit.load(samples)
                case .failure(let e): unit.loadNote = e.localizedDescription
                }
            }
        }
    }

    private func lamp(_ name: String, _ on: Bool) -> some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(on ? PastelTheme.textPrimary : Color.clear)
                .overlay(Rectangle().strokeBorder(PastelTheme.textPrimary, lineWidth: 1))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.hud(PanelMetrics.labelFont, .medium))
                .foregroundStyle(PastelTheme.textPrimary)
        }
    }
}

/// play / rec / loop in seconds under the tape
private struct PositionLine: View {
    @ObservedObject var scope: CafeScope
    @ObservedObject var unit: CafeUnit

    var body: some View {
        let s = unit.hz > 1000 ? unit.hz : 44100
        Text(String(format: "read %.2f s   write %.2f s", Double(scope.play) / s, Double(scope.rec) / s))
            .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
            .foregroundStyle(PastelTheme.textSecondary)
    }
}

/// The tape. Same gestures as coco-pc.html.
private struct TapeView: View {
    @ObservedObject var scope: CafeScope
    @ObservedObject var unit: CafeUnit

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let x = { (s: Int) -> CGFloat in CGFloat(s) / CGFloat(TAPE) * size.width }
                // min / max per bin
                let bw = size.width / CGFloat(BINS)
                var wave = Path()
                for i in 0..<BINS {
                    let top = (1 - CGFloat(scope.maxs[i]) / 255) * size.height
                    let bot = (1 - CGFloat(scope.mins[i]) / 255) * size.height
                    wave.addRect(CGRect(x: CGFloat(i) * bw, y: min(top, bot),
                                        width: max(0.7, bw * 0.85), height: max(0.7, abs(bot - top))))
                }
                ctx.fill(wave, with: .color(PastelTheme.textPrimary.opacity(0.75)))
                // record head (dashed orange) and play head (ink)
                var recLine = Path()
                recLine.move(to: CGPoint(x: x(scope.rec), y: 0))
                recLine.addLine(to: CGPoint(x: x(scope.rec), y: size.height))
                ctx.stroke(recLine, with: .color(PastelTheme.recording), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                ctx.fill(Path(CGRect(x: x(scope.play) - 1, y: 0, width: 2, height: size.height)),
                         with: .color(PastelTheme.textPrimary))
            }
            .background(Rectangle().fill(PastelTheme.padScreen))
            .overlay(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
            .overlay(HudCorners(arm: 7).stroke(PastelTheme.hudBlack, lineWidth: 1.2))
        }
    }

}

/// ASH / YELLOW: what the output did over the last ~5 s (the Cafe sends its min / max with every status line)
private struct OutWindow: View {
    @ObservedObject var outs: OutScope
    let title: String
    let yellow: Bool

    var body: some View {
        let d = yellow ? outs.yellow : outs.ash
        ZStack(alignment: .topLeading) {
            Rectangle().fill(PastelTheme.padScreen)
            Canvas { ctx, size in
                let n = d.count
                guard n > 1 else { return }
                let w = size.width / CGFloat(n)
                let mid = Path { p in p.move(to: CGPoint(x: 0, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width, y: size.height / 2)) }
                ctx.stroke(mid, with: .color(PastelTheme.hudLine.opacity(0.6)), lineWidth: 0.5)
                var p = Path()
                for (i, v) in d.enumerated() {
                    let x = CGFloat(i) * w + w / 2
                    let lo = size.height * (1 - CGFloat(v.0) / 255), hi = size.height * (1 - CGFloat(v.1) / 255)
                    p.move(to: CGPoint(x: x, y: lo))
                    p.addLine(to: CGPoint(x: x, y: min(hi, lo - 0.8)))
                }
                ctx.stroke(p, with: .color(yellow ? PastelTheme.hudOrange : PastelTheme.hudBlack), lineWidth: max(1, w * 0.9))
            }
            Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
            Text(title)
                .font(.hud(7, .semibold))
                .tracking(1)
                .foregroundStyle(PastelTheme.hudBlack)
                .padding(.horizontal, 3)
                .background(PastelTheme.padScreen)
                .padding(3)
        }
    }
}

/// the tape as a WAV file, for the SAVE button's exporter
struct WavDoc: FileDocument {
    static var readableContentTypes: [UTType] { [.wav] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
