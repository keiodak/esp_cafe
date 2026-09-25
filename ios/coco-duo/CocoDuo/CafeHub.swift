// CafeHub.swift — coco duo (k.odk)
// Two Cafes over BLE at once, each running esp_cafe_duo v3 (presets 1–7, see Modes.swift).
// Text lines (Nordic UART):
//   phone -> Cafe:  P  Q  R <0|1>  W …  G <n>  M/B/Y/N/V <id> <0..1000>  K <bpm x10>  Z  U …
//   Cafe -> phone:  HELLO…  T …  O <bin> <hex>  w <start>  U …
// Firmware update: "U <size> <crc32 hex>" -> "U OK" -> binary pieces [offset LE 4 bytes][data] on OTA_RX,
// at most 8 KB ahead of the Cafe's "U A <written>" -> "U DONE" (it restarts) / "U ERR …" / "U R <from>" (resend)

import Foundation
import CoreBluetooth

let NUS    = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
let NUS_RX = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
let NUS_TX = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
let OTA_RX = CBUUID(string: "6E400004-B5A3-F393-E0A9-E50E24DCCA9E")
let TAPE = 131072
let BINS = 512

struct FoundCafe: Identifiable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral
    var rssi: Int
}

/// Tape overview + heads. Kept apart from the unit so the pads don't redraw 30×/s.
final class CafeScope: ObservableObject {
    @Published var mins = [UInt8](repeating: 128, count: BINS)
    @Published var maxs = [UInt8](repeating: 128, count: BINS)
    @Published var play = 0
    @Published var rec = 0
}

/// One Cafe (slot A or B).
final class CafeUnit: ObservableObject {
    let slot: Int
    @Published var name: String? = nil
    @Published var state = "not connected"
    @Published var recording = true
    @Published var preset = -1
    @Published var hz: Double = 0
    @Published var ls = 0
    @Published var le = TAPE
    @Published var speed = 1000               // x1000
    @Published var earth = 0
    @Published var flip = false
    @Published var skip = false
    @Published var button = false
    /// the BLE preset's mode (0 GRAIN, 1 RUNGLER, 2 DELAY, 3 NOISE) and the Cafe's tempo, as it reports them
    @Published var mode = 0
    @Published var bpm: Double = 0
    /// the Cafe's tempo changed by itself (SKIP was tapped): new BPM
    var onBpm: ((Double) -> Void)?
    /// MULTI: the effect the Cafe is on (it can change it itself: FLIP / SKIP)
    @Published var fx = -1
    var onFx: ((Int) -> Void)?
    /// firmware update: 0…1 while it goes, nil otherwise; and what happened
    @Published var ota: Double? = nil
    @Published var otaNote = ""
    fileprivate var otaChar: CBCharacteristic?
    private var otaData: [UInt8]? = nil
    private var otaSent = 0, otaAcked = 0
    private var otaGo = false
    private var otaT0 = Date()
    private var otaLastR = Date.distantPast
    /// true while a finger edits the loop in the WAVE panel: ignore ls/le from the Cafe
    var holdLoop = false
    /// file loading: 0…1 while samples are going over, nil otherwise
    @Published var loadProgress: Double? = nil
    @Published var loadNote = ""
    let scope = CafeScope()

    fileprivate var peri: CBPeripheral?
    fileprivate var rx: CBCharacteristic?
    fileprivate var inbuf = [UInt8]()
    fileprivate var out: [String] = []
    fileprivate var waitingQ = false
    fileprivate var lastQ = Date.distantPast
    fileprivate var lastSmp: (t: Date, n: UInt32)? = nil
    fileprivate var polls = 0
    // file loading: "W <start> <data>" lines of 128 samples, up to 3 waiting for their "w <start>" answer
    private var loadBuf: [UInt16]? = nil
    private var loadSent = 0
    private var loadDone = 0
    private var loadPending: [Int: (t: Date, tries: Int)] = [:]
    private var loadTimer: Timer?
    private static let loadChunk = 128
    private static let loadWindow = 3
    /// called once the Cafe is ready, so the pads can send their current values
    var onReady: (() -> Void)?

    var isConnected: Bool { rx != nil }
    var savedID: UUID? {
        get { UserDefaults.standard.string(forKey: "cafe.slot\(slot)").flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "cafe.slot\(slot)") }
    }

    init(slot: Int) { self.slot = slot }

    /// one writer; your moves go before the status polls; a newer K (or M/B/Y/N/V with the same id)
    /// replaces an older one that is still waiting
    func send(_ s: String) {
        guard rx != nil, let k = s.first else { return }
        if k == "Q" && !out.isEmpty { waitingQ = false; return }
        let key = Self.key(s)
        if "SLJKXMBYNVCF".contains(k), let i = out.firstIndex(where: { Self.key($0) == key }) { out[i] = s; return }
        out.append(s)
        pump()
    }

    private static func key(_ s: String) -> Substring {
        if s.first == "F" {                                // "F <effect> <id> <v>": effect and id are the key
            let parts = s.split(separator: " ", maxSplits: 3)
            if parts.count >= 4 { return s.prefix(parts[0].count + parts[1].count + parts[2].count + 2) }
            return Substring(s)
        }
        if let f = s.first, "XMBYNVC".contains(f) {     // "M 12", "Y 3", …: the id is part of the key
            let parts = s.split(separator: " ", maxSplits: 2)
            if parts.count >= 2 { return s.prefix(parts[0].count + 1 + parts[1].count) }
        }
        return s.prefix(1)
    }

    fileprivate func pump() {
        guard let p = peri, let c = rx else { return }
        let maxLen = max(20, min(180, p.maximumWriteValueLength(for: .withoutResponse)))
        while !out.isEmpty && p.canSendWriteWithoutResponse {
            var text = ""
            while let first = out.first, text.isEmpty || text.utf8.count + first.utf8.count + 1 <= maxLen {
                text += first + "\n"
                out.removeFirst()
            }
            let d = Array(text.utf8)
            var o = 0
            while o < d.count {
                let e = min(o + maxLen, d.count)
                p.writeValue(Data(d[o..<e]), for: c, type: .withoutResponse)
                o = e
            }
        }
    }

    fileprivate func poll() {
        guard rx != nil, loadBuf == nil, otaData == nil else { return }
        let now = Date()
        if waitingQ && now.timeIntervalSince(lastQ) < 0.3 { return }
        waitingQ = true
        lastQ = now
        send("Q")
    }

    fileprivate func receive(_ d: Data) {
        inbuf.append(contentsOf: d)
        while let i = inbuf.firstIndex(of: 0x0A) {
            let line = String(decoding: inbuf[0..<i], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            inbuf.removeSubrange(0...i)
            if !line.isEmpty { handle(line) }
        }
        if inbuf.count > 100_000 { inbuf.removeAll() }
    }

    private func handle(_ l: String) {
        if l.hasPrefix("HELLO") { return }
        guard let c = l.first else { return }
        switch c {
        case "T":
            let a = l.split(separator: " ")
            guard a.count >= 13 else { return }
            let smp = UInt32(a[11]) ?? 0
            let now = Date()
            if let last = lastSmp {
                let dt = now.timeIntervalSince(last.t)
                if dt > 0.5 { hz = Double(smp &- last.n) / dt; lastSmp = (now, smp) }
            } else { lastSmp = (now, smp) }
            let w = Int(a[1]) ?? 0, p = Int(a[2]) ?? 0
            if scope.rec != w { scope.rec = w }
            if scope.play != p { scope.play = p }
            let r = a[3] == "1"
            if recording != r { recording = r }
            let l0 = Int(a[4]) ?? 0, l1 = Int(a[5]) ?? TAPE
            if !holdLoop {
                if ls != l0 { ls = l0 }
                if le != l1 { le = l1 }
            }
            let sp = Int(a[6]) ?? 1000, ea = Int(a[7]) ?? 0
            if speed != sp { speed = sp }
            if earth != ea { earth = ea }
            let f = a[8] == "1", k = a[9] == "1", bt = a[10] == "1"
            if flip != f { flip = f }
            if skip != k { skip = k }
            if button != bt { button = bt }
            let pr = Int(a[12]) ?? -1
            if preset != pr { preset = pr }
            if a.count >= 15 {
                let m = Int(a[13]) ?? 0
                if mode != m { mode = m }
                let b = (Double(a[14]) ?? 0) / 10
                if a.count >= 16, let e = Int(a[15]), e != fx { fx = e; onFx?(e) }
                if abs(b - bpm) > 0.05 {
                    let first = bpm == 0
                    bpm = b
                    if !first { onBpm?(b) }
                }
            }
            waitingQ = false
            polls += 1
        case "U":
            otaLine(l)
        case "w":
            let a = l.split(separator: " ")
            guard a.count >= 2, let st = Int(a[1]), loadPending.removeValue(forKey: st) != nil else { return }
            loadDone += 1
            loadFill()
        case "O":
            let a = l.split(separator: " ")
            guard a.count >= 3, let bin = Int(a[1]) else { return }
            let h = Array(a[2].utf8)
            var mn = scope.mins, mx = scope.maxs
            var k = 0
            while k < 16 && k * 4 + 3 < h.count {
                let b = (bin + k) % BINS
                mn[b] = UInt8(Self.hex(h[k*4]) << 4 | Self.hex(h[k*4+1]))
                mx[b] = UInt8(Self.hex(h[k*4+2]) << 4 | Self.hex(h[k*4+3]))
                k += 1
            }
            scope.mins = mn; scope.maxs = mx
        default:
            break
        }
    }

    // MARK: file loading

    /// Put these samples on the tape from the start. Recording is switched off first
    /// (otherwise the record head would write over the file), and the loop is set to the file.
    func load(_ samples: [UInt16]) {
        guard rx != nil, loadBuf == nil, !samples.isEmpty else { return }
        loadBuf = samples
        loadSent = 0; loadDone = 0; loadPending = [:]
        loadProgress = 0; loadNote = ""
        send("R 0")
        loadTimer?.invalidate()
        loadTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.loadWatch() }
        loadFill()
    }

    private func loadFill() {
        guard let buf = loadBuf else { return }
        while loadPending.count < Self.loadWindow && loadSent < buf.count {
            sendW(loadSent)
            loadPending[loadSent] = (Date(), 1)
            loadSent += Self.loadChunk
        }
        let lines = (buf.count + Self.loadChunk - 1) / Self.loadChunk
        loadProgress = Double(loadDone) / Double(max(1, lines))
        if loadPending.isEmpty && loadSent >= buf.count {
            loadTimer?.invalidate(); loadTimer = nil
            loadBuf = nil; loadProgress = nil
            loadNote = String(format: "loaded %.2f s", hz > 1000 ? Double(buf.count) / hz : Double(buf.count) / 44100)
        }
    }

    private func sendW(_ start: Int) {
        guard let buf = loadBuf else { return }
        let end = min(buf.count, start + Self.loadChunk)
        var bytes = [UInt8]()
        bytes.reserveCapacity((end - start) * 2)
        for i in start..<end {
            let v = Int(buf[i])
            bytes.append(UInt8(48 + ((v >> 6) & 63)))
            bytes.append(UInt8(48 + (v & 63)))
        }
        send("W \(start) " + String(decoding: bytes, as: UTF8.self))
    }

    /// resend a line that got no answer; give up on the file after 5 tries
    private func loadWatch() {
        guard loadBuf != nil else { return }
        guard rx != nil else { cancelLoad("connection lost while loading"); return }
        let now = Date()
        for (st, p) in loadPending where now.timeIntervalSince(p.t) > 0.8 {
            if p.tries >= 5 { cancelLoad("the Cafe stopped answering"); return }
            loadPending[st] = (now, p.tries + 1)
            sendW(st)
        }
    }

    private func cancelLoad(_ why: String) {
        loadTimer?.invalidate(); loadTimer = nil
        loadBuf = nil; loadPending = [:]; loadProgress = nil
        loadNote = why
    }

    // MARK: firmware update over BLE

    /// write this .bin (Arduino IDE: Sketch > Export Compiled Binary, the plain .ino.bin) to the Cafe
    func startUpdate(_ data: [UInt8]) {
        guard rx != nil else { otaNote = "not connected"; return }
        guard otaChar != nil else { otaNote = "no update receiver: upload esp_cafe_duo over USB once"; return }
        guard data.count > 1024, data.first == 0xE9 else { otaNote = "not an ESP32 app image (.ino.bin)"; return }
        guard otaData == nil else { return }
        otaData = data; otaSent = 0; otaAcked = 0; otaGo = false
        ota = 0; otaNote = "asking the Cafe…"; otaT0 = Date()
        out.removeAll()
        send("U \(data.count) \(String(Self.crc32(data), radix: 16))")
    }

    fileprivate func pumpOta() {
        guard otaGo, let data = otaData, let p = peri, let c = otaChar else { return }
        let size = max(16, min(240, p.maximumWriteValueLength(for: .withoutResponse)) - 4)
        while otaSent < data.count && otaSent - otaAcked < 8192 && p.canSendWriteWithoutResponse {
            let n = min(size, data.count - otaSent)
            let o = UInt32(otaSent)
            var pk = [UInt8(o & 0xFF), UInt8((o >> 8) & 0xFF), UInt8((o >> 16) & 0xFF), UInt8((o >> 24) & 0xFF)]
            pk.append(contentsOf: data[otaSent..<(otaSent + n)])
            p.writeValue(Data(pk), for: c, type: .withoutResponse)
            otaSent += n
        }
    }

    private func otaLine(_ l: String) {
        guard otaData != nil else { return }
        let a = l.split(separator: " ")
        guard a.count >= 2 else { return }
        switch a[1] {
        case "OK":
            otaGo = true; otaT0 = Date(); otaNote = "writing…"
            pumpOta()
        case "A":
            otaAcked = Int(a.count > 2 ? a[2] : "0") ?? otaAcked
            if otaSent < otaAcked { otaSent = otaAcked }
            if let d = otaData {
                ota = Double(otaAcked) / Double(d.count)
                let t = max(0.1, Date().timeIntervalSince(otaT0))
                otaNote = String(format: "%ld / %ld KB · %.1f KB/s", otaAcked / 1024, d.count / 1024, Double(otaAcked) / 1024 / t)
            }
            pumpOta()
        case "R":
            if Date().timeIntervalSince(otaLastR) > 0.25, a.count > 2, let from = Int(a[2]) {
                otaLastR = Date()
                otaSent = max(otaAcked, from)
            }
            pumpOta()
        case "DONE":
            otaNote = String(format: "done in %.0f s · restarting", Date().timeIntervalSince(otaT0))
            otaData = nil; ota = nil; otaGo = false
        case "ERR":
            otaNote = "failed: " + a.dropFirst(2).joined(separator: " ") + " (old firmware kept)"
            otaData = nil; ota = nil; otaGo = false
        default:
            break
        }
    }

    private static func crc32(_ b: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for x in b {
            c ^= UInt32(x)
            for _ in 0..<8 { c = (c >> 1) ^ (0xEDB88320 & (0 &- (c & 1))) }
        }
        return ~c
    }

    private static func hex(_ c: UInt8) -> Int {
        switch c {
        case 48...57: return Int(c) - 48
        case 65...70: return Int(c) - 55
        case 97...102: return Int(c) - 87
        default: return 0
        }
    }

    fileprivate func reset(_ why: String) {
        if loadBuf != nil { cancelLoad("connection lost while loading") }
        if otaData != nil { otaNote = "connection lost (the Cafe keeps its old firmware)"; otaData = nil; ota = nil; otaGo = false }
        otaChar = nil
        rx = nil; peri = nil; name = nil
        out.removeAll(); inbuf.removeAll()
        waitingQ = false; lastSmp = nil; polls = 0
        hz = 0; preset = -1; bpm = 0; fx = -1
        state = why
    }
}

/// The Bluetooth side: one central, two slots.
final class CafeHub: NSObject, ObservableObject {
    let units = [CafeUnit(slot: 0), CafeUnit(slot: 1)]
    @Published var found: [FoundCafe] = []
    @Published var bluetoothReady = false

    private var central: CBCentralManager!
    private var pollTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.units.forEach { $0.poll() }
        }
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        found = []
        central.scanForPeripherals(withServices: [NUS], options: nil)
    }
    func stopScan() { if central.isScanning { central.stopScan() } }

    /// put this Cafe in slot A (0) or B (1)
    func assign(_ f: FoundCafe, to slot: Int) {
        let u = units[slot]
        let other = units[1 - slot]
        if other.peri?.identifier == f.id { disconnect(1 - slot); other.savedID = nil }
        if let p = u.peri, p.identifier != f.id { central.cancelPeripheralConnection(p) }
        u.savedID = f.id
        connect(f.peripheral, slot: slot)
    }

    func disconnect(_ slot: Int) {
        let u = units[slot]
        if let p = u.peri { central.cancelPeripheralConnection(p) }
        u.reset("not connected")
    }

    func forget(_ slot: Int) { disconnect(slot); units[slot].savedID = nil }

    private func connect(_ p: CBPeripheral, slot: Int) {
        let u = units[slot]
        u.peri = p
        p.delegate = self
        u.state = "connecting…"
        central.connect(p, options: nil)
    }

    /// on launch: reconnect the Cafes used last time
    private func reconnectSaved() {
        for u in units where u.peri == nil {
            guard let id = u.savedID,
                  let p = central.retrievePeripherals(withIdentifiers: [id]).first else { continue }
            connect(p, slot: u.slot)
        }
    }

    private func unit(for p: CBPeripheral) -> CafeUnit? {
        units.first { $0.peri?.identifier == p.identifier }
    }
}

extension CafeHub: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        bluetoothReady = c.state == .poweredOn
        if bluetoothReady { reconnectSaved() }
        else {
            let why = c.state == .unauthorized ? "Bluetooth not allowed" : "Bluetooth off"
            units.forEach { $0.reset(why) }
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? "Cafe"
        if let i = found.firstIndex(where: { $0.id == p.identifier }) { found[i].rssi = RSSI.intValue }
        else { found.append(FoundCafe(id: p.identifier, name: name, peripheral: p, rssi: RSSI.intValue)) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        unit(for: p)?.state = "looking for the Cafe service…"
        p.discoverServices([NUS])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        unit(for: p)?.reset("could not connect")
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard let u = unit(for: p) else { return }
        u.reset(error == nil ? "not connected" : "connection lost — retrying")
        // came back into range / powered on again: iOS keeps this pending until the Cafe appears
        if error != nil, u.savedID == p.identifier { connect(p, slot: u.slot) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == NUS }) else { unit(for: p)?.state = "not a coco-pc Cafe"; return }
        p.discoverCharacteristics([NUS_RX, NUS_TX, OTA_RX], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let u = unit(for: p) else { return }
        for c in s.characteristics ?? [] {
            if c.uuid == NUS_RX { u.rx = c }
            if c.uuid == NUS_TX { p.setNotifyValue(true, for: c) }
            if c.uuid == OTA_RX { u.otaChar = c }
        }
        guard u.rx != nil else { u.state = "Cafe service incomplete"; return }
        u.name = p.name ?? "Cafe"
        u.state = "connected"
        u.send("P")
        u.onReady?()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let v = c.value { unit(for: p)?.receive(v) }
    }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        guard let u = unit(for: p) else { return }
        u.pump()
        u.pumpOta()
    }
}
