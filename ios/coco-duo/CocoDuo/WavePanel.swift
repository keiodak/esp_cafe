// WavePanel.swift — coco duo (k.odk)
// The WAVE panel: what coco-pc.html does on the Mac, once for each Cafe.
//   tape waveform with the loop, the play head (ink) and the record head (orange)
//   tap = jump · drag = new loop · drag an edge = move it
//   speed bar + -1 / ½ / 1 / 2 / REV / STOP · REC · TO START · WHOLE
//   EARTH / FLIP / SKIP / BUTTON lamps, clock, buffer length, preset
//   LOAD = put an audio file on the tape (from the start; recording is switched off, the loop becomes the file)
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

    private let speedChips: [(String, Int?)] = [("-1", -1000), ("½", 500), ("1", 1000), ("2", 2000), ("REV", nil), ("STOP", 0)]

    var body: some View {
        PanelCard(title: unit.slot == 0 ? "CAFE A" : "CAFE B",
                  note: unit.name.map { "\($0) · \(unit.state)" } ?? unit.state) {
            TapeView(scope: unit.scope, unit: unit)
                .frame(height: 118)
                .opacity(unit.isConnected ? 1 : 0.4)
            PositionLine(scope: unit.scope, unit: unit)

            // speed: the bar spans -4x … +4x, the middle is stop
            HStack(spacing: PanelMetrics.rowGap) {
                Text("SPEED")
                    .font(.system(size: PanelMetrics.labelFont, weight: .medium))
                    .foregroundStyle(PastelTheme.textPrimary)
                    .frame(width: PanelMetrics.labelWidth, alignment: .leading)
                CompactSlider(value: Binding(get: { (Double(unit.speed) + 4000) / 8000 },
                                             set: { unit.send("S \(Int(($0 * 8000 - 4000) / 10) * 10)") }),
                              fillColor: PastelTheme.sliderFill,
                              knobColor: PastelTheme.knobColor)
            }
            HStack(spacing: PanelMetrics.chipSpacing) {
                ForEach(0..<speedChips.count, id: \.self) { i in
                    let chip = speedChips[i]
                    ChipButton(title: chip.0, filled: chip.1 == unit.speed) {
                        unit.send("S \(chip.1 ?? -unit.speed)")
                    }
                }
            }
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: "REC", filled: unit.isConnected && unit.recording) {
                    unit.send("R \(unit.recording ? 0 : 1)")
                }
                ChipButton(title: "TO START", filled: false) { unit.send("J \(unit.ls)") }
                ChipButton(title: "WHOLE", filled: unit.ls == 0 && unit.le == TAPE) { unit.send("L 0 \(TAPE)") }
                ChipButton(title: "LOAD", filled: decoding || unit.loadProgress != nil) {
                    if unit.isConnected && !decoding && unit.loadProgress == nil { picking = true }
                }
            }
            if decoding || unit.loadProgress != nil || !unit.loadNote.isEmpty {
                HStack(spacing: PanelMetrics.rowGap) {
                    Text("FILE")
                        .font(.system(size: PanelMetrics.labelFont, weight: .medium))
                        .foregroundStyle(PastelTheme.textPrimary)
                        .frame(width: PanelMetrics.labelWidth, alignment: .leading)
                    if let p = unit.loadProgress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().strokeBorder(PastelTheme.textPrimary.opacity(0.45), lineWidth: 1)
                                Rectangle().fill(PastelTheme.textPrimary.opacity(0.8))
                                    .frame(width: max(0, (geo.size.width - 2) * CGFloat(p)))
                                    .padding(1)
                            }
                        }
                        .frame(height: 8)
                    } else {
                        Text(decoding ? "reading the file…" : unit.loadNote)
                            .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                            .foregroundStyle(PastelTheme.textSecondary)
                        Spacer(minLength: 0)
                    }
                }
            }

            // what the Cafe's own inputs are doing
            HStack(spacing: PanelMetrics.rowGap) {
                Text("EARTH")
                    .font(.system(size: PanelMetrics.labelFont, weight: .medium))
                    .foregroundStyle(PastelTheme.textPrimary)
                    .frame(width: PanelMetrics.labelWidth, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().strokeBorder(PastelTheme.textPrimary.opacity(0.45), lineWidth: 1)
                        Rectangle().fill(PastelTheme.textPrimary.opacity(0.8))
                            .frame(width: max(0, (geo.size.width - 2) * CGFloat(unit.earth) / 255))
                            .padding(1)
                    }
                }
                .frame(height: 8)
            }
            HStack(spacing: 12) {
                lamp("FLIP", unit.flip)
                lamp("SKIP", unit.skip)
                lamp("BUTTON", unit.button)
                Spacer(minLength: 0)
            }
            DiagRow("CLOCK", unit.hz > 0 ? String(format: "%.1f kHz", unit.hz / 1000) : "—")
            DiagRow("BUFFER", unit.hz > 1000 ? String(format: "%.2f s", Double(TAPE) / unit.hz) : "—")
            DiagRow("PRESET", unit.preset < 0 ? "—" : (unit.preset == 2 ? "3 duo" : "\(unit.preset + 1) — choose 3"))
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { loadFile($0) }
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
                .font(.system(size: PanelMetrics.labelFont, weight: .medium))
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
        Text(String(format: "play %.2f s   rec %.2f s   loop %.2f–%.2f s",
                    Double(scope.play) / s, Double(scope.rec) / s, Double(unit.ls) / s, Double(unit.le) / s))
            .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
            .foregroundStyle(PastelTheme.textSecondary)
    }
}

/// The tape. Same gestures as coco-pc.html.
private struct TapeView: View {
    @ObservedObject var scope: CafeScope
    @ObservedObject var unit: CafeUnit
    private enum Mode { case new, left, right }
    @State private var mode: Mode? = nil
    @State private var anchor = 0
    @State private var moved = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Canvas { ctx, size in
                let x = { (s: Int) -> CGFloat in CGFloat(s) / CGFloat(TAPE) * size.width }
                let lx = x(unit.ls), rx = x(unit.le)
                // loop band and its edges
                ctx.fill(Path(CGRect(x: lx, y: 0, width: max(1, rx - lx), height: size.height)),
                         with: .color(PastelTheme.textPrimary.opacity(0.12)))
                ctx.fill(Path(CGRect(x: lx - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(PastelTheme.textPrimary))
                ctx.fill(Path(CGRect(x: rx - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(PastelTheme.textPrimary))
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
            .overlay(Rectangle().strokeBorder(PastelTheme.textPrimary, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let s = sample(v.location.x, w)
                        if mode == nil {
                            let lx = CGFloat(unit.ls) / CGFloat(TAPE) * w, rx = CGFloat(unit.le) / CGFloat(TAPE) * w
                            if abs(v.startLocation.x - lx) < 16 { mode = .left }
                            else if abs(v.startLocation.x - rx) < 16 { mode = .right }
                            else { mode = .new; anchor = sample(v.startLocation.x, w) }
                            moved = false
                            unit.holdLoop = true
                        }
                        if abs(v.translation.width) > 6 { moved = true }
                        guard moved else { return }
                        switch mode {
                        case .new: unit.ls = min(anchor, s); unit.le = max(anchor, s)
                        case .left: unit.ls = min(s, unit.le - 512)
                        case .right: unit.le = max(s, unit.ls + 512)
                        case .none: break
                        }
                    }
                    .onEnded { v in
                        if mode == .new && !moved {
                            unit.send("J \(sample(v.location.x, w))")
                        } else if moved {
                            if unit.le - unit.ls < 512 { unit.le = min(TAPE, unit.ls + 512); unit.ls = unit.le - 512 }
                            unit.send("L \(unit.ls) \(unit.le)")
                        }
                        mode = nil
                        unit.holdLoop = false
                    }
            )
        }
    }

    private func sample(_ px: CGFloat, _ w: CGFloat) -> Int {
        guard w > 0 else { return 0 }
        return max(0, min(TAPE, Int((px / w * CGFloat(TAPE)).rounded())))
    }
}
