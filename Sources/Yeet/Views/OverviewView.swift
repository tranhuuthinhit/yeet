import SwiftUI

/// Dashboard: disk breakdown, the biggest things worth cleaning across every module,
/// a 7-day growth strip and a health summary.
@MainActor
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(GrowthStore.self) private var growth
    @AppStorage("confirmBeforeClean") private var confirmBeforeClean = true

    private var large: LargeFilesStore { .shared }
    private var dupes: DuplicatesStore { .shared }
    private var browsers: BrowsersStore { .shared }
    private var health: HealthStore { .shared }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(Module.overview.title, subtitle: subtitle) {
                Button {
                    scanEverything()
                } label: {
                    HStack(spacing: 6) {
                        SpinningIcon(systemName: "arrow.clockwise", active: isBusy)
                        Text(isBusy ? L("Scanning…", "Đang quét…") : L("Scan Everything", "Quét tất cả"))
                    }
                }
                .buttonStyle(OutlineButtonStyle(height: 32, fontSize: 13, horizontalPadding: 12))
                .disabled(isBusy)
                .help(L("Scan caches, large files, duplicates and browsers", "Quét cache, file lớn, file trùng và trình duyệt"))
            }

            ScrollView {
                VStack(spacing: 16) {
                    DiskCard(segments: segments, reclaimable: safeReclaimable)
                    HStack(alignment: .top, spacing: 16) {
                        Recommendations()
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 16) {
                            GrowthMini()
                            HealthMini()
                        }
                        .frame(width: 320)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            CacheActionBar(module: .overview)
        }
        .onAppear {
            if !health.loaded { health.refresh() }
        }
    }

    private var isBusy: Bool {
        model.phase == .scanning || large.scanning || dupes.scanning || browsers.scanning
    }

    private var subtitle: String {
        L("Everything Yeet can clean, in one place", "Mọi thứ Yeet dọn được, ở cùng một chỗ")
    }

    private func scanEverything() {
        model.rescan()
        if !large.scanning { large.scan() }
        if !dupes.scanning { dupes.scan() }
        if !browsers.scanning { browsers.scan() }
        health.refresh()
    }

    private var safeReclaimable: Int64 { model.safeTotal }

    private var segments: [DiskSegment] {
        let disk = model.disk
        let used = max(0, disk.total - disk.free)
        let dev = model.moduleNode(.devCaches).size
        let junk = model.moduleNode(.systemJunk).size
        let big = large.scanned ? large.total : 0
        let dup = dupes.scanned ? dupes.total : 0
        let web = browsers.scanned ? browsers.total : 0
        let other = max(0, used - dev - junk - big - dup - web)
        return [
            DiskSegment(name: Module.devCaches.title, bytes: dev, color: Color(hex: 0x45D6A0)),
            DiskSegment(name: Module.systemJunk.title, bytes: junk, color: Color(hex: 0xF7C04F)),
            DiskSegment(name: Module.largeFiles.title, bytes: big, color: Color(hex: 0xFFA552)),
            DiskSegment(name: Module.duplicates.title, bytes: dup, color: Color(hex: 0xA48CFF)),
            DiskSegment(name: Module.browsers.title, bytes: web, color: Color(hex: 0x62CCF7)),
            DiskSegment(name: L("Everything else", "Phần còn lại"), bytes: other, color: Color(hex: 0xC9CFDB)),
            DiskSegment(name: L("Free", "Trống"), bytes: disk.free, color: Color.white.opacity(0.16)),
        ]
    }
}

struct DiskSegment: Identifiable {
    let name: String
    let bytes: Int64
    let color: Color
    var id: String { name }
}

// MARK: - Disk card

private struct DiskCard: View {
    let segments: [DiskSegment]
    let reclaimable: Int64
    @Environment(AppModel.self) private var model

    var body: some View {
        let disk = model.disk
        let total = max(Double(disk.total), 1)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(disk.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.text2)
                    (Text(Fmt.size(disk.free)).font(.system(size: 30, weight: .bold))
                        + Text(L("  free of \(Fmt.capacity(disk.total))", "  trống trên \(Fmt.capacity(disk.total))"))
                            .font(.system(size: 15, weight: .medium)).foregroundColor(DS.text2))
                        .foregroundStyle(DS.text)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("Safe to free up", "Có thể giải phóng an toàn")).font(.system(size: 12.5)).foregroundStyle(DS.text2)
                    Text(Fmt.size(reclaimable))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(DS.success)
                }
            }

            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(segments) { s in
                        let w = g.size.width * CGFloat(Double(s.bytes) / total)
                        if w >= 1 {
                            Rectangle().fill(s.color).frame(width: w)
                        }
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Disk usage by category", "Phân bổ dung lượng ổ đĩa"))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 18, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(segments) { s in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: 10, height: 10)
                        Text(s.name).font(.system(size: 12.5)).foregroundStyle(DS.text2).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Fmt.size(s.bytes)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(DS.text)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .card()
    }
}

// MARK: - Recommendations

private struct Recommendations: View {
    @Environment(AppModel.self) private var model

    private struct Shortcut: Identifiable {
        let module: Module
        let detail: String
        let bytes: Int64
        var id: String { module.rawValue }
    }

    var body: some View {
        let leaves = Array(model.allLeaves.filter { $0.leafSize > 0 }.sorted { $0.leafSize > $1.leafSize }.prefix(7))

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Worth Cleaning", "Nên dọn")).font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.text)
                Text(L("Largest first, from every module", "Lớn nhất trước, từ mọi mục"))
                    .font(.system(size: 12.5)).foregroundStyle(DS.text3)
                Spacer()
                Button(L("See all", "Xem tất cả")) { model.select(.devCaches) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DS.text)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.divider).frame(height: 1) }

            if leaves.isEmpty && shortcuts.isEmpty {
                ModuleEmptyState(symbol: "sparkles", title: model.phase == .scanning ? L("Scanning…", "Đang quét…") : L("Nothing to clean yet", "Chưa có gì để dọn"),
                                 message: L("Run “Scan Everything” to look through caches, files and browsers.",
                                            "Bấm “Quét tất cả” để tìm trong cache, file và trình duyệt."),
                                 busy: model.phase == .scanning)
                    .frame(height: 220)
            }

            ForEach(leaves) { n in
                HStack(spacing: 12) {
                    CheckboxView(state: model.checkState(n)) { model.toggleCheck(n) }
                    ToolTile(color: n.tool.color, symbol: n.tool.symbol, size: 28, radius: 8, glyph: 13)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(n.tool.name) · \(n.name)").font(.system(size: 13.5, weight: .medium)).foregroundStyle(DS.text).lineLimit(1)
                        Text(n.path).font(DS.mono(11.5)).foregroundStyle(DS.text3).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if let r = n.risk { RiskBadge(risk: r) }
                    Text(Fmt.size(n.leafSize))
                        .font(.system(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(DS.text)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.select(.tool(n.tool)); model.focus(n.id) }
                .overlay(alignment: .bottom) { Rectangle().fill(DS.rowDivider).frame(height: 1) }
            }

            ForEach(shortcuts) { s in
                Button {
                    model.select(s.module)
                } label: {
                    HStack(spacing: 12) {
                        Color.clear.frame(width: 18, height: 18)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(s.module.hue.tile)
                            .frame(width: 28, height: 28)
                            .overlay(Image(systemName: s.module.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.module.title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(DS.text)
                            Text(s.detail).font(.system(size: 12)).foregroundStyle(DS.text3).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(Fmt.size(s.bytes))
                            .font(.system(size: 13.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(DS.text)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.text3)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Rectangle().fill(DS.rowDivider).frame(height: 1) }
            }
        }
        .card()
    }

    private var shortcuts: [Shortcut] {
        var out: [Shortcut] = []
        let large = LargeFilesStore.shared
        if large.scanned && large.total > 0 {
            out.append(Shortcut(module: .largeFiles, detail: L("Review and move to the Trash", "Xem và chuyển vào Thùng rác"), bytes: large.total))
        }
        let dupes = DuplicatesStore.shared
        if dupes.scanned && dupes.total > 0 {
            out.append(Shortcut(module: .duplicates, detail: L("Extra copies of the same file", "Bản sao thừa của cùng một file"), bytes: dupes.total))
        }
        let web = BrowsersStore.shared
        if web.scanned && web.total > 0 {
            out.append(Shortcut(module: .browsers, detail: L("Caches and on-device AI models", "Cache và mô hình AI trên máy"), bytes: web.total))
        }
        return out.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Growth strip

private struct GrowthMini: View {
    @Environment(GrowthStore.self) private var growth
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = Array(growth.snapshots.sorted { $0.date < $1.date }.suffix(8))
        let deltas: [Int64] = days.count < 2 ? [] : (1..<days.count).map { days[$0].diskUsed - days[$0 - 1].diskUsed }
        let week = deltas.reduce(Int64(0), +)
        let peak = max(1, deltas.map { abs($0) }.max() ?? 1)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Last 7 days", "7 ngày qua")).font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.text)
                Spacer()
                Button(L("Details", "Chi tiết")) { model.select(Module.growth) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DS.text)
            }
            if deltas.isEmpty {
                Text(L("Yeet measures your disk once a day. Come back tomorrow to see what grew.",
                       "Yeet đo ổ đĩa mỗi ngày một lần. Ngày mai quay lại để xem phần nào tăng."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Fmt.delta(week))
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(week > 0 ? Color(hex: 0xFFC2A0) : DS.success)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(deltas.indices, id: \.self) { i in
                        let v = deltas[i]
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(v > 0 ? Color(hex: 0xFF9A6A).opacity(Double(abs(v)) / Double(peak) > 0.5 ? 1 : 0.5)
                                        : DS.success.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(4, 44 * CGFloat(Double(abs(v)) / Double(peak))))
                    }
                }
                .frame(height: 48, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Daily change in used space", "Dung lượng thay đổi mỗi ngày"))
                if let cause = GrowthScanner.topCause(growth.tree) {
                    (Text(L("Grew most: ", "Tăng nhiều nhất: ")).foregroundColor(DS.text2)
                        + Text(cause.name).font(DS.mono(11.5))
                        + Text("  " + Fmt.delta(cause.delta)).bold().foregroundColor(Color(hex: 0xFFC2A0)))
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Health summary

private struct HealthMini: View {
    @Environment(AppModel.self) private var model
    private var health: HealthStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Module.health.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.text)
                Spacer()
                Button(L("Details", "Chi tiết")) { model.select(.health) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DS.text)
            }
            row(L("Battery", "Pin"), health.batterySummary ?? L("No battery", "Không có pin"))
            row(L("Temperature", "Nhiệt độ"), health.thermalLabel)
            row(L("Free space", "Dung lượng trống"), Fmt.size(model.disk.free))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(DS.text2)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit().foregroundStyle(DS.text)
        }
        .font(.system(size: 13))
    }
}
