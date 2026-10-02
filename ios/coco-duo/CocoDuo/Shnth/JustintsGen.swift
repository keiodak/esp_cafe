// JustintsGen.swift — coco duo (k.odk)
// GEN for JUSTINTS: new .texte (the voices of a slot), learned from justints's 13 examples.
// The examples are read section by section (chinkwonkanater: the prime limit and the antenna's speed;
// sponginger: the four ratios, step, ramp / saw; royalminister / royalfmoutarde: the routings).
//   ORDER — by category: one prime limit for all (3, 5 or 7), the four ratios of each voice built as just
//           intervals over a common denominator (unison, octave, fifth, fourth, thirds …), voices a chorus of
//           each other; routing and FM off, the antenna's prime limit held — a consonant, playable chord.
//   MIX   — each setting drawn from what the examples use, ratios from theirs (now and then a neighbour),
//           routings from their rows.
//   CHAOS — any prime limit or the antenna's, any ratio, routing and FM on and dense, any speed.

import Foundation

enum JustintsGen {
    typealias Mode = ShlispGen.Mode

    struct Corpus {
        var primes: [Int] = [], holds: [Int] = [], strittons: [Int] = [], strittles: [Int] = []
        var ratios: [(Int, Int)] = [], steps: [Int] = [], ramps: [Int] = [], saws: [Int] = []
        var rmOff: [Int] = [], fmOff: [Int] = [], fmShifts: [Int] = []
        var rmRows: [[Int]] = [], fmRows: [[Int]] = []
        var voices: [Int] = []
    }

    static let corpus: Corpus = {
        var c = Corpus()
        for ex in JustintsPlayer.examples {
            let t = ex.text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" }).map(String.init)
            var i = 0, sec = "", n = 0
            func next() -> String { i += 1; return i < t.count ? t[i] : "" }
            while i < t.count {
                let w = t[i]
                switch w {
                case "chubby": n += 1
                case "barre", "chinkwonkanater", "sponginger", "royalminister", "royalfmoutarde": sec = w
                case "inhibit":
                    let v = Int(next()) ?? 1
                    if sec == "chinkwonkanater" { c.holds.append(v) } else if sec == "royalminister" { c.rmOff.append(v) } else { c.fmOff.append(v) }
                case "primelm": c.primes.append(Int(next()) ?? 3)
                case "stritton": c.strittons.append(Int(next()) ?? 8)
                case "strittle": c.strittles.append(Int(next()) ?? 32)
                case "rat":
                    _ = next(); _ = next()
                    let a = Int(next()) ?? 1; _ = next(); let b = Int(next()) ?? 1
                    c.ratios.append((a, b))
                case "bitshift":
                    let v = Int(next()) ?? 0
                    if sec == "sponginger" { c.steps.append(v) } else { c.fmShifts.append(v) }
                case "gingzgongz": c.ramps.append(Int(next()) ?? 1)
                case "quiznoquantan": c.saws.append(Int(next()) ?? 0)
                case "kingals", "queenals", "numals", "denals":
                    _ = next(); _ = next()
                    let row = (0..<4).map { _ in Int(next()) ?? 0 }
                    if w == "kingals" || w == "queenals" { c.rmRows.append(row) } else { c.fmRows.append(row) }
                default: break
                }
                i += 1
            }
            c.voices.append(n)
        }
        return c
    }()

    static let primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97,
                         101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163, 167, 173, 179, 181, 191, 193,
                         197, 199, 211, 223, 227, 229, 233, 239, 241, 251]
    static func lpf(_ v: Int) -> Int {
        var x = max(1, v), p = 2, big = 1
        while x > 1 { while x % p == 0 { x /= p; big = p }; p += 1 }
        return big
    }
    static func pick<T>(_ a: [T], _ fallback: T) -> T { a.randomElement() ?? fallback }

    /// the just intervals a prime limit allows (as num / den)
    static func intervals(_ limit: Int) -> [(Int, Int)] {
        let all: [(Int, Int)] = [(1, 1), (2, 1), (3, 2), (4, 3), (3, 1), (5, 4), (6, 5), (5, 3), (8, 5), (9, 8),
                                 (7, 4), (7, 6), (8, 7), (16, 9), (15, 8), (4, 1)]
        return all.filter { lpf($0.0) <= limit && lpf($0.1) <= limit }
    }

    // MARK: making

    /// a .texte of new voices
    static func make(_ mode: Mode) -> String {
        let c = corpus
        let nv: Int = mode == .order ? Int.random(in: 3...4) : mode == .mix ? max(1, pick(c.voices, 4)) : Int.random(in: 2...6)
        let limit = mode == .order ? [3, 3, 5, 7].randomElement()! : pick(c.primes, 3)
        let speed = mode == .order ? pick(c.strittles, 32) : 0
        var out = ""
        for k in 0..<min(nv, 15) {
            out += "chubby \(k)\n barre\n  atrest\n chinkwonkanater\n"
            switch mode {
            case .order:
                out += "  inhibit 1\n  primelm \(limit)\n  stritton 8\n  strittle \(max(8, speed + Int.random(in: -3...3)))\n"
            case .mix:
                out += "  inhibit \(pick(c.holds, 1))\n  primelm \(pick(c.primes, 3))\n  stritton \(pick(c.strittons, 8))\n  strittle \(pick(c.strittles, 32))\n"
            case .chaos:
                let hold = Int.random(in: 0..<2)
                out += "  inhibit \(hold)\n  primelm \(primes.randomElement()!)\n  stritton \(Int.random(in: 0...8))\n  strittle \(Int.random(in: 4...160))\n"
            }
            out += " sponginger\n"
            let rats = ratios(mode, limit: limit)
            for (i, r) in rats.enumerated() { out += "  rat \(i) = \(r.0) / \(r.1)\n" }
            switch mode {
            case .order: out += "  bitshift \(Int.random(in: 0...2))\n  gingzgongz 1\n  quiznoquantan 0\n"
            case .mix: out += "  bitshift \(pick(c.steps, 0))\n  gingzgongz \(pick(c.ramps, 1))\n  quiznoquantan \(pick(c.saws, 0))\n"
            case .chaos: out += "  bitshift \(Int.random(in: 0...8))\n  gingzgongz \(Int.random(in: 0...1))\n  quiznoquantan \(Int.random(in: 0...1))\n"
            }
            // the routings
            let rmOff = mode == .order ? 1 : mode == .mix ? pick(c.rmOff, 1) : 0
            let fmOff = mode == .order ? 1 : mode == .mix ? pick(c.fmOff, 1) : 0
            out += " royalminister\n  inhibit \(rmOff)\n"
            for i in 0..<4 {
                out += "  kingals \(i) = \(row(mode, c.rmRows)) \n  queenals \(i) = \(row(mode, c.rmRows)) \n"
            }
            out += " royalfmoutarde\n  inhibit \(fmOff)\n"
            for i in 0..<4 {
                out += "  numals \(i) = \(row(mode, c.fmRows)) \n  denals \(i) = \(row(mode, c.fmRows)) \n"
            }
            let fb = mode == .order ? 1 : mode == .mix ? pick(c.fmShifts, 1) : Int.random(in: 0...4)
            out += "  bitshift \(fb)\n"
        }
        return out
    }

    private static func row(_ mode: Mode, _ rows: [[Int]]) -> String {
        let r: [Int]
        switch mode {
        case .order: r = [0, 0, 0, 0]
        case .mix: r = rows.randomElement() ?? [0, 0, 0, 0]
        case .chaos: r = (0..<4).map { _ in Double.random(in: 0..<1) < 0.35 ? [-1, 1].randomElement()! : 0 }
        }
        return r.map(String.init).joined(separator: " ")
    }

    /// the four ratios of a voice
    private static func ratios(_ mode: Mode, limit: Int) -> [(Int, Int)] {
        switch mode {
        case .order:
            // a common denominator within the limit, the four as just intervals over it
            let dens = (16...192).filter { lpf($0) <= limit }
            let ivs = intervals(limit)
            var out: [(Int, Int)] = []
            for i in 0..<4 {
                var r = (1, 1)
                for _ in 0..<60 {
                    let d = dens.randomElement() ?? 32
                    let iv = i == 0 ? (1, 1) : (ivs.randomElement() ?? (1, 1))
                    guard d % iv.1 == 0 else { continue }
                    let n = d / iv.1 * iv.0
                    if n >= 1 && n <= 255 && lpf(n) <= limit { r = (n, d); break }
                }
                out.append(r)
            }
            return out
        case .mix:
            return (0..<4).map { _ in
                var r = corpus.ratios.randomElement() ?? (1, 1)
                if Int.random(in: 0..<4) == 0 { r = (max(1, min(255, r.0 + Int.random(in: -2...2))), r.1) }
                return r
            }
        case .chaos:
            return (0..<4).map { _ in (Int.random(in: 1...255), Int.random(in: 1...255)) }
        }
    }
}
