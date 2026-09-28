// Bytebeat.swift — coco duo (k.odk)
// BYTEBEAT: mode 1 of the BLE preset. ONE formula of t ("J 0 <hex>"); pad 3 = the formula (a die, a tap = the key
// board: t, x, y = the X · Y pad, o = the last output, i = the input). XY: RATE · WINDOW, X · Y (x and y in the formula),
// LOOP · SLICE, PHASE · DRIFT (B pushed on / sliding against A), PING-PONG · STEP (the steps go A, B, A, B),
// CHORD · SPREAD (the frozen loop stacked at other speeds), FILTER · RES. Keys: DICE, SYNC, FREEZE, REV.

import SwiftUI

enum Bytebeat {
    static let seed = "t*(t>>x|t>>y)"

    /// a new formula: one of the well-known shapes with fresh numbers
    static func random() -> String {
        let shapes = ["t*(t>>x|t>>y)", "t*(t>>x&t>>y)&C", "(t>>x)*(t>>y&C)", "t*((t>>x|t>>y)&C&t>>D)",
                      "(t*E&t>>x)|(t*F&t>>y)", "(t>>x|t)*(t>>y&C)", "t*(t^t+(t>>x|y))", "t&t>>x",
                      "(t&t>>x)*(t>>y&C)", "t>>D^t*(t>>x&C)", "(t*E^t>>x)&(t>>y|C)", "t*(t>>x|t>>y)&(t>>D|C)",
                      "(t*E&t>>x|t*F&t>>y)^t>>D", "t*((t>>x)%y+1)&C", "t*y&t>>x", "(t>>x)*y&t>>D",
                      "t*(t>>x|o>>D)", "(t>>x|t)*(o&C)", "t*(t>>x&t>>y)+o", "(t^o)*(t>>x&C)", "t*x&t>>y",
                      "(t*y&t>>x)^t>>D", "t%(x*y+1)*t>>D", "(t*x^t>>y)&C", "t*(x&t>>y)|t>>D"]
        var s = shapes.randomElement()!
        let cs = [3, 7, 15, 31, 63, 127]
        for (k, v) in [("D", Int.random(in: 3...11)), ("C", cs.randomElement()!), ("E", Int.random(in: 1...9)), ("F", Int.random(in: 2...9))] {
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
            if c == "x" || c == "y" {                   // x · y = the X · Y pad (the same as a · b)
                toks.append(.v(c == "x" ? 2 : 3)); words.append(String(c)); i += 1; continue
            }
            if c == "o" || c == "i" {                   // o = the last output (fed back), i = the input jack
                toks.append(.v(c == "o" ? 9 : 25)); words.append(String(c)); i += 1; continue
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
    static let titles = ["RATE · WINDOW", "X · Y", "FORMULA", "LOOP · SLICE",
                         "PHASE · DRIFT", "PING-PONG · STEP", "CHORD · SPREAD", "FILTER · RES"]
    static let starts: [(Double, Double)] = [(0.45, 0.0), (0.3, 0.45), (0, 0), (0.0, 0.0),
                                             (0.0, 0.0), (0.0, 0.5), (0.0, 0.0), (1.0, 0.0)]
    static let chords = ["—", "OCT", "5TH", "MAJ", "MIN", "SUS4", "MAJ7", "5+8"]
    static func loop(_ x: Double) -> Int { x < 0.03 ? 0 : 17 - Int((x - 0.03) / 0.97 * 12.99) }
    /// pad 3 is not XY: the formula
    static func isView(_ i: Int) -> Bool { i == 2 }
    static func caption(_ i: Int, _ x: Double, _ y: Double) -> String {
        switch i {
        case 0:
            let r = 40 * pow(25000, x), b = Int(y * 16)
            return (r < 1000 ? String(format: "%.0f Hz", r) : r < 1_000_000 ? String(format: "%.1f kHz", r / 1000) : String(format: "%.2f MHz", r / 1_000_000)) + " · BITS \(b)–\(b + 7)"
        case 1: return "x \(1 + Int(x * 31.99)) · y \(1 + Int(y * 31.99))"
        case 3: return loop(x) == 0 ? "LOOP OFF" : "LOOP 2^\(loop(x)) · SLICE \(1 + Int(y * 15.99))"
        case 4: return "B +\(Int(x * 16)) STEPS · \(String(format: "%.2f", y * y * 2))%"
        case 5: return "\(Int(x * 100))% · STEP 2^\(15 - Int(y * 9.99))"
        case 6: return chords[min(7, Int(x * 7.99))] + " · \(Int(y * 100))%"
        case 7: return x >= 0.99 ? "OPEN · RES \(Int(y * 100))%" : String(format: "%.0f Hz · RES %d%%", 60 * pow(250, x), Int(y * 100))
        default: return ""
        }
    }
}

/// pad 3: the formula on a little LCD. The die = a new one; a tap = the key board
struct FormulaPad: View {
    @ObservedObject var rig: Rig
    @ObservedObject var xy: PadAxis             // the X · Y pad: x and y in the formula, shown under it
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
                Text("x \(1 + Int(xy.x * 31.99))  ·  y \(1 + Int(xy.y * 31.99))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PastelTheme.hudOrange)
            }
            .padding(7)
        }
        .clipped()
        .sheet(isPresented: $editing) {
            FormulaBoard(start: f, title: BytePad.titles[2]) { set($0) }
        }
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
        ["t", "x", "y", "o", "i", "(", ")", "⌫", "CLR"],
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
