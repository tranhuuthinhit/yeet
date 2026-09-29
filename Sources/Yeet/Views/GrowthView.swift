import AppKit
import Charts
import SwiftUI

// MARK: - Formatting

extension Fmt {
    /// `+3,45 GB`, `−640 MB`, `0 KB`
    static func delta(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 KB" }
        return (bytes > 0 ? "+" : "−") + size(abs(bytes))
    }
}

private func deltaColor(_ d: Int64) -> Color {
    d > 0 ? DS.danger : (d < 0 ? DS.success : DS.text3)
}

// MARK: - Screen

/// "Growth": what made the disk grow between two daily snapshots.
struct GrowthView: View {
    @Environment(GrowthStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            GrowthHeader()
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    GrowthOverview()
                    GrowthTree()
                }
                GrowthInspector().frame(width: 300)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity)
            GrowthFooter()
        }
        .onAppear { if store.snapshots.isEmpty { store.load() } }
    }
}

// MARK: - Header

private struct GrowthHeader: View {
    @Environment(GrowthStore.self) private var store

    private var delta: Int64? {
        guard let c = store.current, let b = store.baseline else { return nil }
        return c.diskUsed - b.diskUsed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ToolTile(color: DS.accent, symbol: "chart.line.uptrend.xyaxis", size: 44, radius: 10, glyph: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("What Made Your Disk Grow?", "Dung lượng tăng do đâu?"))
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(DS.text)
                Text(L("Every day Yeet records your disk usage and the size of each folder, then compares them to show which folders just grew. Growth outside any folder Yeet can measure is counted as “System & other”.",
                       "Mỗi ngày Yeet ghi lại dung lượng ổ đĩa và kích thước từng thư mục, rồi so sánh để chỉ ra thư mục nào vừa phình ra. Phần tăng không nằm trong thư mục nào Yeet đo được sẽ tính vào “Hệ thống & khác”."))
                    .font(.system(size: 13.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(DS.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 680, alignment: .leading)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 0) {
                OverlineText(L("CHANGE", "THAY ĐỔI"))
                Text(delta.map { Fmt.delta($0) } ?? "—")
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(delta.map(deltaColor) ?? DS.text3)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

// MARK: - Overview (chart + summary)

private struct GrowthOverview: View {
    @Environment(GrowthStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                let days = min(store.snapshots.count, 30)
                OverlineText(L("USED SPACE · \(days) \(days == 1 ? "DAY" : "DAYS")",
                               "DUNG LƯỢNG ĐÃ DÙNG · \(days) NGÀY"))
                Spacer()
                BaselinePicker()
            }
            if let skipped = store.current?.skipped, !skipped.isEmpty {
                NotMeasuredBanner(names: GrowthScanner.skippedNames(skipped))
            }
            chart.frame(height: 120)
            summary
        }
        .padding(16)
        .card()
    }

    @ViewBuilder
    private var chart: some View {
        let points = Array(store.snapshots.suffix(30))
        if points.count < 2 {
            Text(points.isEmpty
                 ? L("No data yet. Click “Analyze Now” to take the first snapshot.",
                     "Chưa có số liệu. Nhấn “Phân tích ngay” để chụp lần đầu.")
                 : L("Today’s data is in. Starting tomorrow, Yeet can compare growth day by day.",
                     "Đã có số liệu hôm nay. Từ ngày mai Yeet sẽ so sánh được mức tăng theo ngày."))
                .font(.system(size: 13))
                .foregroundStyle(DS.text3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.bg))
        } else {
            let minGB = (points.map { Double($0.diskUsed) }.min() ?? 0) / 1e9
            Chart(points) { p in
                BarMark(x: .value(L("Date", "Ngày"), p.date, unit: .day),
                        y: .value("GB", Double(p.diskUsed) / 1e9))
                    .foregroundStyle(p.id == store.baselineID || p.id == points.last?.id ? DS.accent : DS.primary.opacity(0.55))
                    .cornerRadius(2)
            }
            .chartYScale(domain: max(0, minGB * 0.95)...(Double(points.map(\.diskUsed).max() ?? 0) / 1e9 * 1.01))
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine()
                    AxisValueLabel { if let g = v.as(Double.self) { Text("\(Int(g)) GB") } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, points.count / 7))) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                }
            }
            .environment(\.locale, AppLanguage.current.locale)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let c = store.current, let b = store.baseline {
            let disk = c.diskUsed - b.diskUsed
            let home = (c.roots[Paths.home.path] ?? 0) - (b.roots[Paths.home.path] ?? 0)
            let tracked = c.trackedTotal - b.trackedTotal
            let other = disk - tracked
            HStack(spacing: 12) {
                stat(L("Disk", "Ổ đĩa"), disk, sub: "\(Fmt.size(b.diskUsed)) → \(Fmt.size(c.diskUsed))")
                stat(L("Home folder", "Thư mục người dùng"), home, sub: "~/")
                if tracked != home {
                    stat(L("Apps & tools", "Ứng dụng & công cụ"), tracked - home, sub: GrowthScanner.extraRoots.map { $0.0.path }.joined(separator: ", "))
                }
                stat(c.skipped.isEmpty ? L("System & other", "Hệ thống & khác")
                                        : L("System, unmeasured & other", "Hệ thống, chưa đo & khác"), other, sub: snapshotsNote(b, c))
            }
        }
    }

    private func snapshotsNote(_ b: DiskSnapshot, _ c: DiskSnapshot) -> String {
        guard b.localSnapshots >= 0, c.localSnapshots >= 0 else { return L("macOS, APFS snapshots, virtual memory", "macOS, snapshot APFS, bộ nhớ ảo") }
        let d = c.localSnapshots - b.localSnapshots
        return L("Time Machine snapshots: \(c.localSnapshots)", "Snapshot Time Machine: \(c.localSnapshots)") + (d != 0 ? " (\(d > 0 ? "+" : "")\(d))" : "")
    }

    private func stat(_ title: String, _ delta: Int64, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(DS.text3)
            Text(Fmt.delta(delta))
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(deltaColor(delta))
            Text(sub).font(.system(size: 11)).foregroundStyle(DS.text3).lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.bg))
    }
}

/// Tells the user which folders weren't measured and how to include them.
private struct NotMeasuredBanner: View {
    let names: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.slash").font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Not measured: \(names.joined(separator: ", "))", "Chưa đo: \(names.joined(separator: ", "))"))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(BuildFlavor.isAppStore
                     ? L("The App Store version can’t read other apps’ data. Growth there is counted as “System, unmeasured & other”.",
                         "Bản App Store không đọc được dữ liệu của ứng dụng khác. Mức tăng ở đó được tính vào “Hệ thống, chưa đo & khác”.")
                     : L("These folders need your permission once (or Full Disk Access). Until then, growth there is counted as “System, unmeasured & other”.",
                         "Các thư mục này cần bạn cho phép một lần (hoặc Full Disk Access). Đến lúc đó, mức tăng ở đó được tính vào “Hệ thống, chưa đo & khác”."))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !BuildFlavor.isAppStore {
                SettingsLink {
                    Text(L("Grant Access…", "Cấp quyền…"))
                }
                .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 12.5, horizontalPadding: 10))
            }
        }
        .foregroundStyle(Color(hex: 0x8A5A00))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.warning.opacity(0.15)))
    }
}

private struct BaselinePicker: View {
    @Environment(GrowthStore.self) private var store

    var body: some View {
        let options = store.snapshots.dropLast().reversed()
        Menu {
            if let y = store.defaultBaseline() {
                Button(L("Previous Snapshot (\(Fmt.modified(y.date)))", "Lần chụp trước (\(Fmt.modified(y.date)))")) { store.selectBaseline(y.id) }
            }
            if let w = store.snapshot(daysBefore: 7) {
                Button(L("~7 Days Ago (\(w.id))", "~7 ngày trước (\(w.id))")) { store.selectBaseline(w.id) }
            }
            if let m = store.snapshot(daysBefore: 30) {
                Button(L("~30 Days Ago (\(m.id))", "~30 ngày trước (\(m.id))")) { store.selectBaseline(m.id) }
            }
            if !options.isEmpty {
                Divider()
                ForEach(Array(options)) { s in
                    Button("\(s.id) · \(Fmt.size(s.diskUsed))") { store.selectBaseline(s.id) }
                }
            }
        } label: {
            Text(store.baselineID.map { L("Compare with \($0)", "So với \($0)") } ?? L("Compare with…", "So với…"))
                .font(.system(size: 12.5, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(options.isEmpty)
    }
}

// MARK: - Tree

private struct GrowthRow: Identifiable {
    let node: GrowthNode
    let depth: Int
    var id: String { node.id }
}

private struct GrowthTree: View {
    @Environment(GrowthStore.self) private var store

    private var rows: [GrowthRow] {
        var out: [GrowthRow] = []
        func walk(_ n: GrowthNode, _ d: Int) {
            out.append(GrowthRow(node: n, depth: d))
            if store.expanded.contains(n.id) { n.children.forEach { walk($0, d + 1) } }
        }
        store.tree.forEach { walk($0, 0) }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                OverlineText(L("FOLDER", "THƯ MỤC")).padding(.leading, 28).frame(maxWidth: .infinity, alignment: .leading)
                OverlineText(L("BEFORE", "TRƯỚC")).frame(width: 84, alignment: .trailing)
                OverlineText(L("AFTER", "SAU")).frame(width: 84, alignment: .trailing)
                OverlineText(L("CHANGE", "THAY ĐỔI")).frame(width: 96, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Rectangle().fill(DS.divider).frame(height: 1)

            if store.baseline == nil && !store.tree.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(L("No snapshot from another day to compare with yet. Showing the largest folders right now.",
                            "Chưa có lần chụp ở ngày khác để so sánh. Đang hiện các thư mục lớn nhất hiện tại."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(DS.text2)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.bg)
            }

            if store.tree.isEmpty {
                Text(store.baseline == nil
                     ? L("At least two snapshots on different days are needed to compare.",
                         "Cần ít nhất hai lần chụp ở hai ngày khác nhau để so sánh.")
                     : L("No folder changed by more than 10 MB.",
                         "Không có thư mục nào thay đổi quá 10 MB."))
                    .font(.system(size: 13))
                    .foregroundStyle(DS.text3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { r in GrowthRowView(row: r) }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }
}

private struct GrowthRowView: View {
    @Environment(GrowthStore.self) private var store
    let row: GrowthRow

    var body: some View {
        let n = row.node
        let open = store.expanded.contains(n.id)
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    if open { store.expanded.remove(n.id) } else { store.expanded.insert(n.id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.text3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(n.children.isEmpty ? 0 : 1)
                .disabled(n.children.isEmpty)

                Image(systemName: row.depth == 0 ? "internaldrive" : "folder.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(row.depth == 0 ? DS.text2 : DS.folder)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.name)
                        .font(.system(size: 13.5, weight: row.depth == 0 ? .semibold : .regular))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    if row.depth > 0 {
                        Text(n.displayPath).font(DS.mono(11)).foregroundStyle(DS.text3)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .padding(.leading, CGFloat(row.depth) * 22)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Fmt.size(n.before)).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(DS.text2)
                .frame(width: 84, alignment: .trailing)
            Text(Fmt.size(n.after)).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(DS.text2)
                .frame(width: 84, alignment: .trailing)
            Text(Fmt.delta(n.delta)).font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(deltaColor(n.delta))
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(minHeight: 38)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(store.focused == n.id ? DS.primary.opacity(0.10) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { store.focused = n.id }
    }
}

// MARK: - Inspector

private struct GrowthInspector: View {
    @Environment(GrowthStore.self) private var store
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let n = store.find(store.focused) {
                ScrollView { content(n).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                Text(L("Select a folder on the left to see details.", "Chọn một thư mục bên trái để xem chi tiết."))
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

    /// Yeet tools that own caches inside (or containing) this folder.
    private func cleanableTools(_ path: String) -> [ToolKind] {
        let p = path.hasSuffix("/") ? path : path + "/"
        var seen: [ToolKind] = []
        for leaf in model.allLeaves where leaf.leafSize > 0 {
            let l = leaf.url.standardizedFileURL.path
            if (l + "/").hasPrefix(p) || p.hasPrefix(l + "/") {
                if !seen.contains(leaf.tool) { seen.append(leaf.tool) }
            }
        }
        return seen
    }

    @MainActor
    @ViewBuilder
    private func content(_ n: GrowthNode) -> some View {
        let tools = cleanableTools(n.id)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                OverlineText(L("CHANGE", "THAY ĐỔI"))
                Text(n.name).font(.system(size: 17, weight: .bold)).foregroundStyle(DS.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Fmt.delta(n.delta))
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(deltaColor(n.delta))
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                OverlineText(L("PATH", "ĐƯỜNG DẪN"))
                Text(n.displayPath)
                    .font(DS.mono(12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.bg))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.divider, lineWidth: 1))
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([n.url])
                } label: {
                    Label(L("Show in Finder", "Mở Finder"), systemImage: "folder")
                }
                .buttonStyle(OutlineButtonStyle(height: 30, fontSize: 12.5, horizontalPadding: 8, fullWidth: true))
            }

            HStack(alignment: .top, spacing: 8) {
                fact(L("Before", "Trước"), Fmt.size(n.before), store.baseline.map { Fmt.modified($0.date) } ?? "—")
                fact(L("After", "Sau"), Fmt.size(n.after), store.current.map { Fmt.modified($0.date) } ?? "—")
            }

            if !n.children.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    OverlineText(L("BIGGEST GROWTH INSIDE", "TĂNG NHIỀU NHẤT BÊN TRONG"))
                    ForEach(n.children.prefix(5)) { c in
                        HStack {
                            Text(c.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Fmt.delta(c.delta)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(deltaColor(c.delta))
                        }
                    }
                }
            }

            if !tools.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    OverlineText(L("CLEANABLE IN YEET", "DỌN ĐƯỢC TRONG YEET"))
                    ForEach(tools) { k in
                        Button {
                            model.select(.tool(k))
                        } label: {
                            HStack(spacing: 8) {
                                ToolTile(color: k.color, symbol: k.symbol, size: 20, radius: 5, glyph: 11)
                                Text(k.name)
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }
                        .buttonStyle(OutlineButtonStyle(height: 30, fontSize: 12.5, horizontalPadding: 10, fullWidth: true))
                    }
                }
            } else if n.delta > 0 {
                Text(L("This folder isn’t a cache Yeet can clean. It may be your own data (projects, photos, virtual machines, backups…), so check it in Finder.",
                        "Thư mục này không phải cache Yeet dọn được. Có thể là dữ liệu của bạn (dự án, ảnh, máy ảo, bản sao lưu…), hãy tự kiểm tra trong Finder."))
                    .font(.system(size: 12.5))
                    .lineSpacing(4)
                    .foregroundStyle(DS.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fact(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(DS.text3)
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(DS.text)
            Text(sub).font(.system(size: 11)).foregroundStyle(DS.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Footer

private struct GrowthFooter: View {
    @Environment(GrowthStore.self) private var store

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.lastCaptureDate.map { L("Last snapshot: \(Fmt.modified($0))", "Lần chụp gần nhất: \(Fmt.modified($0))") }
                     ?? L("No snapshots yet", "Chưa có lần chụp nào"))
                    .font(.system(size: 14))
                    .foregroundStyle(DS.text)
                Text(L("Captured daily while Yeet is open · kept for \(GrowthStore.keepDays) days · \(store.snapshots.count) \(store.snapshots.count == 1 ? "snapshot" : "snapshots")",
                        "Tự chụp mỗi ngày khi Yeet đang mở · giữ \(GrowthStore.keepDays) ngày · \(store.snapshots.count) lần chụp"))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.isCapturing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.isCancelling
                         ? L("Stopping…", "Đang dừng…")
                         : L("Analyzing… \(Fmt.count(store.progressFiles)) \(store.progressFiles == 1 ? "file" : "files")",
                             "Đang phân tích… \(Fmt.count(store.progressFiles)) tệp"))
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(DS.text2)
                }

                Button {
                    store.cancelCapture()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.danger)
                        Text(L("Stop Analysis", "Dừng phân tích"))
                    }
                }
                .buttonStyle(OutlineButtonStyle())
                .keyboardShortcut(.cancelAction)
                .disabled(store.isCancelling)
                .help(L("Stop this analysis. Existing data stays as is; nothing is saved.", "Dừng lượt phân tích này. Số liệu cũ giữ nguyên, không lưu gì."))
            } else {
                Button {
                    store.capture()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.metering.center.weighted").font(.system(size: 14, weight: .medium))
                        Text(L("Analyze Now", "Phân tích ngay"))
                    }
                }
                .buttonStyle(FilledButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(DS.surface)
        .overlay(alignment: .top) { Rectangle().fill(DS.border).frame(height: 1) }
    }
}
