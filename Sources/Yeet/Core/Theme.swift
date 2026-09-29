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

/// Design tokens from the handoff.
enum DS {
    static let primary = Color(hex: 0x2E5C8A)
    static let primaryPressed = Color(hex: 0x1F4468)
    static let accent = Color(hex: 0xF07B3F)
    static let success = Color(hex: 0x2BA776)
    static let warning = Color(hex: 0xF2B441)
    static let danger = Color(hex: 0xE03131)
    static let dangerPressed = Color(hex: 0xC02525)

    static let bg = Color(hex: 0xF5F7FA)
    static let sidebar = Color(hex: 0xEEF2F7)
    static let surface = Color.white
    static let border = Color(hex: 0xC5CDD9)
    static let divider = Color(hex: 0xE3E8EF)
    static let rowDivider = Color(hex: 0xEEF2F7)

    static let text = Color(hex: 0x1A2332)
    static let text2 = Color(hex: 0x4A5668)
    static let text3 = Color(hex: 0x7A8699)

    static let diskTrack = Color(hex: 0xD5DCE6)
    static let disabled = Color(hex: 0xA9B6C8)
    static let folder = Color(hex: 0x5B8DB8)

    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
}

// MARK: - Reusable modifiers

struct OverlineText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .foregroundStyle(DS.text3)
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.surface))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: DS.text.opacity(0.08), radius: 1, x: 0, y: 1)
            .shadow(color: DS.text.opacity(0.06), radius: 1.5, x: 0, y: 1)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

// MARK: - Button styles

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
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(configuration.isPressed ? DS.bg : DS.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DS.border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

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
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, horizontalPadding)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(!isEnabled ? DS.disabled : (configuration.isPressed ? pressedColor : color))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}
