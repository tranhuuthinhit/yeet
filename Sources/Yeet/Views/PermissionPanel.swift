import AppKit
import SwiftUI

/// Full Disk Access status + fixes. Used in onboarding and Settings.
struct PermissionPanel: View {
    @State private var status: FDAStatus = Permissions.fullDiskAccessStatus()
    @State private var checking = false
    @State private var lastChecked: Date? = nil

    private let bundled = Permissions.isRunningAsAppBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow

            if !bundled {
                note(icon: "exclamationmark.triangle",
                     text: L("Yeet is running from Xcode / swift run, not from Yeet.app. macOS applies the permission to Xcode or Terminal, not to Yeet. Run build/Yeet.app (./scripts/build-app.sh) and grant access to that app, or grant Full Disk Access to Xcode/Terminal.",
                             "Yeet đang chạy từ Xcode / swift run, không phải Yeet.app. macOS áp quyền cho Xcode hoặc Terminal chứ không cho Yeet. Hãy chạy build/Yeet.app (./scripts/build-app.sh) rồi cấp quyền cho app đó, hoặc cấp Full Disk Access cho Xcode/Terminal."))
            } else if status != .granted {
                note(icon: "info.circle",
                     text: L("Enabled Yeet in System Settings but it still says no access? macOS usually applies the permission only after the app relaunches, so click “Relaunch Yeet”. If that doesn't help, remove Yeet from the list (the − button) and add the exact file that's running again. Each rebuild changes the ad-hoc signature, so the old permission no longer applies.",
                             "Đã bật Yeet trong Cài đặt mà vẫn báo chưa có? macOS thường chỉ áp quyền sau khi mở lại app, hãy bấm “Mở lại Yeet”. Nếu vẫn chưa được: xoá Yeet khỏi danh sách (nút −) rồi thêm lại đúng file đang chạy. Mỗi lần build lại, chữ ký ad-hoc thay đổi nên quyền cũ không còn hiệu lực."))
                Text(Permissions.appBundleURL.path)
                    .font(DS.mono(11))
                    .foregroundStyle(DS.text3)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                Button {
                    Permissions.openFullDiskAccessSettings()
                } label: {
                    Label(L("Open System Settings", "Mở Cài đặt"), systemImage: "lock.shield")
                }
                .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 12.5, horizontalPadding: 10))

                if bundled && status != .granted {
                    Button {
                        Permissions.revealAppInFinder()
                    } label: {
                        Label(L("Show Yeet.app", "Hiện Yeet.app"), systemImage: "folder")
                    }
                    .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 12.5, horizontalPadding: 10))
                    .help(L("Drag Yeet.app into the Full Disk Access list", "Kéo Yeet.app vào danh sách Full Disk Access"))

                    Button {
                        Permissions.relaunch()
                    } label: {
                        Label(L("Relaunch Yeet", "Mở lại Yeet"), systemImage: "arrow.uturn.right")
                    }
                    .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 12.5, horizontalPadding: 10))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.bg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.divider, lineWidth: 1))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recheck()
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: status == .granted ? "checkmark.shield.fill" : "exclamationmark.shield")
                .font(.system(size: 18))
                .foregroundStyle(status == .granted ? DS.success : DS.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                recheck()
            } label: {
                HStack(spacing: 6) {
                    if checking {
                        ProgressView().controlSize(.mini)
                    }
                    Text(L("Check Again", "Kiểm tra lại"))
                }
            }
            .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 12.5, horizontalPadding: 10))
            .disabled(checking)
        }
    }

    private var title: String {
        switch status {
        case .granted: return L("Full Disk Access granted", "Đã có Full Disk Access")
        case .denied: return L("No Full Disk Access", "Chưa có Full Disk Access")
        case .unknown: return L("Couldn't determine access", "Không xác định được quyền")
        }
    }

    private var subtitle: String {
        var s: String
        switch status {
        case .granted: s = L("Yeet can scan every cache folder.", "Yeet có thể quét mọi thư mục cache.")
        case .denied: s = L("Most caches can still be scanned, but some folders may be skipped.", "Vẫn quét được phần lớn cache, nhưng một số thư mục có thể bị bỏ qua.")
        case .unknown: s = L("No sample folder found to check. Yeet still scans normally.", "Không tìm thấy thư mục mẫu để kiểm tra. Yeet vẫn quét bình thường.")
        }
        if let lastChecked {
            let time = lastChecked.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(AppLanguage.current.locale))
            s += L(" · Checked at ", " · Kiểm tra lúc ") + time
        }
        return s
    }

    private func recheck() {
        checking = true
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { Permissions.fullDiskAccessStatus() }.value
            // Keep the spinner visible briefly so the click has visible feedback.
            try? await Task.sleep(nanoseconds: 250_000_000)
            status = result
            lastChecked = Date()
            checking = false
        }
    }

    private func note(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 13))
            Text(text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(hex: 0x8A5A00))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.warning.opacity(0.15)))
    }
}

// MARK: - App Store build: folder access

/// Sandboxed build: asks the user to grant their Home folder (security-scoped bookmark).
struct FolderAccessPanel: View {
    @Binding var granted: Bool
    @State private var coversHome = FolderAccess.coversHome

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield")
                    .font(.system(size: 18))
                    .foregroundStyle(granted ? DS.success : DS.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text(granted ? L("Folder access granted", "Đã cấp quyền thư mục") : L("Folder access not granted", "Chưa cấp quyền thư mục"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.text)
                    Text(granted ? Paths.tilde(FolderAccess.grantedURL ?? Paths.home)
                                 : L("Choose your Home folder (\(Paths.home.path)) so Yeet can scan caches.", "Chọn thư mục Home (\(Paths.home.path)) để Yeet quét được cache."))
                        .font(.system(size: 12))
                        .foregroundStyle(DS.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(granted ? L("Choose Again…", "Chọn lại…") : L("Grant Access…", "Cấp quyền…")) {
                    if FolderAccess.request() { refresh() }
                }
                .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 12.5, horizontalPadding: 10))
                if granted {
                    Button(L("Revoke", "Thu hồi")) {
                        FolderAccess.revoke()
                        refresh()
                    }
                    .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 12.5, horizontalPadding: 10))
                }
            }

            if granted && !coversHome {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 13))
                    Text(L("The selected folder isn't your Home folder. Caches outside it (e.g. ~/Library, ~/.npm) can't be scanned.", "Thư mục đã chọn không phải Home. Cache nằm ngoài thư mục này (ví dụ ~/Library, ~/.npm) sẽ không quét được."))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color(hex: 0x8A5A00))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.warning.opacity(0.15)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.bg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.divider, lineWidth: 1))
        .onAppear { refresh() }
    }

    private func refresh() {
        granted = FolderAccess.isGranted
        coversHome = FolderAccess.coversHome
    }
}

// MARK: - Build-specific access panel

/// Full Disk Access panel for the direct build, folder-grant panel for the App Store build.
/// `ready` is true when scanning can start.
struct DiskAccessPanel: View {
    @Binding var ready: Bool

    var body: some View {
        #if APPSTORE
        FolderAccessPanel(granted: $ready)
        #else
        PermissionPanel()
            .onAppear { ready = true }
        #endif
    }
}

enum BuildFlavor {
    #if APPSTORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif
}

// MARK: - Protected folders (Desktop / Documents / Downloads / Containers)

/// Lets the user pick which privacy-protected folders Yeet may measure and triggers the
/// macOS prompts *now*, on purpose, instead of at a random moment during a background capture.
/// Hidden when Yeet has Full Disk Access (no prompts then) and in the App Store build.
struct ProtectedFoldersPanel: View {
    @State private var enabled: [String: Bool] = Dictionary(uniqueKeysWithValues:
        ProtectedFolders.folders.map { ($0.key, ProtectedFolders.isEnabled($0.key)) })
    @State private var status: [String: Bool] = [:]
    @State private var needsPreparing = ProtectedFolders.needsPreparing
    @State private var working = false
    @AppStorage(ProtectedFolders.containersKey) private var includeContainers = false
    @AppStorage(ProtectedFolders.containersPreparedKey) private var containersPrepared = false
    @State private var containersOK: Bool?

    private let hasFDA = Permissions.hasFullDiskAccess()

    var body: some View {
        if BuildFlavor.isAppStore || hasFDA {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("macOS-Protected Folders", "Thư mục được macOS bảo vệ"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text(L("macOS asks for permission the first time Yeet reads Desktop, Documents or Downloads. Click “Allow Now” to answer once; until then Yeet won't touch these folders, even in the background.", "macOS hỏi quyền khi Yeet đọc Desktop, Documents, Downloads lần đầu. Bấm “Cho phép ngay” để trả lời một lần; trước đó Yeet không đụng vào các thư mục này, kể cả khi chạy nền."))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text3)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(ProtectedFolders.folders) { f in
                    HStack(spacing: 8) {
                        Toggle(isOn: binding(f.key)) {
                            Text("~/\(f.name)").font(DS.mono(12))
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                        statusLabel(status[f.key], waiting: false)
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Toggle(isOn: $includeContainers) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("Also measure app data (~/Library/Containers)", "Đo cả dữ liệu ứng dụng (~/Library/Containers)")).font(.system(size: 12.5))
                            Text(L("Docker, Mail, Notes… macOS will ask once to “access data from other apps”.", "Docker, Mail, Notes… macOS sẽ hỏi “truy cập dữ liệu của ứng dụng khác” một lần."))
                                .font(.system(size: 11)).foregroundStyle(DS.text3)
                        }
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    if includeContainers { statusLabel(containersOK, waiting: containersPrepared) }
                }

                HStack {
                    Spacer()
                    Button {
                        allowNow()
                    } label: {
                        HStack(spacing: 6) {
                            if working { ProgressView().controlSize(.mini) }
                            Text(needsPreparing || (includeContainers && !containersPrepared) ? L("Allow Now", "Cho phép ngay") : L("Check Again", "Kiểm tra lại"))
                        }
                    }
                    .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 12.5, horizontalPadding: 12))
                    .disabled(working)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.bg))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.divider, lineWidth: 1))
            .onAppear { status = ProtectedFolders.status() }
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { enabled[key] ?? true },
            set: { v in
                enabled[key] = v
                UserDefaults.standard.set(v, forKey: ProtectedFolders.enabledKey(key))
                needsPreparing = ProtectedFolders.needsPreparing
            }
        )
    }

    @ViewBuilder
    private func statusLabel(_ ok: Bool?, waiting: Bool) -> some View {
        if let ok {
            Label(ok ? L("Allowed", "Được phép") : L("Denied", "Bị từ chối"), systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(ok ? DS.success : DS.danger)
                .help(ok ? "" : L("Turn it back on in System Settings → Privacy & Security → Files and Folders.", "Bật lại trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Tệp và thư mục."))
        } else if !waiting {
            Text(L("Not asked", "Chưa hỏi")).font(.system(size: 11.5)).foregroundStyle(DS.text3)
        }
    }

    /// Runs off the main thread: each file access blocks while macOS shows its prompt.
    private func allowNow() {
        working = true
        let wantContainers = includeContainers
        Task { @MainActor in
            let (folders, containers) = await Task.detached(priority: .userInitiated) { () -> ([String: Bool], Bool?) in
                let f = ProtectedFolders.prepare()
                let c: Bool? = wantContainers ? ProtectedFolders.prepareContainers() : nil
                return (f, c)
            }.value
            status = folders.merging(ProtectedFolders.status()) { new, _ in new }
            if let containers { containersOK = containers }
            needsPreparing = ProtectedFolders.needsPreparing
            containersPrepared = UserDefaults.standard.bool(forKey: ProtectedFolders.containersPreparedKey)
            working = false
        }
    }
}
