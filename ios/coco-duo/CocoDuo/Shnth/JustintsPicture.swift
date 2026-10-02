// JustintsPicture.swift — coco duo (k.odk)
// justints's own picture, drawn as its C++ draws it (MultiplexPotentiator / ChubberySituation::draw, Peter
// Blasser, MIT), one point here for one of its pixels:
//   four stripes in the Maryland flag's colours (the four oscillators); a row for each voice (the one chosen
//   at the bottom); for each oscillator the numerator as a square up-left, the denominator down-right, in each
//   number's own random colour, with the runes of their prime factors (a p-pointed star for each prime p,
//   stepped by the antenna); the bars' annex squares (orange up, turquoise down); the king and queen; the
//   prime limit's star in the middle; the step in cardinal red; with ROUTE / FM on, their squares — tap
//   them, as the mouse did, to route the bars.

import SwiftUI

enum JIPicture {
    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(min(255, max(0, r))) / 255, green: Double(min(255, max(0, g))) / 255, blue: Double(min(255, max(0, b))) / 255)
    }
    static let stripes = [rgb(200, 0, 0), rgb(200, 200, 200), rgb(200, 200, 0), rgb(10, 10, 10)]   // MultiplexPotentiator MF
    static let flag = [rgb(245, 0, 0), rgb(245, 245, 245), rgb(245, 255, 0), rgb(0, 0, 0)]        // Barre MarylandFlag
    static let navy = rgb(20, 20, 125), taupe = rgb(120, 120, 125), cardinal = rgb(170, 20, 22)

    private struct Rnd {                                    // (rand(): the colours are random, once)
        var s: UInt64
        mutating func next() -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) & 0x7FFF_FFFF) }
    }
    /// each Numba's two colours (mong / twong — its pens dong / shong are the same)
    static let numColors: ([Color], [Color]) = {
        var r = Rnd(s: 0x5EED)
        var a: [Color] = [], b: [Color] = []
        for _ in 0..<256 {
            let c = (0..<6).map { _ in r.next() & 255 }
            a.append(rgb(c[0], c[2], c[4])); b.append(rgb(c[1], c[3], c[5]))
        }
        return (a, b)
    }()
    /// PerspexStabile's MarylandAnnex: 0…127 orange, 128…255 turquoise
    static let annex: [Color] = {
        var r = Rnd(s: 0xA77E)
        var out = [Color](repeating: .black, count: 256)
        for o in 0..<128 { let s = r.next() % 8; out[o] = rgb(s + 128 + o + (o >> 1), s + 128 + (o >> 1), s + 128) }
        for t in 0..<128 { let s = r.next() % 8; out[255 - t] = rgb(s + 128, s + 128 + (t >> 1), s + 128 + t + (t >> 1)) }
        return out
    }()
    /// each number's prime factors, largest first (computeMultnas), as (prime, how many times)
    static let factors: [[(p: Int, n: Int)]] = (0..<256).map { v in
        var x = max(1, v), out: [(p: Int, n: Int)] = []
        var p = 2
        while x > 1 {
            var k = 0
            while x % p == 0 { x /= p; k += 1 }
            if k > 0 { out.insert((p, k), at: 0) }
            p += 1
        }
        return out
    }

    /// Prime::draw — the p points round a circle of radius p, joined `chink` apart
    static func prime(_ ctx: inout GraphicsContext, _ p: Int, _ x: CGFloat, _ y: CGFloat, _ color: Color, _ chink: Int) {
        guard p > 1 else { return }
        func pt(_ i: Int) -> CGPoint {
            let a = Double(i) / Double(p) * 3.14159 * 2
            return CGPoint(x: x + CGFloat(Int(Double(p) * sin(a))), y: y + CGFloat(Int(Double(p) * cos(a))))
        }
        var path = Path()
        path.move(to: pt(0))
        var off = 0
        for _ in 0..<p { off = (off + chink) % p; path.addLine(to: pt(off)) }
        ctx.stroke(path, with: .color(color), lineWidth: 1)
    }

    /// where one voice's pieces are (its row: numbr 1…amt)
    struct Row {
        var n = [CGRect](), d = [CGRect]()                   // the annex squares (nrectum / drectum)
        var x = [CGFloat](), y: CGFloat = 0, xchub: CGFloat = 0
        init(size: CGSize, amt: Int, numbr: Int) {
            xchub = floor(size.width / 4)
            let ysk = floor(size.height / CGFloat(1 + amt))
            y = CGFloat(numbr) * ysk
            for i in 0..<4 {
                let cx = floor(xchub / 2) + xchub * CGFloat(i)
                x.append(cx)
                n.append(CGRect(x: cx, y: y - 81, width: 81, height: 81))
                d.append(CGRect(x: cx - 81, y: y, width: 81, height: 81))
            }
        }
        static func r(_ l: CGFloat, _ t: CGFloat, _ rr: CGFloat, _ b: CGFloat) -> CGRect { CGRect(x: l, y: t, width: rr - l, height: b - t) }
        // RoyalMinister's squares ([i][m], m = the routing's index)
        func rmNK(_ i: Int, _ m: Int) -> CGRect { let j = CGFloat(3 - m); return Row.r(n[i].minX + j * 4, n[i].minY, n[i].minX + 36 - j * 4, n[i].minY + 36) }
        func rmNQ(_ i: Int, _ m: Int) -> CGRect { let j = CGFloat(3 - m); return Row.r(n[i].maxX - 36 + j * 4, n[i].maxY - 36 + j * 4, n[i].maxX - j * 4, n[i].maxY - j * 4) }
        func rmDK(_ i: Int, _ m: Int) -> CGRect { let j = CGFloat(3 - m); return Row.r(d[i].minX + j * 4, d[i].minY, d[i].minX + 36 - j * 4, d[i].minY + 36) }
        func rmDQ(_ i: Int, _ m: Int) -> CGRect { let j = CGFloat(3 - m); return Row.r(d[i].maxX - 36 + j * 4, d[i].maxY - 36 + j * 4, d[i].maxX - j * 4, d[i].maxY - j * 4) }
        // RoyalFMoutarde's squares
        func fmNK(_ i: Int, _ m: Int) -> CGRect { let s = CGFloat(m + 1) * 9; return Row.r(n[i].minX, n[i].maxY - s, n[i].minX + s, n[i].maxY) }
        func fmNQ(_ i: Int, _ m: Int) -> CGRect { let s = CGFloat(m + 1) * 9; return Row.r(n[i].maxX - s, n[i].minY, n[i].maxX, n[i].minY + s) }
        func fmDQ(_ i: Int, _ m: Int) -> CGRect { let s = CGFloat(m + 1) * 9; return Row.r(d[i].minX, d[i].maxY - s, d[i].minX + s, d[i].maxY) }
        func fmDK(_ i: Int, _ m: Int) -> CGRect { let s = CGFloat(m + 1) * 9; return Row.r(d[i].maxX - s, d[i].minY, d[i].maxX, d[i].minY + s) }
    }

    static func cell(_ m: ((Int8, Int8, Int8, Int8), (Int8, Int8, Int8, Int8), (Int8, Int8, Int8, Int8), (Int8, Int8, Int8, Int8)), _ i: Int, _ j: Int) -> Int {
        Int(withUnsafeBytes(of: m) { Int8(bitPattern: $0[i * 4 + j]) })
    }

    /// the whole picture
    static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ v: ji_view) {
        let W = size.width, H = size.height, amt = Int(v.amt)
        let xc = floor(W / 4)
        for i in 0..<4 { ctx.fill(Path(CGRect(x: xc * CGFloat(i), y: 0, width: i == 3 ? W - xc * 3 : xc, height: H)), with: .color(stripes[i])) }
        guard amt > 0 else { return }
        let ysk = floor(H / CGFloat(1 + amt))
        if v.one != 0 { ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: CGFloat(amt) * ysk)), with: .color(stripes[3])) }
        for i in 0..<amt {
            let k = (amt + Int(v.offset) - i - 1) % amt
            drawVoice(&ctx, size, v.voice(k), Row(size: size, amt: amt, numbr: i + 1))
        }
    }

    private static func drawVoice(_ ctx: inout GraphicsContext, _ size: CGSize, _ x: ji_voice_view, _ row: Row) {
        let nums = x.nums, dens = x.dens
        let gw = withUnsafeBytes(of: x.gw) { $0.map { Int($0) } }        // (as unsigned: the annex index)
        let chink = Int(x.officio)
        // SponGinger::drawMarylandAnnex
        for i in 0..<4 {
            ctx.fill(Path(row.n[i]), with: .color(annex[gw[i] & 255]))
            ctx.fill(Path(row.d[i]), with: .color(annex[255 - (gw[i] & 255)]))
        }
        // SponGinger::draw — the numbers' squares, the king and queen, the runes
        for i in 0..<4 {
            let n = CGFloat(nums[i]), d = CGFloat(dens[i])
            ctx.fill(Path(CGRect(x: row.x[i] - n, y: row.y - n, width: n, height: n)), with: .color(numColors.0[nums[i] & 255]))
            ctx.fill(Path(CGRect(x: row.x[i], y: row.y, width: d, height: d)), with: .color(numColors.1[dens[i] & 255]))
        }
        if x.queen >= 0 { king(&ctx, row.x[Int(x.king)], row.y); queen(&ctx, row.x[Int(x.queen)], row.y) }
        else if x.king >= 0 { king(&ctx, row.x[Int(x.king)], row.y) }
        for i in 0..<4 {
            var acc: CGFloat = 0
            for f in factors[nums[i] & 255] {                    // Numba::drawNumeRunes (direction −1)
                for o in 1...f.n { let off = -CGFloat(f.p * o); prime(&ctx, f.p, row.x[i] + acc + off, row.y + acc + off, numColors.1[nums[i] & 255], chink) }
                acc += -CGFloat(f.p * f.n)
            }
            acc = 0
            for f in factors[dens[i] & 255] {                    // drawDenoRunes (direction +1)
                for o in 1...f.n { let off = CGFloat(f.p * o); prime(&ctx, f.p, row.x[i] + acc + off, row.y + acc + off, numColors.0[dens[i] & 255], chink) }
                acc += CGFloat(f.p * f.n)
            }
        }
        // RoyalMinister::draw
        if x.route != 0 {
            for i in 0..<4 { for j in 0..<4 {
                let m = 3 - j, c = flag[(m + i) % 4]
                ctx.fill(Path(row.rmNK(i, m)), with: .color(cell(x.kingals, i, m) > 0 ? c : navy))
                ctx.fill(Path(row.rmNQ(i, m)), with: .color(cell(x.queenals, i, m) > 0 ? c : navy))
                ctx.fill(Path(row.rmDK(i, m)), with: .color(cell(x.kingals, i, m) < 0 ? c : navy))
                ctx.fill(Path(row.rmDQ(i, m)), with: .color(cell(x.queenals, i, m) < 0 ? c : navy))
            } }
        }
        // RoyalFMoutarde::draw
        if x.fm != 0 {
            let cut = CGFloat(9 - Int(x.fmshift))
            for i in 0..<4 { for j in 0..<4 {
                let m = 3 - j, c = flag[(m + i) % 4]
                var r = row.fmNK(i, m)
                if cell(x.numals, i, m) > 0 { ctx.fill(Path(r), with: .color(c)) }
                r.origin.y += cut; r.size.height -= cut; r.size.width -= cut
                ctx.fill(Path(r.standardized), with: .color(taupe))
                r = row.fmNQ(i, m)
                if cell(x.numals, i, m) < 0 { ctx.fill(Path(r), with: .color(c)) }
                r.size.height -= cut; r.origin.x += cut; r.size.width -= cut
                ctx.fill(Path(r.standardized), with: .color(taupe))
                r = row.fmDQ(i, m)
                if cell(x.denals, i, m) > 0 { ctx.fill(Path(r), with: .color(c)) }
                r.origin.y += cut; r.size.height -= cut; r.size.width -= cut
                ctx.fill(Path(r.standardized), with: .color(taupe))
                r = row.fmDK(i, m)
                if cell(x.denals, i, m) < 0 { ctx.fill(Path(r), with: .color(c)) }
                r.size.height -= cut; r.origin.x += cut; r.size.width -= cut
                ctx.fill(Path(r.standardized), with: .color(taupe))
            } }
        }
        // SponGinger::drawCardinalAccent (the step)
        let s2 = CGFloat(Int(x.step) << 1)
        let n0 = row.n[0]
        var rs: [CGRect] = []
        rs.append(Row.r(n0.minX, row.n[1].minY, n0.minX + 36, row.n[1].minY + s2))
        rs.append(Row.r(n0.minX, row.n[1].minY + 36 - s2, n0.minX + 36, row.n[1].minY + 36))
        let q3t = n0.maxY - 36, q1b = n0.maxY, q0l = n0.maxX - 36, q2r = n0.maxX
        rs.append(Row.r(q0l, q3t, q0l + s2, q3t + s2))                // qnass[0]
        rs.append(Row.r(q0l, q1b - s2, q0l + s2, q1b))                // qnass[1]
        rs.append(Row.r(q2r - s2, q1b - s2, q2r, q1b))                // qnass[2]
        rs.append(Row.r(q2r - s2, q3t, q2r, q3t + s2))                // qnass[3]
        for i in 0..<4 {
            for r in rs {
                let a = r.offsetBy(dx: row.xchub * CGFloat(i), dy: 0)
                ctx.fill(Path(a), with: .color(cardinal))
                ctx.fill(Path(a.offsetBy(dx: -81, dy: 81)), with: .color(cardinal))
            }
        }
        // Chinkwonkanater::drawtittle (the prime limit)
        prime(&ctx, Int(x.prime), row.xchub * 2, row.y, .black, chink)
    }

    private static func king(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat) {
        var i = 10
        while i > 0 { ctx.fill(Path(CGRect(x: x - CGFloat(i), y: y - CGFloat(i), width: CGFloat(2 * i), height: CGFloat(2 * i))), with: .color(flag[i % 4])); i -= 2 }
    }
    private static func queen(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat) {
        for i in stride(from: 9, to: 0, by: -1) { ctx.fill(Path(CGRect(x: x - CGFloat(i), y: y - CGFloat(i), width: CGFloat(2 * i), height: CGFloat(2 * i))), with: .color(flag[i % 4])) }
    }

    /// the mouse: which routing squares a tap is in (every voice, as MultiplexPotentiator::mouseButt) —
    /// (voice, which, i, j) for ji_toggle
    static func hits(_ p: CGPoint, _ size: CGSize, _ v: ji_view) -> [(Int, Int, Int, Int)] {
        let amt = Int(v.amt)
        guard amt > 0 else { return [] }
        func inside(_ r: CGRect) -> Bool { p.x > r.minX && p.x < r.maxX && p.y > r.minY && p.y < r.maxY }
        var out: [(Int, Int, Int, Int)] = []
        for i in 0..<amt {
            let k = (amt + Int(v.offset) - i - 1) % amt
            let x = v.voice(k), row = Row(size: size, amt: amt, numbr: i + 1)
            var hit: (Int, Int, Int, Int)?
            if x.route != 0 {                                    // RoyalMinister::lippingMinisterialEar
                search: for a in 0..<4 { for b in 0..<4 {
                    if inside(row.rmNK(a, b)) { hit = (k, 0, a, b); break search }
                    if inside(row.rmNQ(a, b)) { hit = (k, 1, a, b); break search }
                    if inside(row.rmDK(a, b)) { hit = (k, 2, a, b); break search }
                    if inside(row.rmDQ(a, b)) { hit = (k, 3, a, b); break search }
                } }
            }
            if hit == nil, x.fm != 0 {                           // RoyalFMoutarde::lippingMoutarde
                search: for a in 0..<4 { for b in 0..<4 {
                    if inside(row.fmNK(a, b)) { hit = (k, 4, a, b); break search }
                    if inside(row.fmNQ(a, b)) { hit = (k, 5, a, b); break search }
                    if inside(row.fmDK(a, b)) { hit = (k, 6, a, b); break search }
                    if inside(row.fmDQ(a, b)) { hit = (k, 7, a, b); break search }
                } }
            }
            if let h = hit { out.append(h) }
        }
        return out
    }
}

/// the picture on the screen, tappable
struct JustintsPictureView: View {
    let v: ji_view
    let tap: (Int, Int, Int, Int) -> Void
    var body: some View {
        GeometryReader { g in
            Canvas { ctx, size in JIPicture.draw(&ctx, size, v) }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { e in
                    JIPicture.hits(e.location, g.size, v).forEach { tap($0.0, $0.1, $0.2, $0.3) }
                })
        }
        .clipped()
    }
}
