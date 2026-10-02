// ShlispGen.swift — coco duo (k.odk)
// GEN for SHNTH: new shlisp patches, learned from the 36 example patches in the app.
// The examples are read into: what each word is (its category), how many arguments it takes, and for each
// argument whether the players wrote a number (which numbers) or another expression (which words).
//   ORDER — by category: each side gets a few voices, each a sound source (horn, saw, mount, swoop, string …)
//           shaped by the template the examples use most, and the hands are dealt out among them: bars as
//           volume or pitch, buttons as triggers / gates, antennae as modulation. Numbers from the examples.
//   MIX   — the examples' own grammar: words and numbers drawn with the frequencies they have there.
//   CHAOS — any word anywhere, deeper nesting, numbers anywhere, voices crossing between left and right.
// Every patch is compiled before it plays; one that does not compile is drawn again.

import Foundation

enum ShlispGen {
    enum Mode: String, CaseIterable { case order = "ORDER", mix = "MIX", chaos = "CHAOS" }

    // MARK: the words, by category (tokes.c; instances = how many of each: horn, hornb … hornh)

    static let instances: [String: Int] = [
        "wind": 1, "corp": 2, "bar": 4, "minor": 4, "major": 4, "tar": 1,
        "horn": 8, "saw": 8, "togo": 8, "toggle": 8, "swoop": 8, "mount": 8, "smoke": 8, "dust": 8,
        "fog": 4, "swamp": 4, "haze": 4, "string": 4, "comb": 4, "zither": 4, "wave": 4, "water": 4, "salt": 4,
        "horse": 4, "slew": 8, "wheel": 4, "gear": 8, "pulse": 8, "sauce": 8, "salsa": 8, "press": 4, "leak": 4,
        "reflect": 1, "return": 1, "and": 1, "xor": 1, "square": 1, "modo": 1, "mul": 1, "add": 1, "pan": 1,
    ]
    static let controls = ["bar", "corp", "minor", "major", "tar", "wind"]
    static let sources = ["horn", "saw", "mount", "swoop", "smoke", "dust", "togo", "toggle", "fog", "swamp", "haze",
                          "horse", "wheel", "gear", "pulse", "sauce", "salsa"]
    static let resonators = ["string", "comb", "zither", "wave", "water", "salt", "slew", "leak", "press"]
    static let shapers = ["reflect", "return", "and", "xor", "square", "modo", "mul", "add", "pan"]
    static let letters = Array("abcdefgh")

    /// "hornb" -> ("horn", 1)
    static func split(_ w: String) -> (String, Int)? {
        if instances[w] != nil { return (w, 0) }
        guard w.count > 1, let last = w.last, let k = letters.firstIndex(of: last), k > 0 else { return nil }
        let base = String(w.dropLast())
        guard let n = instances[base], k < max(n, 2) else { return nil }
        return (base, k)
    }
    static func name(_ base: String, _ k: Int) -> String { k == 0 ? base : base + String(letters[k]) }

    // MARK: reading the examples

    indirect enum Node { case num(Int), word(String), list([Node]) }

    static func parse(_ s: String) -> [[Node]] {                  // the presets, each a list of top-level forms
        var toks: [String] = []
        var cur = ""
        var comment = false
        func flush() { if !cur.isEmpty { toks.append(cur); cur = "" } }
        for c in s {
            if comment { if c == "\n" || c == "\r" { comment = false }; continue }
            if c == ";" { flush(); comment = true; continue }
            if "(){}[]".contains(c) { flush(); toks.append(String(c)); continue }
            if c.isWhitespace { flush(); continue }
            cur.append(c)
        }
        flush()
        var i = 0
        func list(_ close: String) -> [Node] {
            var out: [Node] = []
            while i < toks.count {
                let t = toks[i]; i += 1
                if t == close || t == ")" || t == "}" || t == "]" { return out }
                if t == "(" || t == "[" { out.append(.list(list(t == "(" ? ")" : "]"))) }
                else if t == "{" { out.append(.list(list("}"))) }
                else if let n = Int(t) { out.append(.num(n)) }
                else { out.append(.word(t.lowercased())) }
            }
            return out
        }
        var presets: [[Node]] = []
        while i < toks.count {
            let t = toks[i]; i += 1
            if t == "{" { presets.append(list("}")) }
        }
        return presets
    }

    struct Stat {
        var argc: [Int] = []                                       // how many arguments, each time it was written
        var nums: [[Int]] = Array(repeating: [], count: 8)         // per argument: the numbers
        var subs: [[String]] = Array(repeating: [], count: 8)      // per argument: the words of nested expressions
    }
    struct Corpus {
        var stats: [String: Stat] = [:]
        var sideCount: [Int] = []                                  // forms inside (left …) / (right …)
        var sideWords: [String] = []
        var srates: [Int] = []
        var jumps = 0, presets = 0
    }

    static let corpus: Corpus = {
        var c = Corpus()
        func walk(_ n: Node) {
            guard case .list(let xs) = n, case .word(let w)? = xs.first, let (base, _) = split(w) else {
                if case .list(let xs) = n { xs.forEach(walk) }
                return
            }
            var s = c.stats[base] ?? Stat()
            let args = Array(xs.dropFirst())
            s.argc.append(args.count)
            for (p, a) in args.prefix(8).enumerated() {
                switch a {
                case .num(let v): s.nums[p].append(v)
                case .list(let ys): if case .word(let sw)? = ys.first, let (sb, _) = split(sw) { s.subs[p].append(sb) }
                case .word: break
                }
            }
            c.stats[base] = s
            args.forEach(walk)
        }
        for p in ShnthPlayer.patches {
            for preset in parse(p.source) {
                c.presets += 1
                for f in preset {
                    guard case .list(let xs) = f, case .word(let w)? = xs.first else { continue }
                    switch w {
                    case "left", "right":
                        c.sideCount.append(xs.count - 1)
                        for x in xs.dropFirst() {
                            if case .list(let ys) = x, case .word(let sw)? = ys.first, let (sb, _) = split(sw) { c.sideWords.append(sb) }
                            walk(x)
                        }
                    case "srate": if xs.count > 1, case .num(let v) = xs[1] { c.srates.append(v) }
                    case "jump": c.jumps += 1
                    default: walk(f)
                    }
                }
            }
        }
        return c
    }()

    // MARK: making

    /// how many GEN levels (1 = in order … 12 = chaos)
    static let levels = 12
    static func chaos(_ level: Int) -> Double { Double(max(1, min(levels, level)) - 1) / Double(levels - 1) }
    /// the three named ones: ORDER 0 · MIX 0.5 · CHAOS 1
    static func make(_ mode: Mode, presets: Int = 4) -> String? {
        make(chaos: mode == .order ? 0 : mode == .mix ? 0.5 : 1, title: mode.rawValue, presets: presets)
    }
    /// a whole patch at GEN level 1…12
    static func make(level: Int, presets: Int = 4) -> String? { make(chaos: chaos(level), title: "\(level)", presets: presets) }
    /// a whole patch: `presets` presets, each { … }, at chaos c (0 … 1); compiled before it is given (nil: none compiled)
    static func make(chaos c: Double, title: String, presets: Int = 4) -> String? {
        var out = ""
        for _ in 0..<presets {
            var ok: String?
            for _ in 0..<40 {
                let p = preset(c)
                if compiles("{\(p)}") { ok = p; break }
            }
            if let p = ok { out += "{\(p)}\n" }
        }
        return compiles(out) ? out : nil
    }

    static func compiles(_ s: String) -> Bool {
        var buf = [UInt8](repeating: 0, count: 70000)
        var err = [CChar](repeating: 0, count: 256)
        let n = s.withCString { shlisp_compile($0, &buf, Int32(buf.count), &err, Int32(err.count)) }
        return n > 0
    }

    private struct Ctx {
        var c: Double                                               // chaos 0 … 1
        var used: [String: Int] = [:]                               // instances handed out (per preset)
        mutating func take(_ base: String) -> String {
            let n = max(1, ShlispGen.instances[base] ?? 1)
            let k = used[base, default: 0]
            used[base] = k + 1
            // (past the middle, more and more of them shared — coupled, as the same instance twice)
            if k > 0 && Double.random(in: 0..<1) < max(0, c - 0.5) * 0.8 { return ShlispGen.name(base, Int.random(in: 0..<min(n, k))) }
            return ShlispGen.name(base, k % n)
        }
    }
    private static func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }

    /// one preset at chaos c: each voice either one of the examples' templates (more often the lower c is) or
    /// grown from their grammar, words and numbers drawn wider and wider as c rises
    private static func preset(_ c: Double) -> String {
        var cx = Ctx(c: c)
        let k = corpus
        var forms: [String] = []
        let swap = Bool.random()                                   // (the hands dealt out: left bar, barb … right barc, bard)
        for side in 0..<2 {
            let n = c < 0.5 ? max(1, min(4, k.sideCount.randomElement() ?? 2)) : Int.random(in: 1...(1 + Int(c * 4)))
            let mine = (side == 0) != swap ? [0, 1] : [2, 3]
            var parts: [String] = []
            for v in 0..<min(n, 6) {
                if chance(1 - 2 * c) {
                    parts.append(orderVoice(&cx, bar: mine[v % 2], button: mine[v % 2], antenna: side))
                } else {
                    let w = chance(c) ? (sources + resonators + shapers).randomElement()! : (k.sideWords.randomElement() ?? "horn")
                    parts.append(expr(&cx, w, depth: 0))
                }
            }
            forms.append("(\(side == 0 ? "left" : "right") \(parts.joined(separator: " ")))")
        }
        let jp = Double(k.jumps) / Double(max(1, k.presets))
        if chance(jp + (0.5 - jp) * c) {
            forms.append("(jump (\(chance(0.5) ? "minor" : "major")\(["", "b", "c", "d"].randomElement()!) 1))")
        }
        if chance(0.2 + 0.4 * c) {
            forms.append("(srate \(chance(c) ? Int.random(in: 8...250) : (k.srates.randomElement() ?? 64)))")
        }
        return forms.joined(separator: "\n ")
    }

    /// a number for word / argument p: the examples' own, moved further (and more often anywhere) as c rises
    private static func number(_ base: String, _ p: Int, _ c: Double) -> Int {
        if !chance(c * c), let s = corpus.stats[base], p < 8, let v = s.nums[p].randomElement() {
            let j = Int(c * 48)
            return j > 0 ? clampByte(v + Int.random(in: -j...j)) : v
        }
        let lo = Int(8 - 135 * c), hi = Int(120 + 7 * c)
        return Int.random(in: lo...hi)
    }
    private static func clampByte(_ v: Int) -> Int { max(-127, min(127, v)) }

    /// an expression with the word `w`, grown from the examples' grammar (c: how far from it)
    private static func expr(_ cx: inout Ctx, _ w: String, depth: Int) -> String {
        let s = corpus.stats[w]
        let c = cx.c
        var argc = s?.argc.randomElement() ?? Int.random(in: 1...3)
        if chance(c) { argc = max(0, min(6, argc + Int.random(in: -1...2))) }
        let maxDepth = 2 + Int(c * 3.99)
        var args: [String] = []
        for p in 0..<argc {
            let subs = (s != nil && p < 8) ? s!.subs[p] : []
            let nums = (s != nil && p < 8) ? s!.nums[p].count : 0
            let learned = Double(subs.count) / Double(max(1, subs.count + nums))
            let pNest = learned * (1 - c) + 0.55 * c
            if depth < maxDepth && chance(pNest) {
                let sw = chance(c) || subs.isEmpty ? Array(instances.keys).randomElement()! : subs.randomElement()!
                args.append(expr(&cx, sw, depth: depth + 1))
            } else {
                args.append("\(number(w, p, c))")
            }
        }
        return "(\(cx.take(w))\(args.isEmpty ? "" : " " + args.joined(separator: " ")))"
    }

    /// ORDER: one voice — a source in one of the examples' templates, with its share of the hands
    private static func orderVoice(_ cx: inout Ctx, bar: Int, button: Int, antenna: Int) -> String {
        let bar = name("bar", bar)                                    // (the hands keep their own letters)
        let minor = name("minor", button), major = name("major", button)
        let corp = name("corp", antenna)
        func n(_ w: String, _ p: Int) -> Int { number(w, p, cx.c * 0.5) }
        switch Int.random(in: 0..<7) {
        case 0:                                                       // plain: (horn n d (bar)) — the bar is the volume
            let w = ["horn", "saw", "mount"].randomElement()!
            return "(\(cx.take(w)) \(n(w, 0)) \(n(w, 1)) (\(bar)))"
        case 1:                                                       // FM: a horn's pitch from another, bent by the antenna
            return "(\(cx.take("horn")) (\(cx.take("horn")) \(n("horn", 0)) \(n("horn", 1)) (\(bar))) (\(corp) \(n("corp", 0)) \(n("corp", 1))))"
        case 2:                                                       // a filter: noise through wave, the bar opens it
            return "(\(cx.take("wave")) (\(cx.take("smoke")) (\(cx.take("mount")) \(n("mount", 0)) \(n("mount", 1)))) \(n("wave", 1)) (\(bar) \(n("bar", 0))))"
        case 3:                                                       // a plucked string, the button plucks
            return "(\(cx.take("string")) (\(minor)) \(n("string", 1)) \(n("string", 2)) (\(bar) \(n("bar", 0))))"
        case 4:                                                       // a gated tone: square of a horn under the button
            return "(square (\(cx.take("horn")) \(n("horn", 0)) \(n("horn", 1)) (\(minor))))"
        case 5:                                                       // a swoop: the button sweeps a saw
            return "(\(cx.take("swoop")) (\(major)) \(n("swoop", 1)) \(n("swoop", 2)) (\(cx.take("saw")) \(n("saw", 0)) \(n("saw", 1))))"
        default:                                                      // dust into a fog, the antenna thickens it
            return "(\(cx.take("fog")) (\(cx.take("dust")) (\(corp) \(n("corp", 0)))) \(n("fog", 1)) \(n("fog", 2)) (\(bar)))"
        }
    }
}
