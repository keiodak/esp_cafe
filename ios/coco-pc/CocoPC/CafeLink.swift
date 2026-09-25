// CafeLink.swift — coco-pc for iPhone (k.odk)
// Talks to the Cafe BLE firmware (esp_cafe_ble) over the Nordic UART Service.
// Same text lines as the USB page coco-pc.html:
//   iPhone -> Cafe:  P  Q  H  S <milli>  L <a> <b>  J <pos>  R <0|1>  D <start>
//   Cafe -> iPhone:  HELLO…  T …  O <bin> <hex>  B <start> <hex>  H …

import Foundation
import CoreBluetooth

let NUS    = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
let NUS_RX = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")   // iPhone -> Cafe (write)
let NUS_TX = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")   // Cafe -> iPhone (notify)
let TAPE = 131072          // samples in the Cafe buffer
let BINS = 512             // overview bins (256 samples each)

struct CafeStatus {
    var w = 0, p = 0, rec = true, ls = 0, le = TAPE, speed = 1000
    var earth = 0, flip = false, skip = false, btn = false, preset = -1
}

struct FoundCafe: Identifiable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral
    var rssi: Int
}

final class CafeLink: NSObject, ObservableObject {
    @Published var found: [FoundCafe] = []
    @Published var connectedName: String? = nil
    @Published var state = "not connected"
    @Published var st = CafeStatus()
    @Published var mins = [UInt8](repeating: 128, count: BINS)
    @Published var maxs = [UInt8](repeating: 128, count: BINS)
    @Published var hz: Double = 0
    @Published var message = ""
    @Published var dumpProgress: Double? = nil
    @Published var wavURL: URL? = nil
    @Published var polls = 0

    var holdLoop = false                    // true while a finger edits the loop: ignore ls/le from the Cafe

    private var central: CBCentralManager!
    private var peri: CBPeripheral?
    private var rx: CBCharacteristic?
    private var inbuf = [UInt8]()
    private var out: [String] = []
    private var waitingQ = false
    private var lastQ = Date.distantPast
    private var pollTimer: Timer?
    private var lastSmp: (t: Date, n: UInt32)? = nil
    private var dumpBuf: [UInt16]? = nil
    private var dumpWant = -1
    private var dumpTries = 0
    private var dumpT = Date()
    private var dumpTimer: Timer?

    var isConnected: Bool { rx != nil }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)      // callbacks on the main thread
    }

    // MARK: scan / connect

    func startScan() {
        guard central.state == .poweredOn else { message = "Bluetooth is off, or coco-pc is not allowed to use it (Settings > coco-pc)."; return }
        found = []
        central.scanForPeripherals(withServices: [NUS], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    func stopScan() { if central.isScanning { central.stopScan() } }

    func connect(_ f: FoundCafe) {
        stopScan()
        peri = f.peripheral
        f.peripheral.delegate = self
        connectedName = nil
        state = "connecting to \(f.name)…"
        central.connect(f.peripheral, options: nil)
    }
    func disconnect() { if let p = peri { central.cancelPeripheralConnection(p) } }

    // MARK: sending (one writer, commands before polls, newer S/L/J replaces an older one still waiting)

    func send(_ s: String) {
        guard rx != nil, let k = s.first else { return }
        if k == "Q" && !out.isEmpty { waitingQ = false; return }
        if "SLJ".contains(k), let i = out.firstIndex(where: { $0.first == k }) { out[i] = s; return }
        out.append(s)
        pump()
    }

    private func pump() {
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

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self, self.rx != nil, self.dumpBuf == nil else { return }
            let now = Date()
            if self.waitingQ && now.timeIntervalSince(self.lastQ) < 0.3 { return }   // wait for the reply (max 300 ms)
            self.waitingQ = true
            self.lastQ = now
            self.send("Q")
        }
    }

    // MARK: receiving

    private func receive(_ d: Data) {
        inbuf.append(contentsOf: d)
        while let i = inbuf.firstIndex(of: 0x0A) {
            let line = String(decoding: inbuf[0..<i], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            inbuf.removeSubrange(0...i)
            if !line.isEmpty { handle(line) }
        }
        if inbuf.count > 100_000 { inbuf.removeAll() }
    }

    private func handle(_ l: String) {
        if l.hasPrefix("HELLO") { message = "Cafe: " + l; return }
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
            var s = CafeStatus()
            s.w = Int(a[1]) ?? 0; s.p = Int(a[2]) ?? 0; s.rec = a[3] == "1"
            s.ls = Int(a[4]) ?? 0; s.le = Int(a[5]) ?? TAPE; s.speed = Int(a[6]) ?? 1000
            s.earth = Int(a[7]) ?? 0; s.flip = a[8] == "1"; s.skip = a[9] == "1"; s.btn = a[10] == "1"
            s.preset = Int(a[12]) ?? -1
            if holdLoop { s.ls = st.ls; s.le = st.le }
            st = s
            waitingQ = false
            polls += 1
        case "O":
            let a = l.split(separator: " ")
            guard a.count >= 3, let bin = Int(a[1]) else { return }
            let h = Array(a[2].utf8)
            var mn = mins, mx = maxs
            var k = 0
            while k < 16 && k * 4 + 3 < h.count {
                let b = (bin + k) % BINS
                mn[b] = UInt8(hex(h[k*4]) << 4 | hex(h[k*4+1]))
                mx[b] = UInt8(hex(h[k*4+2]) << 4 | hex(h[k*4+3]))
                k += 1
            }
            mins = mn; maxs = mx
        case "B":
            guard dumpBuf != nil else { return }
            let a = l.split(separator: " ")
            guard a.count >= 3, let start = Int(a[1]), start >= 0, start + 256 <= TAPE else { return }
            let h = Array(a[2].utf8)
            var k = 0
            while k < 256 && k * 3 + 2 < h.count {
                dumpBuf![start + k] = UInt16(hex(h[k*3]) << 8 | hex(h[k*3+1]) << 4 | hex(h[k*3+2]))
                k += 1
            }
            if start == dumpWant { dumpNext(start + 256) }
        case "H":
            message = "check: " + l.dropFirst(2)
        default:
            break
        }
    }

    private func hex(_ c: UInt8) -> Int {
        switch c {
        case 48...57: return Int(c) - 48
        case 65...70: return Int(c) - 55
        case 97...102: return Int(c) - 87
        default: return 0
        }
    }

    // MARK: save the whole tape as a WAV

    func saveWav() {
        guard rx != nil, dumpBuf == nil else { return }
        dumpBuf = [UInt16](repeating: 2048, count: TAPE)
        wavURL = nil
        dumpTimer?.invalidate()
        dumpTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.dumpWatch() }
        dumpNext(0)
    }

    private func dumpNext(_ start: Int) {
        if start >= TAPE { finishDump(); return }
        dumpWant = start
        dumpTries = 1
        dumpT = Date()
        dumpProgress = Double(start) / Double(TAPE)
        send("D \(start)")
    }

    private func dumpWatch() {
        guard dumpBuf != nil, rx != nil else { return }
        if Date().timeIntervalSince(dumpT) > 0.4 {                      // no answer: ask again, give up after 3 tries
            if dumpTries >= 3 { dumpNext(dumpWant + 256) }
            else { dumpTries += 1; dumpT = Date(); send("D \(dumpWant)") }
        }
    }

    private func finishDump() {
        dumpTimer?.invalidate(); dumpTimer = nil
        guard let buf = dumpBuf else { return }
        dumpBuf = nil
        dumpProgress = nil
        let rate = UInt32(hz > 1000 ? hz.rounded() : 44100)
        var d = Data()
        func tag(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        let bytes = UInt32(TAPE * 2)
        tag("RIFF"); u32(36 + bytes); tag("WAVE")
        tag("fmt "); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        tag("data"); u32(bytes)
        for v in buf {
            let s = max(-32768, min(32767, (Int(v) - 2048) * 16))
            u16(UInt16(bitPattern: Int16(s)))
        }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cafe-\(f.string(from: Date())).wav")
        do { try d.write(to: url); wavURL = url; message = "saved \(rate) Hz — tap share" }
        catch { message = "could not save: \(error.localizedDescription)" }
    }

    private func resetLink() {
        pollTimer?.invalidate(); pollTimer = nil
        dumpTimer?.invalidate(); dumpTimer = nil
        rx = nil; peri = nil; connectedName = nil
        out.removeAll(); inbuf.removeAll()
        dumpBuf = nil; dumpProgress = nil
        waitingQ = false; lastSmp = nil
    }
}

// MARK: - CoreBluetooth

extension CafeLink: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: if state.hasPrefix("Bluetooth") { state = "not connected" }
        case .unauthorized: state = "Bluetooth not allowed (Settings > coco-pc)"
        case .poweredOff: state = "Bluetooth is off"
        default: state = "Bluetooth not ready"
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? "Cafe"
        if let i = found.firstIndex(where: { $0.id == p.identifier }) { found[i].rssi = RSSI.intValue }
        else { found.append(FoundCafe(id: p.identifier, name: name, peripheral: p, rssi: RSSI.intValue)) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        state = "looking for the Cafe service…"
        p.discoverServices([NUS])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        resetLink()
        state = "could not connect: \(error?.localizedDescription ?? "unknown")"
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        resetLink()
        state = error == nil ? "not connected" : "connection lost"
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == NUS }) else { state = "this is not a coco-pc Cafe"; return }
        p.discoverCharacteristics([NUS_RX, NUS_TX], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            if c.uuid == NUS_RX { rx = c }
            if c.uuid == NUS_TX { p.setNotifyValue(true, for: c) }
        }
        guard rx != nil else { state = "Cafe service incomplete"; return }
        connectedName = p.name ?? "Cafe"
        state = "connected"
        inbuf.removeAll(); lastSmp = nil; polls = 0
        send("P"); send("H")
        startPolling()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let v = c.value { receive(v) }
    }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) { pump() }
}
