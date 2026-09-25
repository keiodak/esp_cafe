import SwiftUI

/// 細身でダーク基調のミニマルなスライダー。トラックは細い線、タップ判定は指で操作しやすい高さを確保。
struct CompactSlider: View {
    @Binding var value: Double // 0...1
    var trackThickness: CGFloat = 4
    /// つまみは卓のフェーダーと同じ「棒」。線を横切る向きに置くので、
    /// 溝に沿う側(knobSize)が薄く、横切る側(knobLength)が長い。
    var knobSize: CGFloat = 6
    var knobLength: CGFloat = 13
    var touchHeight: CGFloat = 22 // ドラッグの当たり判定用(見た目には出ない)
    var fillColor: Color = PastelTheme.pink
    /// つまみ(ノブ)の色。nilならfillColorと同じ色を使う。
    var knobColor: Color? = nil
    /// falseの間はドラッグを受け付けない(値が外部から自動で決まっている場合に使用)。
    var interactionEnabled: Bool = true
    /// trueだと、fillColorの光が照明のように後ろへボワっとにじみ出る(FREQ/Qスライダーなど用)。
    var ambientGlow: Bool = false
    /// trueだと溝と塗りバーをやめて、十字のスライダーと同じ点線で描く。
    /// 点いている側の粒はfillColor、消えている側は目盛りと同じ色。
    var dotted: Bool = false
    /// trueだと枠と同じ太さの細い線 1 本。塗りは墨、残りは薄い墨。先端は小さな丸。
    var thinLine: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fillWidth = min(max(knobSize / 2, w * CGFloat(value)), w)

            ZStack(alignment: .leading) {
                if ambientGlow {
                    // つまみの位置を中心に、fillColorの光が背景ににじみ出るような
                    // ぼんやりしたグローを敷く(値が動くと光の位置も一緒に動く)。
                    Ellipse()
                        .fill(fillColor.opacity(0.5))
                        .frame(width: touchHeight * 3.2, height: touchHeight * 2.2)
                        .blur(radius: touchHeight * 0.7)
                        .offset(x: fillWidth - touchHeight * 1.6)
                }

                if thinLine {
                    // 古い活版の線。版が減っているぶん、太さと墨がわずかに揺れる
                    InkLine(color: PastelTheme.textPrimary.opacity(0.28))
                    InkLine()
                        .frame(width: fillWidth, alignment: .leading)
                        .clipped()
                } else if dotted {
                    // 十字のスライダーと同じ作り。粒の間隔も同じ約12ptで揃える。
                    let count = max(5, Int(w / 12))
                    HStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { index in
                            Circle()
                                .fill(Double(index) + 0.5 <= Double(count) * value
                                      ? fillColor
                                      : fillColor.opacity(PastelTheme.tickOffOpacity))
                                .frame(width: 3, height: 3)
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    // 溝は掘らない。面より一段だけ暗い平らな帯にヘアラインだけ。
                    Capsule()
                        .fill(PastelTheme.chipWell)
                        .overlay(Capsule().strokeBorder(PastelTheme.textPrimary.opacity(0.35), lineWidth: 1))
                        .frame(height: trackThickness)

                    Capsule()
                        .fill(PastelTheme.slideInk)
                        .frame(width: fillWidth, height: trackThickness)
                }

                // つまみ。卓の VOL フェーダーと同じ棒に揃えてある ——
                // 面から浮いた明るいキャップが、線をひとつ横切っている形。
                // 点線モード(メイン画面)だけは影を落とさない。
                if thinLine {
                    Circle()
                        .fill(knobColor ?? PastelTheme.textPrimary)
                        .frame(width: 7, height: 7)
                        .offset(x: min(max(0, fillWidth - 3.5), w - 7))
                } else {
                    Capsule()
                        .fill(knobColor ?? PastelTheme.knobLight)
                        .frame(width: knobSize, height: knobLength)
                        .offset(x: min(max(0, fillWidth - knobSize / 2), w - knobSize))
                }
            }
            .frame(height: touchHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard interactionEnabled else { return }
                        value = min(max(v.location.x / w, 0), 1)
                    }
            )
        }
        .frame(height: touchHeight)
    }
}

/// 活版で刷った1本の線。線そのものはまっすぐで太さもほぼ一定 ――
/// 変わるのは墨の乗りだけ。版が当たり切らないところがときどき薄く抜ける。
/// 揺れは固定の並び（乱数は使わない）。
struct InkLine: View {
    var color: Color = PastelTheme.textPrimary
    var thickness: CGFloat = 1.4

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            let w = max(size.width, 1)
            let y0 = (size.height * 0.5).rounded() + 0.5
            // 下地。まっすぐ引いた1本
            ctx.fill(Path(CGRect(x: 0, y: y0 - thickness * 0.5, width: w, height: thickness)),
                     with: .color(color.opacity(0.86)))
            // 墨の乗り。細かく区切って、濃いところと薄いところを重ねる
            let seg: CGFloat = 2
            var x: CGFloat = 0
            while x < w {
                let x2 = min(x + seg, w)
                let t = Double(x) * 0.07
                let d = Foundation.sin(t) * 0.5 + Foundation.sin(t * 2.3 + 1.7) * 0.3
                    + Foundation.sin(t * 5.1 + 0.6) * 0.2
                // ほとんどは濃いまま。たまに版が当たらず薄く抜ける
                let a = d > 0.72 ? 0.0 : (d < -0.55 ? 0.34 : 0.14)
                if a > 0.001 {
                    ctx.fill(Path(CGRect(x: x, y: y0 - thickness * 0.5, width: x2 - x + 0.3, height: thickness)),
                             with: .color(color.opacity(a)))
                }
                x = x2
            }
            // 縁のざらつき。上下に極く薄い髭を散らす
            var edge = Path()
            var e: CGFloat = 0
            while e < w {
                let t = Double(e) * 0.31
                let up = Foundation.sin(t * 1.9 + 0.3) > 0.62
                let dn = Foundation.sin(t * 1.3 + 2.4) > 0.66
                if up { edge.addRect(CGRect(x: e, y: y0 - thickness * 0.5 - 0.4, width: 1.1, height: 0.4)) }
                if dn { edge.addRect(CGRect(x: e, y: y0 + thickness * 0.5, width: 1.1, height: 0.4)) }
                e += 1.6
            }
            ctx.fill(edge, with: .color(color.opacity(0.5)))
        }
        .frame(height: 4)
        .allowsHitTesting(false)
    }
}

/// 小さめのピル型トグルスイッチ。標準Toggleより一回り小さくシンプル。
/// ニューモーフィズム: トラックはくぼんだ溝、ノブは面から浮き出た円。
struct CompactToggle: View {
    @Binding var isOn: Bool
    var width: CGFloat = 34
    var height: CGFloat = 18
    var onColor: Color = PastelTheme.pink

    var body: some View {
        // 溝は平らな帯。つまみだけを白く浮かせる。
        Capsule()
            .fill(PastelTheme.chipWell)
            .overlay(Capsule().strokeBorder(PastelTheme.textPrimary.opacity(0.35), lineWidth: 1))
            .frame(width: width, height: height)
            .overlay(
                Circle()
                    .fill(PastelTheme.neumorphSurface)
                    .frame(width: height - 5, height: height - 5)
                    .overlay(
                        Circle()
                            .fill(isOn ? onColor : PastelTheme.trackOff)
                            .frame(width: height - 9, height: height - 9)
                    )

                    .offset(x: isOn ? width / 2 - height / 2 + 1 : -(width / 2 - height / 2 - 1))
            )
            .onTapGesture { isOn.toggle() }
            .animation(.easeInOut(duration: 0.12), value: isOn)
    }
}

/// 参考画像風の「ぷっくりしたガラスボタン」の円形背景。
/// 上が明るい面グラデーション+上縁の白いリムライト+下縁のうっすら暗い輪郭+柔らかい落ち影。
struct GlossyCircleBackground: View {
    /// trueだと影を少し強めて、行のアイコンをはっきり浮かせる。
    var strong: Bool = false

    var body: some View {
        Circle()
            .fill(PastelTheme.iconButtonBackground)
            .overlay(Circle().strokeBorder(PastelTheme.textPrimary.opacity(strong ? 0.55 : 0.4),
                                           lineWidth: 1))
    }
}

/// 縦のミニマルなスライダー。EQのバンドを8本並べるために使う。
/// 中央が0dBになるので、塗りは「中央からつまみまで」を埋める。
struct VerticalSlider: View {
    @Binding var value: Double // 0...1
    var trackThickness: CGFloat = 4
    /// 卓のフェーダーと同じ棒。溝に沿う側が薄く、横切る側が長い。
    var knobSize: CGFloat = 6
    var knobLength: CGFloat = 13
    var touchWidth: CGFloat = 20
    var fillColor: Color = PastelTheme.pink
    var knobColor: Color? = nil
    /// 中央からの塗りにする(EQのように0が中央のとき)。falseなら下から塗る。
    var centered: Bool = true

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let inset = knobSize / 2
            let usable = max(1, h - inset * 2)
            // 上が1、下が0。
            let knobY = inset + usable * CGFloat(1.0 - min(max(value, 0), 1))
            let midY = inset + usable * 0.5

            ZStack {
                Capsule()
                    .fill(PastelTheme.chipWell)
                    .overlay(Capsule().strokeBorder(PastelTheme.textPrimary.opacity(0.35), lineWidth: 1))
                    .frame(width: trackThickness)

                // 塗り。centeredなら中央からつまみまで。
                Capsule()
                    .fill(PastelTheme.slideInk)
                    .frame(width: trackThickness,
                           height: centered ? abs(knobY - midY) : (h - knobY))
                    .position(x: geo.size.width / 2,
                              y: centered ? (knobY + midY) / 2 : (knobY + h) / 2)

                Capsule()
                    .fill(knobColor ?? PastelTheme.knobLight)
                    .frame(width: knobLength, height: knobSize)

                    .position(x: geo.size.width / 2, y: knobY)
            }
            .frame(width: geo.size.width, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = 1.0 - Double((g.location.y - inset) / usable)
                        value = min(max(v, 0), 1)
                    }
            )
        }
        .frame(minWidth: touchWidth)
    }
}

/// つまみが2つ乗る溝。素材の「ここから」「ここまで」を1本で決める。
/// 近いほうのつまみを掴む。0…1がそのまま素材の頭と尻に当たるので、
/// どれだけ長いファイルでも端から端まで届く。
struct RangeSlider: View {
    @Binding var low: Double
    @Binding var high: Double
    var trackThickness: CGFloat = 4
    var knobSize: CGFloat = 6
    var knobLength: CGFloat = 13
    var touchHeight: CGFloat = 22
    var fillColor: Color = PastelTheme.knobLight
    var knobColor: Color = PastelTheme.knobLight
    /// 目盛りの点を敷くか（メイン画面の他のスライダーと揃える）。
    var dotted: Bool = true
    /// 2つのつまみが重ならない最小の間。
    private let minGap: Double = 0.01

    @State private var dragging: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let inset = knobSize / 2
            let usable = max(1, w - knobSize)
            let a = min(low, high)
            let b = max(low, high)
            let xa = inset + CGFloat(a) * usable
            let xb = inset + CGFloat(b) * usable

            ZStack(alignment: .leading) {
                if dotted {
                    let count = max(5, Int(w / 12))
                    HStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { index in
                            let t = (Double(index) + 0.5) / Double(count)
                            Circle()
                                .fill(t >= a && t <= b
                                      ? fillColor
                                      : fillColor.opacity(PastelTheme.tickOffOpacity))
                                .frame(width: 3, height: 3)
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    Capsule()
                        .fill(PastelTheme.chipWell)
                        .frame(height: trackThickness)
                    Capsule()
                        .fill(PastelTheme.slideInk)
                        .frame(width: max(0, xb - xa), height: trackThickness)
                        .offset(x: xa)
                }

                // ここから
                Capsule()
                    .fill(knobColor)
                    .frame(width: knobSize, height: knobLength)
                    .offset(x: xa - knobSize / 2)
                // ここまで
                Capsule()
                    .fill(knobColor)
                    .frame(width: knobSize, height: knobLength)
                    .offset(x: xb - knobSize / 2)
            }
            .frame(height: touchHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = min(max(Double((g.location.x - inset) / usable), 0), 1)
                        // 最初に触った時だけ、近いほうのつまみを選ぶ。
                        if dragging == nil {
                            dragging = abs(v - a) <= abs(v - b) ? 0 : 1
                        }
                        if dragging == 0 {
                            low = min(v, high - minGap)
                        } else {
                            high = max(v, low + minGap)
                        }
                    }
                    .onEnded { _ in dragging = nil }
            )
        }
        .frame(height: touchHeight)
    }
}
