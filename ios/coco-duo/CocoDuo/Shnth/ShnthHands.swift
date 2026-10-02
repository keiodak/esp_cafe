// ShnthHands.swift — coco duo (k.odk)
// SHNTH's and JUSTINTS's hands, as in the Shnth app, in coco duo's look:
//   BarPad    — a bar as an XY pad: the upper half bends it up, the lower half down; how far grows from a small dot:
//               the finger's AREA (UIKit's touch radius, as SIDRAX's plates) and how far from the middle, added.
//   Antennae  — the two antennae from TILT (A forward, B sideways) · CAM (the back camera: a hand over its left half
//               A, its right half B) · OFF; ZERO (and TAR) takes what is there now as rest.
//   Library   — KEEP: the code you like, filed in Documents (SHNTH/*.txt · JUSTINTS/*.texte — Files, Finder);
//               SHARE: AirDrop / Mail … (this one, or all kept).

import SwiftUI
import UIKit
import Combine
import CoreMotion
import AVFoundation

// MARK: - a bar as an XY pad

struct BarPad: View {
    let label: String
    let set: (Double) -> Void
    @State private var x = 0.5
    @State private var y = 0.5
    @State private var area = 0.0

    init(label: String, set: @escaping (Double) -> Void) { self.label = label; self.set = set }

    /// −1 … 1: the way from the half the finger is in; how far from its area and its distance from the middle, added
    static func value(y: Double, area: Double) -> Double {
        guard area > 0 else { return 0 }
        let way: Double = y >= 0.5 ? 1 : -1
        let dist = min(1, abs(y - 0.5) * 2)
        return way * min(1, 0.55 * dist + 0.6 * area)
    }

    var body: some View {
        let v = BarPad.value(y: y, area: area)
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(PastelTheme.padScreen)
                Rectangle().fill(PastelTheme.hudBlack.opacity(0.85))
                    .frame(width: w, height: max(0, abs(CGFloat(v)) * h / 2))
                    .offset(y: v > 0 ? h / 2 - CGFloat(v) * h / 2 : h / 2)
                Rectangle().fill(PastelTheme.hudOrange).frame(height: 2).offset(y: h / 2 - 1)        // rest
                if area > 0 {
                    Circle().strokeBorder(PastelTheme.hudOrange, lineWidth: 2)
                        .frame(width: 10 + area * 50, height: 10 + area * 50)
                        .position(x: x * w, y: (1 - y) * h)
                }
                Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1)
                Text(label).font(.hud(PanelMetrics.labelFont, .semibold)).foregroundStyle(PastelTheme.textSecondary).padding(4)
                ShTouch { nx, ny, a in
                    x = nx; y = ny; area = a
                    set(BarPad.value(y: ny, area: a))
                }
            }
        }
    }
}

/// x, y (0…1, y up) and the area (0…1; 0 when the finger lifts)
private struct ShTouch: UIViewRepresentable {
    let report: (Double, Double, Double) -> Void
    func makeUIView(context: Context) -> V { let v = V(); v.report = report; return v }
    func updateUIView(_ v: V, context: Context) { v.report = report }
    final class V: UIView {
        var report: ((Double, Double, Double) -> Void)?
        private var finger: UITouch?
        private var smooth = 0.0
        override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isMultipleTouchEnabled = false }
        required init?(coder: NSCoder) { fatalError() }
        private func area(_ t: UITouch) -> Double {
            let r = Double(t.majorRadius)                            // ~7 fingertip … ~20 flat … ~30 pressed
            var a = min(max((r - 8) / 20, 0), 1)
            if t.maximumPossibleForce > 0 { a = max(a, Double(t.force / t.maximumPossibleForce)) }
            return max(0.02, a)
        }
        private func place(_ t: UITouch) -> (Double, Double) {
            let p = t.location(in: self), w = max(bounds.width, 1), h = max(bounds.height, 1)
            return (min(max(Double(p.x / w), 0), 1), min(max(1 - Double(p.y / h), 0), 1))
        }
        private func send(_ t: UITouch) {
            let (x, y) = place(t), a = area(t)
            smooth = smooth == 0 ? a : smooth + (a - smooth) * 0.35
            report?(x, y, smooth)
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard finger == nil, let t = touches.first else { return }
            finger = t; smooth = 0; send(t)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let f = finger, touches.contains(f) else { return }
            send(f)
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
        private func lift(_ touches: Set<UITouch>) {
            guard let f = finger, touches.contains(f) else { return }
            let (x, y) = place(f)
            finger = nil; smooth = 0
            report?(x, y, 0)
        }
    }
}

/// a button held while touched (minor, MAJOR, TAR)
struct HoldKey: View {
    let label: String
    let press: (Bool) -> Void
    @State private var down = false
    var body: some View {
        Text(label)
            .font(.hud(PanelMetrics.chipFont, .semibold)).lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(down ? PastelTheme.selectionText : PastelTheme.hudBlack)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(IconSquare(filled: down))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; press(true) } }
                .onEnded { _ in down = false; press(false) })
    }
}

// MARK: - the antennae

final class ShTilt {
    var onChange: ((Double, Double) -> Void)?
    private let mm = CMMotionManager()
    private var fwd0 = 0.0, side0 = 0.0, zeroNext = true, sa = 0.0, sb = 0.0
    private static let full = 35.0 * .pi / 180, dead = 3.0 * .pi / 180
    func start() {
        guard mm.isDeviceMotionAvailable, !mm.isDeviceMotionActive else { return }
        zeroNext = true
        mm.deviceMotionUpdateInterval = 1.0 / 60
        mm.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            let fwd = asin(max(-1, min(1, g.z))), side = atan2(g.y, g.x)
            let upright = min(1, hypot(g.x, g.y) / 0.5)
            if self.zeroNext { self.fwd0 = fwd; self.side0 = side; self.zeroNext = false }
            var ds = side - self.side0
            while ds > .pi { ds -= 2 * .pi }
            while ds < -.pi { ds += 2 * .pi }
            func amount(_ d: Double) -> Double { min(1, max(0, abs(d) - ShTilt.dead) / (ShTilt.full - ShTilt.dead)) }
            self.sa += (amount(fwd - self.fwd0) - self.sa) * 0.3
            self.sb += (amount(ds) * upright - self.sb) * 0.3
            self.onChange?(self.sa < 0.005 ? 0 : self.sa, self.sb < 0.005 ? 0 : self.sb)
        }
    }
    func stop() { mm.stopDeviceMotionUpdates() }
    func zero() { zeroNext = true }
}

/// the back camera as two light sensors (left half -> A, right half -> B)
final class ShCam {
    var onChange: ((Double, Double) -> Void)?
    private let c = CameraController()
    private var baseL = 0.0, baseR = 0.0, zeroNext = true, sa = 0.0, sb = 0.0, running = false
    init() {
        c.setPosition(.back)
        c.mosaicEnabled = true
        c.onFrameUpdate = { [weak self] f in
            guard let g = f.mosaicBrightness else { return }
            DispatchQueue.main.async { self?.frame(g) }
        }
    }
    func start() { guard !running else { return }; running = true; zeroNext = true; c.start() }
    func stop() { guard running else { return }; running = false; c.stop() }
    func zero() { zeroNext = true }
    private func frame(_ g: [[Double]]) {
        guard running, let cols = g.first?.count, cols > 1 else { return }
        var l = 0.0, r = 0.0, nl = 0, nr = 0
        for row in g { for (k, v) in row.enumerated() { if k < cols / 2 { l += v; nl += 1 } else { r += v; nr += 1 } } }
        l /= Double(max(1, nl)); r /= Double(max(1, nr))
        if zeroNext || baseL <= 0 { baseL = max(l, 0.02); baseR = max(r, 0.02); zeroNext = false }
        if l > baseL { baseL += (l - baseL) * 0.05 }
        if r > baseR { baseR += (r - baseR) * 0.05 }
        func near(_ v: Double, _ base: Double) -> Double { min(1, max(0, (base - v) / (base * 0.75) - 0.04) / 0.96) }
        sa += (near(l, baseL) - sa) * 0.4
        sb += (near(r, baseR) - sb) * 0.4
        onChange?(sa < 0.01 ? 0 : sa, sb < 0.01 ? 0 : sb)
    }
}

final class Antennae: ObservableObject {
    enum Source: String, CaseIterable { case tilt = "TILT", cam = "CAM", off = "OFF" }
    @Published var source: Source = Source(rawValue: UserDefaults.standard.string(forKey: "ant.source") ?? "") ?? .tilt {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "ant.source"); apply() }
    }
    @Published private(set) var a = 0.0
    @Published private(set) var b = 0.0
    var onChange: ((Double, Double) -> Void)? { didSet { onChange?(a, b) } }
    private let tilt = ShTilt()
    private let cam = ShCam()
    private var active = false
    init() {
        tilt.onChange = { [weak self] a, b in if self?.source == .tilt { self?.put(a, b) } }
        cam.onChange = { [weak self] a, b in if self?.source == .cam { self?.put(a, b) } }
    }
    func begin() { active = true; apply() }
    func end() { active = false; tilt.stop(); cam.stop(); put(0, 0) }
    func zero() { tilt.zero(); cam.zero() }
    private func apply() {
        guard active else { return }
        switch source {
        case .tilt: cam.stop(); tilt.start()
        case .cam: tilt.stop(); cam.start()
        case .off: tilt.stop(); cam.stop()
        }
        put(0, 0)
    }
    private func put(_ na: Double, _ nb: Double) {
        if abs(na - a) > 0.002 || abs(nb - b) > 0.002 || (na == 0) != (a == 0) || (nb == 0) != (b == 0) { a = na; b = nb }
        onChange?(na, nb)
    }
}

/// the antennae: TILT · CAM · OFF, ZERO, two meters
struct AntennaPanel: View {
    @ObservedObject var ant: Antennae
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: PanelMetrics.chipSpacing) {
                Text("ANT").font(.hud(PanelMetrics.chipFont, .semibold)).foregroundStyle(PastelTheme.textSecondary)
                ForEach(Antennae.Source.allCases, id: \.self) { s in
                    ChipButton(title: s.rawValue, filled: ant.source == s) { ant.source = s }.frame(width: 34)
                }
                ChipButton(title: "ZERO", filled: false) { ant.zero() }.frame(width: 38)
            }
            ForEach(0..<2, id: \.self) { k in
                let v = k == 0 ? ant.a : ant.b
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(PastelTheme.padScreen)
                        Rectangle().fill(PastelTheme.hudOrange).frame(width: max(0, CGFloat(v) * g.size.width))
                        Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1)
                    }
                }
                .frame(height: 7)
            }
        }
    }
}

// MARK: - KEEP · SHARE

final class Library: ObservableObject {
    enum Kind: String { case shnth = "SHNTH", justints = "JUSTINTS"
        var ext: String { self == .shnth ? "txt" : "texte" }
    }
    @Published private(set) var shnth: [String] = []
    @Published private(set) var justints: [String] = []
    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    init() {
        for k in [Kind.shnth, .justints] { try? FileManager.default.createDirectory(at: dir(k), withIntermediateDirectories: true) }
        refresh()
    }
    func dir(_ k: Kind) -> URL { docs.appendingPathComponent(k.rawValue, isDirectory: true) }
    func url(_ n: String, _ k: Kind) -> URL { dir(k).appendingPathComponent(n).appendingPathExtension(k.ext) }
    func names(_ k: Kind) -> [String] { k == .shnth ? shnth : justints }
    func refresh() {
        func list(_ k: Kind) -> [String] {
            let fs = (try? FileManager.default.contentsOfDirectory(at: dir(k), includingPropertiesForKeys: nil)) ?? []
            return fs.filter { $0.pathExtension.lowercased() == k.ext }.map { $0.deletingPathExtension().lastPathComponent }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        shnth = list(.shnth); justints = list(.justints)
    }
    @discardableResult
    func keep(_ text: String, name: String, _ k: Kind) -> URL? {
        let f = DateFormatter(); f.dateFormat = "MMdd-HHmmss"
        var base = name.lowercased().replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "patch" }
        base += " " + f.string(from: Date())
        var n = base, i = 2
        while FileManager.default.fileExists(atPath: url(n, k).path) { n = "\(base) \(i)"; i += 1 }
        let u = url(n, k)
        do { try text.write(to: u, atomically: true, encoding: .utf8) } catch { return nil }
        refresh()
        return u
    }
    func read(_ n: String, _ k: Kind) -> String? {
        let u = url(n, k)
        return (try? String(contentsOf: u, encoding: .utf8)) ?? (try? String(contentsOf: u, encoding: .isoLatin1))
    }
    func all(_ k: Kind) -> [URL] { names(k).map { url($0, k) } }
}

struct ShShared: Identifiable { let id = UUID(); let urls: [URL] }

struct ShShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// KEEP and SHARE (THIS · ALL KEPT)
struct KeepShare: View {
    @ObservedObject var lib: Library
    let kind: Library.Kind
    let current: () -> (String, String)
    @State private var flash = false
    @State private var shared: ShShared?
    var body: some View {
        HStack(spacing: PanelMetrics.chipSpacing) {
            ChipButton(title: flash ? "KEPT" : "KEEP", filled: flash) {
                let (t, n) = current()
                lib.keep(t, name: n, kind)
                flash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { flash = false }
            }
            .frame(width: 38)
            Menu {
                Button("THIS") { let (t, n) = current(); if let u = lib.keep(t, name: n, kind) { shared = ShShared(urls: [u]) } }
                Button("ALL KEPT") { lib.refresh(); let us = lib.all(kind); if !us.isEmpty { shared = ShShared(urls: us) } }
            } label: {
                Text("SHARE").font(.hud(PanelMetrics.chipFont, .medium)).foregroundStyle(PastelTheme.hudBlack)
                    .frame(width: 42, height: PanelMetrics.chipHeight)
                    .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1))
            }
        }
        .sheet(item: $shared) { s in ShShareSheet(urls: s.urls) }
    }
}
