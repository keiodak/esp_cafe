// ContentView.swift — coco duo (k.odk)
// Top row = Cafe A, bottom row = Cafe B. Four pads each:
//   LOOP   X = where the loop starts      Y = how long it is (short = scratchy)
//   SPEED  X = speed (centre = stop, right = forward, left = backward)   Y = overdub
//   FOLD   X = fold amount                Y = bias
//   DELAY  X = time                       Y = amount (feedback + wet)

import SwiftUI
import UIKit

enum PadKind: Int, CaseIterable {
    case loop, speed, fold, delay
    var title: String { ["LOOP", "SPEED", "FOLD", "DELAY"][rawValue] }
    /// where the pointer sits before you touch it
    var start: (Double, Double) { [(0, 1), (0.75, 0), (0, 0.5), (0.3, 0)][rawValue] }

    /// pad position -> lines for the Cafe
    func commands(_ x: Double, _ y: Double) -> [String] {
        switch self {
        case .loop:
            let len = 512 + Int(y * y * Double(TAPE - 512))
            var a = Int(x * Double(TAPE))
            let b = min(TAPE, a + len)
            if b - a < 512 { a = b - 512 }
            return ["L \(a) \(b)"]
        case .speed:
            let v = (x - 0.5) * 2
            let milli = abs(v) < 0.04 ? 0 : Int((v < 0 ? -1 : 1) * 4000 * v * v)   // 1x at three quarters
            return ["S \(milli)", "X 2 \(Int(y * 1000))"]
        case .fold:
            return ["X 0 \(Int(x * 1000))", "X 1 \(Int((y * 2 - 1) * 1000))"]
        case .delay:
            return ["X 3 \(Int(x * 1000))", "X 4 \(Int(y * 1000))"]
        }
    }
}

final class PadAxis: ObservableObject {
    @Published var x: Double
    @Published var y: Double
    init(_ p: (Double, Double)) { x = p.0; y = p.1 }
}

struct ContentView: View {
    @StateObject private var hub = CafeHub()
    /// 8 pads: 0–3 = Cafe A, 4–7 = Cafe B
    @StateObject private var padBank = PadBank()
    @StateObject private var camera = CameraRig()
    /// the preset from the phone, and inside duo: LOOP or GRAIN (each has its own 8 pads)
    @StateObject private var grain = GrainMode()
    @State private var padHeight: CGFloat = 122
    @State private var showCafes = false
    @State private var showWave = false
    @State private var safeLeading: CGFloat = 0
    @State private var safeTrailing: CGFloat = 0
    private let rowHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: 8) {
            CafeRow(unit: hub.units[0], camera: camera, grain: grain, hub: hub, showCafes: $showCafes, showWave: $showWave,
                    toggleMode: { Self.setMode((grain.mode + 1) % 3, hub: hub, bank: padBank, grain: grain, camera: camera) })
                .frame(height: rowHeight)

            VStack(spacing: 6) {
                HStack(spacing: 6) { ForEach(0..<4, id: \.self) { pad($0) } }
                HStack(spacing: 6) { ForEach(4..<8, id: \.self) { pad($0) } }
            }
            .frame(maxHeight: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { padHeight = max(60, (geo.size.height - 6) / 2) }
                        .onChange(of: geo.size) { _, s in padHeight = max(60, (s.height - 6) / 2) }
                }
            )

            CafeRow(unit: hub.units[1], camera: camera, grain: grain, hub: hub, showCafes: $showCafes, showWave: $showWave,
                    toggleMode: { Self.setMode((grain.mode + 1) % 3, hub: hub, bank: padBank, grain: grain, camera: camera) })
                .frame(height: rowHeight)
        }
        .padding(8)
        .padding(.leading, max(0, safeTrailing - safeLeading))
        .padding(.trailing, max(0, safeLeading - safeTrailing))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PastelTheme.screenBackdrop.ignoresSafeArea())
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        readSafeArea()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { readSafeArea() }
                    }
                    .onChange(of: geo.size) { _, _ in readSafeArea() }
            }
            .ignoresSafeArea()
        )
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .sheet(isPresented: $showCafes) {
            CafesView(hub: hub, camera: camera, grain: grain,
                      setMode: { on in Self.setMode(on, hub: hub, bank: padBank, grain: grain, camera: camera) },
                      setPreset: { n in Self.setPreset(n, hub: hub, bank: padBank, grain: grain) })
        }
        .sheet(isPresented: $showWave) { WaveView(hub: hub) }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            // when a Cafe (re)connects, give it the pads' current positions
            let bank = padBank
            let mo = grain
            let both = hub.units
            for u in hub.units {
                // (re)connected: put the Cafe on the right preset, then give it every pad's position.
                // In GRAIN, once both are there, start their score together.
                u.onReady = { [weak u] in
                    guard let u else { return }
                    Self.sendAll(to: u, bank: bank, grain: mo)
                    if mo.mode != 0 && both.allSatisfy({ $0.isConnected }) { mo.sync(both) }
                }
            }
            // camera mode moves the pads of the current mode: send each move
            let units = hub.units
            camera.axes = Self.axes(for: grain, bank: bank)
            camera.onPadMoved = { i in Self.padMoved(i, bank: bank, grain: mo, units: units) }
            camera.warm()
        }
    }

    @ViewBuilder private func pad(_ i: Int) -> some View {
        let bank = padBank, mo = grain, units = hub.units
        if grain.isBj {
            DuoPad(axis: grain.bjAxes[i], title: BjPad(rawValue: i)!.title,
                   send: { _, _ in Self.padMoved(i, bank: bank, grain: mo, units: units) },
                   trace: nil,
                   cam: camera.state, cameraMode: camera.enabled, index: i,
                   padHeight: padHeight, corners: Self.corners(i))
                .frame(height: padHeight)
                .id("bj\(i)")
        } else if grain.on {
            DuoPad(axis: grain.axes[i], title: GrainPad(rawValue: i)!.title,
                   send: { _, _ in Self.padMoved(i, bank: bank, grain: mo, units: units) },
                   trace: nil,
                   cam: camera.state, cameraMode: camera.enabled, index: i,
                   padHeight: padHeight, corners: Self.corners(i))
                .frame(height: padHeight)
                .id("grain\(i)")
        } else {
            let kind = PadKind(rawValue: i % 4)!
            let unit = hub.units[i / 4]
            DuoPad(axis: padBank.axes[i], title: kind.title,
                   send: { _, _ in Self.padMoved(i, bank: bank, grain: mo, units: units) },
                   trace: kind == .loop ? AnyView(LoopTrace(scope: unit.scope, unit: unit)) : nil,
                   cam: camera.state, cameraMode: camera.enabled, index: i,
                   padHeight: padHeight, corners: Self.corners(i))
                .frame(height: padHeight)
                .id("duo\(i)")
        }
    }

    /// a pad moved (finger or camera): DUO pads go to their own Cafe, GRAIN pads to both
    static func padMoved(_ i: Int, bank: PadBank, grain: GrainMode, units: [CafeUnit]) {
        if grain.isBj {
            for u in units { grain.bjCommands(pad: i, slot: u.slot).forEach(u.send) }
        } else if grain.on {
            let resync = i == GrainPad.stereo.rawValue && grain.separationReturned()
            for u in units { grain.commands(pad: i, slot: u.slot).forEach(u.send) }
            if resync { grain.sync(units) }                 // separation back to 0: L and R in step again
        } else {
            let k = PadKind(rawValue: i % 4)!
            let a = bank.axes[i]
            k.commands(a.x, a.y).forEach(units[i / 4].send)
        }
    }

    /// the right preset first; on duo also its mode (LOOP / GRAIN) and all pads of that mode
    static func sendAll(to u: CafeUnit, bank: PadBank, grain: GrainMode) {
        u.send("G \(grain.preset)")
        guard grain.preset == 2 else { return }          // coco / echo don't listen to the pads
        u.send("M 25 \(grain.mode)")
        if grain.isBj {
            grain.bjAllCommands(slot: u.slot).forEach(u.send)
        } else if grain.on {
            grain.allCommands(slot: u.slot).forEach(u.send)
        } else {
            for k in PadKind.allCases {
                let a = bank.axes[u.slot * 4 + k.rawValue]
                k.commands(a.x, a.y).forEach(u.send)
            }
        }
    }

    /// LOOP / GRAIN / BENJOLIN (inside the duo preset): switch both Cafes and the camera's pads
    static func setMode(_ m: Int, hub: CafeHub, bank: PadBank, grain: GrainMode, camera: CameraRig) {
        grain.mode = m
        grain.preset = 2
        camera.axes = axes(for: grain, bank: bank)
        for u in hub.units where u.isConnected { sendAll(to: u, bank: bank, grain: grain) }
        if m != 0 { grain.sync(hub.units) }                 // both start together (grain score / benjolin)
    }

    /// the 8 pads the camera moves in the current mode
    static func axes(for grain: GrainMode, bank: PadBank) -> [PadAxis] {
        grain.isBj ? grain.bjAxes : (grain.on ? grain.axes : bank.axes)
    }

    /// a preset for both Cafes, from the phone (1 coco · 2 echo · 3 duo)
    static func setPreset(_ n: Int, hub: CafeHub, bank: PadBank, grain: GrainMode) {
        grain.preset = n
        for u in hub.units where u.isConnected { sendAll(to: u, bank: bank, grain: grain) }
        if n == 2 && grain.mode != 0 { grain.sync(hub.units) }
    }

    private func readSafeArea() {
        let win = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        let i = win?.safeAreaInsets ?? .zero
        safeLeading = i.left
        safeTrailing = i.right
    }

    /// 8 pads as 4 × 2: round only the outer corners
    static func corners(_ i: Int) -> RectangleCornerRadii {
        let r: CGFloat = 16
        let col = i % 4, row = i / 4
        return .init(topLeading: (col == 0 && row == 0) ? r : 0,
                     bottomLeading: (col == 0 && row == 1) ? r : 0,
                     bottomTrailing: (col == 3 && row == 1) ? r : 0,
                     topTrailing: (col == 3 && row == 0) ? r : 0)
    }
}

final class PadBank: ObservableObject {
    let axes: [PadAxis] = (0..<8).map { PadAxis(PadKind(rawValue: $0 % 4)!.start) }
}

// MARK: - one pad

private struct DuoPad: View {
    @ObservedObject var axis: PadAxis
    let title: String
    let send: (Double, Double) -> Void
    let trace: AnyView?
    @ObservedObject var cam: CameraState
    let cameraMode: Bool
    let index: Int
    let padHeight: CGFloat
    let corners: RectangleCornerRadii

    /// edge darkens with movement in front of the camera (same as Þunresdæg)
    private var edgeGlow: Double {
        guard cameraMode else { return 0 }
        return min(max((cam.cameraMotion - 0.05) / 0.22, 0), 1)
    }

    /// this pad's 4 × 4 cells of the 8 × 16 mosaic
    private var block: [[Double]] {
        let g = cam.mosaicBrightness
        let r0 = (index / 4) * 4, c0 = (index % 4) * 4
        guard g.count >= r0 + 4, g[0].count >= c0 + 4 else { return Array(repeating: Array(repeating: 0.5, count: 4), count: 4) }
        return (0..<4).map { r in (0..<4).map { c in g[r0 + r][c0 + c] } }
    }

    var body: some View {
        XYPad(
            label: "", xLabel: "", yLabel: "",
            x: $axis.x, y: $axis.y,
            padHeight: padHeight,
            interactionEnabled: !cameraMode,
            onDrag: { x, y in send(x, y) },
            cornerRadii: corners,
            trace: cameraMode ? nil : trace,
            mosaic: cameraMode ? block : nil,
            edgeGlow: edgeGlow,
            cameraMode: cameraMode
        )
        .overlay(alignment: .topLeading) {
            Text(title)
                .font(.system(size: 7, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(PastelTheme.textPrimary.opacity(0.55))
                .padding(.leading, corners.topLeading > 0 || corners.bottomLeading > 0 ? 12 : 8)
                .padding(.top, 7)
                .allowsHitTesting(false)
        }
    }
}

/// Inside the LOOP pad: the Cafe's tape (left = start of the buffer), the loop, and the play head.
private struct LoopTrace: View {
    @ObservedObject var scope: CafeScope
    @ObservedObject var unit: CafeUnit

    var body: some View {
        Canvas { ctx, size in
            let inset = XYPad.pointerInset
            let w = size.width - inset * 2, h = size.height
            let x = { (s: Int) -> CGFloat in inset + CGFloat(s) / CGFloat(TAPE) * w }
            // loop band
            let lx = x(unit.ls), rx = x(unit.le)
            ctx.fill(Path(CGRect(x: lx, y: 0, width: max(1, rx - lx), height: h)),
                     with: .color(PastelTheme.textPrimary.opacity(0.10)))
            // tape overview
            let bw = w / CGFloat(BINS)
            var wave = Path()
            for i in 0..<BINS {
                let top = h * 0.5 - (CGFloat(scope.maxs[i]) - 128) / 128 * h * 0.42
                let bot = h * 0.5 - (CGFloat(scope.mins[i]) - 128) / 128 * h * 0.42
                wave.addRect(CGRect(x: inset + CGFloat(i) * bw, y: min(top, bot),
                                    width: max(0.6, bw * 0.8), height: max(0.6, abs(bot - top))))
            }
            ctx.fill(wave, with: .color(PastelTheme.textPrimary.opacity(0.30)))
            // heads: record (thin, faint) and play (full ink)
            ctx.fill(Path(CGRect(x: x(scope.rec) - 0.5, y: 0, width: 1, height: h)),
                     with: .color(PastelTheme.recording.opacity(0.7)))
            ctx.fill(Path(CGRect(x: x(scope.play) - 0.75, y: 0, width: 1.5, height: h)),
                     with: .color(PastelTheme.textPrimary.opacity(0.8)))
        }
    }
}

// MARK: - top / bottom row (one Cafe each)

private struct CafeRow: View {
    @ObservedObject var unit: CafeUnit
    @ObservedObject var camera: CameraRig
    @ObservedObject var grain: GrainMode
    let hub: CafeHub
    @Binding var showCafes: Bool
    @Binding var showWave: Bool
    /// LOOP <-> GRAIN (the bottom-left key)
    let toggleMode: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 16) {
                if unit.slot == 0 {
                    // top-left: connected? (tap = the Cafes panel)
                    iconButton("dot.radiowaves.left.and.right", on: unit.isConnected) { showCafes = true }
                } else {
                    // bottom-left: the mode. The picture shows the mode you're in
                    iconButton(GrainMode.modeIcons[grain.mode]) { toggleMode() }
                }
                if grain.isBj {
                    // BENJOLIN: top = hold / record the tape (both Cafes), bottom = LOCK the rungler's pattern
                    if unit.slot == 0 {
                        iconButton("record.circle", on: unit.isConnected && unit.recording) {
                            let r = unit.recording ? 0 : 1
                            hub.units.forEach { $0.send("R \(r)") }
                        }
                    } else { iconButton("lock", on: grain.bjLock) { grain.setBjLock(!grain.bjLock, hub.units) } }
                } else if grain.on {
                    // GRAIN: top = FREEZE (hold this moment), bottom = PERCUSSION (struck grains)
                    if unit.slot == 0 { iconButton("snowflake", on: grain.freeze) { grain.setFreeze(!grain.freeze, hub.units) } }
                    else { iconButton("metronome", on: grain.perc) { grain.setPerc(!grain.perc, hub.units) } }
                } else {
                    // DUO: this Cafe's recording on / off
                    iconButton("record.circle", on: unit.isConnected && unit.recording) {
                        unit.send("R \(unit.recording ? 0 : 1)")
                    }
                }
            }
            PositionBar(scope: unit.scope, unit: unit)
            HStack(spacing: 16) {
                // LOOP: play head back to the loop start / GRAIN: mark · sync / BENJOLIN: sync · new pattern
                if grain.isBj {
                    if unit.slot == 0 { iconButton("arrow.triangle.2.circlepath") { grain.sync(hub.units) } }
                    else { iconButton("dice") { grain.bjKick(hub.units) } }
                } else if grain.on {
                    // top: keep the place of the grain just played (a mark) / bottom: put L and R back in step
                    if unit.slot == 0 { iconButton("bookmark", on: grain.useMarks) { grain.mark(hub.units) } }
                    else { iconButton("arrow.triangle.2.circlepath") { grain.sync(hub.units) } }
                } else {
                    iconButton("backward.end") { unit.send("J \(unit.ls)") }
                }
                // top row: the WAVE panel (both tapes) / bottom row: camera mode on / off
                if unit.slot == 0 { iconButton("waveform") { showWave = true } }
                else { iconButton("camera.aperture", on: camera.enabled) { camera.enabled.toggle() } }
            }
        }
    }

    private func iconButton(_ name: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11))
                .foregroundStyle(on ? PastelTheme.selectionText : PastelTheme.iconColor)
                .frame(width: 19, height: 19)
                .background(IconSquare(filled: on))
        }
    }
}

/// The bar between the keys: where the play head is. Drag it to jump.
private struct PositionBar: View {
    @ObservedObject var scope: CafeScope
    @ObservedObject var unit: CafeUnit

    var body: some View {
        CompactSlider(value: Binding(get: { Double(scope.play) / Double(TAPE) },
                                     set: { unit.send("J \(Int($0 * Double(TAPE - 1)))") }),
                      fillColor: PastelTheme.sliderFill,
                      knobColor: PastelTheme.knobColor, thinLine: true)
            .opacity(unit.isConnected ? 1 : 0.35)
    }
}

/// The four corner keys' square (same as the weekday apps).
struct IconSquare: View {
    var filled: Bool = false

    var body: some View {
        Rectangle()
            .fill(filled ? PastelTheme.selection : PastelTheme.buttonBackground)
            .overlay(Rectangle().strokeBorder(PastelTheme.textPrimary, lineWidth: 1))
            .overlay(
                Rectangle()
                    .strokeBorder(filled ? PastelTheme.selectionText.opacity(0.75)
                                         : PastelTheme.textPrimary.opacity(0.55),
                                  lineWidth: 0.5)
                    .padding(2)
            )
    }
}

// MARK: - the Cafes panel

struct CafesView: View {
    @ObservedObject var hub: CafeHub
    @ObservedObject var camera: CameraRig
    @ObservedObject var grain: GrainMode
    let setMode: (Int) -> Void
    let setPreset: (Int) -> Void

    var body: some View {
        PanelScaffold(title: "CAFES") {
            PanelColumns {
                ModeCard(hub: hub, grain: grain, setMode: setMode, setPreset: setPreset)
                CafeCard(hub: hub, unit: hub.units[0])
                CafeCard(hub: hub, unit: hub.units[1])
            } right: {
                PanelCard(title: "NEARBY", note: hub.bluetoothReady ? "searching" : "bluetooth off") {
                    if hub.found.isEmpty {
                        Text("Turn the Cafe on (esp_cafe_duo, preset 3).")
                            .font(.system(size: PanelMetrics.labelFont))
                            .foregroundStyle(PastelTheme.textSecondary)
                    }
                    ForEach(hub.found) { f in
                        HStack(spacing: PanelMetrics.rowGap) {
                            Text(f.name)
                                .font(.system(size: PanelMetrics.labelFont, weight: .medium))
                                .foregroundStyle(PastelTheme.textPrimary)
                            Spacer(minLength: 0)
                            ChipButton(title: "→ A", filled: hub.units[0].savedID == f.id) { hub.assign(f, to: 0) }
                                .frame(width: 44)
                            ChipButton(title: "→ B", filled: hub.units[1].savedID == f.id) { hub.assign(f, to: 1) }
                                .frame(width: 44)
                        }
                    }
                }
                CameraCard(camera: camera)
            }
        }
        .onAppear { hub.startScan() }
        .onDisappear { hub.stopScan() }
    }
}

private struct CafeCard: View {
    @ObservedObject var hub: CafeHub
    @ObservedObject var unit: CafeUnit

    var body: some View {
        PanelCard(title: unit.slot == 0 ? "CAFE A · TOP" : "CAFE B · BOTTOM") {
            DiagRow("NAME", unit.name ?? "—")
            DiagRow("STATE", unit.state)
            DiagRow("CLOCK", unit.hz > 0 ? String(format: "%.1f kHz", unit.hz / 1000) : "—")
            DiagRow("PRESET", unit.preset < 0 ? "—" : (unit.preset < 3 ? GrainMode.presetNames[unit.preset].lowercased() : "\(unit.preset + 1)"))
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: "DISCONNECT", filled: false) { hub.disconnect(unit.slot) }
                ChipButton(title: "FORGET", filled: false) { hub.forget(unit.slot) }
            }
        }
    }
}

/// Camera settings (same rows as Þunresdæg's CAMERA). MODE cycles MOTION / BRIGHT / DARK.
private struct CameraCard: View {
    @ObservedObject var camera: CameraRig

    var body: some View {
        PanelCard(title: "CAMERA", toggle: $camera.enabled) {
            VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
                HStack(spacing: PanelMetrics.rowGap) {
                    label("MODE")
                    ChipButton(title: CameraRig.attractNames[camera.attractMode], filled: true) {
                        camera.attractMode = (camera.attractMode + 1) % CameraRig.attractNames.count
                    }
                    .frame(width: 60)
                    Spacer(minLength: 0)
                }
                HStack(spacing: PanelMetrics.rowGap) {
                    label("FRONT")
                    Spacer(minLength: 0)
                    CompactToggle(isOn: $camera.usesFront, width: 28, height: 15, onColor: PastelTheme.selection)
                }
                PanelRow(label: "FPS", value: Binding(get: { Double(camera.fps - 1) / 29.0 },
                                                      set: { camera.fps = 1 + Int(($0 * 29.0).rounded()) }))
                PanelRow(label: "SENS", value: $camera.sensitivity)
            }
            .disabled(!camera.enabled)
            .unlit(!camera.enabled)
        }
    }

    private func label(_ t: String) -> some View {
        Text(t)
            .font(.system(size: PanelMetrics.labelFont, weight: .medium))
            .foregroundStyle(PastelTheme.textPrimary)
            .frame(width: PanelMetrics.labelWidth, alignment: .leading)
    }
}

/// presets from the phone; inside DUO: LOOP / GRAIN, and GRAIN's marks
private struct ModeCard: View {
    @ObservedObject var hub: CafeHub
    @ObservedObject var grain: GrainMode
    let setMode: (Int) -> Void
    let setPreset: (Int) -> Void

    var body: some View {
        PanelCard(title: "PRESET", note: "both Cafes") {
            // the Cafes' presets, from the phone (same as the button menu on the Cafe)
            HStack(spacing: PanelMetrics.chipSpacing) {
                ForEach(0..<3, id: \.self) { n in
                    ChipButton(title: GrainMode.presetNames[n], filled: grain.preset == n) { setPreset(n) }
                }
            }
            // inside DUO: play the tape as a LOOP, as GRAINS, or play the BENJOLIN (switches with a short crossfade)
            HStack(spacing: PanelMetrics.chipSpacing) {
                ForEach(0..<3, id: \.self) { m in
                    ChipButton(title: GrainMode.modeNames[m], filled: grain.preset == 2 && grain.mode == m) { setMode(m) }
                }
            }
            if grain.on && grain.preset == 2 {
                HStack(spacing: PanelMetrics.rowGap) {
                    Text("MARKS")
                        .font(.system(size: PanelMetrics.labelFont, weight: .medium))
                        .foregroundStyle(PastelTheme.textPrimary)
                        .frame(width: PanelMetrics.labelWidth, alignment: .leading)
                    ForEach(0..<8, id: \.self) { i in
                        Rectangle()
                            .fill(i < grain.marks ? PastelTheme.textPrimary : Color.clear)
                            .overlay(Rectangle().strokeBorder(PastelTheme.textPrimary, lineWidth: 1))
                            .frame(width: 8, height: 8)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: PanelMetrics.chipSpacing) {
                    ChipButton(title: "SYNC L·R", filled: false) { grain.sync(hub.units) }
                }
                HStack(spacing: PanelMetrics.chipSpacing) {
                    ChipButton(title: "MARK", filled: false) { grain.mark(hub.units) }
                    ChipButton(title: "ONLY MARKS", filled: grain.useMarks) { grain.setUseMarks(!grain.useMarks, hub.units) }
                    ChipButton(title: "CLEAR", filled: false) { grain.clearMarks(hub.units) }
                }
                Text("L input -> Cafe A, R input -> Cafe B. Only the grains come out (no dry sound). Both play one score; L · R pulls them apart.")
                    .font(.system(size: PanelMetrics.valueFont))
                    .foregroundStyle(PastelTheme.textSecondary)
            }
        }
    }
}
