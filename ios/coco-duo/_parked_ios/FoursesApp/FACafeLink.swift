// FACafeLink.swift — Fourses (k.odk)
// (in coco duo: the Fourses app as it is, inside FA — iOS · FOURSES)
// The cup: Fourses linked to Cafes, two: A and B. In coco duo these are coco duo's own Cafes A / B (its Bluetooth,
// its link): the cup's panel shows them, LET GO / LINK each. While one is linked (and FOURSES is on the screen) the
// board has its terminal — CAFE A (node 90) / CAFE B (91): whatever it is joined to goes to that Cafe's ASH output
// as a voltage ("F 83 <0…4095>"; firmware v4.70 or later), and the Cafe goes on with its own preset otherwise.

import Combine
import Foundation

extension FA {
/// a Cafe slot: A (0) or B (1) — coco duo's Cafe of that letter
final class CafeSlot: ObservableObject {
    enum State { case off, linking, linked }
    let slot: Int
    @Published fileprivate(set) var state: State = .off
    @Published fileprivate(set) var name = ""
    /// its firmware; "F 83" needs 4.70 or later
    @Published fileprivate(set) var fw = ""
    var linked: Bool { state == .linked }
    /// coco duo has it (it can be linked here)
    @Published fileprivate(set) var available = false
    /// Bluetooth's lag, as coco duo measures it (half a ping; ms, 0 = not yet)
    @Published fileprivate(set) var lagMs = 0.0
    fileprivate weak var unit: CafeUnit?
    /// LET GO pressed (kept)
    fileprivate var letGo: Bool {
        get { UserDefaults.standard.bool(forKey: "fourses.letGo\(slot)") }
        set { UserDefaults.standard.set(newValue, forKey: "fourses.letGo\(slot)") }
    }
    private var lastSent = -100
    private var lastAt = Date.distantPast
    init(slot: Int) { self.slot = slot }

    /// what ASH has been sent, the last ~2 s (0…1 of its range, newest last) — the panel draws it
    @Published private(set) var trace: [Double] = []
    /// its CAFE terminal, 0…1 of the range it moves in -> the Cafe's ASH (0…4095): sent when it moves, and twice a second anyway
    func ash(level: Double) {
        guard linked else { return }
        let f = max(0, min(1, level))
        trace.append(f)
        if trace.count > 120 { trace.removeFirst(trace.count - 120) }
        let v = Int(f * 4095)
        let now = Date()
        if abs(v - lastSent) < 3 && now.timeIntervalSince(lastAt) < 0.5 { return }
        lastSent = v; lastAt = now
        send("F 83 \(v)")
    }
    fileprivate func send(_ s: String) { unit?.send(s) }
    fileprivate func cleared() { lastSent = -100; trace = [] }
    /// a ping: coco duo times the round trip
    func ping() { if linked { unit?.ping() } }
}

final class CafeLinks: ObservableObject {
    static let maxSlots = 2
    let slots = (0..<CafeLinks.maxSlots).map { CafeSlot(slot: $0) }
    @Published var panelOpen = false
    /// ASH's two sliders (kept): SPREAD — 0 the plain 0…9 V · 1 the range it moves in stretched over all of ASH;
    /// SMOOTH — 0 every jump as it is · 1 slow and soft (~⅓ s)
    @Published var spread: Double = (UserDefaults.standard.object(forKey: "fourses.ashSpread") as? Double) ?? 0.5 {
        didSet { UserDefaults.standard.set(spread, forKey: "fourses.ashSpread") }
    }
    @Published var smooth: Double = (UserDefaults.standard.object(forKey: "fourses.ashSmooth") as? Double) ?? 0.68 {
        didSet { UserDefaults.standard.set(smooth, forKey: "fourses.ashSmooth") }
    }
    /// SYNC (by itself, while a Cafe is linked): how long the phone's sound is held back now, so it meets the Cafes'
    /// ASH (ms; Director sets it)
    @Published var holdMs = 0
    /// a slot linked (true) / let go (false): the board shows or hides its CAFE terminal
    var onLinked: ((Int, Bool) -> Void)?
    var anyLinked: Bool { slots.contains { $0.linked } }
    /// FOURSES on the screen (off: nothing linked, the Cafes' ASH their own)
    var enabled = false { didSet { if enabled != oldValue { poll() } } }

    private var timer: Timer?
    private var bag: Set<AnyCancellable> = []

    init(units: [CafeUnit]) {
        for s in slots {
            s.unit = s.slot < units.count ? units[s.slot] : nil
            s.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)   // (the cup shows them)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    /// coco duo's Cafes as they are now -> A / B
    private func poll() {
        for s in slots {
            let u = s.unit
            let there = u?.isConnected ?? false
            if s.available != there { s.available = there }
            let nm = (u?.name ?? "").uppercased(), fw = u?.fw ?? "", lag = u?.lagMs ?? 0
            if s.name != nm { s.name = nm }
            if s.fw != fw { s.fw = fw }
            if s.lagMs != lag { s.lagMs = lag }
            let want: CafeSlot.State = enabled && there && !s.letGo ? .linked : .off
            guard want != s.state else { continue }
            let was = s.linked
            if was && there { s.send("F 83 -1") }                              // (its ASH back to its preset)
            s.state = want
            s.cleared()
            if was != s.linked { onLinked?(s.slot, s.linked) }
        }
    }
    /// let go of slot k (its ASH back to the Cafe's preset)
    func unlink(_ k: Int) { slots[k].letGo = true; poll() }
    /// link slot k again
    func relink(_ k: Int) { slots[k].letGo = false; poll() }
}
}
