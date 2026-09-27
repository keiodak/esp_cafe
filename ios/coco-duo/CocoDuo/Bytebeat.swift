// Bytebeat.swift — coco duo (k.odk)
// BYTEBEAT: mode 1 of the BLE preset (it replaced COCO there). Four formulas of t; every Cafe runs all four
// (compiled here to a little stack program, "J 0..3 <hex>"). Pads 3 · 4 show them (1 · 2, 3 · 4): a die for a new
// one, a tap for the key board (built from keys, no typing). Pads 7 · 8 let them break each other: CROSS · DRIFT (each
// formula's numbers bent by the next one's output), COLLIDE · CRASH (a hit knocks the other's t away, the other pair's
// bits break into the sound). The settings: RATE · B RATIO, BEAT · LOGIC, MORPH · XOR, CLICK · DECAY.
// The two Cafes are always a pair: the same t (SYNC), B at a ratio of A's rate, B sounds 3 & 4, MORPH turned round.

import SwiftUI

enum Bytebeat {
    static let defaults = ["t*(t>>5|t>>8)", "t&t>>8", "(t>>6)*(t>>9&7)", "t*(t>>4&t>>7)&63"]

    /// a new formula: one of the well-known shapes with fresh numbers
    static func random() -> String {
        let shapes = ["t*(t>>A|t>>B)", "t*(t>>A&t>>B)&C", "(t>>A)*(t>>B&C)", "t*((t>>A|t>>B)&C&t>>D)",
                      "(t*E&t>>A)|(t*F&t>>B)", "(t>>A|t)*(t>>B&C)", "t*(t^t+(t>>A|E))", "t&t>>A",
                      "(t&t>>A)*(t>>B&C)", "t>>D^t*(t>>A&C)", "(t*E^t>>A)&(t>>B|C)", "t*(t>>A|t>>B)&(t>>D|C)",
                      "(t*E&t>>A|t*F&t>>B)^t>>D", "t*((t>>A)%E+1)&C", "t*E&t>>A", "(t>>A)*E&t>>D"]
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

    /// a formula -> the Cafe's program (nil = it does not read); at most 60 bytes
    static func compile(_ src: String) -> [UInt8]? {
        var toks: [Tok] = []
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
                    toks.append(.num(v)); i = j; continue
                }
                while j < ch.count, ch[j].isNumber { s.append(ch[j]); j += 1 }
                guard let v = UInt32(s), v < 65536 else { return nil }
                toks.append(.num(v)); i = j; continue
            }
            if let k = ["t", "a", "b", "c", "d", "e"].firstIndex(of: String(c)) { toks.append(.v(UInt8(k + 1))); i += 1; continue }
            if i + 1 < ch.count, ["<<", ">>", "=="].contains(String([c, ch[i + 1]])) {
                toks.append(.op(String([c, ch[i + 1]]))); i += 2; continue
            }
            if c == "(" { toks.append(.lp); i += 1; continue }
            if c == ")" { toks.append(.rp); i += 1; continue }
            if "+-*/%&|^~<>".contains(c) { toks.append(.op(String(c))); i += 1; continue }
            return nil
        }
        // shunting-yard -> postfix bytes
        var out: [UInt8] = [], stack: [String] = []
        var expectOperand = true
        var depth = 0
        func emit(_ op: String) { if let b = code[op] { out.append(b) } }
        for t in toks {
            switch t {
            case .num(let v):
                guard expectOperand else { return nil }
                if v < 256 { out += [7, UInt8(v)] } else { out += [8, UInt8(v & 255), UInt8(v >> 8)] }
                expectOperand = false; depth += 1
            case .v(let k):
                guard expectOperand else { return nil }
                out.append(k); expectOperand = false; depth += 1
            case .lp:
                guard expectOperand else { return nil }
                stack.append("(")
            case .rp:
                guard !expectOperand else { return nil }
                while let top = stack.last, top != "(" { emit(top); stack.removeLast(); if top != "u-" && top != "~" { depth -= 1 } }
                guard stack.last == "(" else { return nil }
                stack.removeLast()
            case .op(var o):
                if expectOperand {
                    if o == "-" { o = "u-" } else if o == "+" { continue } else if o != "~" { return nil }
                    stack.append(o); continue
                }
                guard o != "~" else { return nil }
                while let top = stack.last, top != "(", let pt = prec[top], let po = prec[o], pt >= po {
                    emit(top); stack.removeLast(); if top != "u-" && top != "~" { depth -= 1 }
                }
                stack.append(o); expectOperand = true
            }
            if depth > 15 { return nil }
        }
        guard !expectOperand else { return nil }
        while let top = stack.popLast() {
            guard top != "(" else { return nil }
            emit(top)
        }
        return out.count <= 60 && !out.isEmpty ? out : nil
    }

    static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
}

enum BytePad {
    static let titles = ["RATE · B RATIO", "BEAT · LOGIC", "FORMULA 1 · 2", "FORMULA 3 · 4",
                         "MORPH · XOR", "CLICK · DECAY", "CROSS · DRIFT", "COLLIDE · CRASH"]
    static let starts: [(Double, Double)] = [(0.4, 0.5), (0.4, 0.0), (0, 0), (0, 0),
                                             (0.0, 0.0), (0.4, 0.4), (0.0, 0.5), (0.0, 0.0)]
    /// B's rate against A's
    static let ratios: [Double] = [0.5, 2.0 / 3.0, 0.75, 1, 4.0 / 3.0, 1.5, 2]
    static let ratioNames = ["×1/2", "×2/3", "×3/4", "×1", "×4/3", "×3/2", "×2"]
    static let logics = ["OR", "XOR", "AND", "2 OF 4"]
    /// the two formula pads (3 · 4): which formulas they hold
    static func formulas(_ i: Int) -> [Int]? { i == 2 ? [0, 1] : (i == 3 ? [2, 3] : nil) }
    static func caption(_ i: Int, _ x: Double, _ y: Double) -> String {
        switch i {
        case 0: return String(format: "%.1f kHz · B %@", 1.0 * pow(32, x), ratioNames[min(6, Int(y * 6.99))])
        case 1: return "BIT \(3 + min(11, Int(x * 11.99))) · \(logics[min(3, Int(y * 3.99))])"
        case 4: return "MORPH \(Int(x * 100))% · XOR \(Int(y * 100))%"
        case 5: return String(format: "%.0f Hz · %.0f ms", 80 * pow(40, x), (0.002 + y * y * 0.25) * 1000)
        case 6: return "CROSS \(Int(x * x * 16)) · 1/\(1 << Int((1 - y) * 12.99))"
        case 7: return "COLLIDE \(Int(x * 100))% · CRASH \(Int(y * 8.99)) BIT"
        default: return ""
        }
    }
}

/// pads 3 · 4: two formulas on a little LCD. A die = a new one; a tap = the key board
struct FormulaPad: View {
    @ObservedObject var rig: Rig
    let ks: [Int]
    let tag: String
    let title: String
    let set: (Int, String) -> Void
    @State private var editing: Int? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(PastelTheme.padScreen)
            HudDots(step: 12)
            Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
            HudCorners(arm: 8).stroke(PastelTheme.hudBlack, lineWidth: 1.2).padding(3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    HudTag(text: tag, size: 7)
                    Text(title).font(.hud(8, .semibold)).tracking(0.8).foregroundStyle(PastelTheme.hudOrange)
                    Spacer(minLength: 0)
                }
                ForEach(ks, id: \.self) { k in line(k) }
            }
            .padding(7)
        }
        .clipped()
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let k = editing {
                FormulaBoard(start: rig.bbFormula[k], title: "FORMULA \(k + 1)") { set(k, $0) }
            }
        }
    }

    private func line(_ k: Int) -> some View {
        let f = rig.bbFormula[k]
        let ok = Bytebeat.compile(f) != nil
        return HStack(alignment: .top, spacing: 5) {
            Text("\(k + 1)")
                .font(.hud(8, .semibold))
                .foregroundStyle(PastelTheme.hudOrange)
                .frame(width: 10, alignment: .leading)
            Text(f.isEmpty ? "—" : f)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(ok ? PastelTheme.hudBlack : PastelTheme.hudOrange)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { editing = k }
            Button { set(k, Bytebeat.random()) } label: {
                Image(systemName: "dice")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PastelTheme.hudBlack)
                    .frame(width: 26, height: 20)
                    .background(IconSquare(filled: false))
            }
            .buttonStyle(.plain)
        }
        .frame(maxHeight: .infinity)
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
        ["t", "e", "(", ")", "⌫", "CLR"],
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
