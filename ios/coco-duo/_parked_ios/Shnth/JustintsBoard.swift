// JustintsBoard.swift — coco duo (k.odk)
// iOS · JUSTINTS: Peter Blasser's justints on the phone, in coco duo's look. A thin line (the example, ‹ ›, the
// antennae's meters); its picture (tap its routing squares) beside its keys; the four minor buttons (king / queen);
// the four bars as XY pads (finger area). GEN: the top left corner's key · the antennae's source: bottom right's left.

import SwiftUI

struct JustintsBoard: View {
    @ObservedObject var jp: JustintsPlayer
    @ObservedObject var ant: Antennae

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 5) {
                line
                TimelineView(.periodic(from: .now, by: 1.0 / 20)) { _ in
                    let v = jp.viewNow()
                    HStack(spacing: 6) {
                        JustintsPictureView(v: v) { k, w, i, j in jp.toggle(k, w, i, j) }
                            .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
                        keys(v).frame(width: 236)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { k in
                        HoldKey(label: "minor" + ["", " B", " C", " D"][k]) { down in
                            if down { jp.minor |= 1 << UInt8(k) } else { jp.minor &= ~(1 << UInt8(k)) }
                            jp.pushReport()
                        }
                    }
                }
                .frame(height: 30)
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        BarPad(label: ["BAR", "BAR B", "BAR C", "BAR D"][i]) { jp.bars[i] = $0; jp.pushReport() }
                    }
                }
                .frame(height: max(70, geo.size.height * 0.34))
            }
        }
        .padding(6)
        .background(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
        .onAppear {
            ant.onChange = { [weak p = jp] a, b in p?.ant = a; p?.antB = b; p?.pushReport() }
            ant.begin()
        }
        .onDisappear { ant.end() }
    }

    /// the example (its list, ‹ ›) · the antennae
    private var line: some View {
        HStack(spacing: PanelMetrics.chipSpacing) {
            Menu {
                ForEach(JustintsPlayer.examples.indices, id: \.self) { i in
                    let n = JustintsPlayer.examples[i].name
                    Button(n) { jp.load(n) }
                }
            } label: {
                Text(jp.example.isEmpty ? "—" : jp.example)
                    .font(.hud(PanelMetrics.labelFont, .semibold)).foregroundStyle(PastelTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6).frame(width: 140, height: PanelMetrics.chipHeight)
                    .overlay(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
            }
            StepKey(left: true) { step(-1) }
            StepKey(left: false) { step(1) }
            Spacer(minLength: 6)
            AntMeters(ant: ant).frame(width: 90, height: 12)
        }
    }
    private func step(_ by: Int) {
        let all = JustintsPlayer.examples
        guard !all.isEmpty else { return }
        let i = all.firstIndex { $0.name == jp.example } ?? (by > 0 ? -1 : 0)
        jp.load(all[((i + by) % all.count + all.count) % all.count].name)
    }

    private func keys(_ v: ji_view) -> some View {
        let x = v.voice(Int(v.offset))
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {                                                 // the slots
                ForEach(0..<10, id: \.self) { k in
                    ChipButton(title: "\(k)", filled: k == Int(v.slot) || k == Int(v.slot2)) { jp.key(Character("\(k)")) }
                }
            }
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: "+", filled: false) { jp.key("\r") }
                ChipButton(title: "−", filled: false) { jp.key("\u{7f}") }
                ChipButton(title: "NEXT", filled: false) { jp.key(" ") }
                ChipButton(title: "ONE", filled: v.one != 0) { jp.key("/") }
                ChipButton(title: "COPY", filled: false) { jp.dupeVoice() }
            }
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: "FM", filled: x.fm != 0) { jp.key("q") }
                ChipButton(title: "ROUTE", filled: x.route != 0) { jp.key("a") }
                ChipButton(title: "HOLD", filled: x.hold != 0) { jp.key("z") }
                ChipButton(title: "RAMP", filled: x.ramp != 0) { jp.key("[") }
                ChipButton(title: "SAW", filled: x.saw != 0) { jp.key("'") }
            }
            row("FM", Array("wertyuiop"), from: 0, now: Int(x.fmshift))
            row("STEP", Array("sdfghjkl;"), from: 0, now: Int(x.step))
            row("ANT", Array("xcvbnm,."), from: 1, now: Int(x.speed))
            Spacer(minLength: 0)
        }
    }
    private func row(_ label: String, _ ks: [Character], from: Int, now: Int) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.hud(PanelMetrics.chipFont, .semibold)).foregroundStyle(PastelTheme.textSecondary)
                .frame(width: 26, alignment: .leading)
            ForEach(ks.indices, id: \.self) { i in
                ChipButton(title: "\(i + from)", filled: now == i + from) { jp.key(ks[i]) }
            }
        }
    }
}
