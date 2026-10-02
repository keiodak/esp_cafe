// ContentView.swift — Fourses (k.odk)
// (in coco duo: the Fourses app as it is, inside FA — iOS · FOURSES)
// The board over the whole screen; above it the eight horses (TARPTERGE, ARPSERGE), below it STARVE, the filters at
// the end, the level and the board's keys; the panel (◌ ◉, presets, camera) rises over the board's foot.

import Combine
import SwiftUI

extension FA {
/// made once (the first time iOS · FOURSES is shown): the state and what drives the circuit. In coco duo its Cafes
/// are coco duo's own (CafeLink.swift: the cup links the ones coco duo is linked to)
final class AppModel: ObservableObject {
    let rig = Rig()
    private let units: [CafeUnit]
    private var made: Director?
    init(units: [CafeUnit]) { self.units = units }
    var director: Director { if let d = made { return d }; let d = Director(rig: rig, units: units); made = d; return d }
    /// sounding (and its Cafes' ASH) only while it is on the screen
    func setActive(_ on: Bool) { if on { director.setActive(true) } else { made?.setActive(false) } }
}

/// coco duo's pad area: the Fourses app's screen
struct Embedded: View {
    let model: AppModel
    var body: some View { ContentView(rig: model.rig, d: model.director, embedded: true) }
}

/// the one measure everything is set on
enum Look {
    /// the ground the board lies on (a shade under its paper)
    static let ground = Color(hex: 0xDDD4C3)                    // (a warm beige)
    static let gutter: CGFloat = 12
    static let label: CGFloat = 6.5
    static let hairline = FrBoard.ink.opacity(0.12)
}

struct ContentView: View {
    @ObservedObject var rig: Rig
    let d: Director
    /// inside coco duo (between its bars): no margins for the home bar
    var embedded = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 3) {
                // above: STARVE, the keys, VOLUME — then DRAW's tools, the mode, DUB
                BottomBar(d: d, rig: rig)
                    .frame(height: 32)
                BoardToolbar(d: d, rig: rig)
                    .frame(height: 26)
                // the board: a sheet of paper on the ground
                FoursesBoard(d: d, rig: rig, live: rig.live, cam: d.camera, light: d.camera.state)
                    .overlay(alignment: .bottom) {
                        if rig.panelOpen {
                            SettingsPanel(d: d, rig: rig, cam: d.camera)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        CafeOverlay(rig: rig, cafe: d.cafe)
                    }
                    .clipShape(Rectangle())                                   // (square, a drawing sheet)
                    .overlay(PadFrame().allowsHitTesting(false))
                // below: the eight horses
                TopBar(d: d, rig: rig)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)                                    // (the horses' room, the pad's foot a little higher)
            }
            .padding(.top, embedded ? 0 : 10)                              // (the whole a little lower: into the foot's margin)
            .padding(.bottom, embedded ? 0 : 16)                           // (the foot's knobs clear of the home bar)
            .padding(.horizontal, embedded ? 4 : max(Look.gutter, geo.safeAreaInsets.leading * 0.5))
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Look.ground.ignoresSafeArea())
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)                                  // (a knob at the foot is turned, not taken for the home swipe)
    }
}

// MARK: - below: the eight horses

struct TopBar: View {
    let d: Director
    @ObservedObject var rig: Rig
    var body: some View {
        HStack(spacing: 0) {
            HorseGroup(d: d, rig: rig, name: "ARP", ink: FrBoard.blue, horses: 4..<8)
            Spacer().frame(width: 8)
            HorseGroup(d: d, rig: rig, name: "TARP", ink: FrBoard.ink, horses: 0..<4)
        }
    }
}

/// a board's four horses behind its name
struct HorseGroup: View {
    let d: Director
    @ObservedObject var rig: Rig
    let name: String
    let ink: Color
    let horses: Range<Int>
    var body: some View {
        HStack(spacing: 0) {
            Text(name)                                                     // (its name, upright: read bottom to top)
                .font(.hud(8, .semibold))
                .tracking(1.0)
                .foregroundStyle(ink)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 12)
                .frame(maxHeight: .infinity)
                .faGridCell(pad: 2)
            ForEach(horses, id: \.self) { h in HorseSlider(d: d, rig: rig, h: h, tint: ink).faGridCell(pad: 5) }
        }
    }
}

/// a board's name
struct BoardTag: View {
    let text: String
    let fill: Color
    var body: some View {
        Text(text)
            .font(.hud(7, .semibold))
            .tracking(0.8)
            .foregroundStyle(FrBoard.paper)
            .frame(width: 34, height: 16)
            .background(Capsule().fill(fill))
    }
}

/// one horse: its LED, its range (a tap: the next), its pot
struct HorseSlider: View {
    let d: Director
    @ObservedObject var rig: Rig
    let h: Int
    let tint: Color
    var body: some View {
        HStack(spacing: 4) {
            FrLed(meters: rig.meters, h: h)                                 // (its LED apart, at the knob's upper left)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.trailing, -3)
            Knob(value: rig.frPots[h], tint: tint, size: 30) { d.setFrPot(h, $0) }
            let rc: Color = [FrBoard.green, FrBoard.blue, Color(hex: 0xD9731F)][rig.frRanges[h]]   // (CV green · LOW blue · AUD orange)
            Text(["CV", "LOW", "AUD"][rig.frRanges[h]])                      // (a square key: its colour in the edge and the name)
                .font(.hud(6.5, .semibold))
                .foregroundStyle(rc)
                .frame(width: 19, height: 19)
                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(rc, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { d.setFrRange(h, (rig.frRanges[h] + 2) % 3) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - above: STARVE, the keys, VOLUME

struct BottomBar: View {
    let d: Director
    @ObservedObject var rig: Rig
    var body: some View {
        HStack(spacing: 0) {                                            // (STARVE and VOLUME alike: the keys between, CLEAR in the middle)
            MeteredLabel(label: "STARVE", meters: rig.meters, kind: 0) {
                ColorSlider(value: rig.frStarve, tint: FrBoard.yellow, mark: FrBoard.ink, center: true) { d.setFrStarve($0) }
            }
            .frame(maxWidth: 170)
            .faGridCell()
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {                                        // (both sides alike wide: CLEAR in the middle)
                HStack(spacing: 4) {
                    KeyPill(label: "RANDOM", ink: FrBoard.red) { d.frRandom() }
                    KeyPill(label: "SORT", ink: Color(hex: 0xD9731F)) { d.frSort() }
                }
                .frame(width: 152, alignment: .trailing)
                KeyPill(label: "CLEAR", ink: FrBoard.ink) { d.frClearShapes() }
                HStack(spacing: 4) {
                    KeyPill(label: "PANEL", on: rig.panelOpen, ink: FrBoard.green) { withAnimation(.easeOut(duration: 0.2)) { rig.panelOpen.toggle(); if rig.panelOpen { d.cafe.panelOpen = false } } }
                    CamKey(d: d, cam: d.camera)
                    CafeKey(d: d, rig: rig, cafe: d.cafe)
                }
                .frame(width: 152, alignment: .leading)
            }
            .fixedSize()
            MeteredLabel(label: "VOLUME", meters: rig.meters, kind: 1) {
                ColorSlider(value: rig.level, tint: FrBoard.red, mark: FrBoard.ink) { d.setLevel($0) }
            }
            .frame(maxWidth: 170)
            .faGridCell()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// a short upright hairline between groups
struct Divider1: View {
    var body: some View { Rectangle().fill(Look.hairline).frame(width: 1, height: 24) }
}

/// a name over its control, a fine meter beside the name (cold to warm): STARVE the supply, VOLUME the output
struct MeteredLabel<Content: View>: View {
    /// cold to warm in quiet colours, as the sliders': slate · sage · mustard · brick
    static func calm(_ a: Double) -> Color {
        let stops: [(Double, Double, Double)] = [(0x5E, 0x7F, 0x9A), (0x76, 0x9A, 0x86), (0xC9, 0xA1, 0x4A), (0xC0, 0x57, 0x3A)]
        let x: Double = min(1, max(0, a)) * Double(stops.count - 1)
        let i: Int = min(stops.count - 2, Int(x))
        let f: Double = x - Double(i)
        let p = stops[i], q = stops[i + 1]
        let r: Double = (p.0 + (q.0 - p.0) * f) / 255
        let g: Double = (p.1 + (q.1 - p.1) * f) / 255
        let b: Double = (p.2 + (q.2 - p.2) * f) / 255
        return Color(red: r, green: g, blue: b)
    }

    let label: String
    @ObservedObject var meters: Meters
    let kind: Int
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.hud(Look.label, .semibold))
                    .tracking(0.4)
                    .foregroundStyle(FrBoard.ink)
                DotMeter(meters: meters, kind: kind)
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
            }
            content()
        }
    }
}

/// the pad's frame, as a drawing sheet's: a fine edge, rulers along it (a tick each 1/48 across, 1/24 down, longer
/// each eighth), solid marks at the corners, its name small in the upper right
struct PadFrame: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { ctx, s in
                let ink = FrBoard.ink
                ctx.stroke(Path(CGRect(origin: .zero, size: s).insetBy(dx: 0.4, dy: 0.4)), with: .color(ink.opacity(0.45)), lineWidth: 0.8)
                var ticks = Path()
                for k in 1..<48 {
                    let x: CGFloat = s.width * CGFloat(k) / 48
                    let l: CGFloat = k % 6 == 0 ? 6 : 3
                    ticks.move(to: CGPoint(x: x, y: 0)); ticks.addLine(to: CGPoint(x: x, y: l))
                    ticks.move(to: CGPoint(x: x, y: s.height)); ticks.addLine(to: CGPoint(x: x, y: s.height - l))
                }
                for k in 1..<24 {
                    let y: CGFloat = s.height * CGFloat(k) / 24
                    let l: CGFloat = k % 6 == 0 ? 6 : 3
                    ticks.move(to: CGPoint(x: 0, y: y)); ticks.addLine(to: CGPoint(x: l, y: y))
                    ticks.move(to: CGPoint(x: s.width, y: y)); ticks.addLine(to: CGPoint(x: s.width - l, y: y))
                }
                ctx.stroke(ticks, with: .color(ink.opacity(0.35)), lineWidth: 0.5)
                let m: CGFloat = 5                                          // (the corners: solid squares)
                for c in [CGPoint(x: 0, y: 0), CGPoint(x: s.width - m, y: 0), CGPoint(x: 0, y: s.height - m), CGPoint(x: s.width - m, y: s.height - m)] {
                    ctx.fill(Path(CGRect(x: c.x, y: c.y, width: m, height: m)), with: .color(ink.opacity(0.8)))
                }
                // a crosshair at the middle of each side
                var cross = Path()
                cross.move(to: CGPoint(x: s.width / 2 - 5, y: 10)); cross.addLine(to: CGPoint(x: s.width / 2 + 5, y: 10))
                cross.move(to: CGPoint(x: s.width / 2, y: 5)); cross.addLine(to: CGPoint(x: s.width / 2, y: 15))
                cross.move(to: CGPoint(x: s.width / 2 - 5, y: s.height - 10)); cross.addLine(to: CGPoint(x: s.width / 2 + 5, y: s.height - 10))
                cross.move(to: CGPoint(x: s.width / 2, y: s.height - 5)); cross.addLine(to: CGPoint(x: s.width / 2, y: s.height - 15))
                ctx.stroke(cross, with: .color(ink.opacity(0.4)), lineWidth: 0.5)
            }
            Text("FOURSES  ·  No.4")
                .font(.hud(6, .semibold))
                .tracking(1.2)
                .foregroundStyle(FrBoard.ink.opacity(0.45))
                .padding(.top, 9).padding(.trailing, 12)
        }
    }
}

/// the grid (マス目): each group in its own cell, a fine line round it — the cells meet edge to edge
struct GridCell: ViewModifier {
    var pad: CGFloat = 7
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, pad)
            .padding(.vertical, 3)
            .frame(maxHeight: .infinity)                                   // (no line round it now: only its room)
    }
}

/// a row of dots out to the slider's right end, lit as far as it reads, each its own colour (cold → warm):
/// STARVE the supply (3 … 12 V), VOLUME the output's level (−36 … 0 dB)
struct DotMeter: View {
    @ObservedObject var meters: Meters
    let kind: Int
    var body: some View {
        let v: Double = kind == 0
            ? min(1, max(0, (meters.supply - 3.0) / 9.0))
            : (meters.level > 0.0001 ? min(1, max(0, (20 * log10(meters.level) + 36) / 36)) : 0)
        Canvas { ctx, s in
            let n: Int = max(4, Int(s.width / 6))
            let step: CGFloat = s.width / CGFloat(n)
            for k in 0..<n {
                let f: Double = (Double(k) + 0.5) / Double(n)
                let c = CGPoint(x: step * (CGFloat(k) + 0.5), y: s.height / 2)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)),
                         with: .color(f <= v ? FrBoard.ramp(f) : FrBoard.ink.opacity(0.12)))
            }
        }
    }
}

/// a small name over its control
struct Labeled<Content: View>: View {
    let label: String
    let ink: Color
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.hud(Look.label, .semibold))
                .tracking(0.4)
                .foregroundStyle(ink)
            content()
        }
    }
}

/// a key: a pill (filled when on)
struct KeyPill: View {
    let label: String
    var on = false
    var ink: Color = FrBoard.ink
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.hud(7, .semibold))
                .tracking(0.5)
                .foregroundStyle(on ? FrBoard.paper : ink)
                .lineLimit(1)
                .frame(width: 48, height: 18)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(on ? ink : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// the cup: opens the Cafe panel (link up to two) — filled while one is linked
struct CafeKey: View {
    let d: Director
    @ObservedObject var rig: Rig
    @ObservedObject var cafe: CafeLinks
    var body: some View {
        let ink = Color(hex: 0x8A5A3C)
        let on = cafe.panelOpen
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                cafe.panelOpen.toggle()
                if cafe.panelOpen { rig.panelOpen = false }                       // (one panel at a time)
            }
        } label: {
            Image(systemName: cafe.anyLinked ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(on ? FrBoard.paper : ink)
                .frame(width: 18, height: 18)                                   // (a small square)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(on ? ink : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// the Cafe panel over the board's foot, while the cup is on (PANEL's place: one at a time)
struct CafeOverlay: View {
    @ObservedObject var rig: Rig
    @ObservedObject var cafe: CafeLinks
    var body: some View {
        if cafe.panelOpen && !rig.panelOpen {
            CafePanel(cafe: cafe).transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// the Cafe panel: A and B (each its Cafe, its firmware, LET GO), and the Cafes in reach (each to A or B)
struct CafePanel: View {
    @ObservedObject var cafe: CafeLinks
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // (coco duo's Cafes A / B: linked by coco duo itself — here only LINK / LET GO)
            ForEach(cafe.slots, id: \.slot) { s in CafeSlotColumn(s: s, holdMs: cafe.holdMs, letGo: { cafe.unlink(s.slot) }, link: { cafe.relink(s.slot) }) }
            PanelColumn(title: "ASH", ink: Color(hex: 0x8A5A3C)) {            // how the terminals go out
                Labeled(label: "SPREAD", ink: FrBoard.ink) { ColorSlider(value: cafe.spread, tint: Color(hex: 0x8A5A3C), mark: FrBoard.ink) { cafe.spread = $0 } }
                Labeled(label: "SMOOTH", ink: FrBoard.ink) { ColorSlider(value: cafe.smooth, tint: Color(hex: 0xB4875C), mark: FrBoard.ink) { cafe.smooth = $0 } }
            }
            .frame(width: 110)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(FrBoard.paper).shadow(color: .black.opacity(0.14), radius: 10, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Look.hairline, lineWidth: 1))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

/// ASH's last ~2 s: a line on a small ruled strip (0 at the bottom, the top of its range at the top)
struct AshScope: View {
    let trace: [Double]
    let ink: Color
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(FrBoard.ink.opacity(0.04)))
            var grid = Path()
            for k in 1..<4 { let y = s.height * CGFloat(k) / 4; grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: s.width, y: y)) }
            ctx.stroke(grid, with: .color(FrBoard.ink.opacity(0.1)), lineWidth: 0.5)
            ctx.stroke(Path(CGRect(origin: .zero, size: s).insetBy(dx: 0.25, dy: 0.25)), with: .color(FrBoard.ink.opacity(0.3)), lineWidth: 0.5)
            guard trace.count > 1 else { return }
            let step = s.width / CGFloat(119)
            let x0 = s.width - CGFloat(trace.count - 1) * step
            var p = Path()
            for (i, v) in trace.enumerated() {
                let pt = CGPoint(x: x0 + CGFloat(i) * step, y: (1 - CGFloat(v)) * (s.height - 2) + 1)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(ink), lineWidth: 1.2)
        }
    }
}

/// one slot: CAFE A / B — its Cafe (or —), its firmware, LET GO
struct CafeSlotColumn: View {
    @ObservedObject var s: CafeSlot
    /// SYNC: how long the phone is held back to meet the Cafes' ASH (by itself, while linked)
    let holdMs: Int
    let letGo: () -> Void
    var link: () -> Void = {}
    var body: some View {
        let ink = Color(hex: s.slot == 0 ? 0x8A5A3C : 0xB4875C)
        PanelColumn(title: "☕ CAFE " + ["A", "B"][s.slot], ink: ink) {
            Text(s.state == .off ? (s.available ? (s.name.isEmpty ? "Cafe" : s.name) + " · LET GO" : "— (not linked to coco duo)") : (s.name.isEmpty ? "Cafe" : s.name) + (s.linked ? "" : " · LINKING…"))
                .font(.hud(7, .semibold)).foregroundStyle(FrBoard.ink).lineLimit(1)
            if s.linked {
                let old = (Double(s.fw) ?? 0) < 4.70
                Text(s.fw.isEmpty ? "ASH ← CAFE " + ["A", "B"][s.slot] : "v\(s.fw)" + (old ? " · ASH NEEDS 4.70" : " · ASH ← CAFE " + ["A", "B"][s.slot]))
                    .font(.hud(6, .semibold)).tracking(0.3).foregroundStyle(old ? FrBoard.red : FrBoard.gray).lineLimit(1)
            }
            if s.linked {
                AshScope(trace: s.trace, ink: ink)                              // what goes out of its ASH
                    .frame(width: 118, height: 26)
                Text("ASH \(Int((s.trace.last ?? 0) * 100))%")
                    .font(.hud(6, .semibold)).tracking(0.3).foregroundStyle(ink)
                Text("SYNC iOS +\(holdMs) ms" + (s.lagMs > 0 ? " · BT \(Int(s.lagMs)) ms" : ""))
                    .font(.hud(6, .semibold)).tracking(0.3).foregroundStyle(FrBoard.blue).lineLimit(1)
            }
            if s.state != .off { KeyPill(label: "LET GO", ink: ink, action: letGo) }
            else if s.available { KeyPill(label: "LINK", ink: ink, action: link) }
        }
        .frame(width: 130)
    }
}

/// the camera, on or off
struct CamKey: View {
    let d: Director
    @ObservedObject var cam: FrCamera
    var body: some View {
        KeyPill(label: "CAM", on: cam.enabled, ink: FrBoard.blue) { d.setCamera(!cam.enabled) }
    }
}

// MARK: - the panel: flicker and sway, the presets, the camera

struct SettingsPanel: View {
    let d: Director
    @ObservedObject var rig: Rig
    @ObservedObject var cam: FrCamera
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            PanelColumn(title: "◌ FLICKER", ink: FrBoard.red) {
                Labeled(label: "SPEED", ink: FrBoard.ink) { ColorSlider(value: rig.flickRate, tint: FrBoard.red, mark: FrBoard.ink, center: true) { rig.flickRate = $0 } }
                Labeled(label: "DEPTH", ink: FrBoard.ink) { ColorSlider(value: rig.flickDepth, tint: FrBoard.red, mark: FrBoard.ink) { rig.flickDepth = $0 } }
            }
            PanelColumn(title: "◉ SWAY", ink: FrBoard.blue) {
                Labeled(label: "SPEED", ink: FrBoard.ink) { ColorSlider(value: rig.swayRate, tint: FrBoard.blue, mark: FrBoard.ink, center: true) { rig.swayRate = $0 } }
                Labeled(label: "REACH", ink: FrBoard.ink) { ColorSlider(value: rig.swayReach, tint: FrBoard.blue, mark: FrBoard.ink) { rig.swayReach = $0 } }
            }
            PanelColumn(title: "PRESET", ink: FrBoard.ink) {
                VStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(1...4, id: \.self) { c in
                                PresetDot(n: row * 4 + c, kept: rig.presetsKept.contains(row * 4 + c), current: rig.preset == row * 4 + c)
                                    .onTapGesture { d.presetTap(row * 4 + c) }
                                    .onLongPressGesture(minimumDuration: 0.6) { d.presetKeep(row * 4 + c) }
                            }
                        }
                    }
                }
                Text("TAP LOAD · HOLD KEEP")
                    .font(.hud(5.5, .semibold))
                    .tracking(0.4)
                    .foregroundStyle(FrBoard.gray)
            }
            .frame(width: 118)
            PanelColumn(title: "CAMERA", ink: FrBoard.green) {
                HStack(spacing: 4) {
                    KeyPill(label: cam.enabled ? "ON" : "OFF", on: cam.enabled, ink: FrBoard.green) { d.setCamera(!cam.enabled) }
                    KeyPill(label: cam.front ? "FRONT" : "BACK", ink: FrBoard.green) { cam.front.toggle() }
                }
                HStack(spacing: 4) {
                    KeyPill(label: "INIT", ink: FrBoard.blue) { d.frDefault() }
                    KeyPill(label: "RESET", ink: FrBoard.red) { d.reset() }
                }
            }
            .frame(width: 108)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(FrBoard.paper).shadow(color: .black.opacity(0.14), radius: 10, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Look.hairline, lineWidth: 1))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

/// a column of the panel: a coloured name, then its controls
struct PanelColumn<Content: View>: View {
    let title: String
    let ink: Color
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.hud(7.5, .semibold))
                .tracking(0.6)
                .foregroundStyle(ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// a preset's number: filled when something is kept there, red when it is the one now
struct PresetDot: View {
    let n: Int
    let kept: Bool
    let current: Bool
    var body: some View {
        Text("\(n)")
            .font(.hud(7.5, .semibold))
            .foregroundStyle(kept ? FrBoard.paper : FrBoard.ink.opacity(0.6))
            .frame(width: 22, height: 22)
            .background(Circle().fill(kept ? (current ? FrBoard.red : FrBoard.ink) : Color.clear))
            .overlay(Circle().strokeBorder(current ? FrBoard.red : FrBoard.ink.opacity(0.35), lineWidth: 1))
            .contentShape(Circle())
    }
}

/// a slider: a thin line in its colour, a round mark
struct ColorSlider: View {
    let value: Double
    let tint: Color
    let mark: Color
    var center = false
    let set: (Double) -> Void
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, y = g.size.height / 2
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16)).frame(height: 2)
                Capsule().fill(tint).frame(width: max(2, w * value), height: 2)
                if center {
                    Rectangle().fill(tint.opacity(0.4)).frame(width: 1, height: 7).position(x: w * 0.5, y: y)
                }
                Circle().fill(mark).frame(width: 10, height: 10)
                    .position(x: w * value, y: y)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { e in
                set(min(1, max(0, e.location.x / max(1, w))))
            })
        }
        .frame(height: 12)
    }
}

/// a knob: turned by dragging up (more) or down (less); a ring in its colour as far as it is turned, a line its pointer
struct Knob: View {
    let value: Double
    let tint: Color
    var size: CGFloat = 30
    let set: (Double) -> Void
    @State private var from: Double? = nil
    var body: some View {
        let v: Double = min(1, max(0, value))
        let a0: Double = 0.375, span: Double = 0.75                     // (from 7 o'clock round to 5)
        let ang: Double = (a0 + span * v) * 2 * .pi
        let r: CGFloat = size / 2
        let cx: CGFloat = CGFloat(cos(ang)), cy: CGFloat = CGFloat(sin(ang))
        let ring: CGFloat = r * 0.74                                      // (a fine ring; the ticks round it)
        let pointerX: CGFloat = r + cx * ring * 0.72
        let pointerY: CGFloat = r + cy * ring * 0.72
        ZStack {
            // the scale: dots round it, as the meters' — lit as far as it is turned, each its own colour (cold → warm)
            ForEach(0..<11, id: \.self) { k in
                let f: Double = Double(k) / 10
                let a: Double = (a0 + span * f) * 2 * .pi
                let rd: CGFloat = r * 0.9
                let len: CGFloat = max(4, size * 0.16)                       // (a slender mark, pointing out)
                let wid: CGFloat = max(1.4, size * 0.045)
                let turn: Double = a + .pi / 2
                let px: CGFloat = r + CGFloat(cos(a)) * rd
                let py: CGFloat = r + CGFloat(sin(a)) * rd
                let lit: Bool = f <= v + 0.001
                let ink: Color = lit ? FrBoard.ink : FrBoard.ink.opacity(0.15)   // (black as far as it is turned, pale grey on)
                Capsule()
                    .fill(ink)
                    .frame(width: wid, height: len)
                    .rotationEffect(.radians(turn))
                    .position(x: px, y: py)
            }
            Circle().stroke(FrBoard.ink, lineWidth: 0.8)
                .frame(width: ring * 2, height: ring * 2)
            Circle()                                                      // (the pointer: a dot)
                .fill(tint)
                .frame(width: r * 0.15, height: r * 0.15)
                .position(x: pointerX, y: pointerY)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { e in
                if from == nil { from = v }
                let dv = Double(-e.translation.height + e.translation.width * 0.5) / 140
                set(min(1, max(0, (from ?? v) + dv)))
            }
            .onEnded { _ in from = nil })
    }
}

/// a knob's pointer: a small triangle, its point up (turned to face out)
struct KnobPointer: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// the supply now (STARVE sags it under the load)
struct SupplyReadout: View {
    @ObservedObject var meters: Meters
    var body: some View {
        Text(String(format: "%.1fV", meters.supply))
            .font(.hud(6.5, .semibold))
            .foregroundStyle(FrBoard.gray)
    }
}
}

extension View {
    func faGridCell(pad: CGFloat = 7) -> some View { modifier(FA.GridCell(pad: pad)) }
}
