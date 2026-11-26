import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Yeet v2 design tokens: white text on a deep per-module gradient, frosted-glass cards.
/// Every window is dark (`.preferredColorScheme(.dark)`), so these values are fixed.
enum DS {
    /// Selection, checkbox fill and the primary button background.
    static let primary = Color.white
    static let primaryPressed = Color(white: 0.86)
    /// Glyphs and text drawn on top of `primary` when no module hue is known.
    static let onPrimary = Color(hex: 0x1A1030)

    static let accent = Color(hex: 0xFFA552)
    static let success = Color(hex: 0x8EEBC5)
    static let warning = Color(hex: 0xFFD98A)
    static let danger = Color(hex: 0xFF9A9A)
    static let dangerPressed = Color(hex: 0xFF7A7A)

    static let bg = Color.clear
    static let sidebar = Color.black.opacity(0.28)
    static let surface = Color.white.opacity(0.08)
    static let surfaceStrong = Color.white.opacity(0.14)
    static let border = Color.white.opacity(0.16)
    static let divider = Color.white.opacity(0.12)
    static let rowDivider = Color.white.opacity(0.06)
    static let inputBg = Color.black.opacity(0.22)
    static let codeBg = Color.black.opacity(0.32)
    static let codeText = Color.white.opacity(0.9)
    /// Solid background for sheets and popovers drawn over a dimmed window.
    static let sheet = Color(hex: 0x1F1830)

    static let text = Color.white
    static let text2 = Color.white.opacity(0.78)
    static let text3 = Color.white.opacity(0.62)

    static let diskTrack = Color.white.opacity(0.16)
    static let disabled = Color.white.opacity(0.3)
    static let folder = Color(hex: 0x9CC4FF)

    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
}

// MARK: - Module hue

/// Each module paints the window with its own gradient; tiles and the primary button ink follow it.
struct Hue: Equatable {
    let top: Color
    let mid: Color
    let bottom: Color
    let tileLight: Color
    let tileDark: Color
    /// Text colour on the white primary button.
    let ink: Color

    var gradient: LinearGradient {
        LinearGradient(stops: [.init(color: top, location: 0), .init(color: mid, location: 0.52),
                               .init(color: bottom, location: 1)],
                       startPoint: UnitPoint(x: 0.1, y: 0), endPoint: UnitPoint(x: 0.9, y: 1))
    }

    var tile: LinearGradient {
        LinearGradient(colors: [tileLight, tileDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Translucent bar colour behind the bottom action bar.
    var bar: Color { top.opacity(0.62) }

    private init(_ t: UInt32, _ m: UInt32, _ b: UInt32, _ l: UInt32, _ d: UInt32, _ ink: UInt32) {
        top = Color(hex: t); mid = Color(hex: m); bottom = Color(hex: b)
        tileLight = Color(hex: l); tileDark = Color(hex: d); self.ink = Color(hex: ink)
    }

    static let violet = Hue(0x2A1140, 0x56206A, 0x8A2C7E, 0xEC6AD2, 0x9B3BC4, 0x5A1E6E)
    static let green = Hue(0x0B2E2A, 0x135447, 0x1D7A5C, 0x45D6A0, 0x17936A, 0x0F4A3A)
    static let amber = Hue(0x33200A, 0x664010, 0x99631A, 0xF7C04F, 0xD9861C, 0x5C3A06)
    static let orange = Hue(0x3A160C, 0x7A3014, 0xB5501C, 0xFFA552, 0xE0611D, 0x7A2E10)
    static let indigo = Hue(0x1B1246, 0x352285, 0x5536B8, 0xA48CFF, 0x6646E0, 0x2E1E78)
    static let cyan = Hue(0x082A40, 0x0F4C6E, 0x1A6FA0, 0x62CCF7, 0x2585D1, 0x0B3D5C)
    static let blue = Hue(0x0D1D47, 0x1A3A85, 0x2A5EC0, 0x62A2FF, 0x2D5FD8, 0x17357A)
    static let teal = Hue(0x07302E, 0x0E5552, 0x167A74, 0x4FD6C8, 0x16918A, 0x0A4744)
    static let rose = Hue(0x36101F, 0x6A1C3A, 0x98294F, 0xFF8496, 0xD63A5C, 0x6A1C3A)
    static let crimson = Hue(0x380C1C, 0x681632, 0x93204A, 0xFF6FA0, 0xC92A62, 0x5E1230)
}

private struct HueKey: EnvironmentKey {
    static let defaultValue = Hue.violet
}

extension EnvironmentValues {
    var hue: Hue {
        get { self[HueKey.self] }
        set { self[HueKey.self] = newValue }
    }
}

/// Full-window gradient for a hue, with a soft glow in two corners.
struct HueBackground: View {
    let hue: Hue
    var body: some View {
        ZStack {
            hue.gradient
            RadialGradient(colors: [hue.tileLight.opacity(0.22), .clear], center: UnitPoint(x: 0.9, y: 0.95),
                           startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Color.white.opacity(0.06), .clear], center: UnitPoint(x: 0.1, y: 0),
                           startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Reusable modifiers

struct OverlineText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(DS.text3)
    }
}

/// Frosted-glass card.
struct CardModifier: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DS.border.opacity(0.85), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(radius: CGFloat = 16) -> some View { modifier(CardModifier(radius: radius)) }
}

// MARK: - Button styles

/// Secondary action: translucent capsule with a hairline border.
struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 34
    var fontSize: CGFloat = 13.5
    var horizontalPadding: CGFloat = 14
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        OutlineBody(configuration: configuration, height: height, fontSize: fontSize,
                    horizontalPadding: horizontalPadding, fullWidth: fullWidth)
    }

    private struct OutlineBody: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        let fontSize: CGFloat
        let horizontalPadding: CGFloat
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(DS.text)
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: height)
                .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

/// Primary action: white capsule whose label takes the module's ink colour.
/// Pass `color` (e.g. `DS.danger`) for a destructive variant.
struct FilledButtonStyle: ButtonStyle {
    var color: Color = DS.primary
    var pressedColor: Color = DS.primaryPressed
    var horizontalPadding: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        FilledBody(configuration: configuration, color: color, pressedColor: pressedColor,
                   horizontalPadding: horizontalPadding)
    }

    private struct FilledBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let pressedColor: Color
        let horizontalPadding: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.hue) private var hue
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(color == DS.primary ? hue.ink : DS.onPrimary)
                .padding(.horizontal, horizontalPadding)
                .frame(height: 36)
                .background(Capsule().fill(configuration.isPressed ? pressedColor : color))
                .shadow(color: hue.tileLight.opacity(isEnabled ? 0.35 : 0), radius: 10, x: 0, y: 5)
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

// MARK: - Segmented pill

/// Compact segmented control: dark track, the chosen segment is a white pill.
struct SegmentedPill<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @Environment(\.hue) private var hue

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                let on = o.value == selection
                Button { selection = o.value } label: {
                    Text(o.label)
                        .font(.system(size: 12.5, weight: on ? .bold : .medium))
                        .foregroundStyle(on ? hue.ink : DS.text2)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Color.white : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.inputBg))
    }
}

// MARK: - Module chrome

/// Title row at the top of every module: title + subtitle on the left, controls on the right.
struct ModuleHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DS.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.divider).frame(height: 1) }
    }
}

extension ModuleHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// Sticky bottom bar: selection summary on the left, actions on the right.
struct ActionBar<Summary: View, Actions: View>: View {
    @ViewBuilder var summary: () -> Summary
    @ViewBuilder var actions: () -> Actions
    @Environment(\.hue) private var hue

    var body: some View {
        HStack(spacing: 12) {
            summary().frame(maxWidth: .infinity, alignment: .leading)
            actions()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(hue.bar)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(DS.divider).frame(height: 1) }
    }
}

/// "Selected 2 items · 1.2 GB" + a secondary line, used inside `ActionBar`.
struct SelectionSummary: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DS.text)
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text3)
                    .lineLimit(1)
            }
        }
    }
}

/// Rounded gradient square with a white SF Symbol, in the module's hue unless a colour is given.
struct HueTile: View {
    let symbol: String
    var color: Color? = nil
    var size: CGFloat = 28
    var glyph: CGFloat = 14
    @Environment(\.hue) private var hue

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.map { c in LinearGradient(colors: [c.opacity(0.8), c], startPoint: .topLeading, endPoint: .bottomTrailing) }
                  ?? hue.tile)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: glyph, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// Small rounded label used for kinds, architectures and statuses.
struct Chip: View {
    let text: String
    var tint: Color = .white
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(tint == .white ? DS.text : tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(tint.opacity(tint == .white ? 0.14 : 0.2)))
    }
}

/// Placeholder shown while a module scans or when it has nothing to show.
struct ModuleEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var busy = false
    var progress: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            if busy {
                ProgressView().controlSize(.regular).tint(.white)
            } else {
                Image(systemName: symbol).font(.system(size: 30, weight: .medium)).foregroundStyle(DS.text2)
            }
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.text)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            if let progress {
                Text(progress).font(.system(size: 12)).monospacedDigit().foregroundStyle(DS.text3)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
