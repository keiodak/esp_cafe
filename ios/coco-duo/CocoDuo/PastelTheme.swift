import SwiftUI

/// アプリ全体で使うほぼ無彩色のパレット。
/// 濃いチャコールの地に、温かいオフホワイトの面を置く。文字はほぼ黒、線は薄いグレー。
/// オレンジはアクセント。中央の月と、パネル内の選択中のチップにだけ使う。
/// 面と地の明度が離れたので、ニューモーフィズムの両側影はやめて落ち影だけにしてある。
/// 面は「浮き出る」ニューモーフィズム、トーンはニュートラルなグレー。
enum PastelTheme {
    // MARK: - ニューモーフィズム(柔らかい影で凹凸を表現するスタイル)基本カラー
    /// 画面全体の背景。ニューモーフィズムの土台になるニュートラルグレー。
    static let screenBackground = Color(hex: 0x1D3E63)

    /// カード・ボタンなど「面」の背景色。背景よりわずかに明るくして浮き出て見せる。
    static let neumorphSurface = Color(hex: 0x1D3E63)

    /// 面の上ふち側。ごくわずかに明るくして、板ではなく緩いドームに見せる。
    static let neumorphSurfaceHigh = Color(hex: 0x24497A)

    /// チップの形。角丸の四角で共通化しておくと、当たり判定(contentShape)も
    /// 同じものを渡せて、見た目と押せる範囲がずれない。
    static let chipShape = RoundedRectangle(cornerRadius: 7, style: .continuous)
    /// 紙の色。モザイクの上に引く罫用
    static let paperTone = Color(hex: 0x1D3E63)
    /// 明るさ 0…1 を、墨（0）から紙（1）までの色にする。カメラのモザイク用
    static func inkTone(_ v: Double) -> Color {
        let t = min(max(v, 0), 1)
        let ink = (0x2B / 255.0, 0x26 / 255.0, 0x21 / 255.0)
        let paper = (0xE6 / 255.0, 0xDE / 255.0, 0xC8 / 255.0)
        return Color(red: ink.0 + (paper.0 - ink.0) * t,
                     green: ink.1 + (paper.1 - ink.1) * t,
                     blue: ink.2 + (paper.2 - ink.2) * t)
    }

    /// パネルの中のボタン(チップ)の、押されていないときのくぼみの地。
    /// 面より一段沈めた色。この上に選択色を載せても凹みの陰影は残す。
    static let chipWell = Color(hex: 0x1D3E63)

    /// ニューモーフィズムの明るい側の影(左上)。黄色はほとんど残していない。
    static let neumorphShadowLight = Color(hex: 0x1D3E63)

    /// ニューモーフィズムの暗い側の影(右下)。
    static let neumorphShadowDark = Color(hex: 0xEAF0F4)

    /// XYパッドのスクリーン地色。4パッドとも同じトーンで、面から浮き出させる。
    static let padScreen = Color(hex: 0x1D3E63)      // パッドはパネルと同じ色

    /// 月(ドローン)がONのときのスクリーン地色。一段落として、月あかりの下の面にする。
    static let padScreenMoon = Color(hex: 0x173353)

    /// 凹んだ溝の「明るい側」。面より明るい=ほぼ白でないと凹んで見えない。
    static let padGrooveLight = Color(hex: 0x1D3E63)

    /// 地より明るいので、浮き出た面の左上のふちに置く「月あかりの縁」。
    static let neumorphRimLight = Color(hex: 0x1D3E63)

    /// パッド内のグリッド線
    static let gridLine = Color(hex: 0xEAF0F4).opacity(0.25)

    /// スライダーの線。掠れた黒(単色ではなく、下のグラデーションで濃淡を付ける)。
    static let sliderFill = Color(hex: 0xEAF0F4)

    /// 選択状態やアクティブを立てるときだけ使う明るいブルー。
    static let highlight = Color(hex: 0xEAF0F4)

    /// スライダーの線。一色だと帯に見えるので、濃淡をわずかに流す。
    static var slideInk: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xEAF0F4), Color(hex: 0xEAF0F4)],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// 目盛り(XYパッドの十字・スライダーのドット)と、スライダーのつまみに使う一色。
    /// 「測るもの」と「指すもの」を同じ色で揃える。
    static let tickColor = Color(hex: 0xEAF0F4).opacity(0.55)

    /// XYパッドのポインターだけは少し白い側に置く(4枚のパッドで一番見たいものなので)。
    static let padPointer = Color(hex: 0xEAF0F4)

    /// スライダーのつまみ。目盛りの薄いグレーではなく、線と同じ「黒い方」に合わせる。
    static let knobColor = Color(hex: 0xEAF0F4)

    /// メイン画面のスライダーのつまみと目盛りに使う白。面(#EDE9DF)より一段明るくして、
    /// 明るいパッドの上でも濃い地の上でも同じように見えるようにする。
    /// 値の外側の目盛りは、この色を薄く落として描く(sunnandægと同じ考え方)。
    static let knobLight = Color(hex: 0xEAF0F4)
    /// 目盛りのうち、まだ届いていない側の薄さ。地に沈むくらいまで落とす。
    static let tickOffOpacity: Double = 0.20

    /// 旧名。tickColorと同じ。
    static var pointerGray: Color { tickColor }

    /// メインアクセント — 未指定時のフォールバック用
    // MARK: - コントロールごとの識別色(モノトーンなので明度差で区別する)

    // ON状態・強調用のモノトーン(濃さの違いだけで区別する)。
    // OFFのアイコンがほぼ白なので、ONは濃いグレーではっきり分かれる。
    static let pink = Color(hex: 0xEAF0F4)
    static let peach = Color(hex: 0xEAF0F4)
    static let lavender = Color(hex: 0xEAF0F4)
    static let aqua = Color(hex: 0xEAF0F4)
    static let skyBlue = Color(hex: 0xEAF0F4)
    static let yellow = Color(hex: 0xEAF0F4)
    static let violet = Color(hex: 0xEAF0F4)
    static let rose = Color(hex: 0xEAF0F4)
    static let teal = Color(hex: 0xEAF0F4)
    static let indigo = Color(hex: 0xEAF0F4)

    /// 選択中のチップ・スイッチの塗り。アクセントのオレンジ。
    /// 上に載る文字は白より黒のほうが小さい字で読めるので textPrimary を使う。
    static let selection = Color(hex: 0xEAF0F4)

    /// 変調先を反転(-X / -Y / -Z)で挿したときの塗り。
    /// オレンジと並んでも一目で違うと分かるよう、明度と彩度はそのままに
    /// 色相だけ黄へ寄せた濃い黄色。文字はオレンジのときと同じ textPrimary。
    static let selectionInverted = Color(hex: 0x98B3CC)

    // MARK: - XYパッド4象限用パレット
    // 1枚のパッドの中を、ごく薄いトーン差だけで4分割する。
    // 「線で区切られている」ではなく「よく見ると濃淡がある」程度に留める。
    static let monoQuadrant1 = Color.clear
    static let monoQuadrant2 = Color.clear
    static let monoQuadrant3 = Color.clear
    static let monoQuadrant4 = Color.clear

    /// ジェスチャー再生中などの状態色
    static let mint = Color(hex: 0xEAF0F4)

    /// 音の詰まり具合を示す3色。ここだけは色そのものが意味なので、
    /// 単色のパレットから外して素の緑・黄・赤を使う(彩度は少し落としてある)。
    static let meterGreen = Color(hex: 0xEAF0F4).opacity(0.45)
    static let meterYellow = Color(hex: 0xEAF0F4).opacity(0.7)
    static let meterRed = Color(hex: 0xEAF0F4)

    /// 録音中などの状態色(最も濃く出す)
    static let coral = Color(hex: 0xEAF0F4)

    /// スライダー/スイッチのOFF・未塗り部分
    static let trackOff = Color(hex: 0xEAF0F4).opacity(0.18)

    /// 小さいボタンの背景(ニューモーフィズムの面と同じ色に統一)
    static let buttonBackground = neumorphSurface

    /// パッドの中のボタンの地。参考図と同じで、面とまったく同じ色にする。
    /// 形は影だけで出す(色で差を付けるとニューモーフィズムに見えない)。
    static let padButtonFace = padScreen

    /// パッド内ボタンの影の暗い側。参考図の #AEAEC0 にあたる、ベージュ寄りの中間グレー。
    /// 真っ黒だと硬くなるので、彩度を面に寄せてある。
    static let padButtonShade = Color(hex: 0xEAF0F4)
    /// 同じく明るい側。ほぼ白。
    static let padButtonLight = Color(hex: 0x1D3E63)

    /// 穴の底。面より一段暗い。内側の影だけだと「くぼみ」が弱いので、
    /// 面そのものに左上→右下の傾斜を付けて、穴の底が沈んで見えるようにする。
    static let padButtonHollow = Color(hex: 0x1D3E63)
    /// 穴の底の明るい側(右下)。面よりわずかに明るい。
    static let padButtonHollowLit = Color(hex: 0x1D3E63)

    /// パッド内の図柄。白地の上なのでグレー(=選ばれていない状態)。
    static let padIconOn = Color(hex: 0xEAF0F4).opacity(0.45)
    /// 選ばれている(入っている)ときはオレンジ。パネルのタイトルと同じ色。
    static let padIconActive = indigo
    /// 旧名。いまは padIconActive を使う。
    static var padIconOff: Color { padIconActive }

    /// 旧名。padIconOn と同じ扱い。
    static var padIconColor: Color { padIconOn }

    /// 丸ボタンのアイコンの色。マニュアルもMODもドローンも全部この一色で固定。
    /// オレンジ(indigo)に変わるのは中央の月だけ。
    static let iconColor = Color(hex: 0xEAF0F4).opacity(0.55)

    /// ボタンの背景円の色。ほぼ白。
    static let iconButtonBackground = Color(hex: 0x1D3E63)

    /// 補助テキスト用。目盛り/ポインターより気持ち濃いところに置く。
    static let textSecondary = Color(hex: 0x98B3CC)

    /// 見出しなど。
    static let textPrimary = Color(hex: 0xEAF0F4)

    /// 録りに行っているあいだだけ使う色。全体が線画の一色なので、
    /// 「いま入力を開けている」ことだけはひと目で分かるようにする。
    static let recording = Color(hex: 0xF2A65A)

    /// 選択中のチップの上に載る文字。塗りが黒なので白で抜く。
    static let selectionText = Color(hex: 0x1D3E63)
}

extension PastelTheme {
    /// 画面の地。濃いグレーの上に、ごく薄い明暗の筋を斜めに重ねて掠れを出す。
    /// 単色のべた塗りだとニューモーフィズムの面が浮いて見えないので、
    /// 面より少しだけざらつかせておく。
    /// 掠れの明るい筋も、白ではなく月の灯り寄りにする。
    static let moonlight = Color(hex: 0x24497A)

    /// パネルとメイン画面の地。単色。光もグラデーションも置かない。
    static var panelBackdrop: some View { screenBackground }

    /// メイン画面の地。パネルと同じ。
    static var screenBackdrop: some View { panelBackdrop }

}

/// EQのフェーダーと、SEQの階段で共有する寸法。
/// 8本を横に並べる形が同じなので、幅・丈・間隔・上下に添える文字の大きさまで
/// 両方ここから引く。左右の列に並べたとき、柱とフェーダーが同じ位置・同じ寸法で
/// 揃って見えるのはこのため(他のつまみやチップはそれぞれの列の幅で普通に並ぶ)。
enum PanelMetrics {
    static let faderWidth: CGFloat = 18
    /// 段の見出し行(EQ / STEPS)を無くしたぶん、その高さだけ伸ばしてある。
    static let faderHeight: CGFloat = 84
    static let faderSpacing: CGFloat = 5
    static let bandCount = 8
    /// 8本の上下に添える文字。上が値、下が名前。
    static let capFont: CGFloat = 8
    static let footFont: CGFloat = 7
    /// 文字と本体のあいだ。
    static let capSpacing: CGFloat = 2

    /// カードの見出しと、段の見出し(EQ / STEPS)の行の高さ。
    /// スイッチが乗る行と乗らない行で高さが変わると、その差だけ
    /// 左右の列で中身の始まる位置がずれる。両方これで固定する。
    static let headerHeight: CGFloat = 15

    // MARK: - 行の組み方
    //
    // 「ラベル / スライダー / 数値」の3点セットは全パネルで同じ幅に揃える。
    // 揃えておくと、パネルをまたいでもスライダーの左端と右端が同じ位置に来る。
    // パネルごとに 38 だったり 40 だったりすると、並べたとき一列ぶんずれて見える。

    /// 行の左端に置くラベルの幅(FREQ / PITCH / VCA cv など)。
    /// OUTPUT パネルが 40、DRONE だけ 38 だったので 40 に合わせた。
    static let labelWidth: CGFloat = 40
    /// 行の右端に置く数値の幅。等幅で桁が揺れないようにしてある。
    static let valueWidth: CGFloat = 26
    /// 1行が横2つに割れるとき(DualFaderRow)のラベル幅。
    static let halfLabelWidth: CGFloat = 34
    static let halfValueWidth: CGFloat = 24
    /// ラベル・スライダー・数値のあいだ。
    static let rowGap: CGFloat = 5
    /// 行と行のあいだ。
    static let rowSpacing: CGFloat = 5
    /// ラベルの文字と数値の文字。
    static let labelFont: CGFloat = 9
    static let valueFont: CGFloat = 8

    /// 選択チップの高さ・文字・間隔。
    static let chipHeight: CGFloat = 14
    static let chipFont: CGFloat = 7.5
    static let chipSpacing: CGFloat = 3
}

extension Color {
    /// 0xRRGGBB形式の16進数からColorを作る。
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

/// パネルの中のボタン(チップ)の地。
/// 一度くぼませてみたが、14ptの高さに内影を入れても窪んで見えず
/// (見えるまで濃くすると今度は汚れに見える)、素の平らな塗りへ戻した。
/// 形だけ角丸の四角にしてある——カプセルは左右の丸みが文字の両端を食うので、
/// 同じ幅でも入る字数が減る。
extension View {
    /// 切ってあるとき。電気が落ちたように、少しだけ暗く沈める。
    ///
    /// 前は薄くしていた(不透明度を下げていた)が、地が明るいので
    /// 白へ抜けて「かすれた」ように見えていた。明度を落とすほうにすると、
    /// 同じ面のまま灯りだけが消えたように読める。
    func unlit(_ off: Bool) -> some View {
        self.brightness(off ? -0.16 : 0.0)
            .contrast(off ? 0.85 : 1.0)
    }
}

struct ChipBackground: View {
    /// 選択中の塗り。nil なら素の地。
    var fill: Color? = nil

    var body: some View {
        // 活版の札。紙に墨の罫、選ばれたら墨で刷る
        PastelTheme.chipShape
            .fill(fill ?? PastelTheme.chipWell)
            .overlay(
                PastelTheme.chipShape
                    .strokeBorder(PastelTheme.textPrimary.opacity(fill == nil ? 0.85 : 1.0),
                                  lineWidth: 0.9)
            )

    }
}

extension View {
    /// 面。地と同じ色を敷いて、輪郭は細い線1本だけ。
    /// 影もグラデーションも塗り分けも使わない —— 参考図と同じ、線で描く作り。
    func neumorphic(cornerRadius: CGFloat = 14, isPressed: Bool = false) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(PastelTheme.neumorphSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(PastelTheme.textPrimary.opacity(isPressed ? 0.85 : 0.5),
                                      lineWidth: 1)
                )
        )
    }

    /// 溝。こちらも線1本。
    func neumorphicInset(cornerRadius: CGFloat = 8) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(PastelTheme.chipWell)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(PastelTheme.textPrimary.opacity(0.4), lineWidth: 1)
                )
        )
    }
}
