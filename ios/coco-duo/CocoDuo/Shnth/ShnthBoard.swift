// ShnthBoard.swift — coco duo (k.odk)
// SHNTH's screen (in place of the pads): the patch and its preset on top, then the Shnth's own controls — four bars
// (press up / down from the middle: they spring back to rest), two antennae (how near: 0 when let go), the eight
// buttons (four minor, four major) and TAR, and the patch's eight LEDs.

import SwiftUI

struct ShnthBoard: View {
    @ObservedObject var sh: ShnthPlayer
    /// a change the Cafes must hear about (the Director sends it)
    let changed: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: PanelMetrics.chipSpacing) {                       // the patch · its preset · where it sounds
                ChipButton(title: "◀", filled: false) { sh.prevPatch(); changed() }.frame(width: 30)
                Text(sh.patchName)
                    .font(.hud(PanelMetrics.labelFont, .semibold)).foregroundStyle(PastelTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(minWidth: 90)
                ChipButton(title: "▶", filled: false) { sh.nextPatch(); changed() }.frame(width: 30)
                Spacer(minLength: 6)
                ChipButton(title: "−", filled: false) { sh.setPreset(sh.preset - 1); changed() }.frame(width: 30)
                Text("\(sh.preset + 1)/\(sh.presetCount)")
                    .font(.hud(PanelMetrics.labelFont, .semibold)).foregroundStyle(PastelTheme.textPrimary)
                    .frame(width: 44)
                ChipButton(title: "+", filled: false) { sh.setPreset(sh.preset + 1); changed() }.frame(width: 30)
                Spacer(minLength: 6)
                ChipButton(title: "iPHONE", filled: sh.onPhone) { sh.onPhone.toggle() }.frame(width: 60)
                ChipButton(title: "CAFE", filled: sh.onCafe) { sh.onCafe.toggle(); changed() }.frame(width: 50)
            }
            if !sh.error.isEmpty {
                Text(sh.error).font(.hud(8)).foregroundStyle(PastelTheme.hudOrange).lineLimit(1)
            }
            HStack(spacing: 10) {
                HStack(spacing: 8) {                                          // the four bars
                    ForEach(0..<4, id: \.self) { i in
                        ShnthStrip(label: ["BAR", "BAR B", "BAR C", "BAR D"][i], bipolar: true) { sh.bars[i] = $0; sh.pushInputs() }
                    }
                }
                HStack(spacing: 8) {                                          // the two antennae
                    ForEach(0..<2, id: \.self) { i in
                        ShnthStrip(label: i == 0 ? "ANT" : "ANT B", bipolar: false) { sh.corp[i] = $0; sh.pushInputs() }
                    }
                }
                .frame(maxWidth: 110)
                VStack(spacing: 6) {                                          // the LEDs, the buttons, TAR
                    TimelineView(.periodic(from: .now, by: 1.0 / 20)) { _ in
                        HStack(spacing: 4) {
                            ForEach(0..<8, id: \.self) { k in
                                let on = (sh.ledsNow() >> UInt8(k)) & 1 == 1
                                Circle().fill(on ? PastelTheme.hudOrange : PastelTheme.hudBlack.opacity(PastelTheme.tickOffOpacity))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(0..<4, id: \.self) { k in
                                let bit = UInt16(1) << UInt16(row * 4 + k)
                                ShnthButton(label: (row == 0 ? "minor" : "MAJOR") + ["", " B", " C", " D"][k]) { down in
                                    if down { sh.buttons |= bit } else { sh.buttons &= ~bit }
                                    sh.pushInputs()
                                }
                            }
                        }
                    }
                    ShnthButton(label: "TAR") { down in
                        let bit = UInt16(1) << 8
                        if down { sh.buttons |= bit } else { sh.buttons &= ~bit }
                        sh.pushInputs()
                    }
                }
                .frame(maxWidth: 260)
            }
        }
        .padding(8)
        .background(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
    }
}

/// a bar (bipolar: up / down from the middle, back to rest when let go) or an antenna (0 at the bottom, back to 0)
private struct ShnthStrip: View {
    let label: String
    let bipolar: Bool
    let set: (Double) -> Void
    @State private var v = 0.0

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { g in
                let h = g.size.height
                let y0 = bipolar ? h / 2 : h                                     // (rest)
                let y = bipolar ? h / 2 - CGFloat(v) * h / 2 : h - CGFloat(v) * h
                ZStack(alignment: .topLeading) {
                    Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
                    Rectangle().fill(PastelTheme.hudBlack.opacity(0.85))
                        .frame(width: g.size.width - 6, height: max(1, abs(y - y0)))
                        .offset(x: 3, y: min(y, y0))
                    Rectangle().fill(PastelTheme.hudBlack.opacity(0.35)).frame(height: 1).offset(y: y0 - 0.5)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { e in
                        let t = bipolar ? Double((h / 2 - e.location.y) / (h / 2)) : Double((h - e.location.y) / h)
                        v = min(1, max(bipolar ? -1 : 0, t)); set(v)
                    }
                    .onEnded { _ in v = 0; set(0) })                            // (let go: back to rest)
            }
            Text(label).font(.hud(8, .medium)).foregroundStyle(PastelTheme.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// a button held while touched
private struct ShnthButton: View {
    let label: String
    let press: (Bool) -> Void
    @State private var down = false

    var body: some View {
        Text(label)
            .font(.hud(8, .semibold)).lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(down ? PastelTheme.selectionText : PastelTheme.hudBlack)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(IconSquare(filled: down))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; press(true) } }
                .onEnded { _ in down = false; press(false) })
    }
}
