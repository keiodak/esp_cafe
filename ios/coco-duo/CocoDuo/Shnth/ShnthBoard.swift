// ShnthBoard.swift — coco duo (k.odk)
// SHNTH's screen (in place of the pads), in coco duo's look: a thin line (the patch, its preset, the LEDs, the
// antennae's meters), then MAJOR over the four bars (XY pads, finger area — large) over minor. SHNTH sounds on the
// Cafes only (the phone's engine runs silent, for the LEDs).
// The corner keys: GEN (top left's right) · TAR (top right's left) · the antennae's source TILT / CAM / OFF (bottom
// right's left) · PATCH (bottom right's right): the panel — the patch, its preset, its code.

import SwiftUI

struct ShnthBoard: View {
    @ObservedObject var sh: ShnthPlayer
    @ObservedObject var ant: Antennae
    /// a change the Cafes must hear about (the Director sends it)
    let changed: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            line
            buttons(major: true).frame(height: 30)
            HStack(spacing: 6) {                                                  // the four bars, as XY pads
                ForEach(0..<4, id: \.self) { i in
                    BarPad(label: ["BAR", "BAR B", "BAR C", "BAR D"][i]) { sh.bars[i] = $0; sh.pushInputs() }
                }
            }
            buttons(major: false).frame(height: 30)
        }
        .padding(6)
        .background(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
        .overlay(alignment: .bottom) {
            if sh.panelOpen { ShnthPanel(sh: sh, changed: changed).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .onAppear { route(); ant.begin() }
        .onDisappear { ant.end(); sh.panelOpen = false }
    }

    /// the antennae: to the Shnth
    private func route() {
        ant.onChange = { [weak p = sh] a, b in p?.corp[0] = a; p?.corp[1] = b; p?.pushInputs() }
        changed()
    }

    /// the patch · its preset · the LEDs · the antennae (only to read: the panel and the corner keys change them)
    private var line: some View {
        HStack(spacing: 8) {
            Text(sh.customName.isEmpty ? sh.patchName : sh.customName)
                .font(.hud(PanelMetrics.labelFont, .semibold)).foregroundStyle(PastelTheme.textPrimary).lineLimit(1)
            Text("\(sh.preset + 1)/\(max(1, sh.presetCount))")
                .font(.hud(PanelMetrics.labelFont, .medium)).foregroundStyle(PastelTheme.textSecondary)
            if !sh.error.isEmpty {
                Text(sh.error).font(.hud(8)).foregroundStyle(PastelTheme.hudOrange).lineLimit(1)
            }
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 1.0 / 20)) { _ in
                let leds = sh.ledsNow()
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { k in
                        Circle().fill((leds >> UInt8(k)) & 1 == 1 ? PastelTheme.hudOrange : PastelTheme.hudBlack.opacity(PastelTheme.tickOffOpacity))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            AntMeters(ant: ant).frame(width: 90)
        }
        .frame(height: 12)
    }

    /// a row of four: MAJOR (above the bars) or minor (below)
    private func buttons(major: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { k in
                let bit = UInt16(1) << UInt16((major ? 4 : 0) + k)
                HoldKey(label: (major ? "MAJOR" : "minor") + ["", " B", " C", " D"][k]) { down in
                    if down { sh.buttons |= bit } else { sh.buttons &= ~bit }
                    sh.pushInputs()
                }
            }
        }
    }
}

/// the antennae's two meters, small (A over B)
private struct AntMeters: View {
    @ObservedObject var ant: Antennae
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { k in
                let v = k == 0 ? ant.a : ant.b
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(PastelTheme.padScreen)
                        Rectangle().fill(PastelTheme.hudOrange).frame(width: max(0, CGFloat(v) * g.size.width))
                        Rectangle().strokeBorder(PastelTheme.hudBlack.opacity(ant.source == .off ? 0.3 : 1), lineWidth: 0.8)
                    }
                }
            }
        }
    }
}

/// PATCH's panel: the patch (its list, ‹ ›), its preset (‹ ›), its code (to read and change: PLAY)
private struct ShnthPanel: View {
    @ObservedObject var sh: ShnthPlayer
    let changed: () -> Void
    @State private var text = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PATCH").font(.hud(PanelMetrics.chipFont, .semibold)).foregroundStyle(PastelTheme.textSecondary)
                HStack(spacing: PanelMetrics.chipSpacing) {
                    StepKey(left: true) { sh.prevPatch(); changed(); load() }
                    Menu {
                        ForEach(ShnthPlayer.patches.indices, id: \.self) { i in
                            Button(ShnthPlayer.patches[i].name) { sh.select(patch: i); changed(); load() }
                        }
                    } label: {
                        Text(sh.customName.isEmpty ? sh.patchName : sh.customName)
                            .font(.hud(PanelMetrics.labelFont, .semibold)).foregroundStyle(PastelTheme.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6).frame(width: 110, height: PanelMetrics.chipHeight)
                            .overlay(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
                    }
                    StepKey(left: false) { sh.nextPatch(); changed(); load() }
                }
                Text("PRESET").font(.hud(PanelMetrics.chipFont, .semibold)).foregroundStyle(PastelTheme.textSecondary)
                HStack(spacing: PanelMetrics.chipSpacing) {
                    StepKey(left: true) { sh.setPreset(sh.preset - 1); changed() }
                    Text("\(sh.preset + 1)/\(max(1, sh.presetCount))")
                        .font(.hud(PanelMetrics.labelFont, .semibold)).foregroundStyle(PastelTheme.textPrimary).frame(width: 40)
                    StepKey(left: false) { sh.setPreset(sh.preset + 1); changed() }
                }
                Spacer(minLength: 0)
                ChipButton(title: "CLOSE", filled: false) { withAnimation(.easeOut(duration: 0.2)) { sh.panelOpen = false } }
                    .frame(width: 60)
            }
            .frame(width: 160)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: PanelMetrics.chipSpacing) {
                    Text("CODE").font(.hud(PanelMetrics.chipFont, .semibold)).foregroundStyle(PastelTheme.textSecondary)
                    Spacer(minLength: 0)
                    ChipButton(title: "PLAY", filled: false) {                       // compile what is written: here and the Cafes
                        if sh.play(source: text, preset: sh.preset) == nil { sh.customName = "CODE"; sh.customSource = text; changed() }
                    }.frame(width: 44)
                    ChipButton(title: "REVERT", filled: false) { load() }.frame(width: 50)
                }
                TextEditor(text: $text)
                    .font(.system(size: 10, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(PastelTheme.padScreen)
                    .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .padding(10)
        .frame(maxHeight: 220)
        .background(PastelTheme.neumorphSurface)
        .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
        .onAppear { load() }
    }

    /// the code playing now
    private func load() {
        text = sh.customName.isEmpty ? (ShnthPlayer.patches.isEmpty ? "" : ShnthPlayer.patches[sh.patch].source) : sh.customSource
    }
}

/// ‹ / ›: a chip with a fine chevron
struct StepKey: View {
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

/// TAR as a corner key: held while touched (it also takes the antennae's rest anew)
struct ShnthTarKey: View {
    let sh: ShnthPlayer
    let ant: Antennae
    @State private var down = false
    var body: some View {
        Text("TAR")
            .font(.hud(8, .semibold)).tracking(0.5)
            .foregroundStyle(down ? PastelTheme.selectionText : PastelTheme.hudBlack)
            .frame(width: 50, height: 21)
            .background(IconSquare(filled: down))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !down else { return }
                    down = true; sh.buttons |= 1 << 8; ant.zero(); sh.pushInputs()
                }
                .onEnded { _ in down = false; sh.buttons &= ~(1 << 8); sh.pushInputs() })
    }
}

/// PATCH as a corner key (bottom right's right): PATCH's panel open / closed
struct ShnthPatchKey: View {
    @ObservedObject var sh: ShnthPlayer
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { sh.panelOpen.toggle() } } label: {
            Text("PATCH")
                .font(.hud(8, .semibold)).tracking(0.5)
                .foregroundStyle(sh.panelOpen ? PastelTheme.selectionText : PastelTheme.hudBlack)
                .frame(width: 50, height: 21)
                .background(IconSquare(filled: sh.panelOpen))
        }
    }
}

/// the antennae's source as a corner key (bottom right's left): TILT → CAM → OFF
struct AntSourceKey: View {
    @ObservedObject var ant: Antennae
    var body: some View {
        Button {
            let all = Antennae.Source.allCases
            ant.source = all[((all.firstIndex(of: ant.source) ?? 0) + 1) % all.count]
        } label: {
            Text(ant.source.rawValue)
                .font(.hud(8, .semibold)).tracking(0.5)
                .foregroundStyle(ant.source != .off ? PastelTheme.selectionText : PastelTheme.hudBlack)
                .frame(width: 50, height: 21)
                .background(IconSquare(filled: ant.source != .off))
        }
    }
}
