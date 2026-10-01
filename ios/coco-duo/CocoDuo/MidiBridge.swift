// MidiBridge.swift — coco duo (k.odk)
// The Cafes play an OP-1 field (or any Bluetooth MIDI instrument) through the phone: SKIP = a note, FLIP = a chord,
// EARTH = where in the scale. Both Cafes alike, one MIDI channel. Each Cafe's FLIP / SKIP / EARTH come from its
// status line (~30x a second); a rise plays, a fall lets go.

import Combine
import CoreAudioKit
import CoreMIDI
import SwiftUI

final class MidiBridge: ObservableObject {
    /// sending to the instrument
    @Published var on = false
    /// how many MIDI destinations there are (the OP-1, once paired, is one)
    @Published var destinations = 0
    /// the scale EARTH walks through (0 major · 1 minor · 2 pentatonic · 3 dorian)
    @Published var scale = 2
    static let scaleNames = ["MAJOR", "MINOR", "PENTA", "DORIAN"]
    private static let scales: [[Int]] = [[0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 8, 10], [0, 2, 4, 7, 9], [0, 2, 3, 5, 7, 9, 10]]
    /// the lowest note (C3) and how many steps of the scale EARTH spans (about two octaves)
    private let root = 48
    private let channel: UInt8 = 0

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

    func countDestinations() { destinations = MIDIGetNumberOfDestinations() }

    /// all notes off (when switched off)
    func panic() {
        for (_, notes) in held { for n in notes { send([0x80 | channel, n, 0]) } }
        held = [:]
    }

    // MARK: -

    private func gate(_ key: [Int], _ up: Bool, earth: Int, chord: Bool) {
        if let notes = held.removeValue(forKey: key) { for n in notes { send([0x80 | channel, n, 0]) } }   // (the fall: let go)
        guard on, up else { return }
        let sc = Self.scales[min(scale, Self.scales.count - 1)]
        let steps = sc.count * 2 + 1
        let deg = min(steps - 1, max(0, Int(Double(earth) / 256.0 * Double(steps))))   // EARTH (0…255): where in the scale
        func note(_ d: Int) -> UInt8 { UInt8(clamping: root + 12 * (d / sc.count) + sc[d % sc.count]) }
        let notes: [UInt8] = chord ? [note(deg), note(deg + 2), note(deg + 4)] : [note(deg)]   // (FLIP: its triad in the scale)
        for n in notes { send([0x90 | channel, n, chord ? 90 : 108]) }
        held[key] = notes
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

/// the CAFES panel's card: on / off, the scale, pairing
struct MidiCard: View {
    @ObservedObject var midi: MidiBridge
    @State private var pairing = false
    var body: some View {
        PanelCard(title: "OP-1 MIDI", note: midi.destinations > 0 ? "\(midi.destinations) out" : "not paired") {
            HStack(spacing: 6) {
                ChipButton(title: midi.on ? "ON" : "OFF", filled: midi.on) {
                    midi.on.toggle(); if !midi.on { midi.panic() }
                }.frame(width: 44)
                ChipButton(title: MidiBridge.scaleNames[midi.scale], filled: false) {
                    midi.scale = (midi.scale + 1) % MidiBridge.scaleNames.count
                }.frame(width: 60)
                ChipButton(title: "PAIR", filled: false) { pairing = true }.frame(width: 44)
            }
            Text("SKIP = note · FLIP = chord · EARTH = pitch")
                .font(.hud(8))
                .foregroundStyle(PastelTheme.textSecondary)
        }
        .sheet(isPresented: $pairing, onDismiss: { midi.countDestinations() }) { BluetoothMidiPicker() }
    }
}
