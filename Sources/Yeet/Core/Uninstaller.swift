// Logic ported from MacSweep (https://github.com/nihal4/macsweep), MIT License, Copyright (c) 2026 S. M. Nihal Ahmed.
//
// App Uninstaller, adapted to the App Sandbox: apps are read from /Applications and
// ~/Applications (Info.plist + Mach-O header only), leftovers are matched in ~/Library
// (the granted Home folder), and everything goes to the Trash with `FileOps.moveToTrash`.
// Yeet never quits an app: running apps are refused. Apple apps and Yeet itself are never listed.

import AppKit
import Foundation
import Observation

// MARK: - /Applications access (sandbox)

/// App Store (sandboxed) build: moving an app out of /Applications needs its own user grant,
/// kept as an app-scoped security-scoped bookmark and re-activated on every launch.
/// Modelled on `FolderAccess`.
enum ApplicationsAccess {
    private static let bookmarkKey = "applicationsFolderBookmark"
    private(set) static var grantedURL: URL?

    static let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

    static var isGranted: Bool { grantedURL != nil }

    /// Call once at launch.
    static func restore() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }
        guard url.startAccessingSecurityScopedResource() else { return }
        grantedURL = url
        if stale { save(url) }
    }

    /// Shows an open panel pointed at /Applications. Returns true when access was granted.
    @MainActor
    @discardableResult
    static func request() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = false
        panel.directoryURL = applicationsURL
        panel.prompt = L("Grant Access", "Cấp quyền")
        panel.message = L("Choose the Applications folder so Yeet can move the apps you uninstall to the Trash.",
                          "Chọn thư mục Applications để Yeet chuyển các ứng dụng bạn gỡ vào Thùng rác.")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        // Only the Applications folder itself is useful here.
        guard url.standardizedFileURL.path == applicationsURL.standardizedFileURL.path else { return false }
        grantedURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        grantedURL = url
        save(url)
        return true
    }

    static func revoke() {
        grantedURL?.stopAccessingSecurityScopedResource()
        grantedURL = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    private static func save(_ url: URL) {
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }
}

// MARK: - Icons

/// Icons of apps (Finder's icon via NSWorkspace), cached by path. NSCache is thread-safe.
enum AppIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let img = cache.object(forKey: key) { return img }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(img, forKey: key)
        return img
    }
}

// MARK: - Model

enum AppSource: Sendable {
    case appStore, direct

    var title: String {
        switch self {
        case .appStore: return L("App Store", "App Store")
        case .direct: return L("Downloaded", "Tải về")
        }
    }
}

enum AppArch: Sendable {
    case universal, appleSilicon, intel, unknown

    var title: String {
        switch self {
        case .universal: return L("Universal", "Universal")
        case .appleSilicon: return L("Apple Silicon", "Apple Silicon")
        case .intel: return L("Intel", "Intel")
        case .unknown: return L("Unknown", "Không rõ")
        }
    }
}

/// Where a leftover lives in ~/Library.
enum LeftoverKind: Sendable {
    case appSupport, cache, preferences, container, groupContainer, savedState, logs, webData, cookies,
         launchAgent, scripts

    var title: String {
        switch self {
        case .appSupport: return L("App Support", "Dữ liệu ứng dụng")
        case .cache: return L("Cache", "Cache")
        case .preferences: return L("Preferences", "Tuỳ chọn")
        case .container: return L("Container", "Container")
        case .groupContainer: return L("Group Container", "Group Container")
        case .savedState: return L("Saved State", "Trạng thái đã lưu")
        case .logs: return L("Logs", "Nhật ký")
        case .webData: return L("Web Data", "Dữ liệu web")
        case .cookies: return L("Cookies", "Cookie")
        case .launchAgent: return L("Launch Agent", "Launch Agent")
        case .scripts: return L("Scripts", "Script")
        }
    }
}

struct Leftover: Identifiable, Sendable {
    /// The full path.
    var id: String { url.path }
    let kind: LeftoverKind
    let url: URL
    let size: Int64
    /// Profiles, accounts, saved documents, logins… kept unless the user ticks it.
    let isUserData: Bool
}

struct InstalledApp: Identifiable, Sendable {
    /// The bundle path.
    var id: String { url.path }
    let name: String
    let bundleID: String
    let version: String
    let url: URL
    let source: AppSource
    let arch: AppArch
    let lastUsed: Date?
    let appSize: Int64
    let leftovers: [Leftover]

    /// Finder's icon for the app.
    var icon: NSImage { AppIconCache.icon(for: url) }
    /// Size of every leftover found (selected or not).
    var dataSize: Int64 { leftovers.reduce(Int64(0)) { $0 + $1.size } }
    /// App + all of its data.
    var totalSize: Int64 { appSize + dataSize }
    /// Lives in /Applications (needs `ApplicationsAccess`).
    var inApplicationsFolder: Bool { url.standardizedFileURL.path.hasPrefix("/Applications/") }
}

enum AppSort: String, CaseIterable, Sendable {
    case size, name, lastUsed

    var title: String {
        switch self {
        case .size: return L("Size", "Dung lượng")
        case .name: return L("Name", "Tên")
        case .lastUsed: return L("Last opened", "Mở lần cuối")
        }
    }
}

/// What one uninstall did.
struct UninstallOutcome {
    var removed: [String] = []
    var freed: Int64 = 0
    var skippedRunning: [String] = []
    var needsAccess: [String] = []
    var failures: [String] = []

    var message: String {
        var parts: [String] = []
        if !removed.isEmpty {
            let n = removed.count
            parts.append(L(n == 1 ? "Moved \(removed[0]) to the Trash · \(Fmt.size(freed))"
                                  : "Moved \(n) apps to the Trash · \(Fmt.size(freed))",
                           "Đã chuyển \(n) ứng dụng vào Thùng rác · \(Fmt.size(freed))"))
        }
        if !skippedRunning.isEmpty {
            let names = skippedRunning.joined(separator: ", ")
            parts.append(L("Quit \(names) first", "Hãy thoát \(names) trước"))
        }
        if !needsAccess.isEmpty {
            parts.append(L("Grant access to Applications to remove \(needsAccess.joined(separator: ", "))",
                           "Cấp quyền thư mục Applications để gỡ \(needsAccess.joined(separator: ", "))"))
        }
        if !failures.isEmpty {
            parts.append(L("\(failures.count) failed: \(failures[0])", "\(failures.count) mục lỗi: \(failures[0])"))
        }
        if parts.isEmpty { return L("Nothing was removed", "Không có gì được gỡ") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Store

@Observable
final class UninstallerStore {
    static let shared = UninstallerStore()

    var apps: [InstalledApp] = []
    var scanning = false
    var scanned = false
    var search = ""
    var sort: AppSort = .size
    /// Ids (bundle paths) of apps ticked for removal.
    var checked: Set<String> = []
    /// Id of the app whose leftovers are shown inline.
    var expanded: String? = nil
    /// Ids (paths) of the leftovers that go with their app. "Your data" starts unticked.
    var selectedLeftovers: Set<String> = []

    // MARK: Derived

    /// Every app plus all of its data.
    var total: Int64 { apps.reduce(Int64(0)) { $0 + $1.totalSize } }
    var appCount: Int { apps.count }

    var visibleApps: [InstalledApp] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? apps : apps.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
        switch sort {
        case .size:
            return filtered.sorted { $0.totalSize > $1.totalSize }
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastUsed:
            // Oldest (or never) first: the likeliest to remove.
            return filtered.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    var selectedApps: [InstalledApp] { apps.filter { checked.contains($0.id) } }

    /// Leftovers that will go with `app` if it is uninstalled.
    func chosenLeftovers(_ app: InstalledApp) -> [Leftover] {
        app.leftovers.filter { selectedLeftovers.contains($0.id) }
    }

    /// Bytes freed by one app: the bundle and its ticked leftovers.
    func removalSize(_ app: InstalledApp) -> Int64 {
        app.appSize + chosenLeftovers(app).reduce(Int64(0)) { $0 + $1.size }
    }

    var selectedSize: Int64 { selectedApps.reduce(Int64(0)) { $0 + removalSize($1) } }

    // MARK: Selection

    func toggleApp(_ app: InstalledApp) {
        if checked.contains(app.id) { checked.remove(app.id) } else { checked.insert(app.id) }
    }

    func toggleLeftover(_ leftover: Leftover) {
        if selectedLeftovers.contains(leftover.id) { selectedLeftovers.remove(leftover.id) }
        else { selectedLeftovers.insert(leftover.id) }
    }

    func toggleExpanded(_ app: InstalledApp) {
        expanded = expanded == app.id ? nil : app.id
    }

    /// Header checkbox state over the visible apps.
    var headerState: CheckState {
        let ids = visibleApps.map(\.id)
        if ids.isEmpty { return .disabled }
        let n = ids.filter { checked.contains($0) }.count
        if n == 0 { return .unchecked }
        return n == ids.count ? .checked : .partial
    }

    func toggleAllVisible() {
        let ids = Set(visibleApps.map(\.id))
        if headerState == .checked { checked.subtract(ids) } else { checked.formUnion(ids) }
    }

    // MARK: Scan

    @MainActor
    func scan() {
        guard !scanning else { return }
        scanning = true
        let ownID = Bundle.main.bundleIdentifier ?? ""
        Task { @MainActor in
            let found: [InstalledApp] = await Task.detached(priority: .userInitiated) {
                UninstallScanner.findApps(excludingBundleID: ownID)
            }.value
            self.apply(found)
            self.scanning = false
            self.scanned = true
        }
    }

    @MainActor
    private func apply(_ found: [InstalledApp]) {
        let oldLeftoverIDs = Set(apps.flatMap { $0.leftovers.map(\.id) })
        var selection = selectedLeftovers
        for app in found {
            for l in app.leftovers where !oldLeftoverIDs.contains(l.id) && !l.isUserData {
                selection.insert(l.id)
            }
        }
        let allLeftoverIDs = Set(found.flatMap { $0.leftovers.map(\.id) })
        selectedLeftovers = selection.intersection(allLeftoverIDs)
        let ids = Set(found.map(\.id))
        checked = checked.intersection(ids)
        if let e = expanded, !ids.contains(e) { expanded = nil }
        apps = found
    }

    // MARK: Uninstall

    /// Selected apps that are running right now (they will be refused).
    @MainActor
    var runningSelected: [InstalledApp] {
        let running = FileOps.runningBundleIDs()
        return selectedApps.filter { !$0.bundleID.isEmpty && running.contains($0.bundleID) }
    }

    /// Moves each ticked app and its chosen leftovers to the Trash, then rescans.
    /// Running apps, Apple apps and Yeet itself are refused.
    @MainActor
    @discardableResult
    func uninstallSelected() -> UninstallOutcome {
        var out = UninstallOutcome()
        let running = FileOps.runningBundleIDs()
        let ownID = Bundle.main.bundleIdentifier ?? ""
        var done: Set<String> = []
        for app in selectedApps {
            if UninstallScanner.isProtected(bundleID: app.bundleID, url: app.url, ownID: ownID) {
                out.failures.append(L("\(app.name) can't be uninstalled", "Không thể gỡ \(app.name)"))
                continue
            }
            if !app.bundleID.isEmpty && running.contains(app.bundleID) {
                out.skippedRunning.append(app.name)
                continue
            }
            if app.inApplicationsFolder && !ApplicationsAccess.isGranted {
                out.needsAccess.append(app.name)
                continue
            }
            let bundle = FileOps.moveToTrash([app.url], sizes: [app.url: app.appSize])
            guard bundle.moved.contains(app.url) else {
                var reason = bundle.failures.first ?? L("\(app.name) could not be moved", "Không chuyển được \(app.name)")
                if app.source == .appStore {
                    reason += L(" (App Store apps may need to be removed from Launchpad or Finder)",
                                " (ứng dụng App Store có thể cần gỡ từ Launchpad hoặc Finder)")
                }
                out.failures.append(reason)
                continue
            }
            out.removed.append(app.name)
            out.freed += bundle.freed
            done.insert(app.id)

            let extras = chosenLeftovers(app)
            var sizes: [URL: Int64] = [:]
            for l in extras { sizes[l.url] = l.size }
            let data = FileOps.moveToTrash(extras.map(\.url), sizes: sizes)
            out.freed += data.freed
            out.failures.append(contentsOf: data.failures)
        }
        checked.subtract(done)
        if !out.failures.isEmpty {
            NSLog("Yeet uninstall failures:\n%@", out.failures.joined(separator: "\n"))
        }
        scan()
        return out
    }
}

// MARK: - Discovery (runs off the main thread)

enum UninstallScanner {
    /// (folder in ~/Library, kind, holds user data?)
    /// User-data folders (browser profiles, mailboxes, logins, saved content)
    /// are never pre-selected: removing them is always the user's explicit choice.
    private static let libraryDirs: [(String, LeftoverKind, Bool)] = [
        ("Application Support", .appSupport, true),
        ("Caches", .cache, false),
        ("Preferences", .preferences, false),
        ("Preferences/ByHost", .preferences, false),
        ("Containers", .container, true),
        ("Group Containers", .groupContainer, true),
        ("Saved Application State", .savedState, false),
        ("Logs", .logs, false),
        ("HTTPStorages", .webData, true),
        ("WebKit", .webData, true),
        ("Cookies", .cookies, true),
        ("LaunchAgents", .launchAgent, false),
        ("Application Scripts", .scripts, false),
    ]

    /// Thread-safe slots for results computed in parallel.
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var slots: [InstalledApp?]
        init(count: Int) { slots = [InstalledApp?](repeating: nil, count: count) }
        func set(_ i: Int, _ app: InstalledApp?) { lock.lock(); slots[i] = app; lock.unlock() }
        var values: [InstalledApp?] { lock.lock(); defer { lock.unlock() }; return slots }
    }

    private struct LibItem {
        let url: URL
        let name: String   // lowercased file name
        let kind: LeftoverKind
        let data: Bool
    }

    private struct BundleInfo {
        var id: String = ""
        var name: String = ""
        var exe: String = ""
        var version: String = ""
    }

    // MARK: File helpers

    static func children(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    static func isSymlink(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink ?? false
    }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    /// Never list or remove Apple's apps, anything in /System, or Yeet itself.
    static func isProtected(bundleID: String, url: URL, ownID: String) -> Bool {
        let id = bundleID.lowercased()
        if id.hasPrefix("com.apple.") { return true }
        if !ownID.isEmpty && id == ownID.lowercased() { return true }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        if path.hasPrefix("/System/") { return true }
        if path == Bundle.main.bundleURL.standardizedFileURL.path { return true }
        return false
    }

    // MARK: Bundle reading

    private static func readBundle(_ app: URL) -> BundleInfo {
        let real = app.resolvingSymlinksInPath()
        let plistURL = real.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let d = obj as? [String: Any] else { return BundleInfo() }
        var b = BundleInfo()
        b.id = d["CFBundleIdentifier"] as? String ?? ""
        b.name = d["CFBundleName"] as? String ?? ""
        b.exe = d["CFBundleExecutable"] as? String ?? ""
        b.version = (d["CFBundleShortVersionString"] as? String) ?? (d["CFBundleVersion"] as? String) ?? ""
        return b
    }

    /// Reads the Mach-O header of the main executable.
    static func detectArch(app: URL, executable: String) -> AppArch {
        guard !executable.isEmpty else { return .unknown }
        let exe = app.resolvingSymlinksInPath().appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
        guard let handle = try? FileHandle(forReadingFrom: exe) else { return .unknown }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096), data.count >= 8 else { return .unknown }
        let bytes: [UInt8] = [UInt8](data)

        func be(_ o: Int) -> UInt32 {
            guard o >= 0, o + 4 <= bytes.count else { return 0 }
            let a = UInt32(bytes[o]) << 24
            let b = UInt32(bytes[o + 1]) << 16
            let c = UInt32(bytes[o + 2]) << 8
            let d = UInt32(bytes[o + 3])
            return a | b | c | d
        }
        func le(_ o: Int) -> UInt32 {
            guard o >= 0, o + 4 <= bytes.count else { return 0 }
            let a = UInt32(bytes[o + 3]) << 24
            let b = UInt32(bytes[o + 2]) << 16
            let c = UInt32(bytes[o + 1]) << 8
            let d = UInt32(bytes[o])
            return a | b | c | d
        }

        let arm64: UInt32 = 0x0100_000C
        let x86_64: UInt32 = 0x0100_0007
        var arm = false
        var intel = false
        let magic = be(0)
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
            let entry = magic == 0xCAFE_BABE ? 20 : 32
            let count = Int(min(be(4), 16))
            for i in 0..<count {
                let o = 8 + i * entry
                if o + 4 > bytes.count { break }
                let cpu = be(o)
                if cpu == arm64 { arm = true }
                if cpu == x86_64 { intel = true }
            }
        } else if le(0) == 0xFEED_FACF {
            let cpu = le(4)
            if cpu == arm64 { arm = true }
            if cpu == x86_64 { intel = true }
        }
        if arm && intel { return .universal }
        if arm { return .appleSilicon }
        if intel { return .intel }
        return .unknown
    }

    /// Spotlight's "last opened" date, else the bundle's last access date.
    static func lastUsed(_ app: URL) -> Date? {
        if let item = NSMetadataItem(url: app),
           let date = item.value(forAttribute: "kMDItemLastUsedDate") as? Date {
            return date
        }
        let values = try? app.resourceValues(forKeys: [.contentAccessDateKey])
        return values?.contentAccessDate
    }

    // MARK: Matching

    /// True if `name` contains the bundle ID `id` as whole dot-separated parts:
    /// "com.foo.app.plist" and "group.com.foo.app" match "com.foo.app", "com.foo.apple" does not.
    static func idIn(_ name: String, _ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        let n = Array(name.utf8)
        let s = Array(id.utf8)
        guard s.count <= n.count else { return false }
        let dot = UInt8(ascii: ".")
        var i = 0
        while i + s.count <= n.count {
            if Array(n[i..<(i + s.count)]) == s {
                let before = i == 0 || n[i - 1] == dot
                let end = i + s.count
                let after = end == n.count || n[end] == dot
                if before && after { return true }
            }
            i += 1
        }
        return false
    }

    /// Does this ~/Library item belong to the app with bundle ID `id`? A longer ID of another
    /// installed app wins: "com.google.chrome.canary.plist" belongs to Chrome Canary, not Chrome.
    static func belongsTo(_ name: String, _ id: String, allIDs: [String]) -> Bool {
        guard idIn(name, id) else { return false }
        for other in allIDs where other.count > id.count && other.hasPrefix(id + ".") {
            if idIn(name, other) { return false }
        }
        return true
    }

    // MARK: Discovery

    /// Top-level apps in /Applications and ~/Applications (and one folder level inside
    /// ~/Applications). Apps nested in /Applications sub-folders can't be moved from the
    /// sandbox, so they aren't listed.
    private static func discover() -> [URL] {
        var out: [URL] = []
        for c in children(ApplicationsAccess.applicationsURL) where c.pathExtension == "app" {
            out.append(c)
        }
        let homeApps = Paths.home.appendingPathComponent("Applications", isDirectory: true)
        for c in children(homeApps) {
            if c.pathExtension == "app" {
                out.append(c)
            } else if isDirectory(c) && !isSymlink(c) {
                for inner in children(c) where inner.pathExtension == "app" { out.append(inner) }
            }
        }
        return out
    }

    /// One listing of ~/Library, shared by every app's leftover search.
    private static func libraryIndex() -> [LibItem] {
        let lib = Paths.home.appendingPathComponent("Library", isDirectory: true)
        var items: [LibItem] = []
        for (dir, kind, data) in libraryDirs {
            for c in children(lib.appendingPathComponent(dir, isDirectory: true)) {
                // "Preferences/ByHost" is listed on its own; don't list it as a leftover of Preferences.
                if dir == "Preferences" && c.lastPathComponent == "ByHost" { continue }
                items.append(LibItem(url: c, name: c.lastPathComponent.lowercased(), kind: kind, data: data))
            }
        }
        return items
    }

    static func findApps(excludingBundleID ownID: String) -> [InstalledApp] {
        let found = discover()
        let bundles: [BundleInfo] = found.map { readBundle($0) }
        let allIDs: [String] = bundles.map { $0.id.lowercased() }.filter { !$0.isEmpty }
        let index = libraryIndex()

        let box = ResultBox(count: found.count)
        DispatchQueue.concurrentPerform(iterations: found.count) { i in
            let app = build(url: found[i], bundle: bundles[i], index: index, allIDs: allIDs, ownID: ownID)
            box.set(i, app)
        }
        let apps: [InstalledApp] = box.values.compactMap { $0 }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func build(url: URL, bundle b: BundleInfo, index: [LibItem], allIDs: [String],
                              ownID: String) -> InstalledApp? {
        if isProtected(bundleID: b.id, url: url, ownID: ownID) { return nil }
        let real = url.resolvingSymlinksInPath()
        let name = url.deletingPathExtension().lastPathComponent
        guard !name.isEmpty else { return nil }

        // Leftovers: match the bundle ID or the exact app name.
        let lowerName = name.lowercased()
        var names: [String] = [lowerName, lowerName.replacingOccurrences(of: " ", with: "")]
        if !b.name.isEmpty { names.append(b.name.lowercased()) }
        let bid = b.id.lowercased()

        var leftovers: [Leftover] = []
        for item in index {
            let n = item.name
            let byID = !bid.isEmpty && belongsTo(n, bid, allIDs: allIDs)
            let stem = (n as NSString).deletingPathExtension
            let byName = names.contains(n) || names.contains(stem)
            guard byID || byName else { continue }
            if isSymlink(item.url) { continue }
            let size = Scanner.stats(item.url).size
            leftovers.append(Leftover(kind: item.kind, url: item.url, size: size, isUserData: item.data))
        }
        leftovers.sort { $0.size > $1.size }

        let receipt = real.appendingPathComponent("Contents/_MASReceipt", isDirectory: true)
        let source: AppSource = FileManager.default.fileExists(atPath: receipt.path) ? .appStore : .direct

        return InstalledApp(
            name: name,
            bundleID: b.id,
            version: b.version,
            url: url,
            source: source,
            arch: detectArch(app: url, executable: b.exe),
            lastUsed: lastUsed(url),
            appSize: Scanner.stats(real).size,
            leftovers: leftovers
        )
    }
}
