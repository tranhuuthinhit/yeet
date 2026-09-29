import SwiftUI

struct CacheTreeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showPaths") private var showPaths = true
    @AppStorage("hideEmpty") private var hideEmpty = false

    var body: some View {
        let rows = model.rows(hideEmpty: hideEmpty)

        VStack(spacing: 0) {
            // Column header
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    CheckboxView(state: model.checkState(model.headNode)) {
                        model.toggleCheck(model.headNode)
                    }
                    .padding(.leading, 28)
                    OverlineText(L("ITEM", "MỤC"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                OverlineText(L("IMPACT", "MỨC ĐỘ")).frame(width: 112, alignment: .leading)
                OverlineText(L("SIZE", "DUNG LƯỢNG")).frame(width: 88, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle().fill(DS.divider).frame(height: 1)

            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            TreeRowView(row: row, showPath: showPaths)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            if model.phase == .scanning {
                ProgressView().controlSize(.small)
                Text(L("Scanning…", "Đang quét…")).font(.system(size: 13)).foregroundStyle(DS.text3)
            } else {
                Image(systemName: "checkmark.seal").font(.system(size: 28)).foregroundStyle(DS.success)
                Text(model.scanned.isEmpty
                     ? L("Not scanned yet. Click “Rescan” to start.", "Chưa quét. Nhấn “Quét lại” để bắt đầu.")
                     : L("No caches found.", "Không tìm thấy cache nào."))
                    .font(.system(size: 13))
                    .foregroundStyle(DS.text3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TreeRowView: View {
    @Environment(AppModel.self) private var model
    let row: TreeRow
    let showPath: Bool

    var body: some View {
        let n = row.node
        let size = n.size
        let empty = size <= 0
        let isExpanded = model.expanded.contains(n.id)
        let focused = model.focused == n.id
        let hasChildren = !(n.children ?? []).isEmpty

        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { model.toggleExpanded(n.id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.text3)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(n.isGroup && hasChildren ? 1 : 0)
                .disabled(!(n.isGroup && hasChildren))

                CheckboxView(state: model.checkState(n)) { model.toggleCheck(n) }

                icon(for: n)

                VStack(alignment: .leading, spacing: 1) {
                    Text(n.name)
                        .font(.system(size: 14, weight: n.isGroup ? .semibold : .regular))
                        .foregroundStyle(empty ? DS.text3 : DS.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if showPath {
                        Text(n.path)
                            .font(DS.mono(11.5))
                            .foregroundStyle(DS.text3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(.leading, CGFloat(row.depth) * 22)
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if let risk = n.risk, !n.isGroup, !empty {
                    RiskBadge(risk: risk)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(width: 112, alignment: .leading)

            Text(Fmt.size(size))
                .font(.system(size: 13.5, weight: n.isGroup ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(empty ? DS.text3 : DS.text)
                .frame(width: 88, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(focused ? DS.primary.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.focus(n.id) }
    }

    @ViewBuilder
    private func icon(for n: CacheNode) -> some View {
        if n.isTool {
            ToolTile(color: n.tool.color, symbol: n.tool.symbol, size: 24, radius: 6, glyph: 13)
        } else if n.isGroup {
            Image(systemName: "folder.fill")
                .font(.system(size: 16))
                .foregroundStyle(DS.folder)
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "folder")
                .font(.system(size: 16))
                .foregroundStyle(DS.text3)
                .frame(width: 24, height: 24)
        }
    }
}
