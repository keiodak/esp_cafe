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

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let rows = brightness.count
            guard rows > 0 else { return }
            let cols = brightness[0].count
            guard cols > 0 else { return }
            let w = size.width / CGFloat(cols)
            let h = size.height / CGFloat(rows)
            for r in 0..<rows {
                let row = brightness[r]
                for c in 0..<min(cols, row.count) {
                    // 0.5pt はみ出させて、マスの間に隙間が出ないようにする。
                    let rect = CGRect(x: CGFloat(c) * w, y: CGFloat(r) * h,
                                      width: w + 0.5, height: h + 0.5)
                    context.fill(Path(rect), with: .color(PastelTheme.inkTone(row[c])))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
