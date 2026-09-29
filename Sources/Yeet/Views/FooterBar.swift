import SwiftUI

struct FooterBar: View {
    @Environment(AppModel.self) private var model
    @AppStorage("confirmBeforeClean") private var confirmBeforeClean = true

    var body: some View {
        let selCount = model.selectedLeaves.count
        let canClean = selCount > 0 && model.phase == .idle

        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                (Text(L("Selected ", "Đã chọn "))
                    + Text(Fmt.size(model.selectedSize)).bold().monospacedDigit()
                    + Text(L(selCount == 1 ? " · 1 item" : " · \(selCount) items", " · \(selCount) mục")).foregroundColor(DS.text2))
                    .font(.system(size: 14))
                    .foregroundColor(DS.text)
                Text(L("Total cache: \(Fmt.size(model.grandTotal)) · \(Fmt.size(model.safeTotal)) safe to delete",
                        "Tổng cache: \(Fmt.size(model.grandTotal)) · \(Fmt.size(model.safeTotal)) an toàn để xoá"))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if case .cleaning(let p) = model.phase {
                HStack(spacing: 10) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.divider)
                            Capsule().fill(DS.primary).frame(width: g.size.width * p)
                        }
                    }
                    .frame(height: 6)
                    Text(L("Cleaning… \(Int((p * 100).rounded()))%", "Đang dọn… \(Int((p * 100).rounded()))%"))
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(DS.text2)
                        .fixedSize()
                }
                .frame(width: 260)
                .transition(.opacity)
            }

            Button {
                model.selectSafe()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.success)
                    Text(L("Select Safe Items", "Chọn mục an toàn"))
                }
            }
            .buttonStyle(OutlineButtonStyle())
            .disabled(model.phase != .idle)

            Button {
                model.requestClean(confirm: confirmBeforeClean)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 14, weight: .medium))
                    Text(L("Clean Up…", "Dọn dẹp…"))
                }
            }
            .buttonStyle(FilledButtonStyle())
            .disabled(!canClean)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(DS.surface)
        .overlay(alignment: .top) { Rectangle().fill(DS.border).frame(height: 1) }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }
}
