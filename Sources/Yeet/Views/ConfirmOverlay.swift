import SwiftUI

/// Confirmation card shown over a 50% black backdrop.
struct ConfirmOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sel = model.selectedLeaves
        let size = Fmt.size(model.selectedSize)
        let runningApps = AppRunning.runningNames(Set(sel.compactMap { $0.action?.requiresQuitBundleID }))

        ZStack {
            Color.black.opacity(0.5)
                .contentShape(Rectangle())
                .onTapGesture { model.showConfirm = false }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Clean Up \(size) of Cache?", "Dọn \(size) cache?"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.text)
                    Text(L((sel.count == 1 ? "1 item" : "\(sel.count) items")
                            + " will be permanently deleted, not moved to the Trash. Tools recreate their caches as needed.",
                           "\(sel.count) mục sẽ bị xoá vĩnh viễn, không vào Thùng rác. Công cụ sẽ tự tạo lại cache khi cần."))
                        .font(.system(size: 13.5))
                        .lineSpacing(5)
                        .foregroundStyle(DS.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sel) { leaf in
                            HStack(spacing: 10) {
                                Circle().fill(leaf.tool.color).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("\(leaf.tool.name) · \(leaf.name)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(DS.text)
                                        .lineLimit(1)
                                    Text(leaf.path)
                                        .font(DS.mono(11))
                                        .foregroundStyle(DS.text3)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                Text(Fmt.size(leaf.leafSize))
                                    .font(.system(size: 12.5))
                                    .monospacedDigit()
                                    .foregroundStyle(DS.text2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Rectangle().fill(DS.rowDivider).frame(height: 1) }
                        }
                    }
                }
                .frame(height: min(220, CGFloat(sel.count) * 47))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.divider, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if !runningApps.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "xmark.octagon").font(.system(size: 16))
                        Text(L("Running: \(runningApps.joined(separator: ", ")). Quit these apps (⌘Q) first, or their caches will be skipped.",
                               "Đang chạy: \(runningApps.joined(separator: ", ")). Thoát hẳn các app này (⌘Q) trước, nếu không cache của chúng sẽ bị bỏ qua."))
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(DS.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.danger.opacity(0.10)))
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button(L("Cancel", "Huỷ")) { model.showConfirm = false }
                        .buttonStyle(OutlineButtonStyle(horizontalPadding: 16))
                        .keyboardShortcut(.cancelAction)
                    Button(L("Delete \(size)", "Xoá \(size)")) { model.startClean() }
                        .buttonStyle(FilledButtonStyle(color: DS.danger, pressedColor: DS.dangerPressed, horizontalPadding: 16))
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.surface))
            .shadow(color: DS.text.opacity(0.24), radius: 24, x: 0, y: 24)
            .onExitCommand { model.showConfirm = false }
        }
    }
}
