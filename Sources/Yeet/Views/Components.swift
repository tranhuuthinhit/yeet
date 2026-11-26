import SwiftUI

struct CheckboxView: View {
    let state: CheckState
    let action: () -> Void

    private var isOn: Bool { state == .checked || state == .partial }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isOn ? DS.primary : Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isOn ? DS.primary : Color.white.opacity(0.45), lineWidth: 1.5)
                if state == .checked {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                } else if state == .partial {
                    Image(systemName: "minus").font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(DS.onPrimary)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(state == .disabled ? 0.4 : 1)
        .disabled(state == .disabled)
        .accessibilityLabel(L("Select", "Chọn"))
        .accessibilityValue(state == .checked ? L("Selected", "Đã chọn")
                            : state == .partial ? L("Partially selected", "Chọn một phần")
                            : L("Not selected", "Chưa chọn"))
    }
}

struct RiskBadge: View {
    let risk: Risk
    var body: some View {
        Text(risk.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(risk.color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(risk.tint))
    }
}

struct ToolTile: View {
    let color: Color
    let symbol: String
    var size: CGFloat = 26
    var radius: CGFloat = 6
    var glyph: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.78), color], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: glyph, weight: .medium))
                    .foregroundStyle(.white)
            )
    }
}

/// Arrow that spins while `active` (0.9s linear loop). Respects Reduce Motion.
struct SpinningIcon: View {
    let systemName: String
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !active || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let angle = (active && !reduceMotion) ? (t.truncatingRemainder(dividingBy: 0.9) / 0.9) * 360 : 0
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .rotationEffect(.degrees(angle))
        }
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(DS.success)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(DS.sheet))
        .overlay(Capsule().strokeBorder(DS.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
        .frame(maxWidth: 640)
    }
}
