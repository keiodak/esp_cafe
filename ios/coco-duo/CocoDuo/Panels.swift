import SwiftUI
import UniformTypeIdentifiers

// パネルの寸法は sunnandæg / Sæternesdæg に合わせてある。
// ルートspacing 10 / 見出し12semibold / Done 10medium /
// カードpadding 8・角丸10・見出し10medium / カード内spacing 7 / 行ラベル9medium

struct PanelCard<Content: View>: View {
    let title: String
    /// 見出しの右へ置く入り切り。持たせないカードは見出しだけ。
    var toggle: Binding<Bool>? = nil
    /// 見出しの右へ置く小さな文字（状態の表示など）。
    var note: String? = nil
    /// 見出しのすぐ隣に並べる小さな札（INIT / RANDOM など）。
    var headerChips: [(String, () -> Void)] = []
    /// 見出しのすぐ隣（札の右）に置く任意の部品。
    var headerView: AnyView? = nil
    /// 見出しの右端に置く任意の部品(長押しの釦など)。
    var trailing: AnyView? = nil
    /// 中身の行間。詰めたいカードだけ小さくする。
    var spacing: CGFloat = 7
    /// 二列に並べたとき、背の高いほうへ丈を合わせる。
    var fill: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 6) {
                // HUD title: a small orange block, then the name in orange with underscores
                Rectangle().fill(PastelTheme.hudOrange).frame(width: 5, height: 5)
                Text(title.replacingOccurrences(of: " · ", with: "_").replacingOccurrences(of: " ", with: "_"))
                    .font(.hud(11, .semibold))
                    .tracking(1.0)
                    .foregroundStyle(PastelTheme.hudOrange)
                ForEach(Array(headerChips.enumerated()), id: \.offset) { _, chip in
                    Text(chip.0)
                        .font(.hud(8, .medium))
                        .foregroundStyle(PastelTheme.textPrimary)
                        .padding(.horizontal, 6)
                        .frame(height: 14)
                        .background(ChipBackground(fill: nil))
                        .contentShape(PastelTheme.chipShape)
                        .onTapGesture { chip.1() }
                }
                if let headerView { headerView }
                Spacer(minLength: 0)
                if let note {
                    Text(note)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(PastelTheme.textSecondary)
                }
                if let trailing { trailing }
                if let toggle {
                    MiniSwitch(isOn: toggle)
                }
            }
            .frame(height: PanelMetrics.headerHeight)
            content
        }
        .padding(8)
        .frame(maxWidth: .infinity,
               maxHeight: fill ? .infinity : nil, alignment: .topLeading)
        .background(LetterpressFrame())
    }
}

/// the card frame, HUD style: a pale face, one thin grey rule, black corner marks
struct LetterpressFrame: View {
    var cornerRadius: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle().fill(PastelTheme.padScreen)
            Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
            HudCorners(arm: 6).stroke(PastelTheme.hudBlack, lineWidth: 1.2)
        }
    }
}

struct PanelRow: View {
    let label: String
    @Binding var value: Double
    var format: (Double) -> String = { String(format: "%.2f", $0) }
    /// 行の丈。詰めたいカードだけ小さくする
    var height: CGFloat = 22

    init(label: String, value: Binding<Double>, height: CGFloat = 22,
         format: @escaping (Double) -> String = { String(format: "%.2f", $0) }) {
        self.label = label
        self._value = value
        self.height = height
        self.format = format
    }

    var body: some View {
        HStack(spacing: PanelMetrics.rowGap) {
            Text(label)
                .font(.hud(PanelMetrics.labelFont, .medium))
                .foregroundStyle(PastelTheme.textPrimary)
                .frame(width: PanelMetrics.labelWidth, alignment: .leading)
            CompactSlider(value: $value,
                          touchHeight: height,
                          fillColor: PastelTheme.sliderFill,
                          knobColor: PastelTheme.knobColor)
            // 数字は出さない（このアプリの決まり）。format は他の卓との互換のため残す
        }
    }
}

struct ChipOption<T: Hashable>: Identifiable {
    let value: T
    let label: String
    var id: T { value }
}

struct PanelChips<T: Hashable>: View {
    let options: [ChipOption<T>]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: PanelMetrics.chipSpacing) {
            ForEach(options) { opt in
                let on = selection == opt.value
                Text(opt.label)
                    .font(.hud(PanelMetrics.chipFont, .medium))
                    .foregroundStyle(on ? PastelTheme.selectionText : PastelTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: PanelMetrics.chipHeight)
                    .background(ChipBackground(fill: on ? PastelTheme.selection : nil))
                    .contentShape(PastelTheme.chipShape)
                    .onTapGesture { selection = opt.value }
            }
        }
    }
}

struct PanelScaffold<Content: View>: View {
    let title: String
    /// 中身を画面の丈ぴったりに広げる。カードが下まで届く。
    var stretch: Bool = false
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Cafe BLE")
                        .font(.hudBig(16))
                        .foregroundStyle(PastelTheme.hudBlack)
                    HudTag(text: title.replacingOccurrences(of: " ", with: "_"), size: 11)
                    Rectangle().fill(PastelTheme.hudLine).frame(height: 1)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.hud(10, .medium))
                        .foregroundStyle(PastelTheme.textPrimary)
                }
                content
            }
            .padding(10)
            // 丈をきっちり画面ぶんにする。minHeight では「下限」を置くだけで
            // 中身への提案が決まらず、カードが伸びない ―― ここは実寸で渡す。
            .modifier(StretchToContainer(on: stretch))
        }
        .background(PastelTheme.panelBackdrop.ignoresSafeArea())
    }
}

/// 入れると、中身をスクロールの見えている丈ぴったりに広げる。
private struct StretchToContainer: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content.containerRelativeFrame(.vertical, alignment: .top)
        } else {
            content
        }
    }
}

// MARK: - 小さな部品

/// 見出しの右に置く入り切り。線と塗りだけ。
struct MiniSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? PastelTheme.selection : PastelTheme.chipWell)
            .overlay(Capsule().strokeBorder(PastelTheme.textPrimary.opacity(0.45), lineWidth: 1))
            .frame(width: 26, height: 13)
            .overlay(
                Circle()
                    .fill(isOn ? PastelTheme.selectionText : PastelTheme.textPrimary)
                    .frame(width: 7, height: 7)
                    .offset(x: isOn ? 6 : -6)
            )
            .contentShape(Capsule())
            .onTapGesture { isOn.toggle() }
            .animation(.easeInOut(duration: 0.12), value: isOn)
    }
}

/// 名前と値だけの行。
struct DiagRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack(spacing: PanelMetrics.rowGap) {
            Text(label)
                .font(.hud(PanelMetrics.labelFont, .medium))
                .foregroundStyle(PastelTheme.textPrimary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                .foregroundStyle(PastelTheme.textSecondary)
            Spacer(minLength: 0)
        }
    }
}

/// パネルの中の押しボタン。選ばれていると地色で抜く。
struct ChipButton: View {
    let title: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.hud(PanelMetrics.chipFont, .medium))
            .foregroundStyle(filled ? PastelTheme.selectionText : PastelTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: PanelMetrics.chipHeight)
            .background(ChipBackground(fill: filled ? PastelTheme.selection : nil))
            .contentShape(PastelTheme.chipShape)
            .onTapGesture { action() }
    }
}

/// 出力の目盛り。輪郭線＋中の塗り。
struct MeterBar: View {
    let label: String
    let value: Double
    /// 狭いところ用。ラベルを詰めて数字を出さない(2本を横に並べるとき)。
    var compact: Bool = false

    var body: some View {
        HStack(spacing: PanelMetrics.rowGap) {
            Text(label)
                .font(.hud(PanelMetrics.labelFont, .medium))
                .foregroundStyle(PastelTheme.textPrimary)
                .frame(width: compact ? 22 : PanelMetrics.labelWidth, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                let v = CGFloat(min(max(value, 0), 1))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(PastelTheme.textPrimary.opacity(0.4), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(value > 0.95 ? PastelTheme.meterRed
                              : (value > 0.7 ? PastelTheme.meterYellow : PastelTheme.meterGreen))
                        .frame(width: max(0, (w - 2) * v))
                        .padding(1)
                }
            }
            .frame(height: 8)
            if !compact {
                Text(String(format: "%.2f", value))
                    .font(.system(size: PanelMetrics.valueFont, design: .monospaced))
                    .foregroundStyle(PastelTheme.textSecondary)
                    .frame(width: PanelMetrics.valueWidth, alignment: .trailing)
            }
        }
    }
}

/// 左右2列。sunnandæg と同じで、上端を揃えて並べる。
/// 二列に並べたとき、背の高いほうへ丈を揃えるための物差し。
private struct ColumnHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PanelColumns<L: View, R: View>: View {
    /// 左右の丈を揃えるかどうか。揃えると、短いほうのカードが
    /// 背の高いほうまで伸びて、二列が同じ高さの箱に見える。
    var equalHeight: Bool = false
    @ViewBuilder var left: L
    @ViewBuilder var right: R

    @State private var tallest: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            column(left)
            column(right)
        }
        .frame(maxHeight: equalHeight ? .infinity : nil, alignment: .top)
        .onPreferenceChange(ColumnHeightKey.self) { h in
            guard equalHeight, h > 0, abs(tallest - h) > 0.5 else { return }
            tallest = h
        }
    }

    private func column<C: View>(_ content: C) -> some View {
        // 丈の指定は1枚のframeにまとめる。あいだに丈の無いframeを挟むと、
        // そこで自然な高さに固まってしまってカードが伸びない。
        VStack(spacing: 8) { content }
            .frame(maxWidth: .infinity,
                   minHeight: equalHeight && tallest > 0 ? tallest : nil,
                   maxHeight: equalHeight ? .infinity : nil,
                   alignment: .top)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ColumnHeightKey.self, value: geo.size.height)
                }
            )
    }
}
