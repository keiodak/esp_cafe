// ContentView.swift — coco-pc for iPhone (k.odk)

import SwiftUI
import UIKit

struct SpeedPreset: Identifiable {
    let milli: Int
    let title: String
    var id: Int { milli }
    static let all = [SpeedPreset(milli: -1000, title: "-1"), SpeedPreset(milli: 500, title: "½"),
                      SpeedPreset(milli: 1000, title: "1"), SpeedPreset(milli: 2000, title: "2"), SpeedPreset(milli: 0, title: "stop")]
}

struct ContentView: View {
    @StateObject private var link = CafeLink()
    @State private var showPicker = false
    @State private var speed: Double = 1000
    @State private var editingSpeed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(link.connectedName.map { "\($0) · \(link.state)" } ?? link.state)
                        .font(.footnote).foregroundStyle(.secondary)

                    WaveView(link: link)
                        .frame(height: 220)
                    Text(positionText).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text("tap = jump · drag = set loop · drag an edge = move it")
                        .font(.caption2).foregroundStyle(.tertiary)

                    card { speedControls }
                    card { transport }
                    card { lamps }

                    if !link.message.isEmpty {
                        Text(link.message).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("coco-pc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if link.connectedName != nil {
                        Button("Disconnect") { link.disconnect() }
                    } else {
                        Button("Connect") { link.startScan(); showPicker = true }
                    }
                }
            }
            .sheet(isPresented: $showPicker, onDismiss: { link.stopScan() }) { picker }
            .onReceive(link.$st) { s in if !editingSpeed { speed = Double(s.speed) } }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: pieces

    private var positionText: String {
        let s = link.hz > 1000 ? link.hz : 44100
        return String(format: "play %.3f s   rec %.3f s   loop %.2f–%.2f s",
                      Double(link.st.p) / s, Double(link.st.w) / s, Double(link.st.ls) / s, Double(link.st.le) / s)
    }

    private var speedControls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("speed").font(.caption).foregroundStyle(.secondary)
                Slider(value: $speed, in: -4000...4000, step: 10, onEditingChanged: { e in editingSpeed = e })
                    .onChange(of: speed) { _, v in if editingSpeed { link.send("S \(Int(v))") } }
                Text(String(format: "%.2fx", speed / 1000)).font(.caption.monospaced()).frame(width: 52, alignment: .trailing)
            }
            HStack {
                ForEach(SpeedPreset.all) { item in
                    Button(item.title) { link.send("S \(item.milli)") }.buttonStyle(.bordered)
                }
                Button("rev") { link.send("S \(-link.st.speed)") }.buttonStyle(.bordered)
            }
            .font(.callout)
        }
    }

    private var transport: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    guard link.polls > 0 else { link.message = "no status from the Cafe yet"; return }
                    link.send("R \(link.st.rec ? 0 : 1)")
                } label: { Label("REC", systemImage: link.st.rec ? "record.circle.fill" : "record.circle") }
                    .buttonStyle(.borderedProminent).tint(link.st.rec ? .red : .gray)
                Button("to loop start") { link.send("J \(link.st.ls)") }.buttonStyle(.bordered)
                Button("whole") { link.send("L 0 \(TAPE)") }.buttonStyle(.bordered)
            }
            HStack {
                if let p = link.dumpProgress {
                    ProgressView(value: p) { Text("reading the tape… \(Int(p * 100))%").font(.caption) }
                } else {
                    Button { link.saveWav() } label: { Label("save wav", systemImage: "waveform") }
                        .buttonStyle(.bordered).disabled(!link.isConnected)
                    if let url = link.wavURL {
                        ShareLink(item: url) { Label("share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered)
                    }
                }
                Spacer()
            }
        }
    }

    private var lamps: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("earth").font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                ProgressView(value: Double(link.st.earth), total: 255)
                Text("\(link.st.earth)").font(.caption.monospaced()).frame(width: 32, alignment: .trailing)
            }
            HStack(spacing: 16) {
                lamp("flip", link.st.flip)
                lamp("skip", link.st.skip)
                lamp("button", link.st.btn)
                Spacer()
            }
            HStack(spacing: 16) {
                stat("clock", link.hz > 0 ? String(format: "%.1f kHz", link.hz / 1000) : "—")
                stat("buffer", link.hz > 1000 ? String(format: "%.2f s", Double(TAPE) / link.hz) : "—")
                stat("preset", link.st.preset < 0 ? "—" : (link.st.preset == 5 ? "6 · coco_pc" : "\(link.st.preset + 1) (choose 6)"))
            }
        }
    }

    private func lamp(_ name: String, _ on: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(on ? Color.orange : Color.gray.opacity(0.35)).frame(width: 10, height: 10)
            Text(name).font(.caption)
        }
    }

    private func stat(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced())
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }

    private var picker: some View {
        NavigationStack {
            List(link.found) { f in
                Button {
                    link.connect(f); showPicker = false
                } label: {
                    HStack { Text(f.name); Spacer(); Text("\(f.rssi) dB").foregroundStyle(.secondary) }
                }
            }
            .overlay { if link.found.isEmpty { ProgressView("looking for a Cafe…") } }
            .navigationTitle("Cafe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPicker = false } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - waveform with loop editing

struct WaveView: View {
    @ObservedObject var link: CafeLink
    private enum Mode { case new, left, right }
    @State private var mode: Mode? = nil
    @State private var anchor = 0
    @State private var moved = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Canvas { ctx, size in
                let x = { (s: Int) -> CGFloat in CGFloat(s) / CGFloat(TAPE) * size.width }
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10), with: .color(.white.opacity(0.05)))
                // loop region
                let lx = x(link.st.ls), rx = x(link.st.le)
                ctx.fill(Path(CGRect(x: lx, y: 0, width: max(1, rx - lx), height: size.height)), with: .color(.teal.opacity(0.18)))
                ctx.fill(Path(CGRect(x: lx - 1, y: 0, width: 2, height: size.height)), with: .color(.teal))
                ctx.fill(Path(CGRect(x: rx - 1, y: 0, width: 2, height: size.height)), with: .color(.teal))
                // waveform (min / max per bin)
                let bw = size.width / CGFloat(BINS)
                var wave = Path()
                for i in 0..<BINS {
                    let top = (1 - CGFloat(link.maxs[i]) / 255) * size.height
                    let bot = (1 - CGFloat(link.mins[i]) / 255) * size.height
                    wave.addRect(CGRect(x: CGFloat(i) * bw, y: min(top, bot), width: max(1, bw * 0.9), height: max(1, abs(bot - top))))
                }
                ctx.fill(wave, with: .color(.white.opacity(0.75)))
                // record head (dashed red) and play head (yellow)
                var recLine = Path(); recLine.move(to: CGPoint(x: x(link.st.w), y: 0)); recLine.addLine(to: CGPoint(x: x(link.st.w), y: size.height))
                ctx.stroke(recLine, with: .color(.red), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                ctx.fill(Path(CGRect(x: x(link.st.p) - 1, y: 0, width: 2, height: size.height)), with: .color(.yellow))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let s = sample(v.location.x, w)
                        if mode == nil {
                            let start = sample(v.startLocation.x, w)
                            let lx = CGFloat(link.st.ls) / CGFloat(TAPE) * w, rx = CGFloat(link.st.le) / CGFloat(TAPE) * w
                            if abs(v.startLocation.x - lx) < 16 { mode = .left }
                            else if abs(v.startLocation.x - rx) < 16 { mode = .right }
                            else { mode = .new; anchor = start }
                            moved = false
                            link.holdLoop = true
                        }
                        if abs(v.translation.width) > 6 { moved = true }
                        guard moved else { return }
                        switch mode {
                        case .new: link.st.ls = min(anchor, s); link.st.le = max(anchor, s)
                        case .left: link.st.ls = min(s, link.st.le - 512)
                        case .right: link.st.le = max(s, link.st.ls + 512)
                        case .none: break
                        }
                    }
                    .onEnded { v in
                        if mode == .new && !moved {
                            link.send("J \(sample(v.location.x, w))")
                        } else if moved {
                            if link.st.le - link.st.ls < 512 { link.st.le = min(TAPE, link.st.ls + 512) }
                            link.send("L \(link.st.ls) \(link.st.le)")
                        }
                        mode = nil
                        link.holdLoop = false
                    }
            )
            .frame(width: w, height: h)
        }
    }

    private func sample(_ px: CGFloat, _ w: CGFloat) -> Int {
        guard w > 0 else { return 0 }
        return max(0, min(TAPE, Int((px / w * CGFloat(TAPE)).rounded())))
    }
}
