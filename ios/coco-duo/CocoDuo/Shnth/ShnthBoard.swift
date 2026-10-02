// ShnthBoard.swift — coco duo (k.odk)
// SHNTH's screen (in place of the pads), as the Shnth app's, in coco duo's look: the patch (its list, ‹ ›), its preset,
// the LEDs; MAJOR over minor, TAR, the antennae (TILT · CAM · OFF); the four bars as XY pads (finger area).
// SHNTH sounds on the Cafes only (the phone's engine runs silent, for the LEDs). GEN is the top left corner's key.

import SwiftUI

struct ShnthBoard: View {
    @ObservedObject var sh: ShnthPlayer
    @ObservedObject var ant: Antennae
    /// a change the Cafes must hear about (the Director sends it)
    let changed: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            top
            shnth
        }
        .padding(8)
        .background(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
        .onAppear { route(); ant.begin() }
        .onDisappear { ant.end() }
    }

    /// the antennae: to the Shnth
    private func route() {
        ant.onChange = { [weak p = sh] a, b in p?.corp[0] = a; p?.corp[1] = b; p?.pushInputs() }
        changed()
    }

    // MARK: the top row

    private var top: some View {
        HStack(spacing: PanelMetrics.chipSpacing) {
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
