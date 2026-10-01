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
        for (_, notes) in held { for n in notes { send([0x80 | channel, n, 0]) } }
        held = [:]
    }

    // MARK: -

    private func gate(_ key: [Int], _ up: Bool, earth: Int, chord: Bool) {
        let st = settings[min(max(key[0], 0), 1)]
        if st.lengthMs == 0 || up { off(key) }                            // (HOLD: the fall lets go; a new rise cuts the last)
        guard on, active, up else { return }
        let sc = OtPad.scales[min(max(st.scale, 0), OtPad.scales.count - 1)]
        let base = 24 + 12 * st.octave + st.root                            // C1…C5, moved up to the root
        let steps = sc.count * st.range + 1
        let deg = min(steps - 1, max(0, Int(Double(earth) / 256.0 * Double(steps))))   // EARTH (0…255): where in the scale
        func note(_ d: Int) -> Int { base + 12 * (d / sc.count) + sc[d % sc.count] }
        var ds: [Int]
        if !chord { ds = [0] }
        else {
            switch st.chord {                                               // (FLIP: a chord built in the scale)
            case 1: ds = [0, 2, 4, 6]
            case 2: ds = [0, 3, 4]
            case 3: ds = [0, 4, sc.count]
            case 4: ds = [0, 2, 4, 6, 8]
            case 5: ds = [0, sc.count]
            default: ds = [0, 2, 4]
            }
        }
        var ns = ds.map { note(deg + $0) }
        if chord && st.spread > 0 && ns.count > 2 {                         // OPEN: the 2nd up an octave · WIDE: every other one
            for i in stride(from: 1, to: ns.count, by: st.spread == 1 ? ns.count : 2) { ns[i] += 12 }
        }
        let notes = ns.map { UInt8(clamping: min(127, max(0, $0))) }
        let vel = UInt8(clamping: chord ? max(1, st.velocity - 18) : st.velocity)
        for n in notes { send([0x90 | channel, n, vel]) }
        let nn = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        last = (key[0] == 0 ? "A " : "B ") + (chord ? "FLIP " : "SKIP ") + notes.map { nn[Int($0) % 12] + "\(Int($0) / 12 - 1)" }.joined(separator: " ")
            + (MIDIGetNumberOfDestinations() == 0 ? "  (no device!)" : "")
        held[key] = notes
        if st.lengthMs > 0 {                                                // LENGTH: let go after it, whatever the gate does
            tokens += 1; let t = tokens; token[key] = t
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(st.lengthMs)) { [weak self] in
                guard let self, self.token[key] == t else { return }
                self.off(key)
            }
        }
    }
    private func off(_ key: [Int]) {
        token[key] = nil
        if let notes = held.removeValue(forKey: key) { for n in notes { send([0x80 | channel, n, 0]) } }
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

/// APP+CAFE+OTHER: its layers (BASIC first, as APP+CAFE's ARP / PHONE_COCO / BOX) and LINK SCALE.
/// (Pairing is in the CAFES card; the scales and the rest are on the XY pads.)
struct Op1Controls: View {
    let d: Director
    @ObservedObject var midi: MidiBridge
    @ObservedObject var rig: Rig
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: PanelMetrics.chipSpacing) {
                ForEach(OtPad.pages.indices, id: \.self) { p in
                    ChipButton(title: OtPad.pages[p], filled: rig.otPage == p) { rig.otPage = p; d.refresh() }
                }
            }
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: "LINK SCALE", filled: rig.otLink) { d.setOtLink(!rig.otLink) }
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
