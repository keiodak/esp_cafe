// MidiBridge.swift — coco duo (k.odk)
// The Cafes play an OP-1 field (or any Bluetooth MIDI instrument) through the phone: SKIP = a note, FLIP = a chord,
// EARTH = where in the scale. Both Cafes alike, one MIDI channel. Each Cafe's FLIP / SKIP / EARTH come from its
// status line (~30x a second); a rise plays, a fall lets go.

import Combine
import CoreAudioKit
import CoreMIDI
import SwiftUI

final class MidiBridge: ObservableObject {
    /// sending to the instrument (the key on APP+CAFE+OTHER's card)
    @Published var on = true
    /// a Cafe is on APP+CAFE+OTHER (the Director sets it): only then is the instrument played
    @Published var active = false
    /// how many MIDI destinations there are (the OP-1, once paired, is one)
    @Published var destinations = 0
    /// their names (the OP-1 field, once paired, among them)
    @Published var names: [String] = []
    /// COCO+SINE: the phone's sine chords (the Director sets sineOn from the layer)
    var sine: SineChords?
    var sineOn = false
    /// COCO+SINE's DIV: a sine chord on every n-th FLIP (each Cafe counts its own)
    var sineDiv = 1
    private var divCount: [[Int]: Int] = [:]
    /// which variation (OtPad.pages): 0 COCO+ · 1 COCO+SINE · 2 STEP · 3 DRONE · 4 THIRDS
    var mode = 0
    /// BOUNCE's FLIP SYNC: every FLIP that goes up (either Cafe) is one tick
    var onFlip: (() -> Void)?
    private var droneOn = [false, false]
    private var stepChord: [[UInt8]] = [[], []]
    private var stepAt = [0, 0]
    /// the last thing played (shown in the CAFES card: is anything going out?)
    @Published var last = ""
    /// each Cafe's scale, root, octave, range, chord, velocity, length (from APP+CAFE+OTHER's pads: OtPad)
    var settings: [OtSettings] = [OtSettings(), OtSettings()]
    private let channel: UInt8 = 0
    /// a SKIP / FLIP that plays with a set LENGTH: its own number, so a later one is not cut by an earlier timer
    private var token: [[Int]: Int] = [:]
    private var tokens = 0

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    /// what each Cafe's SKIP / FLIP is holding down, to let go of on the fall
    private var held: [[Int]: [UInt8]] = [:]
    private var bag: Set<AnyCancellable> = []

    init() {
        MIDIClientCreateWithBlock("coco duo" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.countDestinations() }
        }
        MIDIOutputPortCreate(client, "to the OP-1" as CFString, &port)
        countDestinations()
    }

    /// listen to these Cafes
    func watch(_ units: [CafeUnit]) {
        for u in units {
            u.$skip.removeDuplicates().dropFirst().sink { [weak self, weak u] v in
                guard let self, let u else { return }
                self.gate([u.slot, 0], v, earth: u.earth, chord: false)
            }.store(in: &bag)
            u.$flip.removeDuplicates().dropFirst().sink { [weak self, weak u] v in
                guard let self, let u else { return }
                self.gate([u.slot, 1], v, earth: u.earth, chord: true)
            }.store(in: &bag)
        }
    }

    func countDestinations() {
        let n = MIDIGetNumberOfDestinations()
        destinations = n
        names = (0..<n).map { i in
            var s: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(MIDIGetDestination(i), kMIDIPropertyDisplayName, &s)
            return (s?.takeRetainedValue() as String?) ?? "MIDI \(i + 1)"
        }
    }

    /// all notes off (when switched off)
    func panic() {
        for s in 0..<2 { for k in [0, 1, 9] { sine?.noteOff([s, k]) } }
        droneOn = [false, false]; stepChord = [[], []]; stepAt = [0, 0]
        for (k, _) in held { sine?.noteOff(k) }
        for (_, notes) in held { for n in notes { send([0x80 | channel, n, 0]) } }
        held = [:]
    }

    // MARK: -

    private func gate(_ key: [Int], _ up: Bool, earth: Int, chord: Bool) {
        let slot = min(max(key[0], 0), 1)
        let st = settings[slot]
        let tag = (slot == 0 ? "A " : "B ") + (chord ? "FLIP " : "SKIP ")
        if mode == OtPad.bounce {                                           // BOUNCE: SKIP / FLIP play nothing; FLIP can be the tick
            if chord && up && active { onFlip?() }
            return
        }
        switch (mode, chord) {
        case (1, true):                                                     // COCO+SINE · FLIP: the phone's sine chord
            if !up { sine?.noteOff(key); return }
            guard on, active else { return }
            divCount[key, default: 0] += 1                                  // DIV: every n-th FLIP plays
            guard (divCount[key]! - 1) % max(1, sineDiv) == 0 else { return }
            let ns = notes(settings[0], earth: earth, chord: true)          // (Cafe A's CHORD · SPREAD · OCTAVE · RANGE)
            sine?.noteOn(key, notes: ns, velocity: 110)
            last = tag + "→ SINE " + names(ns)
            return
        case (3, true):                                                     // DRONE · FLIP: a held sine chord, on / off
            guard up, on, active else { return }
            let dk = [slot, 9]
            if droneOn[slot] { droneOn[slot] = false; sine?.noteOff(dk); last = tag + "→ DRONE off"; return }
            let ns = notes(settings[0], earth: earth, chord: true)
            sine?.noteOn(dk, notes: ns, velocity: 100); droneOn[slot] = true
            last = tag + "→ DRONE " + names(ns)
            return
        case (2, true):                                                     // STEP · FLIP: a new chord (from EARTH), from its first tone
            guard up, on, active else { return }
            stepChord[slot] = notes(st, earth: earth, chord: true); stepAt[slot] = 0
            last = tag + "→ chord " + names(stepChord[slot])
            return
        default: break
        }
        if st.lengthMs == 0 || up { off(key) }                            // (HOLD: the fall lets go; a new rise cuts the last)
        guard on, active, up else { return }
        var ns: [UInt8]
        if mode == 2 {                                                      // STEP · SKIP: the next tone of the chord
            if stepChord[slot].isEmpty { stepChord[slot] = notes(st, earth: earth, chord: true) }
            ns = [stepChord[slot][stepAt[slot] % stepChord[slot].count]]; stepAt[slot] += 1
        } else {
            ns = notes(st, earth: earth, chord: chord)                     // SKIP: one note · FLIP: a chord
        }
        let vel = UInt8(clamping: chord ? max(1, st.velocity - 18) : st.velocity)
        for n in ns { send([0x90 | channel, n, vel]) }
        last = tag + names(ns) + (MIDIGetNumberOfDestinations() == 0 ? "  (no device!)" : "")
        held[key] = ns
        if mode == 4 && !chord {                                            // THIRDS: a sine a third (two scale steps) above
            let t = notes(st, earth: earth, chord: false, up: 2)
            sine?.noteOn(key, notes: t, velocity: Int(vel))
            last += " + SINE " + names(t)
        }
        if st.lengthMs > 0 {                                                // LENGTH: let go after it, whatever the gate does
            tokens += 1; let t = tokens; token[key] = t
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(st.lengthMs)) { [weak self] in
                guard let self, self.token[key] == t else { return }
                self.off(key)
            }
        }
    }

    /// the notes for these settings: EARTH picks where in the scale; a chord is built in the scale (CHORD · SPREAD)
    private func notes(_ st: OtSettings, earth: Int, chord: Bool, up: Int = 0) -> [UInt8] {
        let sc = OtPad.scales[min(max(st.scale, 0), OtPad.scales.count - 1)]
        let base = 24 + 12 * st.octave + st.root                            // C1…C5, moved up to the root
        let steps = sc.count * st.range + 1
        let deg = min(steps - 1, max(0, Int(Double(earth) / 256.0 * Double(steps)))) + up   // EARTH (0…255): where in the scale
        var ds: [Int] = [0]
        if chord {
            switch st.chord {
            case 1: ds = [0, 2, 4, 6]
            case 2: ds = [0, 3, 4]
            case 3: ds = [0, 4, sc.count]
            case 4: ds = [0, 2, 4, 6, 8]
            case 5: ds = [0, sc.count]
            default: ds = [0, 2, 4]
            }
        }
        var ns = ds.map { base + 12 * ((deg + $0) / sc.count) + sc[(deg + $0) % sc.count] }
        if chord && st.spread > 0 && ns.count > 2 {                         // OPEN: the 2nd up an octave · WIDE: every other one
            for i in stride(from: 1, to: ns.count, by: st.spread == 1 ? ns.count : 2) { ns[i] += 12 }
        }
        return ns.map { UInt8(clamping: min(127, max(0, $0))) }
    }
    private func names(_ ns: [UInt8]) -> String {
        let nn = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return ns.map { nn[Int($0) % 12] + "\(Int($0) / 12 - 1)" }.joined(separator: " ")
    }

    private func off(_ key: [Int]) {
        token[key] = nil
        if mode == 4 { sine?.noteOff(key) }                               // (THIRDS: the sine goes with its note)
        if let notes = held.removeValue(forKey: key) { for n in notes { send([0x80 | channel, n, 0]) } }
    }

    /// BOUNCE: one note on the OP-1, let go after `ms`
    func playNote(_ n: UInt8, velocity: UInt8, ms: Int) {
        guard on else { return }                                            // (BOUNCE plays with or without a Cafe)
        send([0x90 | channel, n, velocity])
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(20, ms))) { [weak self] in
            self?.send([0x80 | (self?.channel ?? 0), n, 0])
        }
    }

    private func send(_ bytes: [UInt8]) {
        let n = MIDIGetNumberOfDestinations()
        guard n > 0 else { return }
        var list = MIDIPacketList()
        let p = MIDIPacketListInit(&list)
        _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, p, 0, bytes.count, bytes)
        for i in 0..<n { MIDISend(port, MIDIGetDestination(i), &list) }
    }
}

/// iOS's own Bluetooth MIDI pairing screen (find the OP-1 field there: on it, COM → MIDI → BT)
struct BluetoothMidiPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: CABTMIDICentralViewController())
    }
    func updateUIViewController(_ vc: UINavigationController, context: Context) {}
}

/// APP+CAFE+OTHER: its layers (COCO+ · COCO+SINE, as APP+CAFE's ARP / PHONE_COCO / BOX).
/// (Pairing is in the CAFES card; the scales and the rest are on the XY pads.)
struct Op1Controls: View {
    let d: Director
    @ObservedObject var midi: MidiBridge
    @ObservedObject var rig: Rig
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: "COCO+", filled: rig.otPage != OtPad.bounce) { d.setOtPage(rig.otVar) }
                ChipButton(title: "BOUNCE", filled: rig.otPage == OtPad.bounce) { d.setOtPage(OtPad.bounce) }
            }
            if rig.otPage == OtPad.bounce {                                 // BOUNCE: ALIGN (the phone / OP-1 wait for the Cafes)
                BounceAlignChip(seq: d.bounce)
            }
            if rig.otPage != OtPad.bounce {                                 // COCO+'s five: what SKIP / FLIP play
                HStack(spacing: PanelMetrics.chipSpacing) {
                    ForEach(0..<OtPad.bounce, id: \.self) { v in
                        ChipButton(title: "\(v + 1)", filled: rig.otPage == v) { d.setOtPage(v) }
                    }
                }
            }
        }
    }
}

/// the CAFES card, under the Cafes: the other devices paired with the phone (Bluetooth MIDI: an OP-1F …), one line each
struct DevicesSection: View {
    @ObservedObject var midi: MidiBridge
    @State private var pairing = false
    var body: some View {
        HStack(spacing: 5) {
            HudTag(text: "+", fill: midi.destinations > 0 ? PastelTheme.hudOrange : PastelTheme.hudLine, size: 8)
            Text((midi.names.isEmpty ? "no other device" : midi.names.joined(separator: " · ")) + (midi.last.isEmpty ? "" : "  ♪ " + midi.last))
                .font(.hud(PanelMetrics.labelFont, .semibold))
                .foregroundStyle(midi.names.isEmpty ? PastelTheme.textSecondary : PastelTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            ChipButton(title: "PAIR", filled: false) { pairing = true }.frame(width: 40)
            ChipButton(title: "↻", filled: false) { midi.countDestinations() }.frame(width: 26)
        }
        .sheet(isPresented: $pairing, onDismiss: { midi.countDestinations() }) { BluetoothMidiPicker() }
        .onAppear { midi.countDestinations() }
    }
}
