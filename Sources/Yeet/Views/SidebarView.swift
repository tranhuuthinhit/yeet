import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(GrowthStore.self) private var growth

    private var growthDelta: String {
        guard let c = growth.current, let b = growth.baseline else { return "" }
        return Fmt.delta(c.diskUsed - b.diskUsed)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    OverlineText(L("OVERVIEW", "TỔNG QUAN"))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)

                    SidebarRow(tile: nil, symbol: "square.grid.2x2", name: L("All", "Tất cả"),
                               size: model.scanned.isEmpty ? "…" : Fmt.size(model.grandTotal),
                               selected: model.selection == .all) {
                        model.select(.all)
                    }

                    SidebarRow(tile: nil, symbol: "chart.line.uptrend.xyaxis", name: L("Growth", "Tăng trưởng"),
                               size: growthDelta, selected: model.selection == .growth) {
                        model.select(.growth)
                    }

                    ForEach(ToolSection.allCases.filter { s in model.visibleTools.contains { $0.section == s } },
                            id: \.self) { section in
                        OverlineText(section.title)
                            .padding(.horizontal, 8)
                            .padding(.top, 16)
                            .padding(.bottom, 6)

                        ForEach(model.visibleTools.filter { $0.section == section }) { kind in
                            SidebarRow(tile: kind.color, symbol: kind.symbol, name: kind.name,
                                       size: model.scanned.contains(kind) ? Fmt.size(model.toolNode(kind).size) : "…",
                                       selected: model.selection == .tool(kind)) {
                                model.select(.tool(kind))
                            }
                            .contextMenu {
                                Button(L("Hide \(kind.name)", "Ẩn \(kind.name)")) { model.setHidden(kind, true) }
                                SettingsLink { Text(L("Manage Tools…", "Quản lý công cụ…")) }
                            }
                        }
                    }

                    let hiddenCount = model.hiddenTools.count + model.autoHiddenTools.count
                    if hiddenCount > 0 {
                        SettingsLink {
                            HStack(spacing: 6) {
                                Image(systemName: "eye.slash").font(.system(size: 11))
                                Text(L(hiddenCount == 1 ? "1 tool hidden · Manage…" : "\(hiddenCount) tools hidden · Manage…",
                                        "Đã ẩn \(hiddenCount) công cụ · Quản lý…"))
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(DS.text3)
                            .padding(.horizontal, 8)
                            .padding(.top, 10)
                        }
                        .buttonStyle(.plain)
                        .help(L("Right-click a tool to hide it", "Chuột phải vào một công cụ để ẩn nó"))
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            Rectangle().fill(DS.border).frame(height: 1)

            DiskFooter()
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .background(DS.sidebar)
    }
}

private struct SidebarRow: View {
    let tile: Color?
    let symbol: String
    let name: String
    let size: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let tile {
                    ToolTile(color: tile, symbol: symbol)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(size)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
            }
            .foregroundStyle(selected ? Color.white : DS.text)
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? DS.primary : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: selected)
    }
}

private struct DiskFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let disk = model.disk
        let total = max(Double(disk.total), 1)
        let cache = Double(model.grandTotal)
        let other = max(0, Double(disk.total - disk.free) - cache)
        let otherFrac = min(1, other / total)
        let cacheFrac = min(1 - otherFrac, max(0.01, cache / total))

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").font(.system(size: 14))
                Text(disk.name).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(DS.text)

            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle().fill(DS.primary).frame(width: g.size.width * otherFrac)
                    Rectangle().fill(DS.accent).frame(width: g.size.width * cacheFrac)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 6)
            .background(DS.diskTrack)
            .clipShape(Capsule())

            VStack(spacing: 2) {
                kv(L("Dev cache", "Cache dev"), Fmt.size(model.grandTotal))
                kv(L("Free", "Còn trống"), "\(Fmt.size(disk.free)) / \(Fmt.capacity(disk.total))")
                kv(L("Freed", "Đã giải phóng"), Fmt.size(model.freedTotal), valueColor: DS.success, bold: true)
            }
        }
    }

    private func kv(_ label: String, _ value: String, valueColor: Color = DS.text, bold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(DS.text2)
            Spacer()
            Text(value)
                .monospacedDigit()
                .fontWeight(bold ? .semibold : .regular)
                .foregroundStyle(valueColor)
        }
        .font(.system(size: 12))
    }
}
