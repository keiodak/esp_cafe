import SwiftUI

/// ドラッグでX/Y値(各0...1)を操作するシンプルなXYパッド。
struct XYPad: View {
    let label: String
    let xLabel: String
    let yLabel: String
    @Binding var x: Double // 0...1
    @Binding var y: Double // 0...1 (画面上は上が1、下が0)
    var padHeight: CGFloat = 220
    /// falseの間はドラッグ操作を受け付けない(ジェスチャー再生中に手動操作と衝突しないように)。
    var interactionEnabled: Bool = true
    /// ドラッグで値が更新されるたびに呼ばれる(録音用)。
    var onDrag: ((Double, Double) -> Void)? = nil
    /// 指が新しく触れた瞬間(ドラッグ開始)にだけ1回呼ばれる(タッチ回数カウント用)。
    var onTouchBegan: (() -> Void)? = nil
    /// 指が離れた瞬間に呼ばれる(重力ボールのフリック用)。
    var onTouchEnded: (() -> Void)? = nil
    /// インジケーターの色(パッドごとに変えられるように)。
    var accentColor: Color = PastelTheme.pink
    /// 4象限(左上・右上・左下・右下)の薄い塗り色。X/Y入れ替えで一緒に入れ替えられる。
    var quadrantTopLeft: Color = .clear
    var quadrantTopRight: Color = .clear
    var quadrantBottomLeft: Color = .clear
    var quadrantBottomRight: Color = .clear

    @State private var isTouching: Bool = false

    /// ポインターが動ける範囲の内側マージン。値が0や1のときでも、ポインターが
    /// パッドの縁ぴったりに張り付かず、少し内側で止まる。ドラッグの座標変換も
    /// 同じマージンで行うので、指とポインターの対応は保たれる。
    /// (RecordableXYPad側の上乗せポインターと共有するためstaticにする)
    static let pointerInset: CGFloat = 9
    private var pointerInset: CGFloat { Self.pointerInset }

    /// falseにすると内蔵のポインター(黒い点)を描かない。
    /// RecordableXYPadが四隅ボタンより上のレイヤーに自前で描くために使う。
    var showsPointer: Bool = true

    /// 角丸の指定(四隅個別)。パッドの「画面中央側の角」は丸めないことで、
    /// 4枚を並べたとき太陽の周りに背景のグレー領域が露出しないようにする。
    var cornerRadii: RectangleCornerRadii = .init(
        topLeading: 14, bottomLeading: 14, bottomTrailing: 14, topTrailing: 14
    )

    /// 面とポインターのあいだに敷く絵(写像の軌道など)。指は素通しする。
    var trace: AnyView? = nil
    /// カメラモードのとき、このパッドが担当する縦2×横2のモザイク。nilなら描かない
    var mosaic: [[Double]]? = nil
    /// カメラモード中の縁の濃さ(0...1)。映像の動き量に応じて縁がふっと濃くなる
    var edgeGlow: Double = 0.0
    /// カメラモードがONのときtrue。指の操作は受け付けず、面はモザイクになる
    var cameraMode: Bool = false

    private var padShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 面・4象限・グリッド線は、ポインターの位置に依存しない。
                // 別のViewに切り出しておくと、指でポインターが動いても
                // ここのbodyは呼ばれず、影の描き直しも起きない。
                PadSurface(cameraMode: cameraMode,
                           mosaic: mosaic,
                           edgeGlow: edgeGlow,
                           quadrantTopLeft: quadrantTopLeft,
                           quadrantTopRight: quadrantTopRight,
                           quadrantBottomLeft: quadrantBottomLeft,
                           quadrantBottomRight: quadrantBottomRight,
                           cornerRadii: cornerRadii)

                if edgeGlow > 0.001 {
                    PadEdgeGlow(glow: edgeGlow, x: x, y: y, cornerRadii: cornerRadii)
                }

                if let trace {
                    trace
                        .allowsHitTesting(false)
                        .clipShape(padShape)
                }

                // ポジションインジケーター: 影を一切かけない、クッキリした点。
                // 端の値(0/1)でも縁ギリギリまで行かないよう、内側マージン分を縮めて配置する。
                if showsPointer {
                    // HUD pointer: faint tracking lines across the pad, an orange square with a black ring
                    let px = pointerInset + CGFloat(x) * (geo.size.width - pointerInset * 2)
                    let py = pointerInset + CGFloat(1.0 - y) * (geo.size.height - pointerInset * 2)
                    Path { p in
                        p.move(to: CGPoint(x: px, y: 0)); p.addLine(to: CGPoint(x: px, y: geo.size.height))
                        p.move(to: CGPoint(x: 0, y: py)); p.addLine(to: CGPoint(x: geo.size.width, y: py))
                    }
                    .stroke(PastelTheme.hudOrange.opacity(isTouching ? 0.55 : 0.28), lineWidth: 0.7)
                    .allowsHitTesting(false)
                    Rectangle()
                        .fill(PastelTheme.padPointer)
                        .frame(width: 8, height: 8)
                        .overlay(Rectangle().strokeBorder(PastelTheme.hudBlack, lineWidth: 1).padding(-3))
                        .position(x: px, y: py)
                    Text(String(format: "%03ld·%03ld", Int(x * 999), Int(y * 999)))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(PastelTheme.hudBlack.opacity(0.6))
                        .position(x: min(max(px + 26, 26), geo.size.width - 26), y: max(py - 11, 8))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard interactionEnabled, !cameraMode else { return }
                        if !isTouching {
                            isTouching = true
                            onTouchBegan?()
                        }
                        // 表示と同じ内側マージンで座標→値へ変換する(マージンの外を触ったら端の値に丸まる)。
                        let usableW = geo.size.width - pointerInset * 2
                        let usableH = geo.size.height - pointerInset * 2
                        let clampedX = min(max((value.location.x - pointerInset) / usableW, 0), 1)
                        let clampedY = min(max(1.0 - (value.location.y - pointerInset) / usableH, 0), 1)
                        x = clampedX
                        y = clampedY
                        onDrag?(clampedX, clampedY)
                    }
                    .onEnded { _ in
                        isTouching = false
                        onTouchEnded?()
                    }
            )
        }
        .frame(height: padHeight)
    }
}


/// XYパッドの、ポインター以外の全部。ポインターの座標を受け取らないので、
/// ドラッグで値が動いてもこのbodyは再評価されない。
/// (影を2枚重ねているので、毎フレーム作り直すとメインスレッドに効いてくる)
private struct PadSurface: View {
    let cameraMode: Bool
    let mosaic: [[Double]]?
    let edgeGlow: Double
    let quadrantTopLeft: Color
    let quadrantTopRight: Color
    let quadrantBottomLeft: Color
    let quadrantBottomRight: Color
    let cornerRadii: RectangleCornerRadii

    private var padShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // HUD: pale face, dot grid, one grey rule, black corner marks, ticks and a small centre cross
                padShape
                    .fill(PastelTheme.padScreen)
                    .overlay {
                        if cameraMode, let mosaic {
                            MosaicGridView(brightness: mosaic)
                                .clipShape(padShape)
                        } else {
                            HudDots(step: 12)
                        }
                    }
                    .overlay(padShape.strokeBorder(PastelTheme.hudLine, lineWidth: 1))
                HudCorners(arm: 8)
                    .stroke(PastelTheme.hudBlack, lineWidth: cameraMode ? 1.2 + CGFloat(edgeGlow) * 1.5 : 1.2)
                    .padding(3)

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Rectangle().fill(quadrantTopLeft)
                        Rectangle().fill(quadrantTopRight)
                    }
                    HStack(spacing: 0) {
                        Rectangle().fill(quadrantBottomLeft)
                        Rectangle().fill(quadrantBottomRight)
                    }
                }
                .clipShape(padShape)

                Path { path in
                    let w = geo.size.width, h = geo.size.height
                    let cx = w / 2, cy = h / 2
                    path.move(to: CGPoint(x: cx - 5, y: cy)); path.addLine(to: CGPoint(x: cx + 5, y: cy))
                    path.move(to: CGPoint(x: cx, y: cy - 5)); path.addLine(to: CGPoint(x: cx, y: cy + 5))
                    for k in 1...3 {                              // ruler ticks along the bottom and the left edge
                        let fx = w * CGFloat(k) / 4, fy = h * CGFloat(k) / 4
                        path.move(to: CGPoint(x: fx, y: h)); path.addLine(to: CGPoint(x: fx, y: h - (k == 2 ? 6 : 3)))
                        path.move(to: CGPoint(x: 0, y: fy)); path.addLine(to: CGPoint(x: k == 2 ? 6 : 3, y: fy))
                    }
                }
                .stroke(cameraMode ? PastelTheme.paperTone.opacity(0.8) : PastelTheme.hudBlack.opacity(0.55), lineWidth: 0.8)
            }
        }
    }
}

/// パッドの縁。ポインターに近いところほど黒い（Sæternesdæg と同じ）
private struct PadEdgeGlow: View {
    let glow: Double
    let x: Double
    let y: Double
    let cornerRadii: RectangleCornerRadii

    private static let segments = 20

    /// 縁を 20 に切った線とその中点。大きさが変わったときだけ作り直す
    /// （trimmedPath は重いので、描き直しのたびには呼ばない）
    private final class SegmentCache {
        var size: CGSize = .zero
        var radii: RectangleCornerRadii? = nil
        var segments: [(path: Path, mid: CGPoint)] = []
    }
    @State private var cache = SegmentCache()

    private func segments(for size: CGSize) -> [(path: Path, mid: CGPoint)] {
        if cache.size == size, cache.radii == cornerRadii { return cache.segments }
        let shape = UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
        let path = shape.path(in: CGRect(origin: .zero, size: size))
        let n = Self.segments
        var out: [(path: Path, mid: CGPoint)] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let from = Double(i) / Double(n)
            let to = min(Double(i + 1) / Double(n) + 0.004, 1.0)
            let segment = path.trimmedPath(from: from, to: to)
            let box = segment.boundingRect
            guard box.width.isFinite, box.height.isFinite else { continue }
            out.append((path: segment, mid: CGPoint(x: box.midX, y: box.midY)))
        }
        cache.size = size
        cache.radii = cornerRadii
        cache.segments = out
        return out
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let px = x * size.width
            let py = (1.0 - y) * size.height
            let reach = max(max(size.width, size.height) * 0.9, 1.0)
            for seg in segments(for: size) {
                let mid = seg.mid
                let alpha = glow * Self.falloff(hypot(mid.x - px, mid.y - py) / reach)
                guard alpha > 0.01 else { continue }
                context.stroke(seg.path, with: .color(PastelTheme.textPrimary.opacity(alpha)), lineWidth: 3)
            }
        }
        .allowsHitTesting(false)
    }

    private static func falloff(_ d: Double) -> Double {
        let t = min(max(d, 0.0), 1.0)
        if t < 0.5 { return 0.9 + (0.30 - 0.9) * (t / 0.5) }
        return 0.30 + (0.06 - 0.30) * ((t - 0.5) / 0.5)
    }
}

