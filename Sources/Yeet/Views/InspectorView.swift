import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let n = model.find(model.focused) {
                ScrollView {
                    content(n)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(L("Select an item on the left to see details.", "Chọn một mục bên trái để xem chi tiết."))
                    .font(.system(size: 13))
                    .foregroundStyle(DS.text3)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .card()
    }

    @MainActor @ViewBuilder
    private func content(_ n: CacheNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title block
            VStack(alignment: .leading, spacing: 4) {
                OverlineText(n.tool.name.uppercased())
                Text(n.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DS.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Fmt.size(n.size))
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.56)
                    .monospacedDigit()
                    .foregroundStyle(DS.text)
                    .padding(.top, 4)
            }

            // Path
            VStack(alignment: .leading, spacing: 6) {
                OverlineText(L("PATH", "ĐƯỜNG DẪN"))
                Text(n.path)
                    .font(DS.mono(12))
                    .lineSpacing(4)
                    .foregroundStyle(DS.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.bg))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.divider, lineWidth: 1))

                HStack(spacing: 8) {
                    Button {
                        model.copyPath(n)
                    } label: {
                        Label(model.copied ? L("Copied", "Đã sao chép") : L("Copy", "Sao chép"),
                              systemImage: model.copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(OutlineButtonStyle(height: 30, fontSize: 12.5, horizontalPadding: 8, fullWidth: true))

                    Button {
                        model.reveal(n)
                    } label: {
                        Label(L("Show in Finder", "Mở Finder"), systemImage: "folder")
                    }
                    .buttonStyle(OutlineButtonStyle(height: 30, fontSize: 12.5, horizontalPadding: 8, fullWidth: true))
                }
            }

            // Facts
            HStack(alignment: .top, spacing: 8) {
                fact(L("Files", "Số tệp"),
                     n.isGroup ? L(n.leaves.count == 1 ? "1 item" : "\(n.leaves.count) items", "\(n.leaves.count) mục")
                               : Fmt.count(n.fileCount))
                fact(L("Last Modified", "Sửa lần cuối"), Fmt.modified(n.latestModified))
            }

            if !n.isGroup, let risk = n.risk {
                VStack(alignment: .leading, spacing: 6) {
                    OverlineText(L("IMPACT OF DELETING", "ẢNH HƯỞNG KHI XOÁ"))
                    RiskBadge(risk: risk)
                    Text(n.note)
                        .font(.system(size: 13))
                        .lineSpacing(6.5)
                        .foregroundStyle(DS.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !n.isGroup, let action = n.action {
                VStack(alignment: .leading, spacing: 6) {
                    OverlineText(L("HOW IT’S CLEANED", "CÁCH DỌN"))
                    Text(action.display)
                        .font(DS.mono(12))
                        .lineSpacing(4)
                        .foregroundStyle(DS.divider)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.text))
                }
            }

            if n.isGroup {
                let childCount = (n.children ?? []).count
                Text(L("Contains \(childCount == 1 ? "1 item" : "\(childCount) items"). Select each item on the left to see its path and impact.",
                       "Gồm \(childCount) mục. Chọn từng mục bên trái để xem đường dẫn và ảnh hưởng."))
                    .font(.system(size: 13))
                    .lineSpacing(6.5)
                    .foregroundStyle(DS.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(DS.text3)
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(DS.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
