import SwiftUI

/// "Uninstaller": every app with its icon, details and leftovers, in one full-width table.
/// Clicking a row expands it inline to show (and pick) the leftovers that go with it.
@MainActor
struct AppsView: View {
    @Environment(AppModel.self) private var model
    @State private var appsGranted = ApplicationsAccess.isGranted
    @State private var tab: AppsTab = .apps

    private var intelAppCount: Int { store.apps.filter { $0.arch == .intel }.count }

    private var store: UninstallerStore { UninstallerStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(Module.apps.title, subtitle: subtitle) {
                HStack(spacing: 10) {
                    SegmentedPill(selection: $tab, options: [
                        (value: AppsTab.apps, label: L("Apps", "Ứng dụng")),
                        (value: AppsTab.extensions, label: L("Editor Extensions", "Extension của editor")),
                    ])
                    .fixedSize()
                    if tab == .apps {
                        Button {
                            store.scan()
                        } label: {
                            Label(L("Rescan", "Quét lại"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(OutlineButtonStyle())
                        .disabled(store.scanning)
                        .fixedSize()
                    }
                }
            }

            // Toolbar row: room for the search field and full-width sort labels.
            HStack(spacing: 12) {
                searchField
                if tab == .apps {
                    Spacer(minLength: 12)
                    Text(L("Sort by", "Sắp xếp theo"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.text2)
                    SegmentedPill(selection: Binding(get: { store.sort }, set: { store.sort = $0 }),
                                  options: AppSort.allCases.map { (value: $0, label: $0.title) })
                        .fixedSize()
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            VStack(spacing: 12) {
                if tab == .apps {
                    if !appsGranted {
                        grantBanner
                    }
                    if store.scanned && intelAppCount > 0 {
                        RosettaBanner(text: L("\(intelAppCount) apps are built only for Intel and run through Rosetta, which Apple is phasing out in a future macOS. Look for an Apple silicon update, or check the Editor Extensions tab for extensions with the same problem.",
                                              "\(intelAppCount) ứng dụng chỉ build cho Intel và chạy nhờ Rosetta, mà Apple sẽ ngừng hỗ trợ ở một bản macOS tới. Hãy tìm bản cập nhật cho Apple silicon, và xem tab Extension của editor để kiểm tra extension gặp cùng vấn đề."))
                    }
                    content
                } else {
                    ExtensionsPanel(search: store.search)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if tab == .extensions {
                ExtensionsActionBar()
            } else if store.scanned {
                actionBar
            }
        }
        .onAppear {
            appsGranted = ApplicationsAccess.isGranted
            if !store.scanned && !store.scanning { store.scan() }
        }
    }

    private var subtitle: String {
        if !store.scanned {
            return store.scanning ? L("Looking for apps…", "Đang tìm ứng dụng…")
                : L("Apps and the files they leave behind", "Ứng dụng và các file chúng để lại")
        }
        let n = store.appCount
        return L("\(n == 1 ? "1 app" : "\(Fmt.count(n)) apps") · \(Fmt.size(store.total)) including their data",
                 "\(Fmt.count(n)) ứng dụng · \(Fmt.size(store.total)) gồm cả dữ liệu")
    }

    // MARK: Header controls

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.text3)
            TextField(tab == .apps ? L("Search apps", "Tìm ứng dụng") : L("Search extensions", "Tìm extension"),
                      text: Binding(get: { store.search }, set: { store.search = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.text)
            if !store.search.isEmpty {
                Button {
                    store.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Clear search", "Xoá tìm kiếm"))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 260, height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.inputBg))
    }

    // MARK: Grant step

    private var grantBanner: some View {
        HStack(spacing: 12) {
            HueTile(symbol: "folder.badge.plus", size: 32, glyph: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Grant access to Applications", "Cấp quyền thư mục Applications"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text(L("macOS asks you once before Yeet can move apps out of /Applications. Choose the Applications folder in the next window.",
                       "macOS cần bạn cho phép một lần trước khi Yeet có thể chuyển ứng dụng khỏi /Applications. Hãy chọn thư mục Applications trong cửa sổ tiếp theo."))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(L("Grant Access…", "Cấp quyền…")) {
                appsGranted = ApplicationsAccess.request()
            }
            .buttonStyle(FilledButtonStyle())
        }
        .padding(14)
        .card()
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if store.scanning && store.apps.isEmpty {
            ModuleEmptyState(symbol: "app.badge", title: L("Looking for apps…", "Đang tìm ứng dụng…"),
                             message: L("Reading /Applications and the files apps keep in ~/Library.",
                                        "Đang đọc /Applications và các file ứng dụng lưu trong ~/Library."),
                             busy: true)
                .card()
        } else if store.scanned && store.apps.isEmpty {
            ModuleEmptyState(symbol: "app.badge",
                             title: L("No apps to uninstall", "Không có ứng dụng nào để gỡ"),
                             message: L("Apple's apps and Yeet itself are never listed.",
                                        "Ứng dụng của Apple và chính Yeet không bao giờ được liệt kê."))
                .card()
        } else {
            AppsTable()
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        let n = store.checked.count
        return ActionBar {
            SelectionSummary(
                title: n == 0 ? L("No apps selected", "Chưa chọn ứng dụng nào")
                    : L("\(n == 1 ? "1 app" : "\(n) apps") selected · \(Fmt.size(store.selectedSize))",
                        "Đã chọn \(n) ứng dụng · \(Fmt.size(store.selectedSize))"),
                detail: L("Yeet quits nothing: quit apps first, then they go to the Trash",
                          "Yeet không tự thoát ứng dụng: hãy thoát trước, rồi chúng sẽ vào Thùng rác"))
        } actions: {
            Button(L("Deselect", "Bỏ chọn")) { store.checked.removeAll() }
                .buttonStyle(OutlineButtonStyle(height: 36))
                .disabled(n == 0)
            Button(L("Uninstall…", "Gỡ cài đặt…")) { requestUninstall() }
                .buttonStyle(FilledButtonStyle())
                .disabled(n == 0 || store.scanning)
        }
    }

    private func requestUninstall() {
        let apps = store.selectedApps
        guard !apps.isEmpty else { return }
        var items: [ReviewItem] = []
        for app in apps {
            items.append(ReviewItem(id: app.id, title: app.name, detail: Paths.tilde(app.url),
                                    size: app.appSize, method: .trash))
            for l in store.chosenLeftovers(app) {
                let kind = l.isUserData ? "\(l.kind.title) · \(L("Your data", "Dữ liệu của bạn"))" : l.kind.title
                items.append(ReviewItem(id: l.id, title: "\(app.name) · \(kind)", detail: Paths.tilde(l.url),
                                        size: l.size, method: .trash))
            }
        }
        var warnings: [String] = []
        let running = store.runningSelected.map(\.name)
        if !running.isEmpty {
            warnings.append(L("Running: \(running.joined(separator: ", ")). Quit \(running.count == 1 ? "it" : "them") (⌘Q) first; running apps are skipped.",
                              "Đang chạy: \(running.joined(separator: ", ")). Hãy thoát (⌘Q) trước; ứng dụng đang chạy sẽ bị bỏ qua."))
        }
        let blocked = apps.filter { $0.inApplicationsFolder }.map(\.name)
        if !ApplicationsAccess.isGranted && !blocked.isEmpty {
            warnings.append(L("Grant access to Applications first, or \(blocked.joined(separator: ", ")) will be skipped.",
                              "Hãy cấp quyền thư mục Applications trước, nếu không \(blocked.joined(separator: ", ")) sẽ bị bỏ qua."))
        }
        let model = self.model
        model.review = ReviewRequest(
            title: L("Uninstall Apps", "Gỡ ứng dụng"),
            items: items,
            warnings: warnings,
            confirmLabel: L("Move to Trash", "Chuyển vào Thùng rác"),
            perform: {
                model.review = nil
                let out = UninstallerStore.shared.uninstallSelected()
                let failed = !out.failures.isEmpty || !out.skippedRunning.isEmpty || !out.needsAccess.isEmpty
                model.showToast(out.message, seconds: failed ? 6 : 3)
            })
    }
}

// MARK: - Table

@MainActor
private struct AppsTable: View {
    private var store: UninstallerStore { UninstallerStore.shared }

    let versionWidth: CGFloat = 90
    let archWidth: CGFloat = 120
    let dateWidth: CGFloat = 110
    let dataWidth: CGFloat = 80
    let totalWidth: CGFloat = 84

    var body: some View {
        let rows = store.visibleApps
        VStack(spacing: 0) {
            header
            if rows.isEmpty {
                ModuleEmptyState(symbol: "magnifyingglass", title: L("No matches", "Không có kết quả"),
                                 message: L("No app matches “\(store.search)”.", "Không có ứng dụng nào khớp “\(store.search)”."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { app in
                            AppRow(app: app, widths: widths)
                            if store.expanded == app.id {
                                LeftoverPanel(app: app)
                            }
                            Rectangle().fill(DS.rowDivider).frame(height: 1)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    private var widths: AppRow.Widths {
        AppRow.Widths(version: versionWidth, arch: archWidth, date: dateWidth, data: dataWidth, total: totalWidth)
    }

    private var header: some View {
        HStack(spacing: 12) {
            CheckboxView(state: store.headerState) { store.toggleAllVisible() }
            columnButton(L("APP", "ỨNG DỤNG"), sort: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            OverlineText(L("VERSION", "PHIÊN BẢN"))
                .frame(width: versionWidth, alignment: .leading)
            OverlineText(L("ARCHITECTURE", "KIẾN TRÚC"))
                .frame(width: archWidth, alignment: .leading)
            columnButton(L("LAST OPENED", "MỞ LẦN CUỐI"), sort: .lastUsed)
                .frame(width: dateWidth, alignment: .leading)
            OverlineText(L("DATA", "DỮ LIỆU"))
                .frame(width: dataWidth, alignment: .trailing)
            columnButton(L("TOTAL", "TỔNG"), sort: .size)
                .frame(width: totalWidth, alignment: .trailing)
            Color.clear.frame(width: 12, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.divider).frame(height: 1) }
    }

    private func columnButton(_ title: String, sort: AppSort) -> some View {
        let active = store.sort == sort
        return Button {
            store.sort = sort
        } label: {
            HStack(spacing: 3) {
                OverlineText(title)
                if active {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.text2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct AppRow: View {
    struct Widths {
        let version: CGFloat
        let arch: CGFloat
        let date: CGFloat
        let data: CGFloat
        let total: CGFloat
    }

    let app: InstalledApp
    let widths: Widths
    @State private var hovering = false

    init(app: InstalledApp, widths: Widths) {
        self.app = app
        self.widths = widths
    }

    private var store: UninstallerStore { UninstallerStore.shared }

    /// Not opened for six months.
    private var isOld: Bool {
        guard let d = app.lastUsed else { return true }
        return Date().timeIntervalSince(d) > 180 * 86_400
    }

    private var archTint: Color {
        switch app.arch {
        case .universal: return Color(hex: 0x9CC4FF)
        case .appleSilicon: return DS.success
        case .intel: return DS.warning
        case .unknown: return .white
        }
    }

    var body: some View {
        let expanded = store.expanded == app.id
        HStack(spacing: 12) {
            CheckboxView(state: store.checked.contains(app.id) ? .checked : .unchecked) { store.toggleApp(app) }
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    Text(app.source.title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.text3)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(app.version.isEmpty ? "—" : app.version)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(DS.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: widths.version, alignment: .leading)
            HStack(spacing: 0) {
                if app.arch == .unknown {
                    Text("—").font(.system(size: 12)).foregroundStyle(DS.text3)
                } else {
                    Chip(text: app.arch.title, tint: archTint)
                }
                Spacer(minLength: 0)
            }
            .frame(width: widths.arch, alignment: .leading)
            Text(app.lastUsed.map { Fmt.modified($0) } ?? L("Unknown", "Không rõ"))
                .font(.system(size: 12))
                .foregroundStyle(isOld ? DS.warning : DS.text2)
                .lineLimit(1)
                .frame(width: widths.date, alignment: .leading)
            Text(app.dataSize > 0 ? Fmt.size(app.dataSize) : "—")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(DS.text2)
                .frame(width: widths.data, alignment: .trailing)
            Text(Fmt.size(app.totalSize))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DS.text)
                .frame(width: widths.total, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.text3)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(expanded ? DS.surfaceStrong.opacity(0.7) : (hovering ? DS.surface : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) { store.toggleExpanded(app) }
        }
        .contextMenu {
            Button(L("Reveal in Finder", "Hiện trong Finder")) { FileOps.reveal(app.url) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(L("Click to show the files this app leaves behind", "Nhấp để xem các file ứng dụng này để lại"))
    }
}

@MainActor
private struct LeftoverPanel: View {
    let app: InstalledApp

    private var store: UninstallerStore { UninstallerStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if app.leftovers.isEmpty {
                Text(L("No leftovers found in ~/Library. Only the app itself will be removed.",
                       "Không thấy file sót lại trong ~/Library. Chỉ ứng dụng sẽ bị gỡ."))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text3)
                    .padding(.vertical, 8)
            } else {
                ForEach(app.leftovers) { l in
                    leftoverRow(l)
                }
                if app.leftovers.contains(where: { $0.isUserData }) {
                    Label(L("Items marked Your data are kept unless you tick them",
                            "Mục đánh dấu Dữ liệu của bạn sẽ được giữ lại trừ khi bạn tích chọn"),
                          systemImage: "lock.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.text3)
                        .padding(.top, 8)
                }
            }
        }
        .padding(.leading, 76)
        .padding(.trailing, 44)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceStrong.opacity(0.35))
    }

    private func leftoverRow(_ l: Leftover) -> some View {
        let on = store.selectedLeftovers.contains(l.id)
        return HStack(spacing: 10) {
            CheckboxView(state: on ? .checked : .unchecked) { store.toggleLeftover(l) }
            Chip(text: l.isUserData ? "\(l.kind.title) · \(L("Your data", "Dữ liệu của bạn"))" : l.kind.title,
                 tint: l.isUserData ? DS.danger : .white)
            Text(Paths.tilde(l.url))
                .font(DS.mono(11.5))
                .foregroundStyle(DS.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(l.url.path)
            Text(Fmt.size(l.size))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(DS.text2)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { store.toggleLeftover(l) }
        .contextMenu {
            Button(L("Reveal in Finder", "Hiện trong Finder")) { FileOps.reveal(l.url) }
        }
    }
}


enum AppsTab: Hashable {
    case apps, extensions
}
