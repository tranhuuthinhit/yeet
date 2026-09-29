import SwiftUI

struct HeaderView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(GitRoots.key) private var gitRootsRaw = GitRoots.defaultValue

    private var tool: ToolKind? {
        if case .tool(let k) = model.selection { return k }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ToolTile(color: tool?.color ?? DS.text, symbol: tool?.symbol ?? "sparkles",
                     size: 44, radius: 10, glyph: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: tool.map { L("\($0.name) Cache", "Cache của \($0.name)") } ?? L("All Caches", "Tất cả cache"))
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(DS.text)
                Text(tool?.description(gitRoots: GitRoots.list(gitRootsRaw))
                     ?? L("Caches from developer tools, IDEs, apps and macOS found on this Mac. Only items that are recreated or re-downloaded automatically are listed. Select an item to see its path and impact before deleting.",
                           "Cache của công cụ lập trình, IDE, ứng dụng và macOS tìm thấy trên máy. Chỉ liệt kê những gì tự tạo lại hoặc tải lại được. Chọn một mục để xem đường dẫn và ảnh hưởng trước khi xoá."))
                    .font(.system(size: 13.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(DS.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 680, alignment: .leading)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 0) {
                OverlineText(L("TOTAL", "TỔNG"))
                Text(Fmt.size(model.headNode.size))
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.24)
                    .monospacedDigit()
                    .foregroundStyle(DS.text)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}
