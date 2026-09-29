// NobsBoard.swift — coco duo (k.odk)
// The big knob (turned by dragging round it) and the plain slider — STUBER's wheels and resonance knobs.
import SwiftUI

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
