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

private let growColor = Color(hex: 0xFFC2D0)
private let shrinkColor = Color(hex: 0x9CF2CC)

private func deltaColor(_ d: Int64) -> Color {
    d > 0 ? growColor : (d < 0 ? shrinkColor : DS.text3)
}

// MARK: - Screen

/// "Disk Growth": a 30-day chart of used space, health tiles, and the folders that changed most
/// since the chosen baseline (yesterday / 7 days / 30 days).
@MainActor
struct GrowthView: View {
    @Environment(GrowthStore.self) private var store
    @State private var range: GrowthRange = .yesterday

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(Module.growth.title,
                         subtitle: L("Measured once a day, quietly from the menu bar",
                                     "Đo mỗi ngày một lần, chạy nền trên thanh menu")) {
                SegmentedPill(selection: $range, options: GrowthRange.allCases.map { (value: $0, label: $0.title) })
                    .disabled(store.snapshots.count < 2)
                captureButton
            }

            ScrollView {
                VStack(spacing: 16) {
                    if let skipped = store.current?.skipped, !skipped.isEmpty {
                        NotMeasuredBanner(names: GrowthScanner.skippedNames(skipped))
                    }
                    HStack(alignment: .top, spacing: 16) {
                        UsageChartCard(range: range)
                            .frame(maxWidth: .infinity)
                        HealthTiles()
                            .frame(width: 300)
                    }
                    ChangedFoldersCard()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            GrowthActionBar()
        }
        .onAppear {
            if store.snapshots.isEmpty { store.load() }
            if !HealthStore.shared.loaded { HealthStore.shared.refresh() }
            range = GrowthRange.matching(store)
        }
        .onChange(of: range) { _, r in r.apply(to: store) }
    }

    @ViewBuilder
    private var captureButton: some View {
        if store.isCapturing {
            Button {
                store.cancelCapture()
            } label: {
                Label(store.isCancelling ? L("Stopping…", "Đang dừng…") : L("Stop", "Dừng"), systemImage: "stop.circle")
            }
            .buttonStyle(OutlineButtonStyle(height: 32, fontSize: 13, horizontalPadding: 12))
            .disabled(store.isCancelling)
        } else {
            Button {
                store.capture()
            } label: {
                Label(L("Analyze Now", "Phân tích ngay"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(OutlineButtonStyle(height: 32, fontSize: 13, horizontalPadding: 12))
        }
    }
}

// MARK: - Baseline range

enum GrowthRange: String, CaseIterable, Hashable {
    case yesterday, week, month

    var title: String {
        switch self {
        case .yesterday: return L("Yesterday", "Hôm qua")
        case .week: return L("7 days", "7 ngày")
        case .month: return L("30 days", "30 ngày")
        }
    }

    var days: Int {
        switch self {
        case .yesterday: return 1
        case .week: return 7
        case .month: return 30
        }
    }

    func baseline(in store: GrowthStore) -> SnapshotInfo? {
        switch self {
        case .yesterday: return store.defaultBaseline()
        case .week: return store.snapshot(daysBefore: 7) ?? store.snapshots.first
        case .month: return store.snapshot(daysBefore: 30) ?? store.snapshots.first
        }
    }

    func apply(to store: GrowthStore) {
        if let b = baseline(in: store) { store.selectBaseline(b.id) }
    }

    /// The range whose baseline is the one currently selected (yesterday when unknown).
    static func matching(_ store: GrowthStore) -> GrowthRange {
        guard let id = store.baselineID else { return .yesterday }
        return allCases.first { $0.baseline(in: store)?.id == id } ?? .yesterday
    }
}

// MARK: - Chart

private struct UsageChartCard: View {
    let range: GrowthRange
    @Environment(GrowthStore.self) private var store

    private var delta: Int64? {
        guard let c = store.current, let b = store.baseline else { return nil }
        return c.diskUsed - b.diskUsed
    }

    var body: some View {
        let points = Array(store.snapshots.suffix(30))

        VStack(alignment: .leading, spacing: 8) {
            Text(L("Used space · \(points.count) \(points.count == 1 ? "day" : "days")",
                   "Dung lượng đã dùng · \(points.count) ngày"))
                .font(.system(size: 12.5))
                .foregroundStyle(DS.text2)
            if let d = delta {
                (Text(Fmt.delta(d)).font(.system(size: 28, weight: .bold)).foregroundColor(deltaColor(d))
                    + Text("  " + compareLabel).font(.system(size: 14, weight: .medium)).foregroundColor(DS.text2))
                    .monospacedDigit()
            } else {
                Text("—").font(.system(size: 28, weight: .bold)).foregroundStyle(DS.text3)
            }

            if points.count < 2 {
                Text(points.isEmpty
                     ? L("No data yet. Click “Analyze Now” to take the first snapshot.",
                         "Chưa có số liệu. Nhấn “Phân tích ngay” để chụp lần đầu.")
                     : L("Today’s data is in. Starting tomorrow, Yeet can compare growth day by day.",
                         "Đã có số liệu hôm nay. Từ ngày mai Yeet sẽ so sánh được mức tăng theo ngày."))
                    .font(.system(size: 13))
                    .foregroundStyle(DS.text2)
                    .frame(maxWidth: .infinity, minHeight: 170)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.inputBg))
            } else {
                chart(points).frame(height: 190)
            }
        }
        .padding(18)
        .card()
    }

    private var compareLabel: String {
        switch range {
        case .yesterday: return L("vs previous snapshot", "so với lần chụp trước")
        case .week: return L("vs 7 days ago", "so với 7 ngày trước")
        case .month: return L("vs 30 days ago", "so với 30 ngày trước")
        }
    }

    private func chart(_ points: [SnapshotInfo]) -> some View {
        let values = points.map { Double($0.diskUsed) / 1e9 }
        let lo = max(0, (values.min() ?? 0) - 1)
        let hi = (values.max() ?? 1) + 1
        let baseDate = points.first { $0.id == store.baselineID }?.date

        return Chart {
            ForEach(points) { p in
                AreaMark(x: .value(L("Date", "Ngày"), p.date, unit: .day),
                         yStart: .value("GB", lo),
                         yEnd: .value("GB", Double(p.diskUsed) / 1e9))
                    .foregroundStyle(LinearGradient(colors: [growColor.opacity(0.45), growColor.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value(L("Date", "Ngày"), p.date, unit: .day),
                         y: .value("GB", Double(p.diskUsed) / 1e9))
                    .foregroundStyle(growColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let baseDate {
                RuleMark(x: .value(L("Baseline", "Mốc"), baseDate, unit: .day))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(L("Baseline", "Mốc so sánh"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(DS.text)
                    }
            }
        }
        .chartYScale(domain: lo...hi)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let g = v.as(Double.self) { Text("\(Int(g)) GB").foregroundStyle(DS.text3) }
                }
            }
        }
        .chartXAxis {
            // Snapshots are not one per day (the Mac may be off), so let Charts pick ~5 readable dates
            // instead of a label per day, which piled up into an unreadable strip.
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits)).foregroundStyle(DS.text3)
            }
        }
        .chartPlotStyle { $0.clipped() }
        .environment(\.locale, AppLanguage.current.locale)
    }
}

// MARK: - Health tiles

private struct HealthTiles: View {
    private var health: HealthStore { .shared }
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            tile(symbol: "battery.75", c1: 0x45D6A0, c2: 0x17936A,
                 title: L("Battery", "Pin"),
                 value: health.battery?.maxCapacityPct.map { "\($0)%" } ?? L("None", "Không có"),
                 note: batteryNote,
                 status: health.battery?.conditionLabel)
            tile(symbol: "internaldrive.fill", c1: 0x62A2FF, c2: 0x2D5FD8,
                 title: L("Storage", "Ổ đĩa"),
                 value: Fmt.size(model.disk.free),
                 note: L("free of \(Fmt.capacity(model.disk.total))", "trống trên \(Fmt.capacity(model.disk.total))"),
                 status: model.disk.total > 0 && Double(model.disk.free) / Double(model.disk.total) < 0.05
                    ? L("Low", "Sắp đầy") : L("OK", "Tốt"))
            tile(symbol: "thermometer.medium", c1: 0xFFA552, c2: 0xE0611D,
                 title: L("Thermal", "Nhiệt độ máy"),
                 value: health.thermalLabel,
                 note: L("Reported by the system", "Do hệ thống báo"),
                 status: health.thermal == .nominal || health.thermal == .fair ? L("Cool", "Mát") : L("Hot", "Nóng"))
        }
        .onTapGesture { model.select(Module.health) }
        .help(L("Open System Health", "Mở Sức khoẻ máy"))
    }

    private var batteryNote: String {
        guard let b = health.battery else { return L("No battery", "Không có pin") }
        guard let c = b.cycles else { return b.conditionLabel }
        if let d = b.designCycles { return L("\(c) of \(Fmt.count(d)) cycles", "\(c) / \(Fmt.count(d)) lần sạc") }
        return L("\(c) cycles", "\(c) lần sạc")
    }

    private func tile(symbol: String, c1: UInt32, c2: UInt32, title: String, value: String,
                      note: String, status: String?) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: c1), Color(hex: c2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12)).foregroundStyle(DS.text2)
                Text(value).font(.system(size: 19, weight: .bold)).monospacedDigit().foregroundStyle(DS.text).lineLimit(1)
                Text(note).font(.system(size: 11.5)).foregroundStyle(DS.text3).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let status { Chip(text: status, tint: DS.success) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Folders that changed most

private struct ChangedFoldersCard: View {
    @Environment(GrowthStore.self) private var store
    @Environment(AppModel.self) private var model

    /// The folders that explain the change best: biggest |delta| first, dropping a parent when one
    /// of its children accounts for most (≥ 80 %) of its change.
    private var rows: [GrowthNode] {
        var all: [GrowthNode] = []
        func walk(_ n: GrowthNode, depth: Int) {
            if depth > 0 { all.append(n) }
            n.children.forEach { walk($0, depth: depth + 1) }
        }
        store.tree.forEach { walk($0, depth: 0) }
        let explained = Set(all.filter { n in
            n.children.contains { c in n.delta != 0 && Double(c.delta) / Double(n.delta) >= 0.8 }
        }.map(\.id))
        return Array(all.filter { !explained.contains($0.id) && $0.delta != 0 }
            .sorted { abs($0.delta) > abs($1.delta) }
            .prefix(10))
    }

    var body: some View {
        let list = rows
        let peak = max(1, list.map { abs($0.delta) }.max() ?? 1)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("Folders that changed most", "Thư mục thay đổi nhiều nhất"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(DS.text3)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.divider).frame(height: 1) }

            if list.isEmpty {
                Text(store.baseline == nil
                     ? L("At least two snapshots on different days are needed to compare.",
                         "Cần ít nhất hai lần chụp ở hai ngày khác nhau để so sánh.")
                     : L("No folder changed by more than 10 MB.", "Không có thư mục nào thay đổi quá 10 MB."))
                    .font(.system(size: 13))
                    .foregroundStyle(DS.text2)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }

            ForEach(list) { n in
                let tool = cleanableTool(n.id)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(DS.text).lineLimit(1)
                        Text(n.displayPath).font(DS.mono(11)).foregroundStyle(DS.text3).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { g in
                        Capsule()
                            .fill(n.delta > 0
                                  ? AnyShapeStyle(LinearGradient(colors: [growColor, Color(hex: 0xFF7A9A)], startPoint: .leading, endPoint: .trailing))
                                  : AnyShapeStyle(shrinkColor.opacity(0.8)))
                            .frame(width: max(4, g.size.width * CGFloat(Double(abs(n.delta)) / Double(peak))))
                    }
                    .frame(width: 200, height: 8)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    Text(Fmt.delta(n.delta))
                        .font(.system(size: 13.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(deltaColor(n.delta))
                        .frame(width: 90, alignment: .trailing)
                    if let tool {
                        Button(L("Clean →", "Dọn →")) { model.select(.tool(tool)) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(DS.text)
                            .frame(width: 70, alignment: .trailing)
                    } else {
                        Button(L("Show →", "Xem →")) { NSWorkspace.shared.activateFileViewerSelecting([n.url]) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(DS.text2)
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(DS.rowDivider).frame(height: 1) }
            }
        }
        .card()
    }

    private var subtitle: String {
        guard let b = store.baseline else { return "" }
        return L("since \(Fmt.date(b.date)) · changes over 10 MB", "từ \(Fmt.date(b.date)) · thay đổi trên 10 MB")
    }

    /// The Yeet cache tool that owns caches inside (or containing) this folder, if any.
    private func cleanableTool(_ path: String) -> ToolKind? {
        let p = path.hasSuffix("/") ? path : path + "/"
        for leaf in model.allLeaves where leaf.leafSize > 0 {
            let l = leaf.url.standardizedFileURL.path
            if (l + "/").hasPrefix(p) || p.hasPrefix(l + "/") { return leaf.tool }
        }
        return nil
    }
}

/// Tells the user which folders weren't measured.
private struct NotMeasuredBanner: View {
    let names: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.slash").font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Not measured: \(names.joined(separator: ", "))", "Chưa đo: \(names.joined(separator: ", "))"))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(L("Yeet can’t read other apps’ data. Growth there is counted as “System, unmeasured & other”.",
                       "Yeet không đọc được dữ liệu của ứng dụng khác. Mức tăng ở đó được tính vào “Hệ thống, chưa đo & khác”."))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .foregroundStyle(DS.warning)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.warning.opacity(0.12)))
    }
}

// MARK: - Action bar

private struct GrowthActionBar: View {
    @Environment(GrowthStore.self) private var store

    var body: some View {
        ActionBar {
            SelectionSummary(
                title: store.lastCaptureDate.map { L("Last snapshot: \(Fmt.modified($0))", "Lần chụp gần nhất: \(Fmt.modified($0))") }
                    ?? L("No snapshots yet", "Chưa có lần chụp nào"),
                detail: L("Captured daily while Yeet runs · kept for \(GrowthStore.keepDays) days · \(store.snapshots.count) \(store.snapshots.count == 1 ? "snapshot" : "snapshots")",
                          "Tự chụp mỗi ngày khi Yeet chạy · giữ \(GrowthStore.keepDays) ngày · \(store.snapshots.count) lần chụp"))
        } actions: {
            if store.isCapturing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.isCancelling
                         ? L("Stopping…", "Đang dừng…")
                         : L("Analyzing… \(Fmt.count(store.progressFiles)) files", "Đang phân tích… \(Fmt.count(store.progressFiles)) tệp"))
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(DS.text2)
                }
            } else {
                Button(L("Analyze Now", "Phân tích ngay")) { store.capture() }
                    .buttonStyle(FilledButtonStyle())
            }
        }
    }
}
