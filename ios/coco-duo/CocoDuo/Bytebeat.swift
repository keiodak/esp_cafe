// Bytebeat.swift — coco duo (k.odk)
// BYTEBEAT: mode 1 of the BLE preset (it replaced COCO there). Four formulas of t; every Cafe runs all four
// (compiled here to a little stack program, "J 0..3 <hex>"). The formula pads are XY: X and Y are the numbers A and B
// in the formula, so moving a pad rewrites it. The settings pads: RATE · B RATIO, BEAT · LOGIC (one bit of each of
// the four collided like Rollz -> a beat: YELLOW clicks, ASH plays a click), MORPH · XOR, CLICK · DECAY.
// Linked Cafes: the same t (SYNC), B at a ratio of A's rate, B sounds 3 & 4 while A sounds 1 & 2, MORPH turned the
// other way on B. SAME: both play the same.

import SwiftUI

enum Bytebeat {
    /// the four formulas' shapes: A and B are the numbers the formula pad's X and Y move (1 … 16)
    static let defaults = ["t*(t>>A|t>>B)", "t&t>>A+B", "(t>>A)*(t>>B&7)", "t*(t>>A&t>>B)&63"]
    static let shapes = ["t*(t>>A|t>>B)", "t*(t>>A&t>>B)&C", "(t>>A)*(t>>B&C)", "t*((t>>A|t>>B)&C&t>>D)",
                         "(t*E&t>>A)|(t*F&t>>B)", "(t>>A|t)*(t>>B&C)", "t*(t^t+(t>>A|B))", "t&t>>A+B",
                         "(t&t>>A)*(t>>B&C)", "t>>D^t*(t>>A&B)", "(t*E^t>>A)&(t>>B|C)", "t*(t>>A|t>>B)&(t>>D|C)",
                         "(t*E&t>>A|t*F&t>>B)^t>>D", "t*((t>>A)%B+1)&C", "t*B&t>>A", "(t>>A)*B&t>>D"]
    /// a new shape: fresh fixed numbers, A and B left for the pad
    static func randomShape() -> String {
        var s = shapes.randomElement()!
        let cs = [3, 7, 15, 31, 63, 127]
        for (k, v) in [("D", Int.random(in: 3...11)), ("C", cs.randomElement()!), ("E", Int.random(in: 1...9)), ("F", Int.random(in: 2...9))] {
            s = s.replacingOccurrences(of: k, with: String(v))
        }
        return s
    }
    /// the shape with the pad's numbers in it
    static func fill(_ shape: String, _ x: Double, _ y: Double) -> String {
        let a = 1 + min(15, Int(x * 15.99)), b = 1 + min(15, Int(y * 15.99))
        return shape.replacingOccurrences(of: "A", with: String(a)).replacingOccurrences(of: "B", with: String(b))
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
    static let titles = ["RATE · B RATIO", "BEAT · LOGIC", "FORMULA 1", "FORMULA 2",
                         "MORPH · XOR", "CLICK · DECAY", "FORMULA 3", "FORMULA 4"]
    static let starts: [(Double, Double)] = [(0.4, 0.5), (0.4, 0.0), (0.3, 0.45), (0.45, 0.3),
                                             (0.0, 0.0), (0.4, 0.4), (0.5, 0.4), (0.6, 0.25)]
    /// B's rate against A's
    static let ratios: [Double] = [0.5, 2.0 / 3.0, 0.75, 1, 4.0 / 3.0, 1.5, 2]
    static let ratioNames = ["×1/2", "×2/3", "×3/4", "×1", "×4/3", "×3/2", "×2"]
    static let logics = ["OR", "XOR", "AND", "2 OF 4"]
    /// which formula a pad is (-1 = one of the four settings pads)
    static func formula(_ i: Int) -> Int { [-1, -1, 0, 1, -1, -1, 2, 3][i] }
    static func caption(_ i: Int, _ x: Double, _ y: Double) -> String {
        switch i {
        case 0: return String(format: "%.1f kHz · B %@", 1.0 * pow(32, x), ratioNames[min(6, Int(y * 6.99))])
        case 1: return "BIT \(3 + min(11, Int(x * 11.99))) · \(logics[min(3, Int(y * 3.99))])"
        case 4: return "MORPH \(Int(x * 100))% · XOR \(Int(y * 100))%"
        case 5: return String(format: "%.0f Hz · %.0f ms", 80 * pow(40, x), (0.002 + y * y * 0.25) * 1000)
        default: return ""
        }
    }
}
