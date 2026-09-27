// Bytebeat.swift — coco duo (k.odk)
// BYTEBEAT: mode 1 of the BLE preset (it replaced COCO there). ONE formula of t ("J 0 <hex>"); pad 3 = the formula
// (a die, a tap = the key board: t, y = the fed-back output, i = the input), pad 4 = the rhythm.
// XY: RATE · WINDOW (which 8 bits are heard), LOOP · SLICE (t round one slice of the bar), FEEDBACK · DELAY (the output
// pushes t), INPUT · BITS (the input jack pushes t / breaks the low bits: patch the other Cafe in), RULE · STEP (a
// 16-step automaton gates the sound), CLICK · DECAY. B = A with the window two bits higher and the slice four on.

import SwiftUI

enum Bytebeat {
    static let seed = "t*(t>>5|t>>8)"

    /// a new formula: one of the well-known shapes with fresh numbers
    static func random() -> String {
        let shapes = ["t*(t>>A|t>>B)", "t*(t>>A&t>>B)&C", "(t>>A)*(t>>B&C)", "t*((t>>A|t>>B)&C&t>>D)",
                      "(t*E&t>>A)|(t*F&t>>B)", "(t>>A|t)*(t>>B&C)", "t*(t^t+(t>>A|E))", "t&t>>A",
                      "(t&t>>A)*(t>>B&C)", "t>>D^t*(t>>A&C)", "(t*E^t>>A)&(t>>B|C)", "t*(t>>A|t>>B)&(t>>D|C)",
                      "(t*E&t>>A|t*F&t>>B)^t>>D", "t*((t>>A)%E+1)&C", "t*E&t>>A", "(t>>A)*E&t>>D",
                      "t*(t>>A|y>>D)", "(t>>A|t)*(y&C)", "t*(t>>A&t>>B)+y", "(t^y)*(t>>A&C)", "t*(i>>D|t>>A)", "(t*E^i)&t>>A"]
        var s = shapes.randomElement()!
        let cs = [3, 7, 15, 31, 63, 127]
        for (k, v) in [("A", Int.random(in: 3...12)), ("B", Int.random(in: 4...13)), ("D", Int.random(in: 3...11)),
                       ("C", cs.randomElement()!), ("E", Int.random(in: 1...9)), ("F", Int.random(in: 2...9))] {
            s = s.replacingOccurrences(of: k, with: String(v))
        }
        return s
    }

    private enum Tok { case num(UInt32), v(UInt8), op(String), lp, rp }
    private static let prec: [String: Int] = ["u-": 9, "~": 9, "*": 8, "/": 8, "%": 8, "+": 7, "-": 7,
                                             "<<": 6, ">>": 6, "<": 5, ">": 5, "==": 4, "&": 3, "^": 2, "|": 1]
    private static let code: [String: UInt8] = ["+": 10, "-": 11, "*": 12, "/": 13, "%": 14, "&": 15, "|": 16, "^": 17,
                                               "<<": 18, ">>": 19, "~": 20, "u-": 21, "<": 22, ">": 23, "==": 24]

    /// a formula taken apart: the Cafe's program, its cells (the byte of each number / operator, in written order),
    /// and the written tokens (the cells point into them) — for the automaton
    struct Parsed {
        var bytes: [UInt8]
        var cells: [UInt8]
        var toks: [String]
        var cellTok: [Int]
    }
    static let cellOps = ["+", "-", "*", "&", "|", "^", "<<", ">>"]

    static func compile(_ src: String) -> [UInt8]? { parse(src)?.bytes }

    static func parse(_ src: String) -> Parsed? {
        var toks: [Tok] = [], words: [String] = []
        let ch = Array(src.lowercased())
        var i = 0
        while i < ch.count {
            let c = ch[i]
            if c == " " { i += 1; continue }
            if c.isNumber {
                var j = i, s = ""
                if c == "0" && i + 1 < ch.count && ch[i + 1] == "x" {
                    j = i + 2
                    while j < ch.count, ch[j].isHexDigit { s.append(ch[j]); j += 1 }
                    guard let v = UInt32(s, radix: 16), v < 65536 else { return nil }
                    toks.append(.num(v)); words.append(String(v)); i = j; continue
                }
                while j < ch.count, ch[j].isNumber { s.append(ch[j]); j += 1 }
                guard let v = UInt32(s), v < 65536 else { return nil }
                toks.append(.num(v)); words.append(String(v)); i = j; continue
            }
            if let k = ["t", "a", "b", "c", "d", "e"].firstIndex(of: String(c)) {
                toks.append(.v(UInt8(k + 1))); words.append(String(c)); i += 1; continue
            }
            if c == "y" || c == "i" {                   // y = the fed-back output, i = the input jack
                toks.append(.v(c == "y" ? 9 : 25)); words.append(String(c)); i += 1; continue
            }
            if i + 1 < ch.count, ["<<", ">>", "=="].contains(String([c, ch[i + 1]])) {
                toks.append(.op(String([c, ch[i + 1]]))); words.append(String([c, ch[i + 1]])); i += 2; continue
            }
            if c == "(" { toks.append(.lp); words.append("("); i += 1; continue }
            if c == ")" { toks.append(.rp); words.append(")"); i += 1; continue }
            if "+-*/%&|^~<>".contains(c) { toks.append(.op(String(c))); words.append(String(c)); i += 1; continue }
            return nil
        }
        // shunting-yard -> postfix bytes; every number / binary operator remembers where its byte went
        var out: [UInt8] = [], stack: [(String, Int)] = []
        var at = [Int: Int]()                        // token index -> byte position
        var expectOperand = true
        var depth = 0
        func emit(_ e: (String, Int)) {
            guard let b = code[e.0] else { return }
            if e.0 != "u-" && e.0 != "~" { at[e.1] = out.count }
            out.append(b)
        }
        for (ti, t) in toks.enumerated() {
            switch t {
            case .num(let v):
                guard expectOperand else { return nil }
                at[ti] = out.count
                if v < 256 { out += [7, UInt8(v)] } else { out += [8, UInt8(v & 255), UInt8(v >> 8)] }
                expectOperand = false; depth += 1
            case .v(let k):
                guard expectOperand else { return nil }
                out.append(k); expectOperand = false; depth += 1
            case .lp:
                guard expectOperand else { return nil }
                stack.append(("(", ti))
            case .rp:
                guard !expectOperand else { return nil }
                while let top = stack.last, top.0 != "(" { emit(top); stack.removeLast(); if top.0 != "u-" && top.0 != "~" { depth -= 1 } }
                guard stack.last?.0 == "(" else { return nil }
                stack.removeLast()
            case .op(var o):
                if expectOperand {
                    if o == "-" { o = "u-" } else if o == "+" { continue } else if o != "~" { return nil }
                    stack.append((o, ti)); continue
                }
                guard o != "~" else { return nil }
                while let top = stack.last, top.0 != "(", let pt = prec[top.0], let po = prec[o], pt >= po {
                    emit(top); stack.removeLast(); if top.0 != "u-" && top.0 != "~" { depth -= 1 }
                }
                stack.append((o, ti)); expectOperand = true
            }
            if depth > 15 { return nil }
        }
        guard !expectOperand else { return nil }
        while let top = stack.popLast() {
            guard top.0 != "(" else { return nil }
            emit(top)
        }
        guard out.count <= 60, !out.isEmpty else { return nil }
        // the cells, in written order: numbers, and the operators the automaton can turn
        var cells: [UInt8] = [], cellTok: [Int] = []
        for ti in toks.indices {
            guard let pos = at[ti], cells.count < 32 else { continue }
            if case .num = toks[ti] { cells.append(UInt8(pos)); cellTok.append(ti) }
            else if cellOps.contains(words[ti]) { cells.append(UInt8(pos)); cellTok.append(ti) }
        }
        return Parsed(bytes: out, cells: cells, toks: words, cellTok: cellTok)
    }

    static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
}

enum BytePad {
    static let titles = ["RATE · WINDOW", "LOOP · SLICE", "FORMULA", "RHYTHM",
                         "FEEDBACK · DELAY", "INPUT · BITS", "RULE · STEP", "CLICK · DECAY"]
    static let starts: [(Double, Double)] = [(0.4, 0.0), (0.0, 0.0), (0, 0), (0, 0),
                                             (0.0, 0.2), (0.0, 0.0), (0.0, 0.5), (0.4, 0.4)]
    static let rules = [30, 90, 110, 45, 73, 54, 150, 18, 22, 60, 105, 126, 137, 169, 57]
    /// RULE: 0 = no rhythm
    static func rule(_ x: Double) -> Int { x < 0.04 ? 0 : rules[min(14, Int((x - 0.04) / 0.96 * 14.99))] }
    static func step(_ y: Double) -> Int { 14 - Int(y * 8.99) }
    static func loop(_ x: Double) -> Int { x < 0.03 ? 0 : 17 - Int((x - 0.03) / 0.97 * 12.99) }
    /// pads 3 · 4 are not XY: the formula and the rhythm
    static func isView(_ i: Int) -> Bool { i == 2 || i == 3 }
    static func caption(_ i: Int, _ x: Double, _ y: Double) -> String {
        switch i {
        case 0:
            let b = Int(y * 16)
            return String(format: "%.1f kHz · BITS %d–%d", 1.0 * pow(32, x), b, b + 7)
        case 1: return loop(x) == 0 ? "LOOP OFF" : "LOOP 2^\(loop(x)) · SLICE \(1 + Int(y * 15.99))"
        case 4: return "FB \(Int(x * x * 100))% · \(1 + Int(y * y * 2046))"
        case 5: return "IN→t \(Int(x * x * 100))% · \(Int(y * 8.99)) BIT"
        case 6: return (rule(x) == 0 ? "RULE OFF" : "RULE \(rule(x))") + " · STEP 2^\(step(y))"
        case 7: return String(format: "%.0f Hz · %.0f ms", 80 * pow(40, x), (0.002 + y * y * 0.25) * 1000)
        default: return ""
        }
    }
}

/// the rhythm the Cafe plays (a 16-step automaton, a generation every bar), run again here for the picture — on the
/// phone's clock, so it only follows the Cafe loosely; SYNC starts both again
final class RhythmCA: ObservableObject {
    @Published private(set) var rows: [UInt16] = [0x0100]   // the last generations, newest last
    @Published private(set) var step = 0
    private var ca: UInt16 = 0x0100
    private var rule = 0, period = 0.1, frozen = false
    private var timer: Timer?
    private var acc = 0.0, last = Date()
    static let depthRows = 14

    func configure(rule: Int, period: Double, frozen: Bool) {
        self.rule = rule; self.period = max(0.002, period); self.frozen = frozen
    }
    func reseed() { ca = 0x0100; rows = [ca]; step = 0; acc = 0 }
    var on: Bool { rule != 0 }
    func start() {
        guard timer == nil else { return }
        last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func tick() {
        let now = Date(), dt = now.timeIntervalSince(last)
        last = now
        guard !frozen else { return }
        acc += dt
        var s = step, r = rows, moved = false
        var n = 0
        while acc >= period && n < 2000 {
            acc -= period; n += 1; moved = true
            s = (s + 1) & 15
            if s == 0 && rule != 0 {
                var nc: UInt16 = 0
                for i in 0..<16 {
                    let l = Int((ca >> UInt16((i + 15) & 15)) & 1), m = Int((ca >> UInt16(i)) & 1), rr = Int((ca >> UInt16((i + 1) & 15)) & 1)
                    if (rule >> ((l << 2) | (m << 1) | rr)) & 1 == 1 { nc |= 1 << UInt16(i) }
                }
                ca = nc != 0 ? nc : 0x0100
                r.append(ca)
            }
        }
        if acc > period { acc = 0 }
        if moved { step = s; rows = Array(r.suffix(Self.depthRows)) }
    }
}

/// pad 3: the formula on a little LCD. The die = a new one; a tap = the key board
struct FormulaPad: View {
    @ObservedObject var rig: Rig
    let tag: String
    let set: (String) -> Void
    @State private var editing = false

    var body: some View {
        let f = rig.bbCode
        let ok = Bytebeat.compile(f) != nil
        ZStack(alignment: .topLeading) {
            Rectangle().fill(PastelTheme.padScreen)
            HudDots(step: 12)
            Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
            HudCorners(arm: 8).stroke(PastelTheme.hudBlack, lineWidth: 1.2).padding(3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    HudTag(text: tag, size: 7)
                    Text(BytePad.titles[2]).font(.hud(8, .semibold)).tracking(0.8).foregroundStyle(PastelTheme.hudOrange)
                    Spacer(minLength: 0)
                    Button { set(Bytebeat.random()) } label: {
                        Image(systemName: "dice")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PastelTheme.hudBlack)
                            .frame(width: 26, height: 20)
                            .background(IconSquare(filled: false))
                    }
                    .buttonStyle(.plain)
                }
                Text(f.isEmpty ? "—" : f)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ok ? PastelTheme.hudBlack : PastelTheme.hudOrange)
                    .lineLimit(4)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = true }
            }
            .padding(7)
        }
        .clipped()
        .sheet(isPresented: $editing) {
            FormulaBoard(start: f, title: BytePad.titles[2]) { set($0) }
        }
    }
}

/// pad 4: the rhythm — the 16 steps, generation under generation (the playing step marked)
struct RhythmPad: View {
    @ObservedObject var ca: RhythmCA
    let tag: String
    let rule: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(PastelTheme.padScreen)
            Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
            HudCorners(arm: 8).stroke(PastelTheme.hudBlack, lineWidth: 1.2).padding(3)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    HudTag(text: tag, size: 7)
                    Text(BytePad.titles[3]).font(.hud(8, .semibold)).tracking(0.8).foregroundStyle(PastelTheme.hudOrange)
                    Spacer(minLength: 0)
                    Text(rule == 0 ? "OFF" : "R\(rule)").font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PastelTheme.hudBlack.opacity(0.7))
                        .frame(width: 30, alignment: .trailing)
                }
                Canvas { ctx, size in
                    let cw = size.width / 16, ch = size.height / CGFloat(RhythmCA.depthRows)
                    let rows = rule == 0 ? [UInt16(0xFFFF)] : ca.rows
                    let top = CGFloat(RhythmCA.depthRows - rows.count) * ch
                    for (ri, r) in rows.enumerated() {
                        let newest = ri == rows.count - 1
                        for i in 0..<16 where (r >> UInt16(i)) & 1 == 1 {
                            let rect = CGRect(x: CGFloat(i) * cw + 1, y: top + CGFloat(ri) * ch + 1,
                                              width: max(1, cw - 2), height: max(1, ch - 2))
                            let hot = newest && i == ca.step
                            ctx.fill(Path(rect), with: .color(hot ? PastelTheme.hudOrange
                                                              : PastelTheme.hudBlack.opacity(newest ? 0.85 : 0.35)))
                        }
                    }
                    let x = CGFloat(ca.step) * cw
                    ctx.fill(Path(CGRect(x: x, y: size.height - 2, width: cw, height: 2)), with: .color(PastelTheme.hudOrange))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(7)
        }
        .clipped()
        .onAppear { ca.start() }
        .onDisappear { ca.stop() }
    }
}

/// the key board: a formula built from keys (no typing)
struct FormulaBoard: View {
    @State var text: String
    let title: String
    let done: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(start: String, title: String, done: @escaping (String) -> Void) {
        _text = State(initialValue: start)
        self.title = title
        self.done = done
    }

    private let rows: [[String]] = [
        ["t", "y", "i", "e", "(", ")", "⌫", "CLR"],
        ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"],
        ["+", "-", "*", "/", "%", "&", "|", "^", "~", "<<", ">>"],
    ]

    var body: some View {
        let ok = Bytebeat.compile(text) != nil
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.hud(9, .semibold)).tracking(0.8).foregroundStyle(PastelTheme.hudOrange)
                Spacer()
            }
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(ok ? PastelTheme.hudBlack : PastelTheme.hudOrange)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, 10)
                .background(Rectangle().fill(PastelTheme.padScreen))
                .overlay(Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1))
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 5) { ForEach(rows[r], id: \.self) { k in board(k) } }
            }
            HStack(spacing: 5) {
                board("DICE")
                Spacer(minLength: 0)
                board("CANCEL")
                Button { done(text); dismiss() } label: { face("OK", on: ok) }
                    .buttonStyle(.plain)
                    .disabled(!ok)
                    .opacity(ok ? 1 : 0.4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PastelTheme.padScreen.opacity(0.35))
    }

    private func board(_ k: String) -> some View {
        Button { press(k) } label: { face(k, on: false) }.buttonStyle(.plain)
    }
    private func face(_ k: String, on: Bool) -> some View {
        Text(k)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(on ? PastelTheme.selectionText : PastelTheme.hudBlack)
            .frame(minWidth: 34, maxWidth: k.count > 2 ? 70 : 44, minHeight: 32)
            .background(IconSquare(filled: on))
    }
    private func press(_ k: String) {
        switch k {
        case "⌫":
            for two in ["<<", ">>", "=="] where text.hasSuffix(two) { text.removeLast(2); return }
            if !text.isEmpty { text.removeLast() }
        case "CLR": text = ""
        case "DICE": text = Bytebeat.random()
        case "CANCEL": dismiss()
        default: text += k
        }
    }
}
