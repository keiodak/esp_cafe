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
    /// their names (the OP-1 field, once paired, among them)
    @Published var names: [String] = []
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

/// APP+CAFE+OTHER · OP-1F: on / off, the scale, pairing
struct Op1Controls: View {
    @ObservedObject var midi: MidiBridge
    @State private var pairing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: midi.on ? "SENDING" : "MUTED", filled: midi.on) {
                    midi.on.toggle(); if !midi.on { midi.panic() }
                }
                ChipButton(title: MidiBridge.scaleNames[midi.scale], filled: false) {
                    midi.scale = (midi.scale + 1) % MidiBridge.scaleNames.count
                }
                ChipButton(title: "PAIR", filled: false) { pairing = true }
            }
            Text(midi.destinations > 0 ? "to: " + midi.names.joined(separator: " · ") : "nothing paired yet — PAIR, then on the OP-1F: COM → MIDI → BT")
                .font(.hud(8))
                .foregroundStyle(PastelTheme.textSecondary)
                .lineLimit(2)
            Text("SKIP = note · FLIP = chord · EARTH = pitch (both Cafes)")
                .font(.hud(8))
                .foregroundStyle(PastelTheme.textSecondary)
        }
        .sheet(isPresented: $pairing, onDismiss: { midi.countDestinations() }) { BluetoothMidiPicker() }
    }
}

/// the CAFES panel: the other devices paired with the phone (Bluetooth MIDI: an OP-1F …)
struct DevicesCard: View {
    @ObservedObject var midi: MidiBridge
    @State private var pairing = false
    var body: some View {
        PanelCard(title: "OTHER DEVICES", note: midi.destinations > 0 ? "\(midi.destinations) paired" : "none") {
            if midi.names.isEmpty {
                Text("No other device. PAIR finds Bluetooth MIDI ones (OP-1F: COM → MIDI → BT).")
                    .font(.hud(8))
                    .foregroundStyle(PastelTheme.textSecondary)
            }
            ForEach(Array(midi.names.enumerated()), id: \.offset) { _, n in
                HStack(spacing: 5) {
                    Circle().fill(PastelTheme.hudOrange).frame(width: 6, height: 6)
                    Text(n)
                        .font(.hud(PanelMetrics.labelFont, .semibold))
                        .foregroundStyle(PastelTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("MIDI")
                        .font(.hud(8))
                        .foregroundStyle(PastelTheme.textSecondary)
                }
            }
            HStack(spacing: PanelMetrics.chipSpacing) {
                ChipButton(title: "PAIR", filled: false) { pairing = true }.frame(width: 50)
                ChipButton(title: "REFRESH", filled: false) { midi.countDestinations() }.frame(width: 64)
            }
        }
        .sheet(isPresented: $pairing, onDismiss: { midi.countDestinations() }) { BluetoothMidiPicker() }
        .onAppear { midi.countDestinations() }
    }
}
