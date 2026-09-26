import SwiftUI

/// 明るさの2次元配列(rows x cols)を、グリッド状の四角として描く。
/// カメラモザイクで、1パッドあたり縦4×横8=32マスを表示するのに使う。
///
/// sunnandægではRectangleをVStack/HStackで32個並べていたが、こちらはCanvasで
/// 1枚に描く。カメラは最大30fpsで届き、パッドが4枚あるので、Viewとして並べると
/// 毎秒 32×4×30 ≒ 3840個のViewが作り直されてメインスレッドを食う。
/// Canvasなら作られるViewは1つで、中で矩形を32回塗るだけになる。
struct MosaicGridView: View {
    /// [row][col] の明るさ(0...1)。
    let brightness: [[Double]]

    /// halftone: each cell becomes 3 × 3 ink dots, sized by how dark the camera sees it there
    /// (the brightness is interpolated between cells, so the picture flows instead of stepping);
    /// the brightest spots get a small orange dot — the HUD's one accent
    private static let sub = 3

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let rows = brightness.count
            guard rows > 0 else { return }
            let cols = brightness[0].count
            guard cols > 0 else { return }
            let n = Self.sub
            let gx = cols * n, gy = rows * n
            let w = size.width / CGFloat(gx), h = size.height / CGFloat(gy)
            let rMax = min(w, h) * 0.48
            func b(_ x: Double, _ y: Double) -> Double {          // bilinear, x/y in cell units (centres at .5)
                let fx = min(max(x - 0.5, 0), Double(cols - 1)), fy = min(max(y - 0.5, 0), Double(rows - 1))
                let x0 = Int(fx), y0 = Int(fy), x1 = min(x0 + 1, cols - 1), y1 = min(y0 + 1, rows - 1)
                let tx = fx - Double(x0), ty = fy - Double(y0)
                func v(_ r: Int, _ c: Int) -> Double { c < brightness[r].count ? brightness[r][c] : 0.5 }
                let top = v(y0, x0) * (1 - tx) + v(y0, x1) * tx
                let bot = v(y1, x0) * (1 - tx) + v(y1, x1) * tx
                return top * (1 - ty) + bot * ty
            }
            var ink = Path(), glow = Path()
            for j in 0..<gy {
                for i in 0..<gx {
                    let v = b((Double(i) + 0.5) / Double(n), (Double(j) + 0.5) / Double(n))
                    let cx = (CGFloat(i) + 0.5) * w, cy = (CGFloat(j) + 0.5) * h
                    let r = rMax * CGFloat(pow(max(0, 1 - v), 0.75))
                    if r > 0.4 { ink.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)) }
                    if v > 0.82 {
                        let g = rMax * CGFloat((v - 0.82) / 0.18) * 0.7
                        glow.addEllipse(in: CGRect(x: cx - g, y: cy - g, width: 2 * g, height: 2 * g))
                    }
                }
            }
            context.fill(ink, with: .color(PastelTheme.hudBlack.opacity(0.78)))
            context.fill(glow, with: .color(PastelTheme.hudOrange))
        }
        .allowsHitTesting(false)
    }
}
