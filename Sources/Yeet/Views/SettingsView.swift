import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showPaths") private var showPaths = true
    @AppStorage("hideEmpty") private var hideEmpty = false
    @AppStorage("confirmBeforeClean") private var confirmBeforeClean = true
    @AppStorage(GitRoots.key) private var gitRootsRaw = GitRoots.defaultValue

    @State private var accessReady = true
    @AppStorage(GrowthStore.notifyKey) private var growthNotify = false
    @AppStorage(GrowthStore.thresholdKey) private var growthThreshold = 5.0
    @State private var openAtLogin = LoginItem.isEnabled
    @AppStorage(BackgroundMode.key) private var menuBarEnabled = true
    @State private var loginError: String?
    @AppStorage(AppLanguage.key) private var language = AppLanguage.en.rawValue

    private var roots: [String] { GitRoots.list(gitRootsRaw) }

    var body: some View {
        Form {
            Section(L("Language", "Ngôn ngữ")) {
                Picker(L("Language", "Ngôn ngữ"), selection: $language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
            }
            Section(L("Display", "Hiển thị")) {
                Toggle(L("Show paths under item names", "Hiện đường dẫn dưới tên mục"), isOn: $showPaths)
                Toggle(L("Hide empty items (0 KB)", "Ẩn mục trống (0 KB)"), isOn: $hideEmpty)
            }
            Section(L("Disk Access", "Quyền truy cập ổ đĩa")) {
                DiskAccessPanel(ready: $accessReady)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                ProtectedFoldersPanel()
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
            Section {
                Toggle(L("Show in menu bar & keep running when the window is closed", "Hiện trên thanh menu & chạy nền khi đóng cửa sổ"), isOn: $menuBarEnabled)
                Toggle(L("Open Yeet at login (menu bar only)", "Mở Yeet khi đăng nhập (chỉ hiện trên thanh menu)"), isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        loginError = LoginItem.set(on)
                        if loginError != nil { openAtLogin = LoginItem.isEnabled }
                    }
                Toggle(L("Notify when disk usage grows quickly", "Thông báo khi ổ đĩa tăng nhanh"), isOn: $growthNotify)
                    .onChange(of: growthNotify) { _, on in
                        if on { GrowthStore.requestNotificationPermission { ok in if !ok { growthNotify = false } } }
                    }
                Picker(L("Daily growth threshold", "Ngưỡng tăng trong một ngày"), selection: $growthThreshold) {
                    ForEach([1.0, 2.0, 5.0, 10.0, 20.0], id: \.self) { gb in
                        Text("\(Int(gb)) GB").tag(gb)
                    }
                }
                .disabled(!growthNotify)
            } header: {
                Text(L("Storage Monitoring", "Theo dõi dung lượng"))
            } footer: {
                Text(loginError.map { L("Couldn't enable: \($0)", "Không bật được: \($0)") }
                     ?? L("Yeet takes a storage snapshot once a day (even when running only in the menu bar, and after your Mac wakes) and keeps the last \(GrowthStore.keepDays) days on your Mac. With background mode off, closing the window quits Yeet.",
                          "Yeet chụp số liệu dung lượng mỗi ngày một lần (cả khi chỉ chạy trên thanh menu, và sau khi máy thức dậy) và lưu \(GrowthStore.keepDays) ngày gần nhất trên máy của bạn. Tắt “chạy nền” thì đóng cửa sổ là thoát Yeet."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("Auto-hide tools not on this Mac (0 KB)", "Tự ẩn công cụ không có trên máy (0 KB)"), isOn: Binding(
                    get: { model.autoHideEmpty }, set: { model.setAutoHideEmpty($0) }))
                ForEach(ToolSection.allCases, id: \.self) { section in
                    Text(section.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(ToolKind.available.filter { $0.section == section }) { kind in
                        Toggle(isOn: Binding(
                            get: { !model.hiddenTools.contains(kind) },
                            set: { model.setHidden(kind, !$0) })) {
                            HStack(spacing: 8) {
                                ToolTile(color: kind.color, symbol: kind.symbol, size: 20, radius: 5, glyph: 11)
                                Text(kind.name)
                                Spacer()
                                Text(toolStatus(kind))
                                    .font(.system(size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                HStack {
                    Button(L("Enable All", "Bật tất cả")) {
                        for k in ToolKind.available where model.hiddenTools.contains(k) { model.setHidden(k, false) }
                    }
                    Button(L("Keep Only Installed Tools", "Chỉ giữ công cụ có trên máy")) { model.hideAllEmpty() }
                        .disabled(!model.enabledTools.contains(where: model.isEmptyOnThisMac))
                }
            } header: {
                Text(L("Scanned Tools", "Công cụ được quét"))
            } footer: {
                Text(L("Disabled tools aren't scanned, don't appear in the sidebar and aren't counted in the total. Right-click a tool in the sidebar to hide it quickly.", "Công cụ bị tắt không được quét, không hiện trên sidebar và không tính vào tổng. Có thể chuột phải vào công cụ trên sidebar để ẩn nhanh."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section(L("Cleanup", "Dọn dẹp")) {
                Toggle(L("Confirm before cleaning", "Xác nhận trước khi dọn"), isOn: $confirmBeforeClean)
            }
            Section {
                ForEach(roots, id: \.self) { root in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(DS.folder)
                        Text(root).font(DS.mono(12))
                        Spacer()
                        Button {
                            setRoots(roots.filter { $0 != root })
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(DS.text3)
                        }
                        .buttonStyle(.plain)
                        .help(L("Remove this folder", "Bỏ thư mục này"))
                    }
                }
                Button(L("Add Folder…", "Thêm thư mục…")) { addRoot() }
            } header: {
                Text(L("Project Folders", "Thư mục dự án"))
            } footer: {
                Text(L("Yeet looks for Git repos, node_modules and Rust target/ folders in these folders. Click “Rescan” to apply.", "Yeet tìm repo Git, node_modules và thư mục target/ của Rust trong các thư mục này. Nhấn “Quét lại” để áp dụng."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .id(language)
        // Outside the re-id'd Form so it isn't torn down with it.
        .onChange(of: language) { _, _ in
            // Scan results carry text baked in the old language: rebuild them.
            if model.phase == .idle { model.rescan(announce: false) }
            GrowthStore.shared.load()
        }
        .frame(width: 560, height: 780)
    }

    private func toolStatus(_ k: ToolKind) -> String {
        if model.hiddenTools.contains(k) { return L("Disabled", "Đã tắt") }
        guard model.scanned.contains(k) else { return L("Not scanned", "Chưa quét") }
        let size = model.toolNode(k).size
        return size > 0 ? Fmt.size(size) : L("Not on this Mac", "Không có trên máy")
    }

    private func setRoots(_ list: [String]) {
        gitRootsRaw = list.joined(separator: "\n")
    }

    @MainActor
    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L("Add", "Thêm")
        guard panel.runModal() == .OK else { return }
        var list = roots
        for url in panel.urls {
            let p = Paths.tilde(url)
            if !list.contains(p) { list.append(p) }
        }
        setRoots(list)
    }
}
