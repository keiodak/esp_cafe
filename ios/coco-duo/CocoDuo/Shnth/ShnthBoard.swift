// ShnthBoard.swift — coco duo (k.odk)
// SHNTH's screen (in place of the pads), as the Shnth app's, in coco duo's look. Top: the patch (its list, ‹ ›), the
// preset, the LEDs, iPHONE · CAFE (JUSTINTS: its example). SHNTH | JUSTINTS is chosen beside the mode (BLE MODE);
// GEN is the top left corner's key.
// SHNTH: MAJOR over minor, TAR, the antennae (TILT · CAM · OFF); at the foot the four bars as XY pads (finger area).
// The Cafes on SHNTH play the patch with the same hands.
// JUSTINTS: Peter Blasser's justints on the phone (its picture — tap its routing squares — and its keys), the four
// minor buttons (king / queen), the antennae, the four bars. (The Cafes keep SHNTH: justints's ratio table is far
// bigger than a Cafe's memory.)

import SwiftUI

struct ShnthBoard: View {
    @ObservedObject var sh: ShnthPlayer
    @ObservedObject var jp: JustintsPlayer
    @ObservedObject var ant: Antennae
    /// a change the Cafes must hear about (the Director sends it)
    let changed: () -> Void
    @AppStorage("shnth.ji") private var ji = false

    var body: some View {
        VStack(spacing: 6) {
            top
            if ji { justints } else { shnth }
        }
        .padding(8)
        .background(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
        .onAppear { route(); ant.begin() }
        .onDisappear { ant.end() }
        .onChange(of: ji) { _, _ in route() }
    }

    /// the antennae go to the one that is showing
    private func route() {
        if ji {
            sh.corp = [0, 0]; sh.pushInputs()
            ant.onChange = { [weak p = jp] a, b in p?.ant = a; p?.antB = b; p?.pushReport() }
        } else {
            ant.onChange = { [weak p = sh] a, b in p?.corp[0] = a; p?.corp[1] = b; p?.pushInputs() }
        }
        changed()
    }

    // MARK: the top row

    private var top: some View {
        HStack(spacing: PanelMetrics.chipSpacing) {
            if ji {
                Menu {
                    ForEach(JustintsPlayer.examples.indices, id: \.self) { i in
                        let n = JustintsPlayer.examples[i].name
                        Button(n) { jp.load(n) }
                    }
                } label: { name(jp.example) }
                Spacer(minLength: 0)
            } else {
                Menu {
                    ForEach(ShnthPlayer.patches.indices, id: \.self) { i in
                        Button(ShnthPlayer.patches[i].name) { sh.select(patch: i); changed() }
                    }
                } label: { name(sh.customName.isEmpty ? sh.patchName : sh.customName) }
                StepKey(left: true) { sh.prevPatch(); changed() }
                StepKey(left: false) { sh.nextPatch(); changed() }
                Spacer(minLength: 6)
                StepKey(left: true) { sh.setPreset(sh.preset - 1); changed() }
                Text("\(sh.preset + 1)/\(max(1, sh.presetCount))")
                    .font(.hud(PanelMetrics.labelFont, .semibold)).foregroundStyle(PastelTheme.textPrimary).frame(width: 34)
                StepKey(left: false) { sh.setPreset(sh.preset + 1); changed() }
                TimelineView(.periodic(from: .now, by: 1.0 / 20)) { _ in
                    let leds = sh.ledsNow()
                    HStack(spacing: 3) {
                        ForEach(0..<8, id: \.self) { k in
                            Circle().fill((leds >> UInt8(k)) & 1 == 1 ? PastelTheme.hudOrange : PastelTheme.hudBlack.opacity(PastelTheme.tickOffOpacity))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .padding(.horizontal, 4)
                ChipButton(title: "iPHONE", filled: sh.onPhone) { sh.onPhone.toggle() }.frame(width: 50)
                ChipButton(title: "CAFE", filled: sh.onCafe) { sh.onCafe.toggle(); changed() }.frame(width: 40)
            }
        }
    }

    private func name(_ s: String) -> some View {
        Text(s.isEmpty ? "—" : s).font(.hud(PanelMetrics.labelFont, .semibold)).foregroundStyle(PastelTheme.textPrimary)
            .lineLimit(1).minimumScaleFactor(0.6).frame(width: 120, height: PanelMetrics.chipHeight)
            .overlay(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
    }

    // MARK: SHNTH

    private var shnth: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                VStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { row in                         // MAJOR on top, minor under
                        HStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { k in
                                let bit = UInt16(1) << UInt16((row == 0 ? 4 : 0) + k)
                                HoldKey(label: (row == 0 ? "MAJOR" : "minor") + ["", " B", " C", " D"][k]) { down in
                                    if down { sh.buttons |= bit } else { sh.buttons &= ~bit }
                                    sh.pushInputs()
                                }
                            }
                        }
                    }
                }
                VStack(spacing: 4) {
                    HoldKey(label: "TAR") { down in                              // (TAR re-tares: what is there now is rest)
                        let bit = UInt16(1) << 8
                        if down { sh.buttons |= bit; ant.zero() } else { sh.buttons &= ~bit }
                        sh.pushInputs()
                    }
                    AntennaPanel(ant: ant)
                }
                .frame(width: 210)
            }
            .frame(height: 64)
            if !sh.error.isEmpty {
                Text(sh.error).font(.hud(8)).foregroundStyle(PastelTheme.hudOrange).lineLimit(1)
            }
            HStack(spacing: 6) {                                                  // the four bars, as XY pads
                ForEach(0..<4, id: \.self) { i in
                    BarPad(label: ["BAR", "BAR B", "BAR C", "BAR D"][i]) { sh.bars[i] = $0; sh.pushInputs() }
                }
            }
        }
    }

    // MARK: JUSTINTS

    private var justints: some View {
        GeometryReader { geo in
            VStack(spacing: 6) {
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
                    AntennaPanel(ant: ant).frame(width: 210)
                }
                .frame(height: 34)
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        BarPad(label: ["BAR", "BAR B", "BAR C", "BAR D"][i]) { jp.bars[i] = $0; jp.pushReport() }
                    }
                }
                .frame(height: max(70, geo.size.height * 0.32))
            }
        }
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

/// ‹ / ›: a chip with a fine chevron (the patch, the preset)
private struct StepKey: View {
    let left: Bool
    let action: () -> Void
    var body: some View {
        Image(systemName: left ? "chevron.left" : "chevron.right")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(PastelTheme.textPrimary)
            .frame(width: 20, height: PanelMetrics.chipHeight)
            .background(ChipBackground(fill: nil))
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }
}
