// FADirector.swift — Fourses (k.odk)
// (in coco duo: the Fourses app as it is, inside FA — iOS · FOURSES)
// Between the screen and the circuit: the shapes and the fingers become links, the pots and the rest are set,
// shapes flicker and sway (each its own kind), the camera lights the shapes, the LEDs and each node's current
// come back (~30x a second).

import AVFoundation
import CoreMotion
import SwiftUI
import UIKit

extension FA {
final class Director {
    let rig: Rig
    let audio = AudioHost()
    let camera = FrCamera()
    /// the cup: up to two linked Cafes (CafeLink) — each one's ASH from the board's CAFE A / B terminal
    let cafe: CafeLinks
    private var timer: Timer?
    private var activityIds: [Int32] = FrBoard.nodes.map { Int32($0) }

    init(rig: Rig, units: [CafeUnit]) {
        self.rig = rig
        cafe = CafeLinks(units: units)
        audio.onRebuilt = { [weak self] in self?.sendAll() }
        camera.onGrid = { [weak self] g in self?.frLight(g) }
        cafe.onLinked = { [weak self] k, on in self?.cafeShow(k, on) }
        sendAll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in self?.tick() }
        cafeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.cafeTick() }
    }

    private var fr: OpaquePointer? { audio.fr }

    /// (in coco duo) on the screen: it sounds, its Cafes take its ASH; off it: silent, the camera off, the Cafes let be
    private(set) var active = false
    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        audio.run(on)
        cafe.enabled = on
        if !on { setCamera(false); rig.panelOpen = false; cafe.panelOpen = false }
    }

    /// everything the engine holds, anew
    func sendAll() {
        guard let e = fr else { return }
        for h in 0..<8 { fr_set_pot(e, Int32(h), Float(rig.frPots[h])); fr_set_range(e, Int32(h), Int32(rig.frRanges[h])) }
        fr_set_starve(e, Float(rig.frStarve))
        fr_set_level(e, Float(rig.level))
        sendDub()
        fr_set_danger(e, rig.danger ? 1 : 0)
        wireSent = [:]; driftSent = [:]; lightSent = Array(repeating: -1, count: 16)
        frSyncShapes()
        pushLinks()
    }

    // MARK: the pots

    func setFrPot(_ h: Int, _ v: Double) {
        rig.frPots[h] = v
        if let e = fr { fr_set_pot(e, Int32(h), Float(v)) }
    }
    /// one horse's range switch: 0 CV · 1 LOW · 2 AUDIO
    func setFrRange(_ h: Int, _ r: Int) {
        rig.frRanges[h] = r
        if let e = fr { fr_set_range(e, Int32(h), Int32(r)) }
    }
    /// STARVE: the circuit's supply — left starves it (slower, smaller, sagging under its own load), right feeds it
    func setFrStarve(_ v: Double) {
        rig.frStarve = v
        if let e = fr { fr_set_starve(e, Float(v)) }
    }
    func setLevel(_ v: Double) {
        rig.level = v
        if let e = fr { fr_set_level(e, Float(v)) }
    }
    func reset() { if let e = fr { fr_reset(e) } }

    // MARK: DUB

    func setDubOn(_ on: Bool) { rig.dubOn = on; sendDub() }
    /// ANALOG: the output as the hardware's — hard, bright highs — its attacks held down
    func setDanger(_ on: Bool) { rig.danger = on; if let e = fr { fr_set_danger(e, on ? 1 : 0) } }
    func setDubFreq(_ c: Int, _ v: Double) { rig.dubFreq[c] = v; sendDub() }
    func setDubRes(_ c: Int, _ v: Double) { rig.dubRes[c] = v; sendDub() }
    private func sendDub() {
        guard let e = fr else { return }
        fr_set_dub(e, rig.dubOn ? 1 : 0, Float(rig.dubFreq[0]), Float(rig.dubFreq[1]), Float(rig.dubRes[0]), Float(rig.dubRes[1]))
    }

    // MARK: presets

    /// a tap: takes it back (nothing kept there: keeps it) · a long press: keeps it
    func presetTap(_ n: Int) {
        if rig.loadPreset(n) { cafeShowAll(); sendAll() } else { rig.keepPreset(n) }
    }
    func presetKeep(_ n: Int) { rig.keepPreset(n) }

    // MARK: the board

    /// the board's shape (width / height of the field): what lies inside a shape depends on it
    var frAspect: Double = 2.5 { didSet { if abs(frAspect - oldValue) > 0.02 { frSyncShapes() } } }
    /// the shapes as they are now (◌ flickering, ◉ where it has swayed to)
    var frLive: [[Double]] { FrBoard.flickered(rig.frShapes, rig.frFlick, rig.frGrav) }

    private var wireSent: [[Int]: Int] = [:]
    private var fingerLinks: [[Int]: Int] = [:]
    private var driftSent: [Int: Int] = [:]

    func frSyncShapes() {
        let shapes = frLive
        let dr = lightOn ? nil : FrBoard.drift(icons: rig.frIcons, shapes: shapes, aspect: frAspect)   // (once for both)
        var now: [[Int]: Int] = [:]
        for l in FrBoard.links(icons: rig.frIcons, shapes: shapes, aspect: frAspect, light: lightOn, drifted: dr) {
            let k = [l[0], l[1]]
            now[k] = max(now[k] ?? 0, l[2])
        }
        if let dr {                                                     // an empty shape's pull (the camera's light instead, when on)
            let v = dr.volts
            if let e = fr {
                for (k, x) in v where driftSent[k] != x { fr_set_drift(e, Int32(k), Float(Double(x) * 0.0084)) }
            }
            driftSent = v
        }
        if now != wireSent { wireSent = now; pushLinks() }
    }

    /// the fingers' links now (finger node -> node -> 0…1000)
    func frTouches(_ links: [Int: [Int: Int]]) {
        var now: [[Int]: Int] = [:]
        for (f, m) in links { for (i, v) in m { now[[min(f, i), max(f, i)]] = max(1, min(1000, v)) } }
        if now != fingerLinks { fingerLinks = now; pushLinks() }
    }

    /// shapes and fingers together, to the engine
    private func pushLinks() {
        guard let e = fr else { return }
        var a: [Int32] = [], b: [Int32] = [], v: [Int32] = []
        for (k, x) in wireSent { a.append(Int32(k[0])); b.append(Int32(k[1])); v.append(Int32(x)) }
        for (k, x) in fingerLinks { a.append(Int32(k[0])); b.append(Int32(k[1])); v.append(Int32(x)) }
        let n = min(a.count, 512)                             // (FR_MAX_LINKS)
        a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in v.withUnsafeBufferPointer { pv in
            fr_set_links(e, pa.baseAddress, pb.baseAddress, pv.baseAddress, Int32(n))
        } } }
    }

    func frAddShape(_ s: [Double]) { rig.frShapes.append(s); frSyncShapes() }
    func frRemoveShape(_ k: Int) { if rig.frShapes.indices.contains(k) { rig.frShapes.remove(at: k); frSyncShapes() } }
    func frRandom() { rig.frIcons = FrBoard.scatter(aspect: frAspect); cafeShowAll(); frSyncShapes() }
    /// SORT: each board in its place
    func frSort() { rig.frIcons = FrBoard.sorted(aspect: frAspect); cafeShowAll(); frSyncShapes() }
    func frClearShapes() { rig.frShapes = []; frSyncShapes() }
    func frDefault() {
        let d = FrBoard.defaultLayout()
        rig.frIcons = d.icons; rig.frShapes = d.shapes
        cafeShowAll()
        frSyncShapes()
    }

    /// SYNC: the phone held back by what the slowest linked Cafe's ASH takes — the steps here (60 a second: ~8 ms on
    /// average), Bluetooth (measured: half a ping), the Cafe's slew (~16) — less what the
    /// phone's own output already takes. Measured again now and then; changed in 5 ms steps.
    /// CAFE A / B -> their Cafes' ASH, 60 times a second: the voltage as it is that instant (sampled — a fast wave
    /// comes out as jumping steps, not as its flat average), spread over the range it has been moving in (a range that
    /// widens at once and narrows slowly), so even a small swing uses all of ASH
    private var cafeTimer: Timer?
    private var rLo: [Double] = [0, 0], rHi: [Double] = [0, 0], rSeen = [false, false], rOut: [Double] = [0, 0]
    private func cafeTick() {
        guard active, let e = fr else { return }
        var now: [Float] = [0, 0], lo: [Float] = [0, 0], hi: [Float] = [0, 0]
        now.withUnsafeMutableBufferPointer { n in lo.withUnsafeMutableBufferPointer { l in hi.withUnsafeMutableBufferPointer { h in
            fr_take_ash(e, n.baseAddress, l.baseAddress, h.baseAddress)
        } } }
        for s in cafe.slots {
            let k = s.slot
            guard s.linked else { rSeen[k] = false; continue }
            let a = Double(lo[k]), b = Double(hi[k])
            if !rSeen[k] { rLo[k] = a; rHi[k] = b; rSeen[k] = true }
            rLo[k] = a < rLo[k] ? a : rLo[k] + (a - rLo[k]) * 0.01
            rHi[k] = b > rHi[k] ? b : rHi[k] + (b - rHi[k]) * 0.01
            // the Cafe panel's sliders: SPREAD (the plain 0…9 V … the range it moves in, stretched) · SMOOTH (the jumps softened)
            let span = max(1.5, rHi[k] - rLo[k])                       // (a small swing widened, not blown up)
            let spread = min(1, max(0, (Double(now[k]) - rLo[k]) / span))
            let plain = min(1, max(0, Double(now[k]) / 9))
            let m = cafe.spread, follow = 1 - 0.95 * cafe.smooth
            rOut[k] += (m * spread + (1 - m) * plain - rOut[k]) * follow
            s.ash(level: rOut[k])
        }
    }

    private var syncT = 0
    private func cafeSync(_ e: OpaquePointer) {
        syncT += 1
        if syncT % 60 == 1 { cafe.slots.forEach { $0.ping() } }       // (every ~2 s)
        var ms = 0.0
        let linked = cafe.slots.filter { $0.linked }
        if !linked.isEmpty {
            let lag = linked.map { $0.lagMs > 0 ? $0.lagMs : 20 }.max() ?? 20
            let s = AVAudioSession.sharedInstance()
            let own = (s.outputLatency + s.ioBufferDuration) * 1000
            ms = max(0, 8 + lag + 16 - own)                             // (a tick at 60: ~8 on average · Bluetooth · the slew)
        }
        let q = Int((ms / 5).rounded()) * 5
        if q != cafe.holdMs {
            cafe.holdMs = q
            fr_set_out_delay(e, Float(q) / 1000)
        }
    }
    func cafeShowAll() { for s in cafe.slots { cafeShow(s.slot, s.linked) } }
    /// CAFE A / B on the board while its Cafe is linked (where it was last), off it (parked) when not
    func cafeShow(_ k: Int, _ on: Bool) {
        let i = FrBoard.icon(ofNode: FrBoard.cafeNode(k))
        guard rig.frIcons.indices.contains(i) else { return }
        let here = rig.frIcons[i][0] >= 0
        if on && !here {
            let home = [0.45 + 0.1 * Double(k), 0.12]
            let spot = (UserDefaults.standard.array(forKey: "fourses.cafeSpot\(k)") as? [Double]) ?? home
            rig.frIcons[i] = spot.count == 2 && spot[0] >= 0 ? spot : home
        } else if !on && here {
            UserDefaults.standard.set(rig.frIcons[i], forKey: "fourses.cafeSpot\(k)")
            rig.frIcons[i] = FrBoard.parked
        }
        frSyncShapes()
    }

    // MARK: the camera

    func setCamera(_ on: Bool) {
        camera.enabled = on
        if !on && lightOn { lightOn = false; driftSent = [:]; frSyncShapes() }
    }
    /// each shape's light: how bright the picture is inside it (against the room's own level), what moves there kicks it
    private(set) var lightOn = false
    private var lightSent = [Int](repeating: -1, count: 16)
    private var lightT = 0.0
    private var prevGrid: [[Double]] = []
    private var lo = 0.2, hi = 0.8
    private var env = [Double](repeating: 0, count: 16)
    private func frLight(_ raw: [[Double]]) {
        guard raw.count >= 8, raw[0].count >= 16 else { return }
        let grid = FrBoard.fieldGrid(raw, aspect: frAspect)
        if !lightOn { lightOn = true; lightSent = Array(repeating: -1, count: 16); env = Array(repeating: 0, count: 16); frSyncShapes() }
        let flat = grid.flatMap { $0 }
        lo += ((flat.min() ?? 0) - lo) * 0.05; hi += ((flat.max() ?? 1) - hi) * 0.05
        let span = max(0.08, hi - lo)
        let norm = grid.map { $0.map { min(1, max(0, ($0 - lo) / span)) } }
        let prev = prevGrid.count == 8 ? prevGrid : grid
        let move = (0..<8).map { r in (0..<16).map { c in abs(grid[r][c] - prev[r][c]) } }
        prevGrid = grid
        let t = CACurrentMediaTime()
        let send = t - lightT >= 0.05
        if send { lightT = t }
        var shown: [Double] = []
        for (k, s) in rig.frShapes.prefix(16).enumerated() where s.count >= 4 {
            let b = FrBoard.light(s, grid: norm, aspect: frAspect)
            let m = min(1, FrBoard.light(s, grid: move, aspect: frAspect) * 10)
            let target = min(1, 0.15 + 0.75 * b * b + 0.9 * m)          // (dark ~0.15 · bright ~0.9 · a movement jumps it up)
            env[k] = target > env[k] ? env[k] + (target - env[k]) * 0.7 : env[k] + (target - env[k]) * 0.12
            shown.append(env[k])
            let v = Int((env[k] * 1000).rounded())
            if send && abs(v - lightSent[k]) > 8, let e = fr { lightSent[k] = v; fr_set_drift(e, Int32(k), Float(env[k] * 8.4)) }
        }
        if send { camera.state.shapeLight = shown }
    }

    // MARK: ~30x a second

    private let dt = 0.03
    private var moved = false
    private func tick() {
        guard active else { return }
        flickTick()
        swayTick()
        if moved { moved = false; frSyncShapes() }                      // (once, for both)
        guard let e = fr else { return }
        let m = rig.meters
        var l = [Float](repeating: 0, count: 8)
        l.withUnsafeMutableBufferPointer { fr_take_leds(e, $0.baseAddress) }
        let leds = l.map { Double(min(1, $0 * 1.6)) }
        if leds != m.leds { m.leds = leds }
        var c = [Float](repeating: 0, count: 8)
        c.withUnsafeMutableBufferPointer { fr_take_cv(e, $0.baseAddress) }
        let cv = c.map { (min(1, max(0, (Double($0) - 0.22) / 0.56)) * 32).rounded() / 32 }   // (the triangle swings ~⅕ … ⅘: that, cold to warm)
        if cv != m.cv { m.cv = cv }
        let s = (Double(fr_supply(e)) * 50).rounded() / 50              // (finely: its sag shows on STARVE's meter)
        if s != m.supply { m.supply = s }
        cafeSync(e)
        let pk = Double(fr_take_peak(e))                                // (up at once, down slowly)
        let lv = ((pk > m.level ? pk : m.level * 0.7 + pk * 0.3) * 200).rounded() / 200
        if lv != m.level { m.level = lv }
        // each icon's current: 1 nA … 100 µA onto 0 … 1, in steps (fewer redraws)
        var a = [Float](repeating: 0, count: activityIds.count)
        activityIds.withUnsafeBufferPointer { ids in a.withUnsafeMutableBufferPointer { out in
            fr_take_activity(e, ids.baseAddress, out.baseAddress, Int32(ids.count))
        } }
        let act = a.map { i -> Double in
            guard i > 1e-10 else { return 0 }
            return (min(1, max(0.02, (log10(Double(i)) + 9) / 5)) * 24).rounded() / 24
        }
        if act != m.activity { m.activity = act }
    }

    /// the panel's SPEED: ×¼ … ×4 around each kind's own rate
    private func speed(_ v: Double) -> Double { pow(16, v - 0.5) }

    /// ◌ each shape that flickers — SLOW (on and off, ~1 Hz) · FAST (~7 Hz) · IRREG (a new contact at uneven times,
    /// now and then gone) · DRUNK (its contact wandering)
    private var flickPh: [Double] = [], flickWalk: [Double] = [], flickNext: [Double] = [], flickWait: [Double] = []
    private func flickTick() {
        let has = rig.frShapes.contains { FrBoard.flickKind($0) > 0 }
        guard has else { if !rig.frFlick.isEmpty { rig.frFlick = [] }; return }
        let n = rig.frShapes.count
        while flickPh.count < n { flickPh.append(Double.random(in: 0..<1)); flickWalk.append(1); flickNext.append(1); flickWait.append(0) }
        let sp = speed(rig.flickRate), depth = rig.flickDepth
        var f = rig.frShapes.map { _ in 1.0 }
        for (k, s) in rig.frShapes.enumerated() {
            let kind = FrBoard.flickKind(s)
            guard kind > 0 else { continue }
            switch kind {
            case 1, 2:                                                           // SLOW · FAST: on and off
                let hz = (kind == 1 ? 1.0 : 7.0) * sp
                flickPh[k] = (flickPh[k] + hz * dt).truncatingRemainder(dividingBy: 1)
                f[k] = flickPh[k] < 0.5 ? 1 : 1 - depth
            case 3:                                                              // IRREG: uneven times
                flickWait[k] -= dt
                if flickWait[k] <= 0 {
                    flickWait[k] = -log(Double.random(in: 0.02..<1)) / (4.0 * sp)
                    flickNext[k] = Double.random(in: 0..<1) < 0.3 ? 1 - depth : 1 - depth * Double.random(in: 0...0.3)
                }
                f[k] = flickNext[k]
            default:                                                             // DRUNK
                flickWalk[k] = min(1, max(0, flickWalk[k] + Double.random(in: -1...1) * sqrt(3 * sp * dt) * 0.5))
                f[k] = 1 - depth * (1 - flickWalk[k])
            }
            f[k] = (f[k] * 20).rounded() / 20
        }
        if f != rig.frFlick { rig.frFlick = f; moved = true }
    }

    /// ◉ each shape that sways, hung from where it was drawn — SLOW (round its point, ~0.3 Hz) · FAST (a quick tremble,
    /// ~5 Hz) · IRREG (a new place at uneven times, sprung to) · DRUNK (wandering) · TILT (the phone's tilt, twitching)
    private let motion = CMMotionManager()
    private var swayV: [[Double]] = [], swayPh: [Double] = [], swayTarget: [[Double]] = [], swayWait: [Double] = []
    private func swayTick() {
        let has = rig.frShapes.contains { FrBoard.swayKind($0) > 0 }
        let wantMotion = rig.frShapes.contains { FrBoard.swayKind($0) == 5 }
        if !wantMotion && motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        guard has else { if !rig.frGrav.isEmpty { rig.frGrav = [] }; return }
        if wantMotion && !motion.isDeviceMotionActive && motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 30; motion.startDeviceMotionUpdates()
        }
        let reach = 0.01 + 0.11 * rig.swayReach, sp = speed(rig.swayRate)
        let ax = max(0.5, frAspect)
        var pos = rig.frShapes.indices.map { $0 < rig.frGrav.count && rig.frGrav[$0].count >= 2 ? rig.frGrav[$0] : [0, 0] }
        while swayV.count < pos.count { swayV.append([0, 0]); swayPh.append(Double.random(in: 0..<1)); swayTarget.append([0, 0]); swayWait.append(0) }
        var tilt = (0.0, 0.0)
        if wantMotion {
            let g = motion.deviceMotion?.gravity ?? CMAcceleration(x: 0, y: -1, z: 0)
            let o = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .landscapeRight
            switch o {                                                           // (gravity on the screen: x right, y down)
            case .landscapeLeft: tilt = (g.y, g.x)
            case .landscapeRight: tilt = (-g.y, -g.x)
            case .portraitUpsideDown: tilt = (-g.x, g.y)
            default: tilt = (g.x, -g.y)
            }
        }
        for (k, s) in rig.frShapes.enumerated() {
            let kind = FrBoard.swayKind(s)
            guard kind > 0 else { continue }
            var target = [0.0, 0.0]
            var stiff = 0.12, jitter = 0.0
            switch kind {
            case 1:                                                              // SLOW: round its point
                swayPh[k] = (swayPh[k] + 0.3 * sp * dt).truncatingRemainder(dividingBy: 1)
                let a = swayPh[k] * 2 * .pi
                target = [cos(a) * reach / ax, sin(a) * reach]
                stiff = 0.5
            case 2:                                                              // FAST: a tremble
                swayPh[k] = (swayPh[k] + 5 * sp * dt).truncatingRemainder(dividingBy: 1)
                let a = swayPh[k] * 2 * .pi
                target = [sin(a) * reach * 0.6 / ax, sin(a * 1.618 + 1) * reach * 0.6]
                stiff = 0.8
            case 3:                                                              // IRREG: a new place at uneven times
                swayWait[k] -= dt
                if swayWait[k] <= 0 {
                    swayWait[k] = -log(Double.random(in: 0.02..<1)) / (2.0 * sp)
                    let a = Double.random(in: 0..<(2 * .pi)), r = reach * sqrt(Double.random(in: 0...1))
                    swayTarget[k] = [cos(a) * r, sin(a) * r]
                }
                target = [swayTarget[k][0] / ax, swayTarget[k][1]]
                stiff = 0.3
            case 4:                                                              // DRUNK
                for i in 0..<2 {
                    swayTarget[k][i] += Double.random(in: -1...1) * reach * 0.3 * sqrt(2 * sp * dt)
                    swayTarget[k][i] = min(reach, max(-reach, swayTarget[k][i]))
                }
                target = [swayTarget[k][0] / ax, swayTarget[k][1]]
                stiff = 0.3
            default:                                                             // TILT: the phone's tilt, and a twitch
                target = [tilt.0 * reach / ax, tilt.1 * reach]
                stiff = 0.04 + 0.1 * min(2, sp)
                jitter = reach * 0.04 * min(2, sp)
            }
            for a in 0..<2 {
                swayV[k][a] += (target[a] - pos[k][a]) * stiff + (jitter > 0 ? Double.random(in: -jitter...jitter) : 0)
                swayV[k][a] *= 0.78
                pos[k][a] = ((pos[k][a] + swayV[k][a]) * 400).rounded() / 400
            }
        }
        if pos != rig.frGrav { rig.frGrav = pos; moved = true }
    }
}
}
