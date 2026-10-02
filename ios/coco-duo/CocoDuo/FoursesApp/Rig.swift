// Rig.swift — Fourses (k.odk)
// (in coco duo: the Fourses app as it is, inside FA — iOS · FOURSES)
// What the screen shows and the engine is set to; kept between launches.

import Foundation
import Combine

extension FA {
/// what the engine shows back (~30x a second): its own object, so the board is not drawn again for it
final class Meters: ObservableObject {
    @Published var leds: [Double] = Array(repeating: 0, count: 8)
    /// each horse's CV (0…1): the LED's colour, cold to warm
    @Published var cv: [Double] = Array(repeating: 0, count: 8)
    /// how much current each icon passes through its links (0…1, a log scale): its colour, cold to warm
    @Published var activity: [Double] = []
    @Published var supply = 8.4
    /// the output's level (0…1, falling slowly): VOLUME's meter
    @Published var level = 0.0
}

/// the shapes' flicker and sway now (~30x a second): its own object, so only the board is drawn again for it
final class Live: ObservableObject {
    @Published var flick: [Double] = []
    @Published var grav: [[Double]] = []
}

final class Rig: ObservableObject {
    let meters = Meters()
    let live = Live()
    // the board
    @Published var frIcons: [[Double]]
    @Published var frShapes: [[Double]]
    @Published var frMode = 0                  // 0 PLAY · 1 DRAW · 2 EDIT
    @Published var frShape = 0                 // ○ △ □ ／ ✎ (a free stroke)
    var frFlick: [Double] { get { live.flick } set { live.flick = newValue } }      // ◌ each one's contact now
    var frGrav: [[Double]] { get { live.grav } set { live.grav = newValue } }       // ◉ each one's offset now
    // the pots: 0…3 TARPTERGE, 4…7 ARPSERGE
    @Published var frPots: [Double] = Array(repeating: 0.5, count: 8)
    @Published var frRanges: [Int] = Array(repeating: 2, count: 8)   // 0 CV · 1 LOW · 2 AUDIO
    @Published var frStarve = 0.5
    // the filters at the end
    @Published var dubOn = false
    @Published var dubFreq: [Double] = [0.45, 0.55]
    @Published var dubRes: [Double] = [0.6, 0.6]
    @Published var level = 0.8
    @Published var danger = false             // ANALOG: the hardware's hard highs, its attacks held down
    // what a new shape gets (DRAW's pills): its flicker (0 none · SLOW · FAST · IRREG · DRUNK) and sway (0 none · SLOW ·
    // FAST · IRREG · DRUNK · TILT); the panel sets how fast (around each kind's own) and how deep / how far
    @Published var drawWidth = 1               // a line's / a free stroke's width (FrBoard.lineWidths)
    @Published var drawDash = 0                // a straight line's kind: 0 solid · 1 long dashes · 2 short dashes
    @Published var drawFlick = 0
    @Published var drawSway = 0
    @Published var flickRate = 0.5
    @Published var flickDepth = 0.8
    @Published var swayRate = 0.5
    @Published var swayReach = 0.35
    // the panel, the presets
    @Published var panelOpen = false
    @Published var preset = 0                 // (the last one loaded or kept: 1…8, 0 none)
    @Published var presetsKept: Set<Int> = []

    private struct Saved: Codable {
        var icons: [[Double]]; var shapes: [[Double]]
        var pots: [Double]; var ranges: [Int]; var starve: Double
        var dubOn: Bool; var dubFreq: [Double]; var dubRes: [Double]; var level: Double
        var flick: [Double]?; var sway: [Double]?
    }
    private static let key = "fourses.rig.v2"
    private var bag: Set<AnyCancellable> = []

    init() {
        let first = FrBoard.defaultLayout()
        frIcons = first.icons
        frShapes = first.shapes
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(Saved.self, from: data), s.icons.count >= FrBoard.count - 2 {
            apply(s)
        }
        for k in 0..<2 { frIcons[FrBoard.icon(ofNode: FrBoard.cafeNode(k))] = FrBoard.parked }   // (no Cafe linked yet: CAFE off the board)
        for n in 1...8 where UserDefaults.standard.data(forKey: Self.presetKey(n)) != nil { presetsKept.insert(n) }
        // (kept a moment after the last change)
        // (not the LEDs, the supply, ◌ or ◉: they move all the time)
        let changes: [AnyPublisher<Void, Never>] = [
            $frIcons.map { _ in () }.eraseToAnyPublisher(), $frShapes.map { _ in () }.eraseToAnyPublisher(),
            $frPots.map { _ in () }.eraseToAnyPublisher(), $frRanges.map { _ in () }.eraseToAnyPublisher(),
            $frStarve.map { _ in () }.eraseToAnyPublisher(), $dubOn.map { _ in () }.eraseToAnyPublisher(),
            $dubFreq.map { _ in () }.eraseToAnyPublisher(), $dubRes.map { _ in () }.eraseToAnyPublisher(),
            $level.map { _ in () }.eraseToAnyPublisher(),
            $flickRate.map { _ in () }.eraseToAnyPublisher(), $flickDepth.map { _ in () }.eraseToAnyPublisher(),
            $swayRate.map { _ in () }.eraseToAnyPublisher(), $swayReach.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .dropFirst(changes.count)
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &bag)
    }

    private func snapshot() -> Saved {
        Saved(icons: frIcons, shapes: frShapes, pots: frPots, ranges: frRanges, starve: frStarve,
              dubOn: dubOn, dubFreq: dubFreq, dubRes: dubRes, level: level,
              flick: [flickRate, flickDepth], sway: [swayRate, swayReach])
    }
    private func apply(_ s: Saved) {
        if s.icons.count == FrBoard.count { frIcons = s.icons }
        else if s.icons.count >= FrBoard.count - 2 && s.icons.count < FrBoard.count {           // (kept before CAFE A / B came)
            frIcons = s.icons + Array(repeating: FrBoard.parked, count: FrBoard.count - s.icons.count)
        }
        frShapes = s.shapes
        if s.pots.count == 8 { frPots = s.pots }
        if s.ranges.count == 8 { frRanges = s.ranges }
        frStarve = s.starve
        dubOn = s.dubOn
        if s.dubFreq.count == 2 { dubFreq = s.dubFreq }
        if s.dubRes.count == 2 { dubRes = s.dubRes }
        level = s.level
        if let f = s.flick, f.count >= 2 { flickRate = f[f.count - 2]; flickDepth = f[f.count - 1] }
        if let w = s.sway, w.count >= 2 { swayRate = w[w.count - 2]; swayReach = w[w.count - 1] }
    }

    func save() {
        if let data = try? JSONEncoder().encode(snapshot()) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    // MARK: presets 1…8

    private static func presetKey(_ n: Int) -> String { "fourses.preset.\(n)" }
    /// keeps everything now under the number
    func keepPreset(_ n: Int) {
        guard let data = try? JSONEncoder().encode(snapshot()) else { return }
        UserDefaults.standard.set(data, forKey: Self.presetKey(n))
        presetsKept.insert(n); preset = n
    }
    /// takes it back (false: nothing kept there)
    func loadPreset(_ n: Int) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.presetKey(n)),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return false }
        apply(s); preset = n
        return true
    }
}
}
