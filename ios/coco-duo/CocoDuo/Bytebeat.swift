// Bytebeat.swift — coco duo (k.odk)
// BYTEBEAT: mode 1 of the BLE preset (it replaced COCO there). Each Cafe runs two formulas of t; the phone compiles
// them to a little stack program ("J 0|1 <hex>") and moves the settings ("J 9 <id> <v>").
// Pads: 1 · 2 · 5 · 6 are XY (RATE · B RATIO, a · b, MORPH · XOR, c · d), 3 · 4 · 7 · 8 are the four formulas
// (A's two on top, B's two below). The two Cafes are linked: the same t (SYNC), B's rate a ratio of A's, and MORPH
// turned the other way on B — moving it passes the sound from one Cafe to the other.

import SwiftUI

enum Bytebeat {
    static let defaults = ["t*(t>>5|t>>8)", "t&t>>8", "t*(t>>9|t>>13)&a", "(t>>7|t|t>>6)*10+4*(t&t>>13|t>>6)"]

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

    /// a new formula: one of the well-known shapes with fresh numbers (some use a · b · c · d, so the pads play it)
    static func random() -> String {
        let shapes = ["t*(t>>A|t>>B)", "t*(t>>A&t>>B)&C", "(t>>A)*(t>>B&C)", "t*((t>>A|t>>B)&C&t>>D)",
                      "(t*E&t>>A)|(t*F&t>>B)", "t*(a&t>>A)", "(t>>A|t)*(t>>B&b)", "t*(t^t+(t>>A|E))",
                      "(t&t>>A)*(t>>B&c)", "t>>D^t*(t>>A&C)", "(t*E^t>>A)&(t>>B|d)", "t*(t>>A|t>>B)&(t>>D|a)",
                      "(t*E&t>>A|t*F&t>>B)^t>>D", "t*((t>>A)%E+1)&C"]
        var s = shapes.randomElement()!
        let cs = [3, 7, 15, 31, 63, 127]
        for (k, v) in [("A", Int.random(in: 3...12)), ("B", Int.random(in: 4...13)), ("D", Int.random(in: 3...11)),
                       ("C", cs.randomElement()!), ("E", Int.random(in: 1...9)), ("F", Int.random(in: 2...9))] {
            s = s.replacingOccurrences(of: k, with: String(v))
        }
        return s
    }
}

enum BytePad {
    static let titles = ["RATE · B RATIO", "a · b", "A · FORMULA 1", "A · FORMULA 2",
                         "MORPH · XOR", "c · d", "B · FORMULA 1", "B · FORMULA 2"]
    static let starts: [(Double, Double)] = [(0.4, 0.5), (0.25, 0.5), (0, 0), (0, 0), (0.0, 0.0), (0.125, 0.06), (0, 0), (0, 0)]
    /// B's rate against A's
    static let ratios: [Double] = [0.5, 2.0 / 3.0, 0.75, 1, 4.0 / 3.0, 1.5, 2]
    static let ratioNames = ["×1/2", "×2/3", "×3/4", "×1", "×4/3", "×3/2", "×2"]
    /// which formula a pad is (-1 = an XY pad)
    static func formula(_ i: Int) -> Int { [-1, -1, 0, 1, -1, -1, 2, 3][i] }
    static func caption(_ i: Int, _ x: Double, _ y: Double) -> String {
        switch i {
        case 0: return String(format: "%.1f kHz · B %@", 1.0 * pow(32, x), ratioNames[min(6, Int(y * 6.99))])
        case 1: return "a \(Int(x * 255)) · b \(Int(y * 255))"
        case 4: return "MORPH \(Int(x * 100))% · XOR \(Int(y * 100))%"
        case 5: return "c \(Int(x * 255)) · d \(Int(y * 255))"
        default: return ""
        }
    }
}

/// one formula pad: the formula on a small LCD, tap = edit it, the die = a new one
struct FormulaPad: View {
    @ObservedObject var rig: Rig
    let k: Int                  // 0…3
    let tag: String
    let set: (String) -> Void
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        let f = rig.bbFormula[k]
        let ok = Bytebeat.compile(f) != nil
        ZStack(alignment: .topLeading) {
            Rectangle().fill(PastelTheme.padScreen)
            HudDots(step: 12)
            Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
            HudCorners(arm: 8).stroke(PastelTheme.hudBlack, lineWidth: 1.2).padding(3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    HudTag(text: tag, size: 7)
                    Text(BytePad.titles[[2, 3, 6, 7][k]])
                        .font(.hud(8, .semibold)).tracking(0.8)
                        .foregroundStyle(PastelTheme.hudOrange)
                    Spacer(minLength: 0)
                    Button { set(Bytebeat.random()) } label: {
                        Image(systemName: "dice")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PastelTheme.hudBlack)
                            .frame(width: 24, height: 20)
                            .background(IconSquare(filled: false))
                    }
                    .buttonStyle(.plain)
                }
                Text(f.isEmpty ? "—" : f)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ok ? PastelTheme.hudBlack : PastelTheme.hudOrange)
                    .lineLimit(4)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Text(ok ? "TAP TO EDIT" : "CAN'T READ IT")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(PastelTheme.textSecondary)
            }
            .padding(8)
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { draft = f; editing = true }
        .alert("FORMULA", isPresented: $editing) {
            TextField("t*(t>>5|t>>8)", text: $draft)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("OK") { set(draft) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("t a b c d e · + - * / % & | ^ ~ << >> < > ==")
        }
    }
}
