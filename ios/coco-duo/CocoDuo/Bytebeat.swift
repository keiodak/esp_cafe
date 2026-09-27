// Bytebeat.swift — coco duo (k.odk)
// BYTEBEAT: mode 1 of the BLE preset (it replaced COCO there). ONE formula of t, grown by a cellular automaton: every
// number and operator is a cell; where a cell lives, its number moves / its operator turns ("J 1" the cells, "J 0" the
// program; the Cafe runs the automaton). Pad 3 = the formula (a die, a tap = the key board), pad 4 = the automaton.
// XY: RATE · B RATIO, RULE · SEED, MORPH · XOR (the seed formula <-> the grown one), CLICK · DECAY, STEP · DEPTH,
// OPS · BEAT. The two Cafes are a pair: the same t (SYNC), B at a ratio of A's rate, MORPH turned round.

import SwiftUI

enum Bytebeat {
    static let seed = "t*(t>>5|t>>8)"

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
    static let titles = ["RATE · B RATIO", "RULE · SEED", "FORMULA", "AUTOMATON",
                         "MORPH · XOR", "CLICK · DECAY", "STEP · DEPTH", "OPS · BEAT"]
    static let starts: [(Double, Double)] = [(0.4, 0.5), (0.0, 0.0), (0, 0), (0, 0),
                                             (1.0, 0.0), (0.4, 0.4), (0.5, 0.3), (0.3, 0.45)]
    /// B's rate against A's
    static let ratios: [Double] = [0.5, 2.0 / 3.0, 0.75, 1, 4.0 / 3.0, 1.5, 2]
    static let ratioNames = ["×1/2", "×2/3", "×3/4", "×1", "×4/3", "×3/2", "×2"]
    static let rules = [30, 90, 110, 45, 73, 54, 150, 18, 22, 60, 105, 126, 137, 169, 184, 57]
    static func rule(_ x: Double) -> Int { rules[min(15, Int(x * 15.99))] }
    static func seed(_ y: Double) -> Int { Int(y * 255) }
    static func step(_ x: Double) -> Int { 15 - Int(x * 11.99) }
    static func depth(_ y: Double) -> Int { 1 + Int(y * 15) }
    /// pads 3 · 4 are not XY: the formula and the automaton
    static func isView(_ i: Int) -> Bool { i == 2 || i == 3 }
    static func caption(_ i: Int, _ x: Double, _ y: Double) -> String {
        switch i {
        case 0: return String(format: "%.1f kHz · B %@", 1.0 * pow(32, x), ratioNames[min(6, Int(y * 6.99))])
        case 1: return "RULE \(rule(x)) · " + (seed(y) == 0 ? "ONE" : "\(Int(y * 100))%")
        case 4: return "MORPH \(Int(x * 100))% · XOR \(Int(y * 100))%"
        case 5: return String(format: "%.0f Hz · %.0f ms", 80 * pow(40, x), (0.002 + y * y * 0.25) * 1000)
        case 6: return "STEP 2^\(step(x)) · ±\(depth(y))"
        case 7: return "OPS \(Int(x * 100))% · BIT \(3 + min(11, Int(y * 11.99)))"
        default: return ""
        }
    }
}

/// the automaton the Cafe runs, run again here for the picture (the same rule, seed and cells; its clock is the
/// phone's, so it only follows the Cafe loosely — SYNC and a new formula start both again)
final class ByteCA: ObservableObject {
    @Published private(set) var rows: [UInt32] = []      // the last generations, newest last
    @Published private(set) var n = 0
    private(set) var toks: [String] = []
    private(set) var cellTok: [Int] = []
    private var ca: UInt32 = 0
    private var rule = 30, seedd = 0, depth = 5, ops = 77
    private var period = 0.25, frozen = false
    private var timer: Timer?
    private var acc = 0.0, last = Date()
    static let depthRows = 22

    func load(_ src: String) {
        guard let p = Bytebeat.parse(src) else { return }
        toks = p.toks; cellTok = p.cellTok; n = p.cells.count
        reseed()
    }
    func configure(rule: Int, seed: Int, depth: Int, ops: Int, period: Double, frozen: Bool) {
        self.rule = rule; self.depth = depth; self.ops = ops; self.period = max(0.0005, period); self.frozen = frozen
        if seed != seedd { seedd = seed; reseed() }
    }
    func reseed() {
        ca = seedRow()
        rows = [ca]
        acc = 0
    }
    func start() {
        guard timer == nil else { return }
        last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.tick() }
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(last)
        last = now
        guard !frozen, n > 0 else { return }
        acc += dt
        var steps = 0
        var r = rows
        while acc >= period && steps < 400 {
            acc -= period; steps += 1
            stepRow()
            r.append(ca)
        }
        if acc > period { acc = 0 }
        if steps > 0 { rows = Array(r.suffix(Self.depthRows)) }
    }
    private func seedRow() -> UInt32 {
        guard n > 0 else { return 0 }
        var c: UInt32 = 0, st: UInt32 = 12345
        if seedd > 0 {
            for i in 0..<n {
                st = st &* 1103515245 &+ 12345
                if (st >> 16) & 255 < UInt32(seedd) { c |= 1 << UInt32(i) }
            }
        }
        if c == 0 { c = 1 << UInt32(n / 2) }
        return c
    }
    private func bit(_ c: UInt32, _ i: Int) -> Int { Int((c >> UInt32((i + n) % n)) & 1) }
    private func stepRow() {
        var nc: UInt32 = 0
        for i in 0..<n {
            let k = (bit(ca, i - 1) << 2) | (bit(ca, i) << 1) | bit(ca, i + 1)
            if (rule >> k) & 1 == 1 { nc |= 1 << UInt32(i) }
        }
        ca = nc != 0 ? nc : seedRow()
    }
    /// is cell i alive now
    func alive(_ i: Int) -> Bool { n > 0 && bit(rows.last ?? 0, i) == 1 }
    /// the grown formula, word by word (and which words the automaton has changed)
    func grown() -> [(String, Bool)] {
        var w = toks.map { ($0, false) }
        let c = rows.last ?? 0
        for i in 0..<n where bit(c, i) == 1 {
            let l = bit(c, i - 1), r = bit(c, i + 1)
            let ti = cellTok[i]
            if let v = Int(toks[ti]) {
                var d = depth * (1 + l + r)
                if r > l { d = -d }
                var x = v + d
                if x < 1 { x = v != 0 ? 1 : 0 }
                x = min(x, v < 256 ? 255 : 65535)
                w[ti] = (String(x), true)
            } else if (i * 37 + 11) & 255 < ops, let k = Bytebeat.cellOps.firstIndex(of: toks[ti]) {
                w[ti] = (Bytebeat.cellOps[(k + 1 + l + 2 * r) & 7], true)
            }
        }
        return w
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

/// pad 4: the automaton — the grown formula (the changed words lit) over the last generations
struct AutomatonPad: View {
    @ObservedObject var ca: ByteCA
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
                    Text("R\(rule)").font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PastelTheme.hudBlack.opacity(0.7))
                        .frame(width: 30, alignment: .trailing)
                }
                ca.grown().reduce(Text("")) { acc, w in
                    acc + Text(w.0).foregroundColor(w.1 ? PastelTheme.hudOrange : PastelTheme.hudBlack)
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                Canvas { ctx, size in
                    let n = max(ca.n, 1), rows = ca.rows
                    let cw = size.width / CGFloat(n), ch = size.height / CGFloat(ByteCA.depthRows)
                    let top = CGFloat(ByteCA.depthRows - rows.count) * ch
                    for (ri, r) in rows.enumerated() {
                        for i in 0..<ca.n where (r >> UInt32(i)) & 1 == 1 {
                            let rect = CGRect(x: CGFloat(i) * cw + 0.5, y: top + CGFloat(ri) * ch + 0.5,
                                              width: max(1, cw - 1), height: max(1, ch - 1))
                            ctx.fill(Path(rect), with: .color(ri == rows.count - 1 ? PastelTheme.hudOrange : PastelTheme.hudBlack.opacity(0.8)))
                        }
                    }
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
