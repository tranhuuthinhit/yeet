import SwiftUI

/// "Browsers": caches, AI models and website data kept by Chromium-family browsers.
/// Passwords, cookies, history, bookmarks, extensions and sign-ins are never listed.
@MainActor
struct BrowsersView: View {
    @Environment(AppModel.self) private var model

    private var store: BrowsersStore { BrowsersStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(Module.browsers.title, subtitle: subtitle) {
                HStack(spacing: 12) {
                    Label(L("Passwords, cookies, history, bookmarks, extensions and sign-ins are never touched",
                            "Mật khẩu, cookie, lịch sử, dấu trang, tiện ích và đăng nhập không bao giờ bị động đến"),
                          systemImage: "lock.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.text3)
                        .lineLimit(2)
                        .frame(maxWidth: 320, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                    Button {
                        store.scan()
                    } label: {
                        Label(L("Rescan", "Quét lại"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(store.scanning)
                }
            }

            content
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if store.scanned && !store.browsers.isEmpty {
                actionBar
            }
        }
        .onAppear {
            store.refreshRunning()
            if !store.scanned && !store.scanning { store.scan() }
        }
    }

    private var subtitle: String {
        guard store.scanned else {
            return L("Caches, AI models and website data your browsers keep",
                     "Cache, mô hình AI và dữ liệu web trình duyệt lưu lại")
        }
        let n = store.browserCount
        return L("\(Fmt.size(store.total)) kept by \(n == 1 ? "1 browser" : "\(n) browsers")",
                 "\(Fmt.size(store.total)) do \(n) trình duyệt lưu")
    }

    @ViewBuilder
    private var content: some View {
        if store.scanning && store.browsers.isEmpty {
            ModuleEmptyState(symbol: "globe", title: L("Looking at your browsers…", "Đang xem các trình duyệt…"), busy: true)
                .card()
        } else if store.scanned && store.browsers.isEmpty {
            ModuleEmptyState(symbol: "globe",
                             title: L("No supported browsers found", "Không tìm thấy trình duyệt được hỗ trợ"),
                             message: L("Yeet cleans Chrome, Brave, Edge, Arc, Vivaldi, Opera and Chromium.",
                                        "Yeet dọn Chrome, Brave, Edge, Arc, Vivaldi, Opera và Chromium."))
                .card()
        } else {
            HStack(alignment: .top, spacing: 16) {
                BrowserList()
                    .frame(width: 260)
                BrowserDetail()
            }
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        let n = store.selectedItems.count
        let runningNames = store.browsersWithSelection.filter { store.isRunning($0) }.map(\.name)
        let detail: String = runningNames.isEmpty
            ? L("Caches are deleted; AI models and website data go to the Trash",
                "Cache bị xoá; mô hình AI và dữ liệu web vào Thùng rác")
            : L("\(runningNames.joined(separator: ", ")) is open: quit it first or it will be skipped",
                "\(runningNames.joined(separator: ", ")) đang mở: hãy thoát trước, nếu không sẽ bị bỏ qua")
        return ActionBar {
            VStack(alignment: .leading, spacing: 2) {
                SelectionSummary(
                    title: n == 0 ? L("Nothing selected", "Chưa chọn mục nào")
                        : L("\(n == 1 ? "1 item" : "\(n) items") selected · \(Fmt.size(store.selectedSize))",
                            "Đã chọn \(n) mục · \(Fmt.size(store.selectedSize))"),
                    detail: runningNames.isEmpty ? detail : nil)
                if !runningNames.isEmpty {
                    Label(detail, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.warning)
                        .lineLimit(1)
                }
            }
        } actions: {
            Button(L("Deselect", "Bỏ chọn")) { store.checked.removeAll() }
                .buttonStyle(OutlineButtonStyle(height: 36))
                .disabled(n == 0)
            Button(L("Clean", "Dọn")) { requestClean() }
                .buttonStyle(FilledButtonStyle())
                .disabled(n == 0 || store.scanning)
        }
    }

    private func requestClean() {
        store.refreshRunning()
        var items: [ReviewItem] = []
        var running: [String] = []
        for b in store.browsersWithSelection {
            if store.isRunning(b) { running.append(b.name) }
            for i in b.items where store.checked.contains(i.id) {
                let profile = i.profile.map { " · \($0)" } ?? ""
                items.append(ReviewItem(id: i.id, title: "\(b.name) · \(i.title)\(profile)",
                                        detail: i.urls.first.map { Paths.tilde($0) } ?? i.detail,
                                        size: i.size, method: i.method))
            }
        }
        guard !items.isEmpty else { return }
        var warnings: [String] = []
        if !running.isEmpty {
            warnings.append(L("\(running.joined(separator: ", ")) is open. Quit it (⌘Q) first, or nothing of it will be cleaned.",
                              "\(running.joined(separator: ", ")) đang mở. Hãy thoát (⌘Q) trước, nếu không sẽ không dọn được gì của nó."))
        }
        let model = self.model
        model.review = ReviewRequest(
            title: L("Clean Browsers", "Dọn trình duyệt"),
            items: items,
            warnings: warnings,
            perform: {
                model.review = nil
                let out = BrowsersStore.shared.clean()
                let failed = !out.failures.isEmpty || !out.skipped.isEmpty
                model.showToast(out.message, seconds: failed ? 6 : 3)
            })
    }
}

// MARK: - Browser list

@MainActor
private struct BrowserList: View {
    private var store: BrowsersStore { BrowsersStore.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(store.browsers) { b in
                    row(b)
                }
            }
            .padding(8)
        }
        .frame(maxHeight: .infinity)
        .card()
    }

    private func row(_ b: BrowserInfo) -> some View {
        let selected = store.current?.id == b.id
        let profiles = b.profiles.count
        return Button {
            store.selectedBrowser = b.id
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: b.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(b.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.text)
                            .lineLimit(1)
                        if store.isRunning(b) {
                            Chip(text: L("Open", "Đang mở"), tint: DS.warning)
                        }
                    }
                    Text(L(profiles == 1 ? "1 profile" : "\(profiles) profiles", "\(profiles) hồ sơ"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(Fmt.size(b.total))
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? DS.surfaceStrong : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Browser detail

@MainActor
private struct BrowserDetail: View {
    private var store: BrowsersStore { BrowsersStore.shared }

    var body: some View {
        Group {
            if let b = store.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            Image(nsImage: b.icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(DS.text)
                                Text(b.profiles.joined(separator: ", "))
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.text3)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Spacer(minLength: 8)
                            Text(Fmt.size(b.total))
                                .font(.system(size: 20, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(DS.text)
                        }
                        if store.isRunning(b) {
                            Label(L("\(b.name) is open. Quit it before cleaning; Yeet never cleans a browser while it runs.",
                                    "\(b.name) đang mở. Hãy thoát trước khi dọn; Yeet không bao giờ dọn trình duyệt đang chạy."),
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(BrowserGroup.allCases, id: \.self) { g in
                            let items = b.items(in: g)
                            if !items.isEmpty {
                                section(g, items: items, total: b.size(of: g))
                            }
                        }
                        if b.items.isEmpty {
                            Text(L("Nothing to clean in this browser.", "Không có gì để dọn trong trình duyệt này."))
                                .font(.system(size: 13))
                                .foregroundStyle(DS.text2)
                        }
                    }
                    .padding(16)
                }
            } else {
                ModuleEmptyState(symbol: "globe", title: L("Choose a browser", "Chọn một trình duyệt"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    private func section(_ g: BrowserGroup, items: [BrowserItem], total: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                CheckboxView(state: store.state(items)) { store.toggleAll(items) }
                HueTile(symbol: g.symbol, size: 24, glyph: 12)
                Text(g.title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(DS.text)
                Chip(text: g.method == .delete ? L("Deleted", "Xoá") : L("To Trash", "Vào Thùng rác"),
                     tint: g.method.color)
                Spacer(minLength: 8)
                Text(Fmt.size(total))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.text)
            }
            Text(g.description)
                .font(.system(size: 12))
                .foregroundStyle(DS.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 28)
            VStack(spacing: 0) {
                ForEach(items) { i in
                    itemRow(i)
                }
            }
            .padding(.leading, 28)
        }
    }

    private func itemRow(_ i: BrowserItem) -> some View {
        let on = store.checked.contains(i.id)
        return HStack(spacing: 10) {
            CheckboxView(state: on ? .checked : .unchecked) { store.toggle(i) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(i.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let p = i.profile {
                        Chip(text: p)
                    }
                }
                Text(i.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.text3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.size(i.size))
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(DS.text2)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { store.toggle(i) }
        .contextMenu {
            if let first = i.urls.first {
                Button(L("Reveal in Finder", "Hiện trong Finder")) { FileOps.reveal(first) }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(DS.rowDivider).frame(height: 1) }
    }
}
