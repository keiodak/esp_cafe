// NobsBoard.swift — coco duo (k.odk)
// NOBSRINE (BLE mode 8): one instrument, L and R — two big knobs (it sounds only while one turns; where a turn begins
// sets a pitch), a LO / HI switch under each, and DECAY · PITCH · SPREAD · MIX.
import SwiftUI

struct NobsBoard: View {
    let d: Director
    @ObservedObject var rig: Rig

    var body: some View {
        HStack(spacing: 14) {
            knob(0)
            knob(1)
            VStack(spacing: 4) {
                NbSlider(label: "DECAY", a: rig.nbAxes[1], y: false) { d.padMoved(1) }
                NbSlider(label: "PITCH", a: rig.nbAxes[1], y: true) { d.padMoved(1) }
                NbSlider(label: "SPREAD", a: rig.nbAxes[2], y: false) { d.padMoved(2) }
                NbSlider(label: "MIX", a: rig.nbAxes[3], y: false) { d.padMoved(3) }
            }
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// a knob (L / R) with its switch under it
    private func knob(_ h: Int) -> some View {
        VStack(spacing: 6) {
            NbKnob(a: rig.nbAxes[0], y: h == 1) { d.padMoved(0) }
            HStack(spacing: 8) {
                Text(h == 0 ? "L" : "R")
                    .font(.hud(9, .semibold))
                    .foregroundStyle(PastelTheme.hudBlack)
                switchChip(h)
            }
        }
    }

    /// LO / HI (HI: two octaves up)
    private func switchChip(_ h: Int) -> some View {
        let on = rig.nbSw[h]
        return HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { hi in
                Text(hi ? "HI" : "LO")
                    .font(.hud(8, .semibold))
                    .foregroundStyle(on == hi ? PastelTheme.selectionText : PastelTheme.hudBlack)
                    .frame(width: 28, height: 20)
                    .background(Rectangle().fill(on == hi ? PastelTheme.hudBlack : Color.clear))
            }
        }
        .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { d.setNbSw(h, !on) }
    }
}

/// a big knob: turned by dragging round it (300° of travel)
struct NbKnob: View {
    @ObservedObject var a: PadAxis
    let y: Bool
    let moved: () -> Void
    @State private var last: Double? = nil

    private var v: Double { y ? a.y : a.x }

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height), c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            ZStack {
                Circle().fill(PastelTheme.padScreen)
                Circle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1.5)
                Circle().trim(from: 0, to: 300.0 / 360)                                  // the travel
                    .stroke(PastelTheme.trackOff, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(120)).padding(s * 0.08)
                Circle().trim(from: 0, to: 300.0 / 360 * v)
                    .stroke(PastelTheme.hudOrange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(120)).padding(s * 0.08)
                Rectangle().fill(PastelTheme.hudBlack)                                 // the pointer
                    .frame(width: 3, height: s * 0.3)
                    .offset(y: -s * 0.2)
                    .rotationEffect(.degrees(-150 + 300 * v))
                Circle().fill(PastelTheme.hudBlack).frame(width: s * 0.08, height: s * 0.08)
            }
            .frame(width: s, height: s)
            .position(c)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in
                    let ang = atan2(Double(e.location.x - c.x), Double(c.y - e.location.y))   // (0 at the top, clockwise)
                    if let l = last {
                        var da = ang - l
                        if da > .pi { da -= 2 * .pi }
                        if da < -.pi { da += 2 * .pi }
                        let nv = min(1, max(0, v + da / (300.0 / 180 * .pi)))
                        if y { a.y = nv } else { a.x = nv }
                        moved()
                    }
                    last = ang
                }
                .onEnded { _ in last = nil })
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct NbSlider: View {
    let label: String
    @ObservedObject var a: PadAxis
    let y: Bool
    let moved: () -> Void

    var body: some View {
        let v = y ? a.y : a.x
        HStack(spacing: 6) {
            Text(label)
                .font(.hud(7, .semibold))
                .foregroundStyle(PastelTheme.textSecondary)
                .frame(width: 38, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(PastelTheme.trackOff).frame(height: 2)
                    Rectangle().fill(PastelTheme.hudBlack).frame(width: g.size.width * v, height: 2)
                    Rectangle().fill(PastelTheme.hudOrange).frame(width: 4, height: 12)
                        .position(x: g.size.width * v, y: g.size.height / 2)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { e in
                    let nv = min(1, max(0, Double(e.location.x / max(1, g.size.width))))
                    if y { a.y = nv } else { a.x = nv }
                    moved()
                })
            }
        }
        .frame(maxHeight: 22)
    }
}
